import deques, tables, net, options, logging, strutils
import frame

type ConnectionEvent* = enum
  ceRead, ceWrite, ceError

const
  baseEvents = {ceRead, ceError}
  FRAME_MAX_SIZE = 131072

type
  Channel = object
  ChannelTable = TableRef[string, Channel]
  ConnectionState = enum
    csClosed,
    csInit,
    csProtocol,
    csStart,
    csTune,
    csOpen,
    csClosing

  ConnectionParameters = tuple[host: string, port: int]

  Closing = tuple[reply_code: int, reason: string]
  Connection* = ref object
    state: ConnectionState
    outboundBuffer: Deque[string]
    frameBuffer: string
    closing: Closing
    eventState: set[ConnectionEvent]
    parameters: ConnectionParameters
    socket: Option[Socket]
    bytesSent, framesSent, bytesReceived, framesReceived: int

  ConnectionDiagnostics = tuple
    bytesSent, framesSent, bytesReceived, framesReceived: int


proc `$`(connection: Connection): string =
  "AMQP $#:$#" % [connection.parameters.host, $connection.parameters.port]

proc onConnected(connection: var Connection)
proc onDataAvailable(connection: Connection, data: string)
proc flushOutbound(connection: var Connection)

proc initConnection(connection: var Connection, parameters: ConnectionParameters) =
  connection.eventState = baseEvents
  connection.socket = none(Socket)
  connection.parameters = parameters
  connection.outboundBuffer = initDeque[string]()
  connection.frameBuffer = ""

proc newConnection*(parameters: ConnectionParameters): Connection =
  result = Connection()
  initConnection(result, parameters)

proc connect*(connection: var Connection) =
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

# IO

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
  info "$# Reading frame from: $#" % [$connection, connection.frameBuffer]
  result = connection.frameBuffer.decode()

proc trimFrameBuffer(connection: Connection, length: int) =
  connection.frameBuffer.delete(0, length - 1)
  connection.bytesReceived += length

proc processFrame(connection: Connection, frame: Frame) =
  info "$# Processing frame: $#" % [$connection, $frame]
  connection.framesReceived += 1
  # TODO: Process frame, I guess.

proc sendFrame(connection: var Connection, frame: Frame) =
  info "$# Sending $#" % [$connection, $frame]

  if connection.state == csClosed:
    raise newException(ValueError, "Attempted to send frame while closed.")

  let marshaled = frame.marshal()

  connection.bytesSent += marshaled.len
  connection.framesSent += 1

  connection.outboundBuffer.addLast(marshaled)

  connection.flushOutbound()

  # TODO: Detect backpressure.

proc flushOutbound(connection: var Connection) =
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

# Callbacks

proc onConnected(connection: var Connection) =
  connection.state = csProtocol
  connection.sendFrame(protocolHeader())

proc onDataAvailable(connection: Connection, data: string) =
  connection.frameBuffer &= data
  while connection.frameBuffer.len > 0:
    let (bytesDecoded, frame) = connection.readFrame()
    if not frame.isSome:
      return

    connection.trimFrameBuffer(bytesDecoded)
    connection.processFrame(frame.get())

# Public methods

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
