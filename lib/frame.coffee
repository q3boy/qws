zlib   = require 'zlib'
crypto = require 'crypto'

# mask & unmask data
unmask = (data, mask) ->
  d1 = new Buffer data.length
  for i in [0...data.length] by 4
    d1[i+3] = data[i+3] ^ mask[3]
    d1[i+2] = data[i+2] ^ mask[2]
    d1[i+1] = data[i+1] ^ mask[1]
    d1[i] = data[i] ^ mask[0]

  mod = data.length % 4
  d1[i]   = data[i]   ^ mask[0] if mod > 0
  d1[i+1] = data[i+1] ^ mask[0] if mod > 1
  d1[i+2] = data[i+2] ^ mask[0] if mod > 2
  d1


# inflate frame
inflate = (frame, stream, cb) ->
  return cb null, frame unless frame.rsv1
  stream.once 'error', (err) ->
    cb err
  stream.once 'data', (data) ->
    frame.data = data
    cb null, frame
  len = frame.data.length
  b = new Buffer len + 4
  b[len] = 0x00
  b[len+1] = 0x00
  b[len+2] = 0xff
  b[len+3] = 0xff
  frame.data.copy b
  stream.write b
  return
  # zlib.inflateRaw frame.data, (err, data) ->
  #   return cb err if err
  #   frame.data = data
  #   cb null, frame


# opcodes defines
opcodes = [
  'continue', 'text', 'binary'
  'non-control 3', 'non-control 4', 'non-control 5', 'non-control 6',' non-control 7'
  'close', 'ping', 'pong'
  'control B', 'control C', 'control D', 'control E',' control F'
]

# unpack frame
unpack = (buf, frame) ->

  # 2+ chunks
  if frame
    if buf.length > frame.left
      frame.data.push buf.slice 0, frame.left
      buf = buf.slice frame.left
      frame.left = 0
    else 
      frame.data.push buf
      frame.left -= buf.length
      buf = null
  # first chunk
  else
    b1 = buf[0]
    b2 = buf[1]
    frame =
      # first byte
      fin    : 0 < (b1 & 0x80)
      rsv1   : 0 < (b1 & 0x40)
      rsv2   : 0 < (b1 & 0x20)
      rsv3   : 0 < (b1 & 0x10)
      opcode : opcodes[b1 & 0xf]
      # second byte
      mask   : 0 < (b2 & 128)
      length : b2 & 127
      data   : []
      left   : 0
      done   : false

    idx = 2
    if frame.length > 0
      # mid length
      if frame.length is 126
        frame.length = buf.readUInt16BE(2, true)
        idx = 4
      # long length
      else if frame.length is 127
        frame.length = buf.readUInt32BE(2, true) * 0xffffffff +  buf.readUInt32BE(6, true)
        idx = 10

      # maskkey
      frame.maskKey = buf.slice idx, idx +=4 if frame.mask
      # set data chunk
      frame.data.push buf.slice idx, idx += frame.length
      # calc left bytes
      frame.left = frame.length - frame.data[0].length

    # cut buffer
    if buf.length > idx
      buf = buf.slice idx
    else 
      buf = null


  # check done
  if frame.left is 0
    # not empty frame
    if frame.length > 0
      # concat to one big buffer
      frame.data = Buffer.concat frame.data
      # unmask
      frame.data = unmask frame.data, frame.maskKey if frame.mask and frame.length > 0
    else frame.data = null
    frame.done = true
    # remove left
    delete frame.left

  [frame, buf]

pack = (frame, data) ->
  # set first byte
  b1  = opcodesMap[frame.opcode]
  b1 |= 0x10 if frame.rsv3
  b1 |= 0x20 if frame.rsv2
  b1 |= 0x40 if frame.rsv1
  b1 |= 0x80 if frame.fin


  dlen = if data? then data.length else 0

  # length flag
  if dlen > 0xffff
    lenFix = 10
    plen = 127
  else if dlen >= 126
    lenFix = 4
    plen = 126
  else
    lenFix = 2
    plen = dlen

  # no mask if no data
  if dlen is 0
    frame.mask = false

  # second byte
  b2 = plen


  # use mask
  if frame.mask
    b2 |= 0x80
    buf = new Buffer lenFix + 4 + dlen
    frame.maskKey = crypto.randomBytes(4)
    frame.maskKey.copy buf, lenFix
    lenFix += 4
    data = unmask(data, frame.maskKey)
  else
    buf = new Buffer lenFix + dlen

  buf[0] = b1
  buf[1] = b2

  # length extends
  if dlen > 0xffff
    buf.writeUInt32BE Math.floor(dlen / 0xffffffff), 2, true
    buf.writeUInt32BE dlen % 0xffffffff, 6, true
  else if dlen >= 126
    buf.writeUInt16BE dlen, 2, true

  if dlen > 0
  # set data
    data.copy buf, lenFix
  buf

opcodesMap =
  'continue' : 0,  'text'  : 1
  'binary'   : 2,  'close' : 8
  'ping'     : 9,  'pong'  : 10

class Frame
  constructor : (prop) ->
    @minDeflateLength = 32
    @opcode  = 'text'
    @fin     = false
    @rsv1    = false
    @rsv2    = false
    @rsv3    = false
    @mask    = false
    @data    = null

    (@[k] = prop[k] if prop) for k of prop

  pack : (deflate, cb) ->
    return cb new Error "Opcode Not Found \"#{@opcode}\"" unless opcodesMap[@opcode]?

    # data to buffer
    unless @data?
      data = null
    else if @data instanceof Buffer
      data = @data
    else
      data = new Buffer if typeof @data is 'string' then @data else @data.toString()

    # check length for deflate
    if deflate && data.length < @minDeflateLength
      deflate = false

    # if use deflate
    if deflate
      @rsv1 = true
      zlib.deflateRaw data, (err, data) =>
        # return cb err if err
        cb null, pack @, data
        return
    else
      @rsv1 = false
      cb null, pack @, data
    return



exports.unpack  = unpack
exports.inflate = inflate
exports.Frame   = Frame
