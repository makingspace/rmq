import asyncdispatch, logging, net
import rmqsrc/[connection, events]

addHandler newConsoleLogger()

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

  info "Connection diagnostics: " & $c.diagnostics
