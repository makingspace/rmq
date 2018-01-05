import endians, tables, strutils, sequtils
import spec, frame, methods, values

# Encode basic types
proc encode(v: seq[char]): seq[char] =
  return v

proc encode(v: uint8): array[0..0, char] =
  return [v.char]

proc encode(v: int16): array[0..1, char] =
  var v = v
  bigEndian16(addr result, addr v)

proc encode(v: uint16): array[0..1, char] =
  var v = v
  bigEndian16(addr result, addr v)

proc encode(v: uint32): array[0..3, char] =
  var v = v
  bigEndian32(addr result, addr v)

proc encode(v: string): seq[char] =
  v.mapIt(it.char)

# Encode value nodes
proc encode(vnode: ValueNode): seq[char] =
  result = newSeq[char]()
  case vnode.valueType
  of vtBool:
    result &= encode(vnode.boolValue.uint8)
  of vtShortStr:
    result &= encode(vnode.shortStrValue.len.uint8)
    result &= encode(vnode.shortStrValue)
  of vtLongStr:
    result &= encode(vnode.longStrValue.len.uint32)
    result &= encode(vnode.longStrValue)
  of vtTable:
    var encodedTable = newSeq[char]()
    for i in 0 .. vnode.keys.high:
      encodedTable &= encode(vnode.keys[i].toNode(vtShortStr))
      encodedTable &= encode(vnode.values[i])

    result &= encode(encodedTable.len.uint32)
    result &= encodedTable
  of vtShort:
    result &= encode(vnode.shortValue.int16)
  of vtShortU:
    result &= encode(vnode.shortUValue.uint16)
  else:
    # TODO add more cases
    raise newException(ValueError, "Cannot encode $#" % [$vnode])

proc encode*(params: varargs[ValueNode]): seq[char] =
  return params.foldl(a & encode(b), newSeq[char]())

# Encode frame components
proc encode*(m: Method): seq[char] =
  result = newSeq[char]()

  result &= m.class.uint16.encode()
  result &= m.kind.uint16.encode()

  case m.kind
  of mStartOk:
    let p = m.mStartOkParams
    result &= encode(
      p.serverProperties.toNode(),
      p.mechanisms.toNode(vtShortStr),
      p.response.toNode(vtLongStr),
      p.locales.toNode(vtShortStr)
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
