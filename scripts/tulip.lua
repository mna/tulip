#!/usr/bin/env lua

local tulip = require 'tulip'
local OptionParser = require 'optparse'

local help = string.format([[
tulip v%s
Usage: tulip CMD [SUBCMD] [<options>]

The following tulip commands are supported:

  certs                 Manage the localhost certificates.
  db                    Manage the postgresql database.
  env                   Manage the development environment.
  secrets               Manage the local development's secrets.

Options:

  -h, --help            Display this help and exit.
  -V, --version         Display the version and exit.
]], tulip.VERSION)

local parser = OptionParser(help)
local arg, opts = parser:parse(_G.arg)
if #arg == 0 then
  parser:opterr('the command is required')
  return
end

local main = require 'tulip.main'
main(arg[1], arg, opts)
