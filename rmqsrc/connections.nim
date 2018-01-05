import deques, tables, net, options, logging, strutils, math, sequtils, asyncnet, asyncdispatch
import frame, spec, decode, methods, values, encode

type ConnectionEvent* = enum
  ceRead, ceWrite, ceError
const baseEvents = {ceRead, ceError}

type
  Channel = object
  ChannelTable = TableRef[int, Channel]
  ConnectionState* = enum
    csClosed,
    csInit,
    csProtocol,
    csStart,
    csTune,
    csOpen,
    csClosing

  ConnectionParameters = tuple
    host: string
    port: int
    username: string
    password: string

  Connection* = ref object
    state*: ConnectionState
    outboundBuffer: Deque[string]
    frameBuffer: string
    closingParams: ClosingParams
    eventState: set[ConnectionEvent]
    serverProperties*: Table[string, ValueNode]
    parameters: ConnectionParameters
    socket: Option[AsyncSocket]
    bytesSent, framesSent, bytesReceived, framesReceived: int
    channels: ChannelTable

  ConnectionDiagnostics = tuple
    bytesSent, framesSent, bytesReceived, framesReceived: int

  MessageContent = tuple
    properties: string
    body: string


proc `$`*(connection: Connection): string =
  "AMQP $#:$# ($#)" % [
    connection.parameters.host, $connection.parameters.port, $connection.state
  ]

proc onConnected(connection: Connection)
proc onDataAvailable*(connection: Connection, data: string)
proc flushOutbound(connection: Connection)
proc onConnectionStart(connection: Connection, methodFrame: Frame)
proc onCloseReady(connection: Connection)
proc onConnectionCloseOk(connection: Connection, _: Frame)

proc initConnection(connection: Connection, parameters: ConnectionParameters) =
  connection.eventState = baseEvents
  connection.socket = none(AsyncSocket)
  connection.parameters = parameters
  connection.outboundBuffer = initDeque[string]()
  connection.frameBuffer = ""
  connection.channels = newTable[int, Channel]()

proc newConnection*(parameters: ConnectionParameters): Connection =
  result = Connection()
  initConnection(result, parameters)

proc connect*(connection: Connection) =
  connection.state = csInit
  var socket = newAsyncSocket(buffered = false)
  try:
    info "Connecting to $# on $#" % [connection.parameters.host, $connection.parameters.port]
    asyncCheck socket.connect(connection.parameters.host, Port(connection.parameters.port))

    info "Connected."
    connection.socket = some(socket)
    connection.onConnected()

  except OSError:
    info "Connection to $# failed." % connection.parameters.host
    connection.state = csClosed

proc close*(connection: Connection, replyCode = 200, reply_text = "Normal shutdown") =
  info "$# Closing." % $connection

  # TODO: Close channels

  connection.state = csClosing

  connection.closingParams = (replyCode, reply_text)

  if connection.channels.len == 0:
    connection.onCloseReady()
  else:
    info "$# Waiting for $# channels to close." % [
      $connection, $connection.channels.len
    ]

proc getMethodCallback(cm: MethodId): proc(c: Connection, f: Frame) =
  case cm
  of mStart: result = onConnectionStart
  of mCloseOk: result = onConnectionCloseOk
  else:
    discard

proc processCallbacks(connection: Connection, frame: Frame): bool =
  case frame.kind
  of fkMethod:
    let callback = getMethodCallback(frame.rpcMethod.kind)
    callback(connection, frame)
    result = true
  else:
    result = false

proc send*(connection: Connection, msg: string) {.async.} =
  let socket = connection.socket.get()
  asyncCheck socket.send(msg)

proc recv*(connection: Connection): Future[int] {.async.} =
  var
    socket = connection.socket.get()
    data = newString(FRAME_MAX_SIZE)

  try:
    result = await socket.recvInto(addr data[0], FRAME_MAX_SIZE)
    data.setLen(result)
  except TimeoutError:
    discard

  if data.len > 0:
    connection.onDataAvailable(data)
  result = data.len

# Frame handling

proc readFrame(connection: Connection): DecodedFrame =
  info "$# Reading frame (buffer length: $#)" % [
    $connection, $connection.frameBuffer.len
  ]
  result = connection.frameBuffer.decode()

proc trimFrameBuffer(connection: Connection, length: int) =
  connection.frameBuffer.delete(0, length - 1)
  connection.bytesReceived += length

proc processFrame(connection: Connection, frame: Frame) =
  info "$# Processing frame: $#" % [$connection, $frame]
  connection.framesReceived += 1
  if connection.processCallbacks(frame):
    return

