import tables
from spec import MethodId, ChannelNumber
import values

type
  Method* = object
    case kind*: MethodId
    of mStart:
      versionMajor*, versionMinor*: uint8
      serverProperties*: Table[string, ValueNode]
      mechanisms*, locales*: string
    of mStartOk:
      serverPropertiesOk*: Table[string, string]
      mechanismsOk*, responseOk*, localesOk*: string
    else:
      discard

proc initMethodStart*(versionMajor, versionMinor: uint8, serverProperties: Table[string, ValueNode], mechanisms, locales: string): Method =
  result = Method(
    kind: mStart,
    versionMajor: versionMajor,
    versionMinor: versionMinor,
    serverProperties: serverProperties,
    mechanisms: mechanisms,
    locales: locales
  )
