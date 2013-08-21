os                       = require 'options-stream'
crypto                   = require 'crypto'
zlib                    = require 'zlib'
{parse: urlParse}        = require 'url'
{EventEmitter}           = require 'events'
{unpack, inflate, Frame} = require './frame'
class Message extends EventEmitter
  constructor : (@req, @socket, options)->
    @options = os {
      url                : '/ws'
      deflate            : true
      min_deflate_length : 32
      close_timeout      : 100
    }, options
    @deflated = false
    unless true is msg = @handShake()
      @socket.end 'HTTP/1.1 400 Bad Request\r\n\r\n' + msg + "\r\n"
      return

    frame = null
    @inflate = zlib.createInflateRaw chunkSize : 128 * 1024
    socket.on 'data', (chunk)=>
      # first chunk
      # if frame is null
      while chunk and chunk.length
        [frame, chunk] = unpack chunk, frame
      # 2+ chunks
      # else
        # [frame, buf] = unpack chunk, frame
      # if done
        if frame.done
          # decompress
          inflate frame, @inflate, (err, f) =>
            return @emit 'error', err if err
            # emit event
            @onFrame f
          # reset frame
          frame = null

    socket.on 'error', (err)=>
      @emit 'error', err

    socket.on 'close', =>
      @emit 'close'

  write : (data, opcode, mask, cb) ->
    # mask
    if typeof mask is 'function'
      cb = mask
      mask = null
    # opcode
    switch typeof opcode
      when 'function'
        cb = opcode
        opcode = null
      when 'boolean'
        mask = opcode
        opcode = null

    # text frame as defalut
    opcode ?= 'text'
    # no mask as defalut
    mask ?= false
    # data is frame
    # if data instanceof Frame
    #   frame = data
    # else
    frame = new Frame
      data             : data
      opcode           : opcode
      fin              : true
      mask             : mask
      minDeflateLength : @options.min_deflate_length
    # pack
    frame.pack @deflated, (err, bin) =>
      if err
        cb err if cb
        return
      # write
      @socket.write bin
      cb null if cb
    return

  ping : (cb)->
    @write '', 'ping', false, cb
    return

  pong : (cb)->
    @write '', 'pong', false, cb
    return

  continue : (cb)->
    @write '', 'continue', false, cb
    return

  writeRaw : (bin) ->
    @socket.write bin


  end : (data, opcode, mask)->
    if data?
      @write data, opcode, mask, =>
        @close()
    else
      @close()
    return

  close : ->
    closed = false
    @write '', 'close', false, =>
      @socket.on 'close', (err)=>
        clearTimeout timer
        closed = true
        @emit 'closed', err
      timer = setTimeout =>
        return if closed
        @socket.end()
      , @options.close_timeout

  onFrame : (frame) ->
    switch frame.opcode
      when 'text' then @emit 'message', frame.data.toString(), @
      when 'binary' then @emit 'message', frame.data, @
      when 'ping' then @emit 'ping'
      when 'pong' then @emit 'pong'
      when 'close'
        @socket.end()
        @emit 'close'
      when 'continue' then @emit 'continue'
      # else @emit 'control', frame.opcode
    return

  handShake : ->
    req = @req

    {path} = uinfo = urlParse req.url
    return 'protocol not match' if uinfo.protocol and uinfo.protocol isnt 'ws:'
    # request check
    return 'url not match' unless path is @options.url
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
      Sec-WebSocket-Accept: #{sign}\r\n
    """

    # handOrigin
    # self.client.send("Sec-WebSocket-Origin: " + headers["Origin"] + "\r\n")

    # use deflate
    if @options.deflate and req.headers['sec-websocket-extensions'] is 'x-webkit-deflate-frame'
      @deflated = true
      head += "Sec-WebSocket-Extensions: x-webkit-deflate-frame\r\n"
    head += "\r\n"

    # send response
    @socket.write head
    true
exports.Message = Message
