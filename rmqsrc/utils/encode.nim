import endians, tables, strutils, sequtils

# Encode basic types
proc encode*(v: seq[char]): seq[char] =
  return v

proc encode*(v: int8 | uint8): array[0..0, char] =
  return [v.char]

proc encode*(v: int16 | uint16): array[0..1, char] =
  var v = v
  bigEndian16(addr result, addr v)

proc encode*(v: int32 | uint32): array[0..3, char] =
  var v = v
  bigEndian32(addr result, addr v)

proc encode*(v: string): seq[char] =
  v.mapIt(it.char)
