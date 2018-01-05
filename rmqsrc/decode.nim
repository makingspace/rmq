import strutils, options, streams, endians, tables, sequtils
import times
import frame, spec, methods, values

type
  FrameParams = tuple
    frameKind: FrameKind
    frameChannel: uint16
    frameSize: uint32
  DecodedFrame* = tuple[consumed: int, frame: Option[Frame]]

proc readFrameKind(s: Stream): FrameKind =
  result = s.readUInt8.FrameKind

proc readBigEndianU16(s: Stream): uint16 =
  result = s.readUInt16
  bigEndian16(addr result, addr result)

proc readChannelNumber(s: Stream): auto = readBigEndianU16(s)

proc readBigEndian16(s: Stream): int16 =
  result = s.readInt16
  bigEndian16(addr result, addr result)

proc readClassId(s: Stream): auto = readBigEndianU16(s)
proc readMethodId(s: Stream): auto = readBigEndianU16(s)

proc readBigEndianU32(s: Stream): uint32 =
  result = s.readUInt32
  bigEndian32(addr result, addr result)

proc readFrameSize(s: Stream): auto = readBigEndianU32(s)

proc readBigEndian32(s: Stream): int32 =
  result = s.readInt32
  bigEndian32(addr result, addr result)

proc readBigEndianU64(s: Stream): uint64 =
  result = s.readUInt64
  bigEndian64(addr result, addr result)

proc readBigEndian64(s: Stream): int64 =
  result = s.readInt64
  bigEndian64(addr result, addr result)

proc readFrameParams(s: Stream): FrameParams =
  let
    frameKind = s.readFrameKind
    channelNumber = s.readChannelNumber
    frameSize = s.readFrameSize
  (frameKind, channelNumber, frameSize)

proc initSubStream(s: Stream, length: int): Stream =
  ## Given a number of bytes, consume them from the stream and return a new
  ## stream made from the resulting string.
  let substring = s.readStr(length)
  result = substring.newStringStream

proc decodeValue(data: Stream, typeChr: char = 0.chr): ValueNode =
  var
    valueTypeChr: char
  if typeChr == 0.chr:
    valueTypeChr = data.readChar
  else:
    valueTypeChr = typeChr

  case valueTypeChr:
    of 't':
      result = ValueNode(
        valueType: vtBool,
        boolValue: data.readUInt8.bool
      )
    of 'b':
      result = ValueNode(
        valueType: vtShortShort,
        shortShortValue: data.readInt8.int
      )
    of 'B':
      result = ValueNode(
        valueType: vtShortShortU,
        shortShortUValue: data.readUInt8.int
      )
    of 'U':
      result = ValueNode(
        valueType: vtShort,
        shortValue: data.readBigEndian16.int
      )
    of 'u':
      result = ValueNode(
        valueType: vtShortU,
        shortUValue: data.readBigEndianU16.int
      )
    of 'I':
      result = ValueNode(
        valueType: vtLong,
        longValue: data.readBigEndian32.int
      )
    of 'i':
      result = ValueNode(
        valueType: vtLongU,
        longUValue: data.readBigEndianU32.int
      )
    of 'L':
      result = ValueNode(
        valueType: vtLongLong,
        longLongValue: data.readBigEndianU64.int
      )
    of 'l':
      result = ValueNode(
        valueType: vtLongLongU,
        longLongUValue: data.readBigEndianU64.int
      )
    of 'f':
      result = ValueNode(
        valueType: vtFloat,
        floatValue: data.readFloat32.float
      )
    of 'd':
      result = ValueNode(
        valueType: vtDouble,
        doubleValue: data.readFloat64
      )
    of 'D':
      result = ValueNode(
        valueType: vtDecimal,
        decimalValue: data.readStr(4)
      )
    of 's':
      let length = data.readUInt8.int
      result = ValueNode(
        valueType: vtShortStr,
        shortStrValue: data.readStr(length)
      )
    of 'S':
      let
        length = data.readBigEndianU32.int
        longStrValue = data.readStr(length)
      result = ValueNode(
        valueType: vtLongStr,
        longStrValue: longStrValue
      )
    of 'A':
      let length = data.readBigEndianU32.int

      var
        substream = data.initSubStream(length)
        arrayNodeValue = newSeq[ValueNode]()

      while not substream.atEnd:
        let arrayValue = substream.decodeValue
        arrayNodeValue.add(arrayValue)

      result = ValueNode(
        valueType: vtArray,
        arrayValue: arrayNodeValue
      )
    of 'T':
      result = ValueNode(
        valueType: vtTimeStamp,
        timeStampValue: data.readBigEndianU64.int.fromUnix
      )
    of 'F':
      let size = data.readBigEndianU32.int

      var
        substream = data.initSubStream(size)
        keys = newSeq[string]()
        values = newSeq[ValueNode]()

      while not substream.atEnd:
        var
          key = substream.decodeValue(typeChr = 's')
          valueNode = substream.decodeValue

        keys.add(key.shortStrValue)
        values.add(valueNode)

      result = ValueNode(
        valueType: vtTable,
        keys: keys,
        values: values
      )
    else:
      result = ValueNode(valueType: vtNull)

proc decodeConnectionStart(data: Stream): Method =
  let
    versionMajor = data.readUInt8
    versionMinor = data.readUInt8
    serverProperties = data.decodeValue(typeChr = 'F')
    serverPropertiesTable = zip(serverProperties.keys, serverProperties.values).toTable
    mechanismsLength = data.readBigEndian32.int
    mechanisms = data.readStr(mechanismsLength)
    localesLength = data.readBigEndian32.int
    locales = data.readStr(localesLength)

  result = initMethodStart(
    versionMajor, versionMinor, serverPropertiesTable, mechanisms, locales
  )

proc decodeMethod(data: Stream): Method =
  let
    classNum = data.readClassId
    methodNum = data.readMethodId

  let
    pair = toMethod(classNum, methodNum)
    class = pair[0]
    methodId = pair[1]

  case methodId
  of mStart: data.decodeConnectionStart()
  else: raise newException(ValueError, "Cannot decode Method ID: $#" % [$methodId])

proc decode*(data: string): DecodedFrame =
  if data.startsWith("AMQP"):
    try:
      let
        major = data[5]
        minor = data[6]
        revision = data[7]

      return (8, some initProtocolHeader(major, minor, revision))
    except IndexError:
      return (0, none Frame)
  else:
    var stream = newStringStream(data)
    let
      (frameKind, frameChannel, frameSize) = readFrameParams(stream)
      frameEnd = FRAME_HEADER_SIZE + frameSize.int + FRAME_END_SIZE

    if frameEnd > data.len:
      # We don't have all the data yet.
      return (0, none Frame)

    case frameKind
    of fkMethod:
      let decodedMethod = decodeMethod(stream)
      return (frameEnd, some initMethod(frameChannel, decodedMethod))
    else:
      return (0, none Frame)
