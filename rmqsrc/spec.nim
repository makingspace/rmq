type
  Class* = enum
    cConnection = 10, # work with socket connections
    cChannel = 20,    # work with channels
    cExchange = 30,   # work with exchanges
    cQueue = 40,      # work with exchanges
    cBasic = 50       # work with basic content

  Method* = enum
    mStart = 10,      # start connection negotiation
    mStartOk = 11,    # select security mechanism and locale
    mSecure = 20,     # security mechanism challenge
    mSecureOk = 21,   # security mechanism response
    mTune = 30,       # propose connection tuning parameters
    mTuneOk = 31,     # negotiate connection tuning parameters
    mOpen = 40,       # open connection to virtual host
    mOpenOk = 41,     # signal that connection is ready
    mClose = 50,      # request a connection close
    mClosek = 51,     # confirm a connection close

# TODO add more methods
