import endians, tables
from frame import FrameKind
from spec import FRAME_END

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
  let m = (index: 0x000A000B.uint32,
           clientProps: clientProps,
           mechanism: (mechanism, len(mechanism).uint8),
           response: (response, len(response).uint32),
           locale: (locale, len(locale).uint8))
  return m.encode()


# method frame marshalling method
# TODO probably should move this to frame.nim
proc encode*(channelNumber: uint16, payload: seq[char]): seq[char] =
  let frameType = fkMethod.uint8
  
  result = newSeq[char]()
  result.add(frameType.encode())
  result.add(channelNumber.encode())
  result.add(len(payload).uint32.encode())
  result.add(payload)
  result.add(FRAME_END.encode())


when isMainModule:
  echo encode(uint8(1))
  echo encode(uint16(1))
  echo encode(uint32(1))
  echo encode("hi")

  let
    channelNumber = 1.uint16
    payload = newConnectionStartOk(initTable[string, string](), "PLAIN", "hi", "en_US")

  echo payload
  echo encode(channelNumber, payload)

