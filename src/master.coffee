cluster = require 'cluster'
events  = require 'events'
fs      = require 'fs'
http    = require 'http'
path    = require 'path'
utils   = require './utils'

env = process.env.NODE_ENV ? 'development'

class Master extends events.EventEmitter
  constructor: (serverModule, options = {}) ->
    @serverModule     = require.resolve path.resolve serverModule
    @forceKillTimeout = options.forceKillTimeout ? 30000
    @numWorkers       = options.workers          ? if (env == 'development') then 1 else require('os').cpus().length
    @port             = options.port             ? 3000
    @restartCooldown  = options.restartCooldown  ? 2000
    @socketTimeout    = options.socketTimeout    ? 10000
    @watchForChanges  = options.watch            ? if (env == 'development') then true else false

    @shuttingDown = false
    @reloading    = []
    @workers      = {}

    @runAs = options.runAs ?
      dropPrivileges: true
      gid: 'www-data'
      uid: 'www-data'

    @setupMaster = options.setupMaster ?
      exec:   __dirname + '/worker.js'
      silent: false
    cluster.setupMaster @setupMaster

    switch typeof options.logger
      when 'function'
        @logger = log: options.logger
      when 'object'
        @logger = options.logger
      when 'undefined'
        @logger = utils.logger
      else
        @logger = false

  # fork worker
  fork: ->
    options =
      NODE_ENV:           env
      FORCE_KILL_TIMEOUT: @forceKillTimeout
      PORT:               @port
      SERVER_MODULE:      @serverModule
      SOCKET_TIMEOUT:     @socketTimeout

    if @runAs
      options.DROP_PRIVILEGES = @runAs.dropPrivileges
      options.SET_GID = @runAs.gid
      options.SET_UID = @runAs.uid

    worker = cluster.fork options

    worker.on 'message', (message) =>
      switch message.type
        when 'error'
          @emit 'worker:exception', worker, utils.deserialize message.error

          setTimeout =>
            @fork()
          , @restartCooldown

          worker.timeout = setTimeout =>
            worker.kill()
            @emit 'worker:killed', worker
          , @forceKillTimeout

        when 'shutdown'
          @emit 'worker:shutdown', worker

        when 'watch'
          @emit 'watch', message

    @workers[worker.id] = worker

    @emit 'worker:forked', worker

  # handle worker exit
  onExit: (worker, code, signal) ->
    delete @workers[worker.id]

    if worker.timeout?
      return clearTimeout worker.timeout

    if code != 0
      setTimeout =>
        @emit 'worker:restarting', worker
        @fork() unless @shuttingDown
      , @restartCooldown

    if @shuttingDown and Object.keys(@workers).length == 0
      process.exit 0

  # handle worker listening
  onListening: (worker, address) ->
    @emit 'worker:listening', worker, address
    @reloadNext() if @reloading.length

  # reload worker
  reloadNext: ->
    unless (worker = @reloading.shift())?
      return @reloading = false

    worker.reloading = true

    worker.timeout = setTimeout =>
      worker.kill()
      @emit 'worker:killed', worker
    , @forceKillTimeout

    worker.send type: 'stop'
    @fork()

  # reload all workers
  reload: ->
    return if @shuttingDown or @reloading.length

    @emit 'reloading'

    @reloading = (worker for id, worker of @workers when not worker.reloading)
    @reloadNext()

  # shutdown workers
  shutdown: ->
    process.exit 1 if @shuttingDown

    @shuttingDown = true

    @emit 'shutdown'

    for id, worker of @workers
      worker.send type: 'stop'

    setTimeout =>
      for id, worker of @workers
        worker.kill()
        @emit 'worker:killed', worker
      process.exit 1
    , @forceKillTimeout

  # Start up debugger
  debug: ->
    for id, worker of cluster.workers
      # Only kill first worker
      pid = worker.process.pid
      require('child_process').exec "kill -s 30 #{pid}"
      return

  # run worker modules
  run: (cb) ->
    @once 'worker:listening', (worker, address) =>
      @running = true
      cb null

    @fork() for n in [1..@numWorkers]

    cluster.on 'exit', (worker, code, signal) => @onExit worker, code, signal
    cluster.on 'listening', (worker, address) => @onListening worker, address

    # handle various signals
    process.on 'SIGHUP',  => @reload()
    process.on 'SIGTERM', => @shutdown()
    process.on 'SIGINT',  => @shutdown()
    process.on 'SIGUSR1', => @debug()

    # listen for keyboard shortcuts if this is a terminal
    if process.stdin.isTTY
      process.stdin.resume()
      process.stdin.setEncoding 'utf8'
      process.stdin.setRawMode true
      process.stdin.on 'data', (char) =>
        switch char
          when '\u0003'  # ctrl-c
            @shutdown()
          when '\u0004'  # ctrl-d
            @debug()

    if @logger
      @on 'worker:exception', (worker, err) =>
        @logger.log 'error', err, pid: worker.process.pid
      @on 'worker:listening', (worker, address) =>
        @logger.log 'info', "worker listening on #{address.address}:#{address.port}", pid: worker.process.pid
      @on 'worker:killed', (worker) =>
        @logger.log 'error', 'worker killed', pid: worker.process.pid
      @on 'worker:restarting', (worker) =>
        @logger.log 'info', 'worker restarting', pid: worker.process.pid
      @on 'shutdown', =>
        @logger.log 'info', 'shutting down'
      @on 'reloading', =>
        @logger.log 'info', 'reloading'

    # start watching files for changes
    @watch() if @watchForChanges

  # watch files for changes and reload gracefully
  watch: (dir = process.cwd()) ->
    server = http.createServer()
    bebop = (require 'bebop').websocket server: server
    server.listen 3456

    watch = (require 'vigil').watch dir, (filename, stats, isModule) =>
      @logger.log 'info', "#{filename} modified" if @logger

      unless isModule
        bebop.modified filename
      else
        # change in backend, reload application and then bebop
        @once 'worker:listening', (worker, address) =>
          bebop.modified filename

        # should just @reload() , but not working properly for some reason
        worker.kill() for id, worker of @workers
        @fork()

    # worker has detected file to watch
    @on 'watch', ({filename, isDirectory}) ->
      watch filename, (not isDirectory)

module.exports = Master
