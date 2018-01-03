import strutils, options, streams, endians
from spec import Class, Method

const
  VERSION_MAJOR = 0.char
  VERSION_MINOR = 9.char
  VERSION_REVISION = 1.char

  FRAME_HEADER_SIZE = 7
  FRAME_END_SIZE = 1

type
  FrameKind = enum
    fkProtocol = 0,
    fkMethod = 1,
    fkHeader = 2,
    fkBody = 3,
    fkHeartbeat = 4

  Frame* = object of RootObj
    case kind: FrameKind
    of fkProtocol:
      major, minor, revision: cchar
    of fkMethod:
      methodClassId: Class
      MethodId: Method
      args: string          # TODO specific type
    of fkHeader:
      headerClassId: Class
      bodySize: clong       # TODO change to unsigned
      propFlags: cshort     # TODO change to unsigned
      propList: string      # TODO change to unsigned
    of fkBody:
      payload: string       # TODO specify type
    of fkHeartbeat:
      discard

  DecodedFrame* = tuple[consumed: int, frame: Option[Frame]]
  FrameParams = tuple
    frameType: uint8
    frameChannel: uint16
    frameSize: uint32

proc `$`*(frame: Frame): string =
  "Frame: $#" % $frame.kind

proc marshal*(header: Frame): string =
  case header.kind
  of fkProtocol:
    "AMQP" & 0.char & header.major & header.minor & header.revision
  else:
    # Not implemented
    ""

proc initProtocolHeader(major, minor, revision: char): Frame = Frame(
  kind: fkProtocol,
  major: major,
  minor: minor,
  revision: revision
)

proc protocolHeader*: Frame = initProtocolHeader(
  VERSION_MAJOR, VERSION_MINOR, VERSION_REVISION
)

proc readFrameType(s: Stream): uint8 =
  result = s.readUInt8

proc readChannelNumber(s: Stream): uint16 =
  result = s.readUInt16
  bigEndian16(addr result, addr result)

proc readFrameSize(s: Stream): uint32 =
  result = s.readUInt32
  bigEndian32(addr result, addr result)

proc readFrameParams(s: Stream): FrameParams =
  let
    frameType = s.readFrameType
    channelNumber = s.readChannelNumber
    frameSize = s.readFrameSize
  (frameType, channelNumber, frameSize)

proc decode*(data: string): DecodedFrame =
  if data.startsWith("AMQP"):
    try:
      let
        major = data[5]
        minor = data[6]
        revision = data[7]

      result = (8, some initProtocolHeader(major, minor, revision))
    except IndexError:
      result = (0, none Frame)
  else:
    var stringStream = newStringStream(data)
    let
      frameParams = readFrameParams(stringStream)
      frameEnd = FRAME_HEADER_SIZE + frameParams.frameSize.int + FRAME_END_SIZE
    echo "Frame Params", frameParams
    if frameEnd > data.len:
      # We don't have all the data yet.
      result = (0, none Frame)

    let frameData = data[FRAME_HEADER_SIZE..<frameEnd - 1]
    echo frameData
