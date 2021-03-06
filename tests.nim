import unittest, strutils, sequtils, tables, algorithm, options, streams
import rmqsrc/connections, rmqsrc/values, rmqsrc/spec, rmqsrc/methods, rmqsrc/frame, rmqsrc/decode

const
  handShakeStart = @[
    1, 0, 0, 0, 0, 1, 230, 0, 10, 0, 10, 0, 9, 0, 0, 1, 193, 12, 99, 97,
    112, 97, 98, 105, 108, 105, 116, 105, 101, 115, 70, 0, 0, 0, 199, 18,
    112, 117, 98, 108, 105, 115, 104, 101, 114, 95, 99, 111, 110, 102,
    105, 114, 109, 115, 116, 1, 26, 101, 120, 99, 104, 97, 110, 103, 101,
    95, 101, 120, 99, 104, 97, 110, 103, 101, 95, 98, 105, 110, 100, 105,
    110, 103, 115, 116, 1, 10, 98, 97, 115, 105, 99, 46, 110, 97, 99,
    107, 116, 1, 22, 99, 111, 110, 115, 117, 109, 101, 114, 95, 99, 97,
    110, 99, 101, 108, 95, 110, 111, 116, 105, 102, 121, 116, 1, 18, 99,
    111, 110, 110, 101, 99, 116, 105, 111, 110, 46, 98, 108, 111, 99,
    107, 101, 100, 116, 1, 19, 99, 111, 110, 115, 117, 109, 101, 114, 95,
    112, 114, 105, 111, 114, 105, 116, 105, 101, 115, 116, 1, 28, 97,
    117, 116, 104, 101, 110, 116, 105, 99, 97, 116, 105, 111, 110, 95,
    102, 97, 105, 108, 117, 114, 101, 95, 99, 108, 111, 115, 101, 116, 1,
    16, 112, 101, 114, 95, 99, 111, 110, 115, 117, 109, 101, 114, 95,
    113, 111, 115, 116, 1, 15, 100, 105, 114, 101, 99, 116, 95, 114, 101,
    112, 108, 121, 95, 116, 111, 116, 1, 12, 99, 108, 117, 115, 116, 101,
    114, 95, 110, 97, 109, 101, 83, 0, 0, 0, 14, 114, 97, 98, 98, 105,
    116, 64, 118, 97, 103, 114, 97, 110, 116, 9, 99, 111, 112, 121, 114,
    105, 103, 104, 116, 83, 0, 0, 0, 46, 67, 111, 112, 121, 114, 105,
    103, 104, 116, 32, 40, 67, 41, 32, 50, 48, 48, 55, 45, 50, 48, 49,
    55, 32, 80, 105, 118, 111, 116, 97, 108, 32, 83, 111, 102, 116, 119,
    97, 114, 101, 44, 32, 73, 110, 99, 46, 11, 105, 110, 102, 111, 114,
    109, 97, 116, 105, 111, 110, 83, 0, 0, 0, 53, 76, 105, 99, 101, 110,
    115, 101, 100, 32, 117, 110, 100, 101, 114, 32, 116, 104, 101, 32,
    77, 80, 76, 46, 32, 32, 83, 101, 101, 32, 104, 116, 116, 112, 58, 47,
    47, 119, 119, 119, 46, 114, 97, 98, 98, 105, 116, 109, 113, 46, 99,
    111, 109, 47, 8, 112, 108, 97, 116, 102, 111, 114, 109, 83, 0, 0, 0,
    15, 69, 114, 108, 97, 110, 103, 47, 79, 84, 80, 32, 49, 56, 46, 51,
    7, 112, 114, 111, 100, 117, 99, 116, 83, 0, 0, 0, 8, 82, 97, 98, 98,
    105, 116, 77, 81, 7, 118, 101, 114, 115, 105, 111, 110, 83, 0, 0, 0,
    6, 51, 46, 54, 46, 49, 52, 0, 0, 0, 14, 80, 76, 65, 73, 78, 32, 65,
    77, 81, 80, 76, 65, 73, 78, 0, 0, 0, 5, 101, 110, 95, 85, 83, 206
  ].mapIt(it.char).join()

  expectedCapabilities = @[
    "authentication_failure_close", "basic.nack", "connection.blocked",
    "consumer_cancel_notify", "consumer_priorities", "direct_reply_to",
    "exchange_exchange_bindings", "per_consumer_qos", "publisher_confirms"
  ]
  expectedCapabilitiesValuesTypes = @[
    vtBool, vtBool, vtBool, vtBool, vtBool, vtBool, vtBool, vtBool, vtBool
  ]


suite "connection tests":

  setUp:
    let
      params = initConnectionParameters("", 0, username = "", password = "")
      c = newConnection(params)

  test "handle incomplete buffer":
    var handShakeStart = handShakeStart
    handShakeStart.delete(handShakeStart.high - 100, handShakeStart.high)

    c.onDataAvailable(handShakeStart)
    check c.bufferRemaining

    let diagnostics = c.diagnostics
    check (0, 0, 0, 0) == diagnostics
    check 0 == c.serverProperties.len
    check csClosed == c.state

  test "handle Connection.Start":
    c.onDataAvailable(handShakeStart)
    check(not c.bufferRemaining)

    let diagnostics = c.diagnostics
    check (34, 1, 494, 1) == diagnostics
    check 7 == c.serverProperties.len
    check csStart == c.state
    check 9 == c.serverProperties["capabilities"].keys.len
    check expectedCapabilities == c.serverProperties["capabilities"].keys.sorted(system.cmp)
    check expectedCapabilitiesValuesTypes == c.serverProperties["capabilities"].values.mapIt(it.valueType)

