type
  ChannelNumber* = uint16
  Class* = enum
    cConnection = 10, # work with socket connections
    cChannel = 20,    # work with channels
    cExchange = 30,   # work with exchanges
    cQueue = 40,      # work with exchanges
    cBasic = 50       # work with basic content

  MethodId* = enum
    mNull = 0,        # For discriminant
    mStart = 10,      # start connection negotiation
    mStartOk = 11,    # select security mechanism and locale
    mSecure = 20,     # security mechanism challenge
    mSecureOk = 21,   # security mechanism response
    mTune = 30,       # propose connection tuning parameters
    mTuneOk = 31,     # negotiate connection tuning parameters
    mOpen = 40,       # open connection to virtual host
    mOpenOk = 41,     # signal that connection is ready
    mClose = 50,      # request a connection close
    mCloseOk = 51     # confirm a connection close

# TODO add more methods

const
  VERSION_MAJOR* = 0.char
  VERSION_MINOR* = 9.char
  VERSION_REVISION* = 1.char

  FRAME_HEADER_SIZE* = 7
  FRAME_END_SIZE* = 1

  FRAME_MAX_SIZE* = 131072
  BODY_MAX_LENGTH* = FRAME_MAX_SIZE - FRAME_HEADER_SIZE - FRAME_END_SIZE
