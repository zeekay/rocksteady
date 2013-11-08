cluster = require 'cluster'
events  = require 'events'
fs      = require 'fs'
http    = require 'http'
path    = require 'path'

# Start up debugger
debug = ->
  for id, worker of cluster.workers

    # Only kill first worker
    pid = worker.process.pid
    require('child_process').exec "kill -s 30 #{pid}"
    return

# deserialize exception object back into error object
deserialize = (exc) ->
  for frame in exc.structuredStackTrace
    {path, line, isNative, name, type, method} = frame
    do (frame, path, line, isNative, name, type, method) ->
      frame.getFileName     = -> path
      frame.getLineNumber   = -> line
      frame.isNative        = -> isNative
      frame.getFunctionName = -> name
      frame.getTypeName     = -> type
      frame.getMethodName   = -> method

  err = new Error()
  err.name                 = exc.name
  err.message              = exc.message
  err.stack                = exc.stack
  err.structuredStackTrace = exc.structuredStackTrace
  err

class Master extends events.EventEmitter
  constructor: (serverModule, options = {}) ->
    @serverModule     = require.resolve path.resolve serverModule

    @forceKillTimeout = options.forceKillTimeout ? 30000
    @numWorkers       = options.workers          ? require('os').cpus().length
    @port             = options.port             ? 3000
    @restartCooldown  = options.restartCooldown  ? 2000
    @socketTimeout    = options.socketTimeout    ? 10000
    @env              = options.env              ? process.env.NODE_ENV ? 'development'

    @shuttingDown = false
    @reloading    = []
    @workers      = {}

    @runAs = options.runAs ?
      dropPrivileges: true
      gid: 'www-data'
      uid: 'www-data'

    @setupMaster = options.setupMaster ?
      exec : __dirname + '/worker.js'
      silent : false
    cluster.setupMaster @setupMaster

    switch typeof options.logger
      when 'function'
        @logger = log: options.logger
      when 'object'
        @logger = options.logger
      when 'undefined'
        @logger = require('./utils').logger
      else
        @logger = false

  # fork worker
  fork: ->
    options =
      NODE_ENV:           @env
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
          @emit 'worker:exception', worker, deserialize message.error

          setTimeout =>
            @fork()
          , @restartCooldown

          worker.timeout = setTimeout =>
            worker.kill()
            @emit 'worker:killed', worker
          , @forceKillTimeout

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
    @reloadNext() if @reloading.length > 0

  # reload worker
  reloadNext: ->
    return unless (worker = @reloading.shift())?

    worker.reloading = true

    worker.timeout = setTimeout =>
      worker.kill()
      @emit 'worker:killed', worker
    , @forceKillTimeout

    worker.send type: 'stop'
    @fork()

  # reload all workers
  reload: ->
    return unless @running

    @emit 'reload'
    @running = false

    @once 'worker:listening', (worker, address) =>
      @running = true

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

  # run worker modules
  run: (cb) ->
    # try require server module
    try
      server = require @serverModule
    catch err
      return cb err

    unless server instanceof http.Server
      return cb new Error 'Server (#{serverModule}) must be an instance of http.Server'

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

    # default logging
    @startLogging() if @logger

    # start watching files for changes
    # @startWatching() if @env == 'development'

  startLogging: ->
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
    @on 'reload', =>
      @logger.log 'info', 'reloading'

  # watch files for changes and reload gracefully
  startWatching: ->
    bebop   = new (require 'bebop').Bebop()
    watcher = new (require 'vigil').Watcher()

    bebop.run()

    watcher.on 'modified', (filename, vm) ->
      @logger.log 'info', "#{filename} modified"

      if vm
        # change in backend, reload application and then bebop
        @once 'worker:listening', (worker, address) =>
          bebop.reload()
        @reload()
      else
        # change in frontend, just reload bebop
        bebop.reload()

    # worker has detected file to watch
    @on 'watch', ({filename, isDirectory}) ->
      watcher.watch
        filename:  filename
        directory: isDirectory
        vm:        true

module.exports = Master
