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
      if result = @_handShake req, socket
        socket.end "HTTP/1.1 400 Bad Request\r\n\r\n#{result}\r\n"
        return

      msg = new Message socket, {deflate:false}

      {path} = urlParse req.url

      for config in @serverConfigList
        if path is config.url
          if result = @_domainCheck req, config
            msg.errorHandle "HTTP/1.1 403 Forbidden\r\n\r\n#{result}\r\n"
            return
          msg.reset config
          return @emit 'connect', msg

      msg.errorHandle 'HTTP/1.1 400 Bad Request\r\n\r\nurl not matched\r\n'
      return

  addServer : (options, cb) ->
    serverConfig = os {
      url                : '/ws'
      deflate            : false
      min_deflate_length : 32
      origins            : []
      cb                 : cb
    }, options

    if serverConfig.origins.length
      serverConfig.origins[i] = origin.replace /\/$/g, '' for origin, i in serverConfig.origins

    @serverConfigList.push serverConfig


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
    false

  _domainCheck : (req, config) ->
    origins = config.origins
    {host} = urlParse req.headers.origin
    reqOrigin = req.headers.origin.replace /\/$/g, ''

    if host isnt req.headers.host
      for origin in origins
        return false if origin is reqOrigin
      return "Origin #{req.headers.origin} is not allowed"
    false

exports.Server = Server
