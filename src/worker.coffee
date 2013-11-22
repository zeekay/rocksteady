# pull out various env variables set by master
{ NODE_ENV
  FORCE_KILL_TIMEOUT
  PORT
  SERVER_MODULE
  SOCKET_TIMEOUT
  DROP_PRIVILEGES
  SET_GID
  SET_UID } = process.env

# try to resolve server_module, if this fails, assume it's coffeescript
try
  require.resolve SERVER_MODULE
catch err
  require 'coffee-script'

http  = require 'http'
utils = require './utils'
(require 'postmortem').install()

shuttingDown = false
server       = null

# shutdown worker
shutdown = ->
  return if shuttingDown
  shuttingDown = true

  server.close -> process.exit 0

  setTimeout ->
    process.exit 0
  , FORCE_KILL_TIMEOUT

# marshal runtime errors back to master process
process.on 'uncaughtException', (err) ->
  process.send type: 'error', error: utils.serialize err
  shutdown()

# handle shutdown gracefully
process.on 'message', (message) ->
  return if shuttingDown or not message?.type

  switch message.type
    when 'stop'
      shutdown()

# detect modules being used by server and notify master to watch them for changes
if NODE_ENV == 'development'
  require('vigil').vm (filename, stats) ->
    process.send
      type: 'watch',
      filename: filename
      isDirectory: stats.isDirectory()

  # require server and attach bebop to serve static files
  server = require('bebop').middleware attach: (require SERVER_MODULE), port: 3456
else
  # simply require server
  server = require SERVER_MODULE

unless server instanceof http.Server
  server = http.createServer server

server.listen PORT, ->
  if DROP_PRIVILEGES and process.getgid() == 0
    process.setgid SET_GID
    process.setuid SET_UID

server.setTimeout SOCKET_TIMEOUT

# handle shutdown
process.on 'SIGTERM', -> shutdown()
process.on 'SIGINT', -> shutdown()
