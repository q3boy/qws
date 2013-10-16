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
    @server.__QWS_NUM = 0 unless @server.__QWS_NUM 
    @server.__QWS_NUM++

    server.on 'upgrade', (req, socket) =>
      socket.__QWS_NUM = @server.__QWS_NUM unless socket.__QWS_NUM
      try 
        msg = new Message req, socket, @options
      catch e
        if 'URLNOTMATCHED' is e.message 
          if 0 is --socket.__QWS_NUM
            socket.end 'HTTP/1.1 400 Bad Request\r\n\r\nurl not matched\r\n'
          return
        else
          throw e
        
      @emit 'connect', msg
      return

exports.Server = Server
