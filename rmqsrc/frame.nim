import strutils

const
  VERSION_MAJOR = 0.cchar
  VERSION_MINOR = 9.cchar
  VERSION_REVISION = 1.cchar

type
  FrameKind = enum
    fkProtocol
  Frame* = object of RootObj
    case kind: FrameKind
    of fkProtocol:
      major, minor, revision: cchar

proc `$`*(frame: Frame): string =
  "Frame: $#" % $frame.kind

proc marshal*(header: Frame): string =
  case header.kind
  of fkProtocol:
    "AMQP" & 0.char & header.major & header.minor & header.revision

proc protocolHeader*: Frame = Frame(
  kind: fkProtocol,
  major: VERSION_MAJOR,
  minor: VERSION_MINOR,
  revision: VERSION_REVISION
)
