import tables
from spec import MethodId, ChannelNumber

type
  Method* = object
    case kind*: MethodId
    of mStart:
      versionMajor*, versionMinor*: uint16
      serverProperties*: Table[string, string]
      mechanisms*, locales*: string
    else:
      discard

proc initMethodStart*(versionMajor, versionMinor: uint8, serverProperties: Table[string, string], mechanisms, locales: string): Method =
  result = Method(
    kind: mStart,
    versionMajor: versionMajor,
    versionMinor: versionMinor,
    serverProperties: serverProperties,
    mechanisms: mechanisms,
    locales: locales
  )
