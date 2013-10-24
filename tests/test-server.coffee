#mocha
e = require 'expect.js'
ws = require '../lib/index.js'
http = require 'http'
net = require 'net'
{EventEmitter} = require 'events'

describe 'WebSocket Server', ->
  hs = null
  port = null
  beforeEach (done)->
    hs = new http.Server();
    hs.on 'listening', ->
      {port} = hs.address()
      done()
    hs.listen()

  afterEach (done)->
    hs.close ->
      setTimeout done, 50

  req = (bin, cb, cbhs) ->
    client = net.connect port:port
    client.on 'connect', ->
      client.write '''
        GET ws://localhost:8080/ws HTTP/1.1
        Origin: http://localhost:8080
        Host: localhost:8080
        Sec-WebSocket-Key: TtP40xnf6AdhK2cpyo7vCw==
        Upgrade: websocket
        Sec-WebSocket-Extensions: x-webkit-deflate-frame
        Connection: Upgrade
        Sec-WebSocket-Version: 13\r\n\r\n
      '''
      handShake = null
      client.once 'data', (chunk)->
        handShake = chunk.toString()
        cbhs handShake if cbhs
        client.write bin
        client.once 'data', (chunk) ->
          cb handShake, chunk if cb
  it 'createServer', (done) ->
    w = ws.createServer hs, (data, msg) ->
      e(data).to.be 'abc'
      msg.close()
      done()
    req bin = new Buffer [0x81, 0x03, 0x61, 0x62, 0x63]
    e(w).to.be.a ws.Server
  it 'createServer compressed', (done) ->
    w = ws.createServer hs, (data, msg) ->
      e(data).to.be 'abc'
      msg.close()
      done()
    req new Buffer [0xc1, 0x85, 0x2c, 0x12, 0x5c, 0x24, 0x66, 0x5e, 0x16, 0x22, 0x2c]
  it 'createFrame', ->
    f = ws.createFrame data : new Buffer [0x61, 0x62, 0x63, 0x61, 0x62, 0x63]
    e(f).to.be.a ws.Frame
  it 'create server but url not matched', (done)->
    w = ws.createServer hs, url : '/aa', (data, msg) ->
      # e(data).to.be 'abc'
      # msg.close()
      # done()
    req (bin = new Buffer [0x81, 0x03, 0x61, 0x62, 0x63]), null, (handShake) ->
      # console.log handShake
      e(handShake).to.be.match /^HTTP\/1\.1 101/
      e(handShake).to.be.match /HTTP\/1\.1 400/
      e(handShake).to.be.match /url not matched/
      done()
    # e(w).to.be.a ws.Server


class MockSocket extends EventEmitter
  constructor : ->
    @data = []
  toString : ->
    d = ''
    d += chunk.toString() for chunk in @data
    d
  write : (chunk) -> @data.push chunk
  end : (data)->
    @write data if data?
    @emit 'end'
  mdata : (data)->
    @emit 'data', data
  merror : (err)-> @emit 'error', err
  mclose : -> @emit 'close'
  mreset : -> @data = []

req = (props = {})->
  r =
    url     : props.url or '/ws'
    headers :
      upgrade                    : props.upgrade or 'websocket'
      'sec-websocket-version'    : props.version or '13'
      'origin'                   : props.origin  or 'http://localhost:8080'
      'host'                     : 'localhost:8080'
  unless props.key is false
    r.headers['sec-websocket-key'] = props.key or 'abcde'
  r.headers['sec-websocket-extensions'] = 'x-webkit-deflate-frame'
  r

describe 'WebSocket handShake', ->
  hs = null
  port = null
  beforeEach (done)->
    hs = new http.Server();
    hs.on 'listening', ->
      {port} = hs.address()
      done()
    hs.listen()

  afterEach (done)->
    hs.close ->
      setTimeout done, 50

  describe 'hand shake', ->
    describe 'success', ->
      it 'without cross domain', ->
        ws.createServer hs, (data, msg) ->
        s = new MockSocket
        hs.emit 'upgrade', req(), s
        e(s.toString()).to.be '''
          HTTP/1.1 101 Switching Protocols\r
          Upgrade: websocket\r
          Connection: Upgrade\r
          Sec-WebSocket-Accept: 8m4i+0BpIKblsbf+VgYANfQKX4w=\r
          Sec-WebSocket-Extensions: x-webkit-deflate-frame\r
          Sec-WebSocket-Origin: http://localhost:8080\r
          Sec-WebSocket-Location: ws://localhost:8080/ws\r\n\r\n
        '''
      it 'with cross domain', ->
        ws.createServer hs, origins : ['http://a/aa/'], (data, msg) ->
        s = new MockSocket
        hs.emit 'upgrade', req(origin : 'http://a/aa'), s
        e(s.toString()).to.be '''
          HTTP/1.1 101 Switching Protocols\r
          Upgrade: websocket\r
          Connection: Upgrade\r
          Sec-WebSocket-Accept: 8m4i+0BpIKblsbf+VgYANfQKX4w=\r
          Sec-WebSocket-Extensions: x-webkit-deflate-frame\r
          Sec-WebSocket-Origin: http://a/aa\r
          Sec-WebSocket-Location: ws://localhost:8080/ws\r\n\r\n
        '''
      it 'with two servers', ->
        ws.createServer hs, (data, msg) ->
        ws.createServer hs, url : '/test', (data, msg) ->
        s = new MockSocket
        hs.emit 'upgrade', req(url : '/test'), s
        e(s.toString()).to.be '''
          HTTP/1.1 101 Switching Protocols\r
          Upgrade: websocket\r
          Connection: Upgrade\r
          Sec-WebSocket-Accept: 8m4i+0BpIKblsbf+VgYANfQKX4w=\r
          Sec-WebSocket-Extensions: x-webkit-deflate-frame\r
          Sec-WebSocket-Origin: http://localhost:8080\r
          Sec-WebSocket-Location: ws://localhost:8080/test\r\n\r\n
        '''
    describe 'fail when', ->
      failTest = (prop, txt)->
        ws.createServer hs, (data, msg) ->
        s = new MockSocket
        hs.emit 'upgrade', req(prop), s
        e(s.toString()).to.be "HTTP/1.1 400 Bad Request\r\n\r\n#{txt}\r\n"
      it 'protocol not match', -> failTest url : 'ws1://a/aa', 'protocol not match'
      it 'upgrade not match',  -> failTest upgrade : 'aaa'   , 'upgrade not match'
      it 'version not match',  -> failTest version : '14'    , 'version not match'
      it 'key missed',         -> failTest key : false       , 'key missed'
    describe 'error when', ->
      it 'domain is not allowed', -> 
        ws.createServer hs, (data, msg) ->
        s = new MockSocket
        hs.emit 'upgrade', req(origin : 'http://a/aa'), s
        e(s.toString()).to.be '''
          HTTP/1.1 101 Switching Protocols\r
          Upgrade: websocket\r
          Connection: Upgrade\r
          Sec-WebSocket-Accept: 8m4i+0BpIKblsbf+VgYANfQKX4w=\r
          Sec-WebSocket-Extensions: x-webkit-deflate-frame\r
          Sec-WebSocket-Origin: http://a/aa\r
          Sec-WebSocket-Location: ws://localhost:8080/ws\r\n\r
          \ufffd=HTTP/1.1 403 Forbidden\r\n\r
          Origin http://a/aa is not allowed\r\n\ufffd\u0000
        '''