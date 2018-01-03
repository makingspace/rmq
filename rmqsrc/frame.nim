import strutils, options

const
  VERSION_MAJOR = 0.char
  VERSION_MINOR = 9.char
  VERSION_REVISION = 1.char

type
  FrameKind = enum
    fkProtocol
  Frame* = object of RootObj
    case kind: FrameKind
    of fkProtocol:
      major, minor, revision: cchar
  DecodedFrame* = tuple[consumed: int, frame: Option[Frame]]

proc `$`*(frame: Frame): string =
  "Frame: $#" % $frame.kind

proc marshal*(header: Frame): string =
  case header.kind
  of fkProtocol:
    "AMQP" & 0.char & header.major & header.minor & header.revision

proc initProtocolHeader(major, minor, revision: char): Frame = Frame(
  kind: fkProtocol,
  major: major,
  minor: minor,
  revision: revision
)

proc protocolHeader*: Frame = initProtocolHeader(
  VERSION_MAJOR, VERSION_MINOR, VERSION_REVISION
)

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
    # TODO: Implement rest if frame types.
    result = (0, none Frame)