proc sendMessage(connection: Connection, channelNumber: ChannelNumber, rpcMethod: Method, content: MessageContent) =
  let length = content.body.len
  var writeBuf = @[
      initMethod(channelNumber, rpcMethod).marshal(),
      initHeader(channelNumber, length, content.properties).marshal()
    ]
  if length > 0:
    let chunks = (length / BODY_MAX_LENGTH).ceil.int
    for chunk in 0..<chunks:
      var
        bodyStart = chunk * BODY_MAX_LENGTH
        bodyEnd = bodyStart + BODY_MAX_LENGTH
      if bodyEnd > length:
        bodyEnd = length

      writeBuf.add(initBody(channelNumber, content.body[bodyStart..bodyEnd]).marshal())

    for frame in writeBuf:
      connection.outboundBuffer.addLast(frame)

    connection.framesSent += writeBuf.len
    connection.bytesSent += writeBuf.mapIt(it.len).sum
    connection.flushOutbound()

proc sendFrame(connection: Connection, frame: Frame) =
  info "$# Sending $#" % [$connection, $frame]

  if connection.state == csClosed:
    raise newException(ValueError, "Attempted to send frame while closed.")

  let marshaled = frame.marshal()

  connection.bytesSent += marshaled.len
  connection.framesSent += 1

  connection.outboundBuffer.addLast(marshaled)

  connection.flushOutbound()

  # TODO: Detect backpressure.

proc sendMethod(connection: Connection, channelNumber: ChannelNumber, rpcMethod: Method, content = none MessageContent) =
  if content.isSome:
    connection.sendMessage(channelNumber, rpcMethod, content.get())
  else:
    connection.sendFrame(initMethod(channelNumber, rpcMethod))

proc flushOutbound(connection: Connection) =
  info "$# Flushing outbound buffer ($# items)" % [
    $connection, $connection.outboundBuffer.len
  ]

  if connection.outboundBuffer.len > 0:
    if ceWrite notin connection.eventState:
      connection.eventState.incl(ceWrite)
      # Update handler
  elif ceWrite in connection.eventState:
    connection.eventState = baseEvents
    # Update handler

proc getCredentials(connection: Connection, frame: Frame): string =
  result = 0.char & connection.parameters.username & 0.char & connection.parameters.password

proc sendConnectionStartOk(connection: Connection, connectionStartFrame: Frame, response: string) =
  var
    connectionStartOkFrame = Frame(
      kind: fkMethod,
      rpcMethod: Method(
        class: cConnection,
        kind: mStartOk,
        mStartOkParams: (
          connectionStartFrame.rpcMethod.mStartParams.serverProperties,
          connectionStartFrame.rpcMethod.mStartParams.mechanisms,
          response,
          connectionStartFrame.rpcMethod.mStartParams.locales
        )
      )
    )

  connection.sendFrame(connectionStartOkFrame)

proc sendConnectionClose(connection: Connection, params: ClosingParams) =
  var
    connectionCloseFrame = Frame(
      kind: fkMethod,
      rpcMethod: Method(
        class: cConnection,
        kind: mClose,
        mCloseParams: (
          params.replyCode, params.reason
        )
      )
    )

  connection.sendFrame(connectionCloseFrame)

# Callbacks

proc onConnectionStart(connection: Connection, methodFrame: Frame) =
  connection.state = csStart
  connection.serverProperties = methodFrame.rpcMethod.mStartParams.serverProperties
  # if self._is_protocol_header_frame(method_frame):
  #     raise exceptions.UnexpectedFrameError
  # self._check_for_protocol_mismatch(method_frame)
  # self._set_server_information(method_frame)
  # self._add_connection_tune_callback()

  # TODO parametrize connection start response string?
  connection.sendConnectionStartOk(methodFrame, "Connection received")

proc onConnected(connection: Connection) =
  connection.state = csProtocol
  connection.sendFrame(protocolHeader())

proc onDataAvailable*(connection: Connection, data: string) =
  connection.frameBuffer &= data
  while connection.frameBuffer.len > 0:
    try:
      let (bytesDecoded, frame) = connection.readFrame()
      if not frame.isSome:
        return

      connection.trimFrameBuffer(bytesDecoded)
      connection.processFrame(frame.get())
    except IOError:
      return

proc onCloseReady(connection: Connection) =
  if connection.state == csClosed:
    warn "$# Attempted to close closed connection." % $connection

  connection.sendConnectionClose(connection.closingParams)

proc onConnectionCloseOk(connection: Connection, _: Frame) =
  if connection.socket.isSome:
    connection.socket.get().close()

  connection.state = csClosed
  info "$# Closed." % $connection


# Public methods

proc scheduleWrite*(connection: Connection) =
  connection.eventState.incl(ceWrite)

proc clearWrite*(connection: Connection) =
  connection.eventState.excl(ceWrite)

proc bufferRemaining*(connection: Connection): bool =
  connection.frameBuffer.len > 0

proc framesWaiting*(connection: Connection): bool =
  connection.outboundBuffer.len > 0

proc nextFrame*(connection: Connection): string =
  connection.outboundBuffer.popFirst()

proc connected*(connection: Connection): bool =
  connection.socket.isSome

proc events*(connection: Connection): set[ConnectionEvent] =
  connection.eventState

proc closed*(connection: Connection): bool =
  connection.state = csClosed

proc diagnostics*(connection: Connection): ConnectionDiagnostics =
  (connection.bytesSent,
   connection.framesSent,
   connection.bytesReceived,
   connection.framesReceived)
