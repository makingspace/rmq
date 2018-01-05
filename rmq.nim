import asyncdispatch, logging, net, os
import rmqsrc/[connections, events]
import parseopt2
from strutils import parseInt

addHandler newConsoleLogger()

proc run(connection: Connection) {.async.} =

  connection.connect()

  assert connection.connected, "Unable to connect to AMQP server."
  assert connection.framesWaiting, "Not ready to initiate AMQP protocol."

  while connection.connected and not (connection.state == csClosed):
    await connection.handleEvents()
    await sleepAsync 1

when isMainModule:
  var
    host = "192.168.111.222"
    port = 5672
    username = "user"
    password = "password"

  for kind, key, value in getopt():
    case kind
    of cmdLongOption:
      case key
      of "host":
        host = value
      of "port":
        port = parseInt(value)
    else:
      continue

  let
    params = (host: host, port: port, username: username, password: password)
    connection = newConnection(params)

  proc closeHandler() {.noconv.} = connection.close()

  setControlCHook(closeHandler)

  waitFor connection.run()

  info "Session complete. Diagnostics: ", $connection.diagnostics
