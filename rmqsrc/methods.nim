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
      mStartParams*: tuple[
        versionMajor, versionMinor: VersionNumber,
        serverProperties: Table[string, ValueNode],
        mechanisms, locales: string
      ]
    of mStartOk:
      mStartOkParams: tuple[serverProperties: Table[string, ValueNode], mechanisms, response, locales: string]
    of mTune, mTuneOk:
      mTuneParams*: tuple[
        channelMax: ChannelNumber, frameMax: FrameSize, heartbeat: HeartbeatInterval
      ]
    of mClose:
      mCloseParams*: ClosingParams
    of mOpen:
      mOpenParams*: tuple[virtualHost, capabilities: string, insist: bool]
    of mOpenOk:
      mOpenOkParams*: tuple[knownHosts: string]
    else:
      discard

proc initMethodStart*(
  versionMajor, versionMinor: VersionNumber,
  serverProperties: Table[string, ValueNode], mechanisms, locales: string
): Method =
  result = Method(
    class: cConnection,
    kind: mStart,
    mStartParams: (versionMajor, versionMinor, serverProperties, mechanisms, locales)
  )

proc initMethodStartOk*(
  serverProperties: Table[string, ValueNode],
  mechanisms, response, locales: string
): Method =
  result = Method(
    class: cConnection,
    kind: mStartOk,
    mStartOkParams: (serverProperties, mechanisms, response, locales)
  )

proc initMethodTune*(
  channelMax: ChannelNumber,
  frameMax: FrameSize,
  heartbeat: HeartbeatInterval
): Method =
  result = Method(
    class: cConnection,
    kind: mTune,
    mTuneParams: (channelMax, frameMax, heartbeat)
  )

proc initMethodTuneOk*(
  channelMax: ChannelNumber,
  frameMax: FrameSize,
  heartbeat: HeartbeatInterval
): Method =
  result = Method(
    class: cConnection,
    kind: mTuneOk,
    mTuneParams: (channelMax, frameMax, heartbeat)
  )

proc initMethodClose*(params: ClosingParams): Method =
  result = Method(
    class: cConnection,
    kind: mClose,
    mCloseParams: (
      params.replyCode, params.reason
    )
  )

proc initMethodCloseOk*(): Method =
  result = Method(
    class: cConnection,
    kind: mCloseOk
  )

proc initMethodOpen*(virtualHost: string, insist: bool, capabilities = ""): Method =
  result = Method(
    class: cConnection,
    kind: mOpen,
    mOpenParams: (virtualHost, capabilities, insist)
  )

proc initMethodOpenOk*(knownHosts: string): Method =
  result = Method(
    class: cConnection,
    kind: mOpenOk,
    mOpenOkParams: (knownHosts: knownHosts)
  )

# Encode frame components
proc encode*(m: Method): seq[char] =
  result = newSeq[char]()

  let (classId, methodId) = fromMethod(m.class, m.kind)
  result &= classId.encode()
  result &= methodId.encode()

  case m.kind
  of mStart:
    let p = m.mStartParams
    result &= encode(
      p.versionMajor.toNode,
      p.versionMinor.toNode,
      p.serverProperties.toNode,
      p.mechanisms.toNode(vtLongStr),
      p.locales.toNode(vtLongStr)
    )
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
  of mOpen:
    let p = m.mOpenParams
    result &= encode(
      p.virtualHost.toNode(vtShortStr),
      p.capabilities.toNode(vtShortStr),
      p.insist.toNode()
    )
  else:
    raise newException(ValueError, "Cannot encode: undefined method of '$#'" % [$m.kind])
