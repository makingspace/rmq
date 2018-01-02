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
  Marshaled* = array[4, cchar]

proc `$`*(frame: Frame): string =
  "Frame: $#" % $frame.kind

proc marshal*(header: Frame): Marshaled =
  case header.kind
  of fkProtocol:
    [0.cchar, header.major, header.minor, header.revision]

proc protocolHeader*: Frame = Frame(
  kind: fkProtocol,
  major: VERSION_MAJOR,
  minor: VERSION_MINOR,
  revision: VERSION_REVISION
)

