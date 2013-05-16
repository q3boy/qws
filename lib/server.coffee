{Message}      = require './message'
{EventEmitter} = require 'events'
os             = require 'options-stream'
class Server extends EventEmitter
  constructor : (@server, options) ->
    @options = os {
      url                : '/ws'
      deflate            : true
      min_deflate_length : 32
    }, options

    server.on 'upgrade', (req, socket) =>
      @emit 'connect', new Message req, socket, @options

exports.Server = Server
