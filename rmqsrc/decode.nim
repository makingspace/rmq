import strutils, options, streams, endians, tables, sequtils, times
import frame, spec, methods, values, utils/strutils as rmqStrUtils


type
  FrameParams = tuple
    frameKind: FrameKind
    frameChannel: uint16
    frameSize: uint32
  DecodedFrame* = tuple[consumed: int, frame: Option[Frame]]

proc readBigEndian32(s: Stream): int32 =
  result = s.readInt32
  bigEndian32(addr result, addr result)

proc readBigEndianU64(s: Stream): uint64 =
  result = s.readUInt64
  bigEndian64(addr result, addr result)

proc readBigEndian64(s: Stream): int64 =
  result = s.readInt64
  bigEndian64(addr result, addr result)

proc readBigEndianU32(s: Stream): uint32 =
  result = s.readUInt32
  bigEndian32(addr result, addr result)

proc readBigEndian16(s: Stream): int16 =
  result = s.readInt16
  bigEndian16(addr result, addr result)

proc readBigEndianU16(s: Stream): uint16 =
  result = s.readUInt16
  bigEndian16(addr result, addr result)

proc readVersionNumber(s: Stream): auto = s.readUInt8
proc readFrameKind(s: Stream): FrameKind = s.readUInt8.FrameKind
proc readChannelNumber(s: Stream): auto = s.readBigEndianU16
proc readClassId(s: Stream): auto = s.readBigEndianU16
proc readMethodId(s: Stream): auto = s.readBigEndianU16
proc readHeartbeat(s: Stream): auto = s.readBigEndianU16
proc readFrameSize(s: Stream): auto = s.readBigEndianU32

proc readFrameParams(s: Stream): FrameParams =
  let
    frameKind = s.readFrameKind
    channelNumber = s.readChannelNumber
    frameSize = s.readFrameSize
  (frameKind, channelNumber, frameSize)

proc decodeValue*(data: Stream, typeChr: char = 0.chr): ValueNode =
  var
    valueTypeChr: char
  if typeChr == 0.chr:
    valueTypeChr = data.readChar
  else:
    valueTypeChr = typeChr

  let valueType = parseEnumStyleSensitive[ValueType]($valueTypeChr)
  result = ValueNode(valueType: valueType)
  case valueType:
    of vtBool:
      result.boolValue = data.readUInt8.bool
    of vtShortShort:
      result.shortShortValue = data.readInt8.int
    of vtShortShortU:
      result.shortShortUValue = data.readUInt8.int
    of vtShort:
      result.shortValue = data.readBigEndian16.int
    of vtShortU:
      result.shortUValue = data.readBigEndianU16.int
    of vtLong:
      result.longValue = data.readBigEndian32.int
    of vtLongU:
      result.longUValue = data.readBigEndianU32.int
    of vtLongLong:
      result.longlongValue = data.readBigEndianU64.int
    of vtLongLongU:
      result.longLongUValue = data.readBigEndianU64.int
    of vtFloat:
      result.floatValue = data.readFloat32.float
    of vtDouble:
      result.doubleValue = data.readFloat64
    of vtDecimal:
      result.decimalValue = data.readStr(4)
    of vtShortStr:
      let length = data.readUInt8.int
      result.shortStrValue = data.readStr(length)
    of vtLongStr:
      let
        length = data.readBigEndianU32.int
        longStrValue = data.readStr(length)
      result.longStrValue = longStrValue
    of vtArray:
      let length = data.readBigEndianU32.int

      var
        substream = data.newStringStream(length)
        arrayNodeValue = newSeq[ValueNode]()

      while not substream.atEnd:
        let arrayValue = substream.decodeValue
        arrayNodeValue.add(arrayValue)

      result.arrayValue = arrayNodeValue
    of vtTimeStamp:
      result.timeStampValue = data.readBigEndianU64.int.fromUnix
    of vtTable:
      let size = data.readBigEndianU32.int

      var
        substream = data.newStringStream(size)
        keys = newSeq[string]()
        values = newSeq[ValueNode]()

      while not substream.atEnd:
        var
          key = substream.decodeValue(typeChr = 's')
          valueNode = substream.decodeValue

        keys.add(key.shortStrValue)
        values.add(valueNode)

      result.keys = keys
      result.values = values
    of vtNull:
      discard

proc decodeConnectionStart(data: Stream): Method =
  let
    versionMajor = data.readVersionNumber
    versionMinor = data.readVersionNumber
    serverPropertiesNode = data.decodeValue(typeChr = 'F')
    serverPropertiesTable = zip(serverPropertiesNode.keys, serverPropertiesNode.values).toTable
    mechanisms = data.decodeValue(typeChr = 'S').longStrValue
    locales = data.decodeValue(typeChr = 'S').longStrValue

  result = initMethodStart(
    versionMajor, versionMinor, serverPropertiesTable, mechanisms, locales
  )

proc decodeTune(data: Stream): Method =
  let
    channelMax = data.readChannelNumber
    frameMax = data.readFrameSize
    heartbeat = data.readHeartbeat

  result = initMethodTune(channelMax, frameMax, heartbeat)

proc decodeOpenOk(data: Stream): Method =
  let knownHosts = data.decodeValue(typeChr = 's').shortStrValue

  result = initMethodOpenOk(knownHosts)

proc decodeCloseOk(data: Stream): Method =
  result = initMethodCloseOk()

proc decodeMethod(data: Stream): Method =
  let
    classNum = data.readClassId
    methodNum = data.readMethodId

  let (_, methodId) = toMethod(classNum, methodNum)

  case methodId
  of mStart: data.decodeConnectionStart()
  of mTune: data.decodeTune()
  of mCloseOk: data.decodeCloseOk()
  of mOpenOk: data.decodeOpenOk()
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
