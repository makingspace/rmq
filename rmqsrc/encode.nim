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
    raise newException(ValueError, "Encode")

# Define encodings method parameters
type 
  MethodParams = seq[tuple[name: string, valueType: ValueType]]

const
  paramsLookup: Table[MethodId, MethodParams] = {
    mStartOk: @[("clientProps", vtTable), ("mechanism", vtShortStr), ("response", vtLongStr), ("locale", vtShortStr)]
  }.toTable

proc encode*(mid: MethodId, params: varargs[ValueNode]): seq[char] =
  let reqParams = paramsLookup[mid]
  if reqParams.len != params.len:
      raise newException(ValueError, "$# arguments required, but only supplied $#" % [$reqParams.len, $params.len])

  result = newSeq[char]()
  for i in 0 .. reqParams.high:
    if reqParams[i].valueType != params[i].valueType:
      raise newException(ValueError, "Argument $# ($#) must have value type $#" % [$i, $reqParams[i].name, $params[i].valueType])

    result.add(params[i].encode())

# Encode frame components
proc encode*(m: Method): seq[char] =
  result = newSeq[char]()
  case m.kind
  of mStartOk:
    # FIXME only works if table is empty
    result.add(encode(m.kind,
                      ValueNode(valueType: vtTable),
                      ValueNode(valueType: vtShortStr, shortStrValue: m.mechanismsOk),
                      ValueNode(valueType: vtLongStr, longStrValue: m.responseOk),
                      ValueNode(valueType: vtShortStr, shortStrValue: m.localesOk)))
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

when isMainModule:
  echo encode(uint8(1))
  echo encode(uint16(1))
  echo encode(uint32(1))
  echo encode("hi")
  # echo newConnectionStartOk(initTable[string, string](), "PLAIN", "hi", "en_US")

  var rpcMethod = Method()

  rpcMethod.kind = mStartOk
  rpcMethod.serverPropertiesOk = initTable[string, string]()
  rpcMethod.mechanismsOk = "PLAIN"
  rpcMethod.responseOk = "hi"
  rpcMethod.localesOk = "en_US"

  let methodFrame = initMethod(1.uint16, rpcMethod)
  echo methodFrame.marshal()

