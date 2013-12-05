args = process.argv.slice 2

error = (message) ->
  console.error message
  process.exit 1

usage = ->
  console.log '''
  rocksteady server.js [options]

  Options:
    --host             Specify host address to bind to, defaults to localhost.
    --port             Specify port to listen on.
    --workers          Number of workers to start.
    --restart-cooldown Seconds to wait before respawning workers that die.
    --force-kill       Seconds to wait before killing unresponsive worker.
    --watch            Watch for and reload server/browser on changes.
  '''
  process.exit 0

serverModule = args.shift()

while opt = args.shift()
  switch opt
    when '--host', '-h'
      host = args.shift()
    when '--port', '-p'
      port = parseInt args.shift(), 10
    when '--workers', '-n'
      workers = parseInt args.shift(), 10
    when '--force-kill'
      forceKillTimeout = parseInt args.shift(), 10
    when '--restart-cooldown'
      restartCooldown = parseInt args.shift(), 10
    when '--watch', '-w'
      watch = true
    when '--help', '-h'
      usage()
    else
      if opt.charAt(0) == '-'
        error 'Unrecognized option'

unless serverModule?
  usage()

require('./').run serverModule,
  forceKillTimeout: forceKillTimeout
  host:             host
  port:             port
  restartCooldown:  restartCooldown
  workers:          workers
