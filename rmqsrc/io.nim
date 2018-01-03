import asyncdispatch, net, logging
import connection

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

proc handleEvents*(connection: Connection) {.async.} =
  let events = connection.events
  if connection.connected and ceWrite in events:
    connection.handleWrite()

  # TODO:
  # if connection.connected and READ in events:
  #   connection.handleRead()

  # if connection.connected and ERROR in events:
  #   connection.handleError()

