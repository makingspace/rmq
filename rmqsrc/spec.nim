import tables, sequtils, strutils

type
  ChannelNumber* = uint16
  Class* = enum
    cNull                       # For discriminant
    cConnection = "Connection"  # work with socket connections
    cChannel = "Channel"        # work with channels
    cExchange = "Exchange"      # work with exchanges
    cQueue = "Queue"            # work with exchanges
    cBasic = "Basic"            # work with basic content

  MethodId* = enum
    mNull                     # For discriminant
    mStart = "Start"          # start connection negotiation
    mStartOk = "StartOk"      # select security mechanism and locale
    mSecure = "Secure"        # security mechanism challenge
    mSecureOk = "SecureOk"    # security mechanism response
    mTune = "Tune"            # propose connection tuning parameters
    mTuneOk = "TuneOk"        # negotiate connection tuning parameters
    mOpen = "Open"            # open connection to virtual host
    mOpenOk = "OpenOk"        # signal that connection is ready
    mClose = "Close"          # request a connection close
    mCloseOk = "CloseOk"      # confirm a connection close

# TODO add more methods

const
  VERSION_MAJOR* = 0.char
  VERSION_MINOR* = 9.char
  VERSION_REVISION* = 1.char

  FRAME_HEADER_SIZE* = 7
  FRAME_END_SIZE* = 1
  FRAME_END* = 206.uint8

  FRAME_MAX_SIZE* = 131072.uint32
  BODY_MAX_LENGTH* = FRAME_MAX_SIZE - FRAME_HEADER_SIZE - FRAME_END_SIZE

  MAX_CHANNELS* = uint16.high
  DEFAULT_HEARTBEAT_TIMEOUT* = uint16.low

let
  METHODS = {
    (10.uint16, 10.uint16): (cConnection, mStart),       # start connection negotiation
    (10.uint16, 11.uint16): (cConnection, mStartOk),     # select security mechanism and locale
    (10.uint16, 20.uint16): (cConnection, mSecure),      # security mechanism challenge
    (10.uint16, 21.uint16): (cConnection, mSecureOk),    # security mechanism response
    (10.uint16, 30.uint16): (cConnection, mTune),        # propose connection tuning parameters
    (10.uint16, 31.uint16): (cConnection, mTuneOk),      # negotiate connection tuning parameters
    (10.uint16, 40.uint16): (cConnection, mOpen),        # open connection to virtual host
    (10.uint16, 41.uint16): (cConnection, mOpenOk),      # signal that connection is ready
    (10.uint16, 50.uint16): (cConnection, mClose),       # request a connection close
    (10.uint16, 51.uint16): (cConnection, mCloseOk)      # confirm a connection close
  }.toTable

  METHOD_VALS = toSeq(METHODS.pairs).mapIt((it[1], it[0])).toTable

proc toMethod*(cNum: uint16, mNum: uint16): (Class, MethodId)  =
  let key = (cnUm, mNum)
  if key notin METHODS:
    raise newException(KeyError, "No method for Class ID: $# and Method ID: $#" % [$cNum, $mNum])
  return METHODS[key]

proc fromMethod*(c: Class, m: MethodId): (uint16, uint16) =
  let key = (c, m)
  if key notin METHOD_VALS:
    raise newException(KeyError, "No value for Class: $# and Method: $#" % [$c, $m])
  return METHOD_VALS[key]
