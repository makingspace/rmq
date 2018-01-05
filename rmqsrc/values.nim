import tables

import times
type
  ValueType* = enum
    vtNull,
    vtBool,
    vtShortShort,
    vtShortShortU,
    vtShort,
    vtShortU,
    vtLong,
    vtLongU,
    vtLongLong,
    vtLongLongU,
    vtFloat,
    vtDouble,
    vtDecimal,
    vtShortStr,
    vtLongStr,
    vtArray,
    vtTimeStamp,
    vtTable

  ValueNode* = object
    case valueType*: ValueType
    of vtNull: discard
    of vtBool:
      boolValue*: bool
    of vtShortShort:
      shortShortValue*: int
    of vtShortShortU:
      shortShortUValue*: int
    of vtShort:
      shortValue*: int
    of vtShortU:
      shortUValue*: int
    of vtLong:
      longValue*: int
    of vtLongU:
      longUValue*: int
    of vtLongLong:
      longLongValue*: int
    of vtLongLongU:
      longLongUValue*: int
    of vtFloat:
      floatValue*: float
    of vtDouble:
      doubleValue*: float
    of vtDecimal:
      decimalValue*: string
    of vtShortStr:
      shortStrValue*: string
    of vtLongStr:
      longStrValue*: string
    of vtArray:
      arrayValue*: seq[ValueNode]
    of vtTimeStamp:
      timeStampValue*: Time
    of vtTable:
      keys*: seq[string]
      values*: seq[ValueNode]

proc initVtLongStrNode*(value: string): ValueNode =
  result = ValueNode(
    valueType: vtLongStr,
    longStrValue: value
  )

proc initVtTableNode*(table: Table[string, ValueNode]): ValueNode =
  # TODO add grammar checks
  # e.g. keys start with '$', '#', or letters. See 4.2.1 Formal Protocol Grammar for full spec
  result = ValueNode(valueType: vtTable, keys: @[], values: @[])
  for k, v in table.pairs:
    result.keys.add(k)
    result.values.add(v)


proc `$`*(valueNode: ValueNode): string =
  "Value Node " & $valueNode.valueType


# TODO make this a test suite later...
when isMainModule:
  echo initVtTableNode({"a": ValueNode(valueType: vtShort, shortValue: 1)}.toTable)
