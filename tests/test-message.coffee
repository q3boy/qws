#mocha
e                        = require 'expect.js'
zlib                     = require 'zlib'
{EventEmitter}           = require 'events'
{Message}                = require '../lib/message'
{Frame, unpack, inflate} = require '../lib/frame'

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

describe 'WebSocket Message', ->
  prepare = -> [s = new MockSocket(), new Message(s)]
  describe 'got message', ->
    frame = (prop, cb)->
      f = new Frame
        rsv1 : true
        rsv2 : false
        rsv3 : false
        fin : true
        data : new Buffer [0x61, 0x62, 0x63, 0x61, 0x62, 0x63]
      for k of prop
        f[k] = prop[k]
      f.pack true, cb
    describe 'text frame', ->
      it '1 chunk', (done)->
        [s, m] = prepare()
        frame {}, (err, bin) ->
          m.on 'message', (msg)->
            e(msg).to.be 'abcabc'
            done()
          s.mdata bin
      it '2 chunks masked', (done)->
        [s, m] = prepare()
        frame {mask : true}, (err, bin) ->
          m.on 'message', (msg)->
            e(msg).to.be 'abcabc'
            done()
          process.nextTick -> s.mdata bin.slice 0, 6
          process.nextTick -> s.mdata bin.slice 6
      it '3 chunks', (done)->
        [s, m] = prepare()
        frame {}, (err, bin) ->
          m.on 'message', (msg)->
            e(msg).to.be 'abcabc'
            done()
          process.nextTick -> s.mdata bin.slice 0, 4
          process.nextTick -> s.mdata bin.slice 4, 6
          process.nextTick -> s.mdata bin.slice 6
      it '2 chunks 3 frames', (done) ->
        [s, m] = prepare()
        flag = 0
        frame {}, (err, bin) ->
          m.on 'message', (msg)->
            switch ++flag
              when 1 then e(msg).to.be 'abcabc'
              when 2 then e(msg).to.be 'abcabc'
              when 3 
                e(msg).to.be 'abcabc'
                done()
              else 
                e(false).to.be true
                done()
          process.nextTick -> s.mdata Buffer.concat [bin, bin.slice(0, 4)]
          process.nextTick -> s.mdata Buffer.concat [bin.slice(4), bin]
      it 'error chunk', (done)->
        [s, m] = prepare()
        data = new Buffer 64
        data.fill 'a'
        frame {data : data}, (err, bin) ->
          bin.fill 0, 2, 8
          m.on 'error', (err)->
            done()
          s.mdata bin
    describe 'other opcodes', ->
      opcodeTest = (code, event, done) ->
        [s, m] = prepare()
        frame {opcode : code}, (err, bin) ->
          m.on event, done
          s.mdata bin

      it 'binary', (done) ->
        [s, m] = prepare()
        frame {opcode : 'binary'}, (err, bin) ->
          m.on 'message', (msg)->
            e(msg).to.be.a Buffer
            e(msg.toString()).to.be 'abcabc'
            done()
          s.mdata bin
      it 'ping', (done)     -> opcodeTest 'ping', 'ping', done
      it 'pong', (done)     -> opcodeTest 'pong', 'pong', done
      it 'continue', (done) -> opcodeTest 'continue', 'continue', done
      it 'close', (done)    -> opcodeTest 'close', 'close', done
  describe 'write', ->
    inflateStream = null
    beforeEach ->
      inflateStream = zlib.createInflateRaw()
    it 'short text', (done) ->
      [s, m] = prepare()
      s.mreset()
      txt = 'some short text'
      m.write txt, (err)->
        inflate unpack(s.data[0])[0], inflateStream, (err, frame)->
          e(frame.fin).to.be true
          e(frame.rsv1).to.be false
          e(frame.data.toString()).to.be txt
          done()
    it 'long text', (done) ->
      [s, m] = prepare()
      s.mreset()
      txt = 'some long text'
      txt += txt
      txt += txt
      txt += txt
      m.write txt, (err)->
        inflate unpack(s.data[0])[0], inflateStream, (err, frame)->
          e(frame.fin).to.be true
          e(frame.rsv1).to.be true
          e(frame.data.toString()).to.be txt
          done()
    opcodeTest = (code, done) ->
      [s, m] = prepare()
      s.mreset()
      m[code] (err)->
        frame = unpack(s.data[0])[0]
        e(frame.opcode).to.be code
        done()
    it 'ping', (done) -> opcodeTest 'ping', done
    it 'pong', (done) -> opcodeTest 'pong', done
    it 'continue', (done) -> opcodeTest 'continue', done
    it 'with mask', (done) ->
      [s, m] = prepare()
      s.mreset()
      txt = 'with mask'
      m.write txt, true, (err)->
        [frame] = unpack(s.data[0])
        e(frame.mask).to.be true
        e(frame.data.toString()).to.be txt
        done()
    it 'with opcode and mask', (done) ->
      [s, m] = prepare()
      s.mreset()
      txt = 'with opcode and mask'
      m.write txt, 'binary', true, (err)->
        [frame] = unpack(s.data[0])
        e(frame.opcode).to.be 'binary'
        e(frame.mask).to.be true
        e(frame.data.toString()).to.be txt
        done()
    it 'write raw', ->
      [s, m] = prepare()
      s.mreset()
      m.writeRaw new Buffer 'abc'
      e(s.data[0].toString()).to.be 'abc'
    it 'opcode error', (done) ->
      [s, m] = prepare()
      s.mreset()
      m.write '', 'some others', (err)->
        e(err).to.be.an Error
        e(err.message).to.not.empty()
        done()
  describe 'others case', ->
    it 'pass error from socket', (done)->
      [s, m] = prepare()
      etxt = 'err'
      m.on 'error', (err) ->
        e(err).to.be etxt
        done()
      s.merror etxt
    it 'pass close from socket', (done)->
      [s, m] = prepare()
      m.on 'close', done
      s.mclose()
    it 'end with data', (done)->
      [s, m] = prepare()
      s.mreset()
      txt = 'end'
      s.on 'end', ->
        [frame] = unpack(s.data[0])
        e(frame.data.toString()).to.be txt
        done()
      m.end txt
    it 'end without data', (done)->
      [s, m] = prepare()
      s.on 'end', done
      m.end()
    it 'close', (done)->
      [s, m] = prepare()
      s.on 'end', done
      m.close()
