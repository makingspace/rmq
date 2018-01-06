import tables, strutils
from spec import Class, MethodId, ChannelNumber
import values, spec
import utils.encode

type
  ClosingParams* = tuple[replyCode: int, reason: string]
  Method* = object
    class*: Class
    case kind*: MethodId
    of mStart:
      mStartParams*: tuple[versionMajor, versionMinor: uint8, serverProperties: Table[string, ValueNode], mechanisms, locales: string]
    of mStartOk:
      mStartOkParams: tuple[serverProperties: Table[string, ValueNode], mechanisms, response, locales: string]
    of mTune, mTuneOk:
      mTuneParams*: tuple[channelMax: uint16, frameMax: uint32, heartbeat: uint16]
    of mClose:
      mCloseParams*: ClosingParams
    of mOpen:
      mOpenParams*: tuple[virtualHost, capabilities: string, insist: bool]
    else:
      discard

proc initMethodStart*(versionMajor, versionMinor: uint8, serverProperties: Table[string, ValueNode], mechanisms, locales: string): Method =
  result = Method(
    class: cConnection,
    kind: mStart,
    mStartParams: (versionMajor, versionMinor, serverProperties, mechanisms, locales)
  )

proc initMethodStartOk*(serverProperties: Table[string, ValueNode], mechanisms, response, locales: string): Method =
  result = Method(
    class: cConnection,
    kind: mStartOk,
    mStartOkParams: (serverProperties, mechanisms, response, locales)
  )

proc initMethodTune*(channelMax: uint16, frameMax: uint32, heartbeat: uint16): Method =
  result = Method(
    class: cConnection,
    kind: mTune,
    mTuneParams: (channelMax, frameMax, heartbeat)
  )

proc initMethodTuneOk*(channelMax: uint16, frameMax: uint32, heartbeat: uint16): Method =
  result = Method(
    class: cConnection,
    kind: mTuneOk,
    mTuneParams: (channelMax, frameMax, heartbeat)
  )

proc initMethodCloseOk*(): Method =
  result = Method(
    class: cConnection,
    kind: mCloseOk
  )

proc initMethodOpen*(virtualHost, capabilities: string, insist: bool): Method =
  result = Method(
    class: cConnection,
    kind: mOpen,
    mOpenParams: (virtualHost, capabilities, insist)
  )

# Encode frame components
proc encode*(m: Method): seq[char] =
  result = newSeq[char]()

  let (classId, methodId) = fromMethod(m.class, m.kind)
  result &= classId.encode()
  result &= methodId.encode()

  case m.kind
  of mStartOk:
    let p = m.mStartOkParams
    result &= encode(
      p.serverProperties.toNode(),
      p.mechanisms.toNode(vtShortStr),
      p.response.toNode(vtLongStr),
      p.locales.toNode(vtShortStr)
    )
  of mTuneOk:
    let p = m.mTuneParams
    result &= encode(
      p.channelMax,
      p.frameMax,
      p.heartbeat
    )
  of mClose:
    let p = m.mCloseParams
    result &= encode(
      p.replyCode.int16,
      p.reason.toNode(vtShortStr),
      m.class.uint16,
      m.kind.uint16
    )
  else:
    raise newException(ValueError, "Cannot encode: undefined method of '$#'" % [$m.kind])
