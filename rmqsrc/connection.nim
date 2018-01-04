import deques, tables, net, options, logging, strutils, math, sequtils
import frame, spec, decode, methods, values, encode

type ConnectionEvent* = enum
  ceRead, ceWrite, ceError
const baseEvents = {ceRead, ceError}

type
  Channel = object
  ChannelTable = TableRef[string, Channel]
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

  Closing = tuple[reply_code: int, reason: string]
  Connection* = ref object
    state*: ConnectionState
    outboundBuffer: Deque[string]
    frameBuffer: string
    closing: Closing
    eventState: set[ConnectionEvent]
    serverProperties*: Table[string, ValueNode]
    parameters: ConnectionParameters
    socket: Option[Socket]
    bytesSent, framesSent, bytesReceived, framesReceived: int

  ConnectionDiagnostics = tuple
    bytesSent, framesSent, bytesReceived, framesReceived: int

  MessageContent = tuple
    properties: string
    body: string


proc `$`(connection: Connection): string =
  "AMQP $#:$#" % [connection.parameters.host, $connection.parameters.port]

proc onConnected(connection: Connection)
proc onDataAvailable*(connection: Connection, data: string)
proc flushOutbound(connection: Connection)
proc onConnectionStart(connection: Connection, methodFrame: Frame)

proc initConnection(connection: Connection, parameters: ConnectionParameters) =
  connection.eventState = baseEvents
  connection.socket = none(Socket)
  connection.parameters = parameters
  connection.outboundBuffer = initDeque[string]()
  connection.frameBuffer = ""

proc newConnection*(parameters: ConnectionParameters): Connection =
  result = Connection()
  initConnection(result, parameters)

proc connect*(connection: Connection) =
  connection.state = csInit
  var socket = newSocket()
  try:
    info "Connecting to $# on $#" % [connection.parameters.host, $connection.parameters.port]
    socket.connect(connection.parameters.host, Port(connection.parameters.port))

    info "Connected."
    connection.socket = some(socket)
    connection.onConnected()

  except OSError:
    info "Connection to $# failed." % connection.parameters.host
    connection.state = csClosed

proc getMethodCallback(cm: MethodId): proc(c: Connection, f: Frame) =
  case cm
  of mStart: result = onConnectionStart
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

proc send*(connection: Connection, msg: string): bool =
  let socket = connection.socket.get()
  result = socket.trySend(msg)

proc recv*(connection: Connection): int =
  let
    socket = connection.socket.get()
    data = socket.recv(FRAME_MAX_SIZE)

  if data == "":
    error "Socket disconnect on read."
    quit()

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
  #
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

proc sendConnectionStartOk(connection: Connection, usernamePassword: string) =
  discard
  # TODO: Implement StartOk Method
  # connection.sendMethod(0.ChannelNumber, startOk)

# Callbacks
#
proc onConnectionStart(connection: Connection, methodFrame: Frame) =
  connection.state = csStart
  connection.serverProperties = methodFrame.rpcMethod.serverProperties
  # if self._is_protocol_header_frame(method_frame):
  #     raise exceptions.UnexpectedFrameError
  # self._check_for_protocol_mismatch(method_frame)
  # self._set_server_information(method_frame)
  # self._add_connection_tune_callback()
  connection.sendConnectionStartOk(connection.getCredentials(methodFrame))

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

# Public methods
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

proc diagnostics*(connection: Connection): ConnectionDiagnostics =
  (connection.framesSent,
   connection.bytesSent,
   connection.bytesReceived,
   connection.framesReceived)
