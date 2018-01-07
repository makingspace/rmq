proc parseEnumStyleSensitive*[T: enum](s: string): T =
  ## Parses an enum ``T``.
  ##
  ## Raises ``ValueError`` for an invalid value in `s`. The comparison is
  ## done in a style insensitive way.
  for e in low(T)..high(T):
    if s == $e:
      return e
  raise newException(ValueError, "invalid enum value: " & s)
