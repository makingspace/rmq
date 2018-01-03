import asyncdispatch, logging, net
import rmqsrc/[connection, events]
import parseopt2
from strutils import parseInt

addHandler newConsoleLogger()

proc main(host: string, port: int) =
  var
    params = (host: host, port: port)
    c = newConnection(params)

  connect(c)

  assert c.connected
  assert c.framesWaiting

  waitFor c.handleEvents()

  assert(not c.framesWaiting)

  info "Connection diagnostics: " & $c.diagnostics

when isMainModule:
  var
    host = "192.168.111.222"
    port = 5672

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

  main(host, port)
