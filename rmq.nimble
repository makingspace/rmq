# Package

version       = "0.1.0"
author        = "Zach Smith"
description   = "An AMQP library for Nim."
license       = "BSD3"
srcDir        = "src"

# Dependencies

requires "nim >= 0.17.2"

task tests, "Run test suite":
    exec "nim c -r tests"
