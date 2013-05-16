#mocha
e = require 'expect.js'
ws = require '../lib/index.js'
http = require 'http'
net = require 'net'


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

  req = (bin, cb) ->
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

