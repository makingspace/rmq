import deques, tables, net, options, logging, strutils, math, sequtils, asyncnet, asyncdispatch
import frame, spec, decode, methods, values

proc negotiateIntegerValue[T](a, b: T): T =
  if (a == 0) or (b == 0): max(a, b)
  else: min(a, b)

type ConnectionParameters = object
  host: string
  port: int
  username: string
  password: string
  channelMax: ChannelNumber
  frameMax: FrameSize
  heartbeat: HeartbeatInterval
  virtualHost: string

proc initConnectionParameters*(
  host: string, port: int,
  username = "user",
  password = "user",
  channelMax = MAX_CHANNELS,
  frameMax = FRAME_MAX_SIZE,
  heartbeat = DEFAULT_HEARTBEAT_TIMEOUT,
  virtualHost = "/"
): ConnectionParameters =
  ConnectionParameters(
    host: host,
    port: port,
    username: username,
    password: password,
    channelMax: channelMax,
    frameMax: frameMax,
    heartbeat: heartbeat,
    virtualHost: virtualHost
  )

type ConnectionEvent* = enum
  ceRead, ceWrite, ceError
const baseEvents = {ceRead, ceError}

type
  Channel = object
  ChannelTable = TableRef[ChannelNumber, Channel]
  ConnectionState* = enum
    csClosed = "Closed"
    csInit = "Init"
    csProtocol = "Protocol"
    csStart = "Start"
    csTune = "Tune"
    csOpen = "Open"
    csClosing = "Closing"

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
    knownHosts: string

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
proc onConnectionTune(connection: Connection, methodFrame: Frame)
proc onConnectionOpenOk(connection: Connection, methodFrame: Frame)
proc onCloseReady(connection: Connection)
proc onConnectionCloseOk(connection: Connection, _: Frame)

proc initConnection(connection: Connection, parameters: ConnectionParameters) =
  connection.eventState = baseEvents
  connection.socket = none(AsyncSocket)
  connection.parameters = parameters
  connection.outboundBuffer = initDeque[string]()
  connection.frameBuffer = ""
  connection.channels = newTable[ChannelNumber, Channel]()

proc newConnection*(parameters: ConnectionParameters): Connection =
  result = Connection()
  initConnection(result, parameters)

proc log(connection: Connection, msg: string) =
    info $connection & " " & msg

proc connect*(connection: Connection) =
  connection.log "Connecting to $# on $#" % [
    connection.parameters.host, $connection.parameters.port
  ]
  connection.state = csInit
  var socket = newAsyncSocket(buffered = false)
  try:
    waitFor socket.connect(connection.parameters.host, Port(connection.parameters.port))

    connection.log "Connected."
    connection.socket = some(socket)
    connection.onConnected()
  except OSError as e:
    let eMsg = e.msg.splitLines()[0]
    error "Connection to $# failed: $#" % [connection.parameters.host, eMsg]
    connection.state = csClosed
    quit()

proc close*(connection: Connection, replyCode = 200, reply_text = "Normal shutdown") =
  connection.log "Closing."

  # TODO: Close channels

  connection.state = csClosing

  connection.closingParams = (replyCode, reply_text)

  if connection.channels.len == 0:
    connection.onCloseReady()
  else:
    connection.log "Waiting for $# channels to close." % $connection.channels.len

type FrameCallback = proc(c: Connection, f: Frame)
proc methodNoOp(c: Connection, f: Frame) = discard
proc getMethodCallback(cm: MethodId): FrameCallback =
  case cm
  of mStart: onConnectionStart
  of mTune: onConnectionTune
  of mOpenOk: onConnectionOpenOk
  of mCloseOk: onConnectionCloseOk
  else: methodNoOp

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

proc recv*(connection: Connection): Future[FrameSize] {.async.} =
  var
    socket = connection.socket.get()
    data = newString(FRAME_MAX_SIZE)

  try:
    let bytesReceived = await socket.recvInto(addr data[0], FRAME_MAX_SIZE.int)
    data.setLen(bytesReceived)
  except TimeoutError:
    discard

  if data.len > 0:
    connection.onDataAvailable(data)

  result = data.len.FrameSize

# Frame handling

proc readFrame(connection: Connection): DecodedFrame = connection.frameBuffer.decode()

proc trimFrameBuffer(connection: Connection, length: FrameSize) =
  connection.frameBuffer.delete(0, length.int - 1)
  connection.bytesReceived += length.int

proc processFrame(connection: Connection, frame: Frame) =
  connection.log "Processing frame: $#" % $frame
  connection.framesReceived += 1
  if connection.processCallbacks(frame):
    return

proc sendMessage(connection: Connection, channelNumber: ChannelNumber, rpcMethod: Method, content: MessageContent) =
  let
    length = content.body.len
    bodyMaxLength = BODY_MAX_LENGTH.int
  var writeBuf = @[
      initMethod(channelNumber, rpcMethod).marshal(),
      initHeader(channelNumber, length, content.properties).marshal()
    ]
  if length > 0:
    let chunks = (length / bodyMaxLength).ceil.int
    for chunk in 0..<chunks:
      var
        bodyStart = chunk * bodyMaxLength
        bodyEnd = bodyStart + bodyMaxLength
      if bodyEnd > length:
        bodyEnd = length

      writeBuf.add(initBody(channelNumber, content.body[bodyStart..bodyEnd]).marshal())

    for frame in writeBuf:
      connection.outboundBuffer.addLast(frame)

    connection.framesSent += writeBuf.len
    connection.bytesSent += writeBuf.mapIt(it.len).sum
    connection.flushOutbound()

