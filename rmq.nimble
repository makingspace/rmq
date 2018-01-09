# Package

version       = "0.1.0"
author        = "Zach Smith"
description   = "An AMQP library for Nim."
license       = "BSD3"
srcDir        = "src"

# Dependencies
requires "nim >= 0.17.2"

import strutils
proc runApp(release = false) =
    let cmd = "nim c -r $# rmq" % (if release: "-d:release" else: "")
    exec cmd

task tests, "Run test suite":
    exec "nim c -r tests"

task app, "Start AMQP client":
    runApp()

task release, "Start AMQP client (release mode)":
    runApp(release = true)
