import deques, tables, net, options, logging, strutils
import frame

const
  READ* = 0x0001i16
  WRITE* = 0x0004i16
  ERROR* = 0x0008i16
  baseEvents = {READ, ERROR}

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
    eventState: set[int16]
    parameters: ConnectionParameters
    socket: Option[Socket]
    bytesSent, framesSent: int

proc `$`(connection: Connection): string =
  "AMQP $#:$#" % [connection.parameters.host, $connection.parameters.port]

proc connect*(connection: var Connection)
proc onConnected(connection: var Connection)
proc flushOutbound(connection: var Connection)
proc sendFrame(connection: var Connection, frame: Frame)

proc initConnection(connection: var Connection, parameters: ConnectionParameters) =
  connection.eventState = baseEvents
  connection.socket = none(Socket)
  connection.parameters = parameters
  connection.outboundBuffer = initDeque[string]()

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

proc send*(connection: Connection, msg: string): bool =
  let socket = connection.socket.get()
  result = socket.trySend(msg)

proc onConnected(connection: var Connection) =
  connection.state = csProtocol
  connection.sendFrame(protocolHeader())

proc sendFrame(connection: var Connection, frame: Frame) =
  info "$# Sending $#" % [$connection, $frame]

  if connection.state == csClosed:
    raise newException(ValueError, "Attempted to send frame while closed.")

  let marshaled = frame.marshal()

  connection.bytesSent += 1
  connection.framesSent += 1

  connection.outboundBuffer.addLast(marshaled)

  connection.flushOutbound()

  # TODO: Detect backpressure.

proc flushOutbound(connection: var Connection) =
  info "$# Flushing outbound buffer ($# items)" % [
    $connection, $connection.outboundBuffer.len
  ]

  if connection.outboundBuffer.len > 0:
    if WRITE notin connection.eventState:
      connection.eventState.incl(WRITE)
      # Update handler
  elif WRITE in connection.eventState:
    connection.eventState = baseEvents
    # Update handler

proc framesWaiting*(connection: Connection): bool =
  connection.outboundBuffer.len > 0

proc nextFrame*(connection: Connection): string =
  connection.outboundBuffer.popFirst()

proc connected*(connection: Connection): bool =
  connection.socket.isSome

proc events*(connection: Connection): set[int16] =
  connection.eventState
