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
    info "Socket timeout on write."

proc handleRead(connection: Connection) =
  try:
    discard connection.recv()
  except TimeoutError:
    info "Socket timeout on read."


proc handleEvents*(connection: Connection) {.async.} =
  let events = connection.events
  if connection.connected and ceWrite in events:
    connection.handleWrite()

  if connection.connected and ceRead in events:
    connection.handleRead()

  # if connection.connected and ERROR in events:
  #   connection.handleError()

