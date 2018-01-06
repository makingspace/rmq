import strutils, options, streams, endians, tables
import methods
from spec import Class, MethodId, ChannelNumber, VERSION_MAJOR, VERSION_MINOR, VERSION_REVISION, FRAME_END
import utils.encode

type
  FrameKind* = enum
    fkProtocol = 0,
    fkMethod = 1,
    fkHeader = 2,
    fkBody = 3,
    fkHeartbeat = 4

  Frame* = object of RootObj
    channelNumber*: ChannelNumber
    case kind*: FrameKind
    of fkProtocol:
      major*, minor*, revision*: char
    of fkMethod:
      rpcMethod*: Method
    of fkHeader:
      bodySize*: uint32
      propFlags*: uint16
      propList*: string      # TODO change to unsigned
    of fkBody:
      payload*: string       # TODO specify type
    of fkHeartbeat:
      discard

proc `$`*(frame: Frame): string =
  case frame.kind
  of fkMethod: "Frame $#: $#.$#" % [
    $frame.kind, $frame.rpcMethod.class, $frame.rpcMethod.kind
  ]
  else: "Frame: $#" % $frame.kind


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

proc encode*(frame: Frame): seq[char] =
  result = newSeq[char]()
  result &= frame.kind.uint8.encode()
  result &= frame.channelNumber.uint16.encode()
  case frame.kind
  of fkMethod:
    let payload = encode(frame.rpcMethod)
    result &= len(payload).uint32.encode()
    result &= payload
  else:
    raise newException(ValueError, "Cannot encode: undefined frame kind of '$#'" % [$frame.kind])
  result &= FRAME_END.encode()

proc marshal*(frame: Frame): string =
  case frame.kind
  of fkProtocol:
    "AMQP" & 0.char & frame.major & frame.minor & frame.revision
  else:
    frame.encode().join()
