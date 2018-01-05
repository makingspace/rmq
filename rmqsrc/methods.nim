import tables
from spec import Class, MethodId, ChannelNumber
import values

type
  Method* = object
    class*: Class
    case kind*: MethodId
    of mStart:
      mStartParams*: tuple[versionMajor, versionMinor: uint8, serverProperties: Table[string, ValueNode], mechanisms, locales: string]
    of mStartOk:
      mStartOkParams*: tuple[serverProperties: Table[string, ValueNode], mechanisms, response, locales: string]
    else:
      discard

proc initMethodStart*(versionMajor, versionMinor: uint8, serverProperties: Table[string, ValueNode], mechanisms, locales: string): Method =
  result = Method(
    class: cConnection,
    kind: mStart,
    mStartParams: (versionMajor, versionMinor, serverProperties, mechanisms, locales)
  )
