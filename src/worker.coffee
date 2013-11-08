try
  require 'coffee-script'
catch err

(require 'postmortem').install()

# pull out various env variables set by master
{ NODE_ENV
  FORCE_KILL_TIMEOUT
  PORT
  SERVER_MODULE
  SOCKET_TIMEOUT
  DROP_PRIVILEGES
  SET_GID
  SET_UID } = process.env

shuttingDown = false

# serialize exceptions
serialize = (err) ->
  message:              err.message
  name:                 err.name
  stack:                err.stack
  structuredStackTrace: err.structuredStackTrace

# shutdown worker
shutdown = ->
  return if shuttingDown
  shuttingDown = true

  try
    server.close -> process.exit 0
  catch _

  setTimeout ->
    process.exit 0
  , FORCE_KILL_TIMEOUT

# marshal runtime errors back to master process
process.on 'uncaughtException', (err) ->
  process.send type: 'error', error: serialize err
  shutdown()

# handle shutdown gracefully
process.on 'message', (message) ->
  return if shuttingDown or not message?.type

  switch message.type
    when 'stop'
      shutdown()

# detect modules being used by server and notify master to watch them for changes
if NODE_ENV == 'development'
  bebop = require 'bebop'
  vigil = require 'vigil'

  vigil.vm (filename, stats) ->
    process.send type: 'watch',
      filename: filename
      isDirectory: stats.isDirectory()

  # require server and attach bebop to serve static files
  server = bebop.middleware require SERVER_MODULE
else
  # simply require server
  server = require SERVER_MODULE

# begin listening
server.listen PORT, ->
  if DROP_PRIVILEGES and process.getgid() == 0
    process.setgid SET_GID
    process.setuid SET_UID

# set socket timeout
server.setTimeout SOCKET_TIMEOUT

# handle shutdown
process.on 'SIGTERM', -> shutdown()
process.on 'SIGINT', -> shutdown()
