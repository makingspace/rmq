import strutils, options, streams, endians, tables
from spec import Class, MethodId

const
  VERSION_MAJOR = 0.char
  VERSION_MINOR = 9.char
  VERSION_REVISION = 1.char

  FRAME_HEADER_SIZE* = 7
  FRAME_END_SIZE* = 1

type
  ChannelNumber* = uint16
  Method* = object
    case kind*: MethodId
    of mStart:
      versionMajor*, versionMinor*: uint16
      serverProperties*: Table[string, string]
      mechanisms*, locales*: string
    else:
      discard

  FrameKind* = enum
    fkProtocol = 0,
    fkMethod = 1,
    fkHeader = 2,
    fkBody = 3,
    fkHeartbeat = 4

  Frame* = object of RootObj
    channelNumber: ChannelNumber
    case kind: FrameKind
    of fkProtocol:
      major, minor, revision: char
    of fkMethod:
      rpcMethod: Method
    of fkHeader:
      bodySize: uint32
      propFlags: uint16
      propList: string      # TODO change to unsigned
    of fkBody:
      payload: string       # TODO specify type
    of fkHeartbeat:
      discard

proc `$`*(frame: Frame): string =
  "Frame: $#" % $frame.kind

proc marshal*(header: Frame): string =
  case header.kind
  of fkProtocol:
    "AMQP" & 0.char & header.major & header.minor & header.revision
  else:
    # Not implemented
    ""

proc initProtocolHeader*(major, minor, revision: char): Frame = Frame(
  kind: fkProtocol,
  major: major,
  minor: minor,
  revision: revision
)

proc initMethod*(channelNumber: ChannelNumber, rpcMethod: Method): Frame = Frame(
  kind: fkMethod,
  channelNumber: channelNumber,
  rpcMethod: rpcMethod
)

proc initHeader*(channelNumber: ChannelNumber, bodySize: int, properties: string): Frame = Frame(
  kind: fkHeader,
  channelNumber: channelNumber,
  propList: properties
)

proc initBody*(channelNumber: ChannelNumber, body: string): Frame = Frame(
  kind: fkBody,
  payload: body
)

proc protocolHeader*: Frame = initProtocolHeader(
  VERSION_MAJOR, VERSION_MINOR, VERSION_REVISION
)
