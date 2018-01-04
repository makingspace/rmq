import endians

proc encode*(v: uint8): array[0..0, char] =
  return [v.char]

proc encode*(v: uint16): array[0..1, char] =
  var v = v
  bigEndian16(addr result, addr v)

proc encode*(v: uint32): array[0..3, char] =
  var v = v
  bigEndian32(addr result, addr v)

when isMainModule:
  echo encode(uint8(1))
  echo encode(uint16(1))
  echo encode(uint32(1))
