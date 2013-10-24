{Message}         = require './message'
{EventEmitter}    = require 'events'
{parse: urlParse} = require 'url'
crypto            = require 'crypto'
os                = require 'options-stream'
class Server extends EventEmitter
  constructor : (@server, options, cb) ->
    @serverConfigList = []
    @addServer options, cb

    server.on 'upgrade', (req, socket) =>
      unless true is result = @_handShake req, socket
        socket.end "HTTP/1.1 400 Bad Request\r\n\r\n#{result}\r\n"
        return

      try 
        msg = new Message socket, {deflate:false}
      catch e
        throw e

      {path} = urlParse req.url
      num = @serverConfigList.length

      for config in @serverConfigList
        if path is config.url
          unless true is result = @_domainCheck req, config
            msg.write "HTTP/1.1 403 Forbidden\r\n\r\n#{result}\r\n"
            msg.close()
            return
          msg.options = os msg.options, config
          msg.__QWS_CB = config.__cb
          break
        else if 0 is --num
          msg.write 'HTTP/1.1 400 Bad Request\r\n\r\nurl not matched\r\n'
          msg.close()
          return

      @emit 'connect', msg
      return

  addServer : (options, cb) ->
    @serverConfigList.push os {
      url                : '/ws'
      deflate            : false
      min_deflate_length : 32
      origins            : []
      __cb               : cb
    }, options

  _handShake : (req, socket) ->
    uinfo = urlParse req.url
    return 'protocol not match' if uinfo.protocol and uinfo.protocol isnt 'ws:'
    return 'upgrade not match' unless 'websocket' is req.headers.upgrade
    return 'version not match'  unless '13' is req.headers['sec-websocket-version']
    return 'key missed' unless req.headers['sec-websocket-key']

    # sign
    key  = req.headers['sec-websocket-key']
    sha1 = crypto.createHash 'sha1'
    sha1.update key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'
    sign = sha1.digest 'base64'

    # response header
    head = """
      HTTP/1.1 101 Switching Protocols\r
      Upgrade: websocket\r
      Connection: Upgrade\r
      Sec-WebSocket-Accept: #{sign}\r
      Sec-WebSocket-Extensions: x-webkit-deflate-frame\r
      Sec-WebSocket-Origin: #{req.headers.origin}\r
      Sec-WebSocket-Location: ws://#{req.headers.host + req.url}\r\n\r\n
    """
    socket.write head
    true

  _domainCheck : (req, config) ->
    origins = config.origins
    {host} = urlParse req.headers.origin
    flag = false

    if host isnt req.headers.host
      for origin in origins
        if origin.replace(/\/$/, '') is req.headers.origin
          flag = true
          break
      return "Origin #{req.headers.origin} is not allowed" unless flag
    true

exports.Server = Server
