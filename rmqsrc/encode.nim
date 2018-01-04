import endians, tables, strutils
import spec, frame

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
  result = newSeq[char]()
  for ch in v:
    result.add(ch)

proc encode(v: Table[string, string]): seq[char] =
  # TODO fill this out, right now we will just assume the table is empty
  result = newSeq[char]()
  for ch in encode(0.uint32):
    result.add(ch)

# Define encodings method parameters
type 
  ConnectionStartOk = tuple
    index: uint32
    clientProps: Table[string, string]
    mechanism: (string, uint8) # short string
    response: (string, uint32) # long string
    locale: (string, uint8)    # short string

proc encode*(v: ConnectionStartOk): seq[char] =
  result = newSeq[char]()

  result.add(v.index.encode())
  result.add(v.clientProps.encode())  # FIXME: this only works for empty tables at the moment
  result.add(v.mechanism[1].encode())
  result.add(v.mechanism[0].encode())
  result.add(v.response[1].encode())
  result.add(v.response[0].encode())
  result.add(v.locale[1].encode())
  result.add(v.locale[0].encode())

proc newConnectionStartOk*(clientProps: Table[string, string], mechanism: string = "PLAIN", response: string, locale: string = "en_US"): seq[char] =
  let m = (index: 0x000A000B.uint32,   # TODO can we specify functions by IDs instead of hardcoding this?
           clientProps: clientProps,
           mechanism: (mechanism, len(mechanism).uint8),
           response: (response, len(response).uint32),
           locale: (locale, len(locale).uint8))
  return m.encode()

# Encode frame components
proc encode*(rpcMethod: Method): seq[char] =
  result = newSeq[char]()
  case rpcMethod.kind
  of mStartOk:
    result.add(newConnectionStartOk(rpcMethod.serverPropertiesOk, rpcMethod.mechanismsOk, rpcMethod.responseOk, rpcMethod.localesOk))
  else:
    raise newException(ValueError, "Cannot encode: undefined method of '$#'" % [$rpcMethod.kind])

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
  echo newConnectionStartOk(initTable[string, string](), "PLAIN", "hi", "en_US")

  var rpcMethod = Method()

  rpcMethod.kind = mStartOk
  rpcMethod.serverPropertiesOk = initTable[string, string]()
  rpcMethod.mechanismsOk = "PLAIN"
  rpcMethod.responseOk = "hi"
  rpcMethod.localesOk = "en_US"

  let methodFrame = initMethod(1.uint16, rpcMethod)
  echo methodFrame.marshal()