suite "decoding":

  test "handle Connection.OpenOk":
    const response = @[
      0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x05, 0x00, 0x0a, 0x00, 0x29, 0x00, 0xce
    ].mapIt(it.char).join

    let (consumed, responseFrame) = response.decode()
    check responseFrame.isSome

    check:
      13 == consumed.int
      "" == responseFrame.get.rpcMethod.mOpenOkParams.knownHosts

suite "encoding":

  test "marshall startok method frame":
    let
      serverProperties = initTable[string, ValueNode]()
      mechanisms = "PLAIN"
      response = "userpassword"
      locales = "en_US"
      m = initMethodStartOk(serverProperties, mechanisms, response, locales)
      f = Frame(
        channelNumber: 1.uint16,
        kind: fkMethod,
        rpcMethod: m
      )

    const expectedMarshaled = @[
      '\x01', '\x00', '\x01', '\x00', '\x00', '\x00', '$', '\x00', '\x0A',
      '\x00', '\x0B', '\x00', '\x00', '\x00', '\x00', '\x05', 'P', 'L', 'A',
      'I', 'N', '\x00', '\x00', '\x00', '\x0C', 'u', 's', 'e', 'r', 'p', 'a',
      's', 's', 'w', 'o', 'r', 'd', '\x05', 'e', 'n', '_', 'U', 'S', '\xCE'
    ]

    check f.marshal() == expectedMarshaled.join()

  test "table encoding":
    let
      t = {"canFoo": true.toNode}.toTable
      node = t.toNode

    check:
      @["canFoo"] == node.keys
      1 == node.values.len
      true == node.values[0].boolValue

    const expectedBytes = @[
      0.chr, 0.chr, 0.chr, 9.chr, 6.chr, 99.chr, 97.chr, 110.chr, 70.chr,
      111.chr, 111.chr, 116.chr, 1.chr
    ]

    let
      simpleTable = {"canFoo": true.toNode}.toTable.toNode
      simpleEncoded = simpleTable.encode()

    check simpleEncoded == expectedBytes

    let
      encoded = node.encode().join().newStringStream
      decoded = encoded.decodeValue(typeChr = 'F')

    check:
      @["canFoo"] == decoded.keys
      1 == decoded.values.len
      true == decoded.values[0].boolValue


suite "codec":

  setUp:
    let
      sampleProperties = {"capabilities": {"canFoo": true.toNode}.toTable.toNode}.toTable
      mechanisms = "PLAIN"
      response = "userpassword"
      locales = "en_US"

  proc reDecode(f: Frame): Frame =
    f.marshal().decode()[1].get()

  test "Protocol":
    let
      f = initProtocolHeader(0.char, 9.char, 1.char)
      decoded = f.reDecode

    check:
      f.major == decoded.major
      f.minor == decoded.minor
      f.revision == decoded.revision

  template checkSharedStartParams() =
    check:
      @["canFoo"] == fParams.serverProperties["capabilities"].keys
      @["canFoo"] == decodedParams.serverProperties["capabilities"].keys
      true == fParams.serverProperties["capabilities"].values[0].boolValue
      true == decodedParams.serverProperties["capabilities"].values[0].boolValue
      mechanisms == fParams.mechanisms
      mechanisms == decodedParams.mechanisms
      locales == fParams.locales
      locales == decodedParams.locales

  test "Connection.Start":
    let
      f = initMethod(0, initMethodStart(0, 9, sampleProperties, "PLAIN", "en_US"))
      decoded = f.reDecode
      fParams = f.rpcMethod.mStartParams
      decodedParams = decoded.rpcMethod.mStartParams
    check:
      fParams.versionMajor == decodedParams.versionMajor
      fParams.versionMinor == decodedParams.versionMinor

    checkSharedStartParams()

  test "Connection.StartOk":
    let
      f = initMethod(0, initMethodStartOk(sampleProperties, mechanisms, response, locales))
      decoded = f.reDecode
      fParams = f.rpcMethod.mStartOkParams
      decodedParams = decoded.rpcMethod.mStartOkParams

    check fParams.response == response
    check decodedParams.response == response
    checkSharedStartParams()

  template checkTuneParams() =

    check:
      fParams.channelMax == decodedParams.channelMax
      fParams.frameMax == decodedParams.frameMax
      fParams.heartbeat == decodedParams.heartbeat

  test "Connection.Tune":
    let
      f = initMethod(0, initMethodTune(0.ChannelNumber, FRAME_MAX_SIZE, DEFAULT_HEARTBEAT_TIMEOUT))
      decoded = f.reDecode
      fParams = f.rpcMethod.mTuneParams
      decodedParams = decoded.rpcMethod.mTuneParams

    checkTuneParams()

  test "Connection.TuneOk":
    let
      f = initMethod(0, initMethodTuneOk(0.ChannelNumber, FRAME_MAX_SIZE, DEFAULT_HEARTBEAT_TIMEOUT))
      decoded = f.reDecode
      fParams = f.rpcMethod.mTuneParams
      decodedParams = decoded.rpcMethod.mTuneParams

    checkTuneParams()
