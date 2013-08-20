#mocha
zlib  = require 'zlib'
e     = require 'expect.js'
frame = require '../lib/frame'

describe 'WebSocket Frame', ->
  describe 'unpack', ->
    assertFrame = (f, props) ->
      exp =
        fin: true
        rsv1: false
        rsv2: false
        rsv3: false
        opcode: 'text'
        mask: false
        length: 0
        data: null
        done: true
      exp[k] = props[k] for k of props
      e(f).to.eql exp
    describe 'no compressed', ->

      describe 'single chunk', ->
        it 'with mask', ->
          bin = new Buffer [0x81, 0x83, 0xf8, 0xc1, 0x07, 0x08, 0x99, 0xa3, 0x64]
          [f] = frame.unpack bin
          assertFrame f,
            length  : 3
            mask    : true
            maskKey : new Buffer [0xf8, 0xc1, 0x07, 0x08]
            data    : new Buffer [0x61, 0x62, 0x63]
        it 'without mask', (done)->
          bin = new Buffer [0x81, 0x03, 0x61, 0x62, 0x63]
          [f] = frame.unpack bin
          assertFrame f,
            length  : 3
            data    : new Buffer [0x61, 0x62, 0x63]
          frame.inflate f, (err, f) ->
            assertFrame f,
              length  : 3
              data    : new Buffer [0x61, 0x62, 0x63]
              done()
        it 'length is 0', ->
          bin = new Buffer [0x81, 0x00]
          [f] = frame.unpack bin
          assertFrame f,
            length  : 0
            data    : null
      describe 'multi chunks', ->
        it '3 chunks with mask', ->
          bin1 = new Buffer [0x81, 0x83, 0xf8, 0xc1, 0x07, 0x08, 0x99]
          bin2 = new Buffer [0xa3]
          bin3 = new Buffer [0x64]
          exp =
            length  : 3
            mask    : true
            maskKey : new Buffer [0xf8, 0xc1, 0x07, 0x08]
            data    : [new Buffer [0x99]]
            done    : false
            left    : 2
          [f] = frame.unpack bin1
          assertFrame f, exp
          exp.data.push new Buffer [0xa3]
          exp.left--
          frame.unpack bin2, f
          assertFrame f, exp
          frame.unpack bin3, f
          assertFrame f,
            length  : 3
            mask    : true
            maskKey : new Buffer [0xf8, 0xc1, 0x07, 0x08]
            data    : new Buffer [0x61, 0x62, 0x63]

    describe 'compressed', ->
      it 'single chunk', (done)->
        bin = new Buffer [0xc1, 0x85, 0x2c, 0x12, 0x5c, 0x24, 0x66, 0x5e, 0x16, 0x22, 0x2c]
        [f] = frame.unpack bin
        frame.inflate f, (err, f) ->
          assertFrame f,
            rsv1    : true
            length  : 5
            mask    : true
            maskKey : new Buffer [0x2c, 0x12, 0x5c, 0x24]
            data    : new Buffer [0x61, 0x62, 0x63]
          done()
      it 'error frame', (done)->
        bin = new Buffer [0xc1, 0x85, 0x2c, 0x12, 0x5c, 0x24, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa]
        [f] = frame.unpack bin
        frame.inflate f, (err, f) ->
          e(err).to.not.be.empty()
          done()
    describe 'on chunk multi frame', ->
      it '"111" * 4', (done)->
        buf = new Buffer [
          0xc1, 0x85, 0xe8, 0x31, 0x95, 0xf2, 0xda, 0x03, 0xa7, 0xf0, 0xe8, 
          0xc1, 0x85, 0x16, 0x49, 0xa2, 0x25, 0x24, 0x7f, 0x94, 0x23, 0x16, 
          0xc1, 0x85, 0xad, 0x85, 0x1a, 0x45, 0x9f, 0xb4, 0x2b, 0x44, 0xad]
        # 1st part
        [f, buf] = frame.unpack buf
        frame.inflate f, (err, f) ->
          assertFrame f, 
          rsv1 : true
          length : 5
          data : new Buffer '222'
          mask : true
          maskKey : new Buffer [0xe8, 0x31, 0x95, 0xf2]

          # 2nd part
          [f, buf] = frame.unpack buf
          # console.log f
          frame.inflate f, (err, f) ->
            assertFrame f, 
            rsv1 : true
            length : 5
            data : new Buffer '333'
            mask : true
            maskKey : new Buffer [0x16, 0x49, 0xa2, 0x25]

            # 3rd part
            [f, buf] = frame.unpack buf
            # console.log f
            frame.inflate f, (err, f) ->
              assertFrame f, 
              rsv1 : true
              length : 5
              data : new Buffer '444'
              mask : true
              maskKey : new Buffer [0xad, 0x85, 0x1a, 0x45]
              done()

  describe 'pack', ->
    describe 'no compressed', ->
      it 'without mask', (done)->
        f = new frame.Frame
          rsv1 : true
          rsv2 : true
          rsv3 : true
          fin : true
          data : new Buffer [0x61, 0x62, 0x63, 0x61, 0x62, 0x63]
        f.pack false, (err, bin) ->
          [f1] = frame.unpack bin
          e(f1.rsv1).to.eql f.rsv1
          e(f1.rsv2).to.eql f.rsv2
          e(f1.rsv3).to.eql f.rsv3
          e(f1.fin).to.eql  f.fin
          e(f1.data).to.eql f.data
          done()
      it 'with mask', (done)->
        f = new frame.Frame
          data : 'abcabc'
          mask : true
        f.pack false, (err, bin) ->
          [f1] = frame.unpack bin
          e(f1.data.toString()).to.be f.data
          e(f1.mask).to.be true
          done()

      it '256 bytes data', (done)->
        f = new frame.Frame
          data : new Buffer 256
        f.pack false, (err, bin) ->
          [f1] = frame.unpack bin
          e(f1.data).to.eql f.data
          done()
      it '80000 bytes data', (done)->
        f = new frame.Frame
          data : new Buffer 80000
        f.pack false, (err, bin) ->
          [f1] = frame.unpack bin
          e(f1.data).to.eql f.data
          done()

      it 'empty data', (done) ->
        f = new frame.Frame
        f.pack false, (err, bin) ->
          [f1] = frame.unpack bin
          e(f1.data).to.be null
          done()

    describe 'compressed', ->
      it 'without mask', (done)->
        f = new frame.Frame
          data : new Buffer [0x61, 0x62, 0x63, 0x61, 0x62, 0x63]
          minDeflateLength : 3
        f.pack true, (err, bin) ->
          [f1] = frame.unpack bin
          frame.inflate f1, (err, f1) ->
            e(f1.data).to.eql f.data
            done()
      it 'with mask', (done)->
        f = new frame.Frame
          data : new Buffer [0x61, 0x62, 0x63, 0x61, 0x62, 0x63]
          mask : true
          minDeflateLength : 3
        f.pack true, (err, bin) ->
          [f1] = frame.unpack bin
          frame.inflate f1, (err, f1) ->
            e(f1.data).to.eql f.data
            e(f1.mask).to.be true
            done()
      it 'skip when length is not enough', (done)->
        f = new frame.Frame
          data : new Buffer [0x61, 0x62, 0x63, 0x61, 0x62, 0x63]
        f.pack true, (err, bin) ->
          [f1] = frame.unpack bin
          e(f1.data).to.eql f.data
          done()
      it 'opcode error', (done)->
        f = new frame.Frame opcode : 'asdasd'
        f.pack true, (err, bin) ->
          e(err.message).to.be 'Opcode Not Found "asdasd"'
          done()
