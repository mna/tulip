#!/usr/bin/env lua

local fn = require 'fn'
local tulip = require 'tulip'
local OptionParser = require 'optparse'

local help = string.format([[
v%s
Usage: tulip [<options>] DOMAIN

By default, this is sufficient to run the most common case, which
is to deploy the latest tagged version to the existing infrastructure
associated with that sub-domain (as identified by looking up the

Options:

  --create=R:S:I        Create a new node using region R, size S and the optional
                        image I (creates a new image if not provided).
  --firewall=NAME       Assign this firewall to the new node. Requires --create.
  -h, --help            Display this help and exit.
  --project=NAME        Assign the new node to this project. Requires --create.
  --ssh-keys=k1,k2,...  Associate the ssh keys identified by the comma-separated list of key
                        names with the new node. Requires --create.
  --tags=t1,t2,...      Associate the comma-separated list of tags with the new node.
                        Requires --create.
  -V, --version         Display the version and exit.
  --with-code=TAG       Installs the code at the git version identified by TAG. Defaults to
                        the latest tag.
  --with-db=DB          Restores or installs the specified database backup.
  --without-code        Does not deploy code.
]], tulip.VERSION)

local parser = OptionParser(help)
local arg, opts = parser:parse(_G.arg)

local found, ix = fn.any(function(_, v)
  return string.match(v, '^%-%-?[^%-]+')
end, ipairs(arg))
if found then
  parser:opterr(string.format('unrecognized flag: %s', arg[ix]))
  return
elseif #arg > 1 then
  parser:opterr(string.format('unexpected arguments starting with: %s', arg[1]))
  return
elseif #arg == 0 then
  parser:opterr('the domain argument is required')
  return
end

local main = require 'tulip.main'
main(arg[1], opts)
