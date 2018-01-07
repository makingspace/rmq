import tables, times, sequtils, strutils
import utils.encode

type
  ValueType* = enum
    vtNull
    vtBool = "t"
    vtShortShort = "b"
    vtShortShortU = "B"
    vtShort = "U"
    vtShortU = "u"
    vtLong = "I"
    vtLongU = "i"
    vtLongLong = "L"
    vtLongLongU = "l"
    vtFloat = "f"
    vtDouble = "d"
    vtDecimal = "D"
    vtShortStr = "s"
    vtLongStr = "S"
    vtArray = "A"
    vtTimeStamp = "T"
    vtTable = "F"

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

proc `$`*(valueNode: ValueNode): string =
  "Value Node " & $valueNode.valueType

converter toNode*(v: bool): ValueNode =
  return ValueNode(valueType: vtBool, boolValue: v)

proc toNode*(v: string, vtype: ValueType): ValueNode =
  result = ValueNode(valueType: vtype)
  case vtype
  of vtShortStr:
    result.shortStrValue = v
  of vtLongStr:
    result.longStrValue = v
  else:
    raise newException(ValueError, "Cannot transform string to non-string ValueNode")

converter toNode*(table: Table[string, ValueNode]): ValueNode =
  # TODO add grammar checks
  # e.g. keys start with '$', '#', or letters. See 4.2.1 Formal Protocol Grammar for full spec
  result = ValueNode(valueType: vtTable, keys: @[], values: @[])
  for k, v in table.pairs:
    result.keys.add(k)
    result.values.add(v)

converter toNode*(v: int8 | uint8): ValueNode =
  result = ValueNode(
    valueType: vtShortShort,
    shortShortValue: v.int
  )

converter toNode*(v: int16): ValueNode =
  result = ValueNode(
    valueType: vtShort,
    shortValue: v
  )

converter toNode*(v: uint16): ValueNode =
  result = ValueNode(
    valueType: vtShortU,
    shortUValue: v.int
  )

converter toNode*(v: uint32): ValueNode =
  result = ValueNode(
    valueType: vtLongU,
    longUValue: v.int
  )

# Encode value nodes
proc encode*(vnode: ValueNode): seq[char] =
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
      # Encode key
      encodedTable &= encode(vnode.keys[i].toNode(vtShortStr))
      let valueValue = vnode.values[i]
      assert 1 == ($valueValue.valueType).len
      # Encode value type
      encodedTable &= ($valueValue.valueType)[0]
      # Encode value
      encodedTable &= encode(valueValue)

    result &= encode(encodedTable.len.uint32)
    result &= encodedTable
  of vtShortShort:
    result &= encode(vnode.shortShortValue.int8)
  of vtShortShortU:
    result &= encode(vnode.shortShortUValue.uint8)
  of vtShort:
    result &= encode(vnode.shortValue.int16)
  of vtShortU:
    result &= encode(vnode.shortUValue.uint16)
  of vtLongU:
    result &= encode(vnode.longUValue.uint32)
  else:
    # TODO add more cases
    raise newException(ValueError, "Cannot encode $#" % [$vnode])

proc encode*(params: varargs[ValueNode]): seq[char] =
  return params.foldl(a & encode(b), newSeq[char]())
# TODO make this a test suite later...
when isMainModule:
  echo toNode({"a": ValueNode(valueType: vtShort, shortValue: 1)}.toTable)
