import asyncdispatch, net, logging, strutils, asyncnet
import connections

proc handleWrite(connection: Connection) {.async.} =
    while connection.framesWaiting:
      let frame = connection.nextFrame()
      await connection.send(frame)

proc handleRead(connection: Connection) {.async.} =
  try:
    asyncCheck connection.recv()
  except TimeoutError:
    info "Socket timeout on read."

proc manageEventState(connection: Connection) =
  if connection.framesWaiting:
    connection.scheduleWrite()
  else:
    connection.clearWrite()

proc handleEvents*(connection: Connection) {.async.} =
  let events = connection.events

  if connection.connected and ceWrite in events:
    await connection.handleWrite()
    connection.manageEventState()

  if connection.connected and ceRead in events:
    await connection.handleRead()

  # if connection.connected and ERROR in events:
  #   connection.handleError()

