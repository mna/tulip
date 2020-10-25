#!/usr/bin/env -S llrocks run

local fn = require 'fn'
local OptionParser = require 'optparse'

local help = [[
v0.0.0
Usage: deploy.lua [<options>] DOMAIN

The deploy script is the combination of:
1. create an infrastructure (optional)
2. install the database on that infrastructure (optional)
3. deploy the new code to that infrastructure (optional)
4. (re)start the application's services
5. activate this deployment (optional)

The usage of the command looks like this:

$ deploy www.example.com

By default, this is sufficient to run the most common case, which
is to deploy the current HEAD to the existing infrastructure
associated with that sub-domain (as identified by looking up the
node with the IP address linked to the sub-domain). The existing
database is left untouched, and only the new code is deployed and
the application is restarted (so only steps 3 and 4 are executed).

More complex scenarios follow:

$ deploy --create 'region:size[:image]' --ssh-keys 'list,of,names' --tags 'list,of,tags' www.example.com

    Create a new infrastructure with the specified region, size, and optional image,
    and enable the ssh keys identified by name and apply the set of tags.
    If no image is provided, a new image is created and used. Steps 1, 2 (an empty database),
    3, 4 and 5 are executed. Step 5 simply involves mapping the sub-domain to the IP address
    of the new node.

$ deploy --create ... --with-db 'db-backup-id' www.example.com

    Create a new infrastructure, but restores the database from the specified backup.

$ deploy --with-db 'db-backup-id' --with-code 'git-tag' www.example.com

    Restore the database from the specified backup in the existing infrastructure (so, execute
    steps 2, 3 and 4 only).

$ deploy --with-db 'db-backup-id' --without-code www.example.com

    Restore the database from the specified backup in the existing infrastructure and do not
    deploy any code (so, execute steps 2 and 4 only).

Options:

  --create=R:S:I        Create a new node using region R, size S and the optional
                        image I (creates a new image if not provided).
  -h, --help            Display this help and exit.
  --ssh-keys=k1,k2,...  Associate the ssh keys identified by the comma-separated list of key
                        names with the new node. Requires --create.
  --tags=t1,t2,...      Associate the comma-separated list of tags with the new node.
                        Requires --create.
  -V, --version         Display the version and exit.
  --with-code=TAG       Installs the code at the git version identified by TAG. Defaults to
                        the current HEAD.
  --with-db=DB          Restores or installs the specified database backup.
  --without-code        Does not deploy code.
]]

-- TODO: assign infra to a project, assign a firewall to node?

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

local cmd = require 'scripts.cmds.deploy'
cmd(arg[1], opts)
