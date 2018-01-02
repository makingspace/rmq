import asyncdispatch, logging, net
import rmqsrc/connection

addHandler newConsoleLogger()

proc handleWrite(connection: Connection) =
  try:
    while connection.framesWaiting:
      let frame = connection.nextFrame()
      while true:
        let success = connection.send(frame)
        if success:
          break
        else:
          raise newException(ValueError, "Socket failed.")
  except TimeoutError:
    info "Socket timeout."

proc handleEvents(connection: Connection) {.async.} =
  let events = connection.events
  if connection.connected and WRITE in events:
    connection.handleWrite()

  # TODO:
  # if connection.connected and READ in events:
  #   connection.handleRead()

  # if connection.connected and ERROR in events:
  #   connection.handleError()


when isMainModule:
  # user:user@192.168.111.222:5672
  var
    params = (host: "192.168.111.222", port: 5672)
    c = newConnection(params)

  connect(c)

  assert c.connected
  assert c.framesWaiting

  waitFor c.handleEvents()

  assert (not c.framesWaiting)
