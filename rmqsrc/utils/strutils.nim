import streams

proc parseEnumStyleSensitive*[T: enum](s: string): T =
  ## Parses an enum ``T``.
  ##
  ## Raises ``ValueError`` for an invalid value in `s`. The comparison is
  ## done in a style insensitive way.
  for e in low(T)..high(T):
    if s == $e:
      return e
  raise newException(ValueError, "invalid enum value: " & s)

proc newStringStream*(s: Stream, length: int): Stream =
  ## Given a number of bytes, consume them from the stream and return a new
  ## stream made from the resulting string.
  let substring = s.readStr(length)
  result = substring.newStringStream
