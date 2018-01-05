import endians, tables, strutils, sequtils
import spec, frame, methods, values

# Encode basic types
proc encode(v: uint8): array[0..0, char] =
  return [v.char]

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
  of vtShortStr:
    result.add(encode(vnode.shortStrValue.len.uint8))
    result.add(encode(vnode.shortStrValue))
  of vtLongStr:
    result.add(encode(vnode.longStrValue.len.uint32))
    result.add(encode(vnode.longStrValue))
  of vtTable:
    # FIXME: this only works for empty tables
    result.add(encode(0.uint32))
  else:
    # TODO add more cases
    raise newException(ValueError, "Encode")

proc encode*(params: varargs[ValueNode]): seq[char] =
  result = newSeq[char]()
  for i in 0 .. params.high:
    result.add(params[i].encode())

# Encode frame components
proc encode*(m: Method): seq[char] =
  case m.kind
  of mStartOk:
    let p = m.mStartOkParams
    return encode(
      ValueNode(valueType: vtTable),       # FIXME only works if table is empty
      ValueNode(valueType: vtShortStr, shortStrValue: p.mechanisms),
      ValueNode(valueType: vtLongStr, longStrValue: p.response),
      ValueNode(valueType: vtShortStr, shortStrValue: p.locales)
    )
  else:
    raise newException(ValueError, "Cannot encode: undefined method of '$#'" % [$m.kind])

proc encode*(frame: Frame): seq[char] =
  result = newSeq[char]()
  result.add(frame.kind.uint8.encode())
  result.add(frame.channelNumber.uint16.encode())
  case frame.kind
  of fkMethod:
    let payload = encode(frame.rpcMethod)
    result.add(len(payload).uint32.encode())
    result.add(payload)
  else:
    raise newException(ValueError, "Cannot encode: undefined frame kind of '$#'" % [$frame.kind])
  result.add(FRAME_END.encode())

proc marshal*(frame: Frame): string =
  case frame.kind
  of fkProtocol:
    "AMQP" & 0.char & frame.major & frame.minor & frame.revision
  else:
    frame.encode().join()