proc sendFrame(connection: Connection, frame: Frame) =
  connection.log "Sending $#" % $frame

  if connection.state == csClosed:
    raise newException(ValueError, "Attempted to send frame while closed.")

  let marshaled = frame.marshal()

  connection.bytesSent += marshaled.len
  connection.framesSent += 1

  connection.outboundBuffer.addLast(marshaled)

  connection.flushOutbound()

  # TODO: Detect backpressure.

proc sendMethod(connection: Connection, rpcMethod: Method, channelNumber: ChannelNumber = 0, content = none MessageContent) =
  if content.isSome:
    connection.sendMessage(channelNumber, rpcMethod, content.get())
  else:
    connection.sendFrame(initMethod(channelNumber, rpcMethod))

proc flushOutbound(connection: Connection) =
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
  connection.sendMethod(
    initMethodStartOk(
        initTable[string, ValueNode](),
        "PLAIN",
        response,
        connectionStartFrame.rpcMethod.mStartParams.locales
    )
  )

proc sendConnectionTune(
  connection: Connection,
  channelMax: ChannelNumber,
  frameMax: FrameSize,
  heartbeat: HeartbeatInterval,
  ok = false
) =
  let f = if ok: initMethodTuneOk else: initMethodTune
  connection.sendMethod(
    f(channelMax, frameMax, heartbeat)
  )

proc sendConnectionOpen(connection: Connection, virtualHost: string, insist: bool) =
  connection.sendMethod(
    initMethodOpen(virtualHost, insist)
  )

proc sendConnectionClose(connection: Connection, params: ClosingParams) =
  connection.sendMethod(
    initMethodClose(params)
  )

# Callbacks

proc onConnected(connection: Connection) =
  connection.log "Starting protocol handshake."
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

proc onConnectionStart(connection: Connection, methodFrame: Frame) =
  connection.log "Starting AMQP connection."
  connection.state = csStart
  connection.serverProperties = methodFrame.rpcMethod.mStartParams.serverProperties
  # if self._is_protocol_header_frame(method_frame):
  #     raise exceptions.UnexpectedFrameError
  # self._check_for_protocol_mismatch(method_frame)
  # self._set_server_information(method_frame)

  # TODO parametrize connection start response string?
  connection.sendConnectionStartOk(methodFrame, connection.getCredentials(methodFrame))

proc onConnectionTune(connection: Connection, methodFrame: Frame) =
  let frameParams = methodFrame.rpcMethod.mTuneParams
  connection.log "Starting AMQP tuning."
  connection.state = csTune
  let
    channelMax = negotiateIntegerValue(
      connection.parameters.channelMax, frameParams.channelMax
    )
    frameMax = negotiateIntegerValue(
      connection.parameters.frameMax, frameParams.frameMax
    )
    heartbeat = negotiateIntegerValue(
      connection.parameters.heartbeat, frameParams.heartbeat
    )
  connection.parameters.channelMax = channelMax
  connection.parameters.frameMax = frameMax
  connection.parameters.heartbeat = heartbeat
  # Calculate the maximum pieces for body frames
  #self._body_max_length = self._get_body_frame_max_length()

  # Create a new heartbeat checker if needed
  #self.heartbeat = self._create_heartbeat_checker()

  # Send the TuneOk response with what we've agreed upon
  connection.sendConnectionTune(channelMax, frameMax, heartbeat, ok = true)
  connection.sendConnectionOpen(connection.parameters.virtualHost, insist = true)

proc onConnectionOpenOk(connection: Connection, methodFrame: Frame) =
  let frameParams = methodFrame.rpcMethod.mOpenOkParams
  connection.state = csOpen
  connection.log "AMQP connection open."
  connection.knownHosts = frameParams.knownHosts

proc onCloseReady(connection: Connection) =
  case connection.state
  of csClosed:
    warn "$# Attempted to close closed connection." % $connection
  of csInit, csProtocol:
    connection.log "Not connected; Closing immediately."
    connection.onConnectionCloseOk(Frame())
  else:
    connection.sendConnectionClose(connection.closingParams)

proc onConnectionCloseOk(connection: Connection, _: Frame) =
  if connection.socket.isSome:
    connection.socket.get().close()

  connection.log "Closing AMQP Connection."
  connection.state = csClosed


# Public methods

proc scheduleWrite*(connection: Connection) =
  connection.eventState.incl(ceWrite)

proc clearWrite*(connection: Connection) =
  connection.eventState.excl(ceWrite)

proc bufferRemaining*(connection: Connection): bool {.noSideEffect.} =
  connection.frameBuffer.len > 0

proc framesWaiting*(connection: Connection): bool {.noSideEffect.} =
  connection.outboundBuffer.len > 0

proc nextFrame*(connection: Connection): string =
  connection.outboundBuffer.popFirst()

proc connected*(connection: Connection): bool {.noSideEffect.} =
  connection.socket.isSome

proc events*(connection: Connection): set[ConnectionEvent] =
  connection.eventState

proc closed*(connection: Connection): bool {.noSideEffect.} =
  connection.state == csClosed

proc diagnostics*(connection: Connection): ConnectionDiagnostics =
  (connection.bytesSent,
   connection.framesSent,
   connection.bytesReceived,
   connection.framesReceived)
