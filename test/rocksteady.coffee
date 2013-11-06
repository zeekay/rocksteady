rocksteady = require '../lib'
request    = require 'request'

describe 'rocksteady', ->
  describe '#run', ->
    it 'should run server module', (done) ->
      rocksteady.run __dirname + '/assets/server', port: 3333, logger: false, ->
        request 'http://localhost:3333', (err, res, body) ->
          body.should.eq 'hi'
          done()

    it 'should fail to run server module with error', (done) ->
      rocksteady.run __dirname + '/assets/server-error', port: 3333, logger: false, ->
        request 'http://localhost:3333', (err, res, body) ->
          body.should.eq 'hi'
          done()
