import strutils, options, streams, endians, tables
import frame, spec

type
  FrameParams = tuple
    frameKind: FrameKind
    frameChannel: uint16
    frameSize: uint32
  DecodedFrame* = tuple[consumed: int, frame: Option[Frame]]

proc readFrameKind(s: Stream): FrameKind =
  result = s.readUInt8.FrameKind

proc readBigEndian16(s: Stream): uint16 =
  result = s.readUInt16
  bigEndian16(addr result, addr result)

proc readChannelNumber(s: Stream): uint16 = readBigEndian16(s)
proc readMethodId(s: Stream): uint32 = readBigEndian16(s)

proc readBigEndian32(s: Stream): uint32 =
  result = s.readUInt32
  bigEndian32(addr result, addr result)

proc readFrameSize(s: Stream): uint32 = readBigEndian32(s)

proc readFrameParams(s: Stream): FrameParams =
  let
    frameKind = s.readFrameKind
    channelNumber = s.readChannelNumber
    frameSize = s.readFrameSize
  (frameKind, channelNumber, frameSize)

proc decodeShortString(data: Stream): string =
  let length = data.readUInt8.int
  result = data.readStr(length.int)

proc decodeLongString(data: Stream): string =
  let length = data.readBigEndian16
  result = data.readStr(length.int)

type
  TaggedValue = tuple[valueType: ValueType, length, consumed: int]
  ValueType = enum
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
    vtTable,

proc getValueType(data: Stream): TaggedValue =
  let
    valueTypeChr = data.readChar

  result = case valueTypeChr:
    of 't': (vtBool, 1, 1)
    of 'b': (vtShortShort, 1, 1)
    of 'B': (vtShortShortU, 1, 1)
    of 'U': (vtShort, 2, 1)
    of 'u': (vtShortU, 2, 1)
    of 'I': (vtLong, 4, 1)
    of 'i': (vtLongU, 4, 1)
    of 'L': (vtLongLong, 8, 1)
    of 'l': (vtLongLongU, 8, 1)
    of 'f': (vtFloat, 4, 1)
    of 'd': (vtDouble, 8, 1)
    of 'D': (vtDecimal, 4, 1)
    of 's': (vtShortStr, data.readUInt8.int, 2)
    of 'S': (vtLongStr, data.readBigEndian32.int, 5)
    of 'A': (vtArray, data.readBigEndian32.int, 5)
    of 'T': (vtTimeStamp, 8, 1)
    of 'F': (vtTable, data.readBigEndian32.int, 5)
    else: (vtNull, 0, 1)


proc decodeTable(data: Stream): Table[string, string] =
  # TODO: For now we do not evaluate table values.
  result = initTable[string, string]()
  let
    size = data.readBigEndian16.int
  var
    subBuffer = data.readStr(size).newStringStream()
    read = 0

  while read < size:
    var
      key = subBuffer.decodeShortString
      (_, length, consumed) = subBuffer.getValueType
      value = subBuffer.readStr(length)

    read += key.len + 1
    read += consumed
    read += length
    result[key] = value

proc decodeMethod(data: Stream): Method =
  result = Method()
  let methodId = readMethodId(data).MethodId
  data.setPosition(data.getPosition + 2)
  case methodId
  of mStart:
    result.kind = mStart
    result.versionMajor = data.readUInt8
    result.versionMinor = data.readUInt8

    data.setPosition(data.getPosition + 2)
    result.serverProperties = data.decodeTable

    data.setPosition(data.getPosition + 2)
    let mechanismsLength = data.readBigEndian16.int
    result.mechanisms = data.readStr(mechanismsLength)

    data.setPosition(data.getPosition + 2)
    let localesLength = data.readBigEndian16.int
    result.locales = data.readStr(localesLength)
  else:
    discard

proc decode*(data: string): DecodedFrame =
  if data.startsWith("AMQP"):
    try:
      let
        major = data[5]
        minor = data[6]
        revision = data[7]

      result = (8, some initProtocolHeader(major, minor, revision))
    except IndexError:
      result = (0, none Frame)
  else:
    var stringStream = newStringStream(data)
    let
      (frameKind, frameChannel, frameSize) = readFrameParams(stringStream)
      frameEnd = FRAME_HEADER_SIZE + frameSize.int + FRAME_END_SIZE

    if frameEnd > data.len:
      # We don't have all the data yet.
      result = (0, none Frame)

    case frameKind
    of fkMethod:
      let decodedMethod = decodeMethod(stringStream)
      result = (frameEnd, some initMethod(frameChannel, decodedMethod))
    else:
      result = (0, none Frame)
