Master = require './master'

wrapper =
  Master: Master
  run: (serverModule, opts = {}, cb = ->) ->
    if typeof opts is 'function'
      [cb, opts] = [opts, ->]

    opts.forceKillTimeout ?= process.env.FORCE_KILL_TIMOUT
    opts.host             ?= process.env.HOST
    opts.port             ?= process.env.PORT
    opts.restartCooldown  ?= process.env.RESTART_COOLDOWN
    opts.socketTimeout    ?= process.env.SOCKET_TIMEOUT
    opts.workers          ?= process.env.WORKERS

    master = new Master serverModule, opts
    master.run cb
    master

module.exports = wrapper
