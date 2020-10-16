#!/usr/bin/env -S llrocks run

-- ensure luashell is present
if not os.execute('llrocks list | grep luashell') then
  assert(os.execute('llrocks install luashell'))
end

-- now we can require it and run the script
local sh = require 'shell'

-- genpwd generates a secure random password and stores it in the file
-- run/secrets/{name}. If label is provided, the file is chcon'd with
-- this label.
local function genpwd(name, label)
  local file = string.format('run/secrets/%s', name)
  ;(sh.cmd('openssl', 'rand', '-base64', '32') | sh.cmd('tr', '-d', '/')):redirect(file, true)
  sh('chmod', '0600', file)

  if label then
    sh('chcon', '-Rt', label, file)
  end
end

io.write('>>> database directories\n')
if sh.test[[-d db/postgres/data]] then
  io.write('<<< database directories already created, skipping\n')
else
  sh('mkdir', '-p', 'db/postgres/data')

  -- change the SELinux label for the volume to be mounted on the container
  sh('chcon', '-Rt', 'svirt_sandbox_file_t', 'db/postgres/data')
  sh('chcon', '-Rt', 'svirt_sandbox_file_t', 'db/postgres/config')
end

io.write('>>> certificates\n')
sh('mkdir', '-p', 'run/certs')
if sh.test[[-s run/certs/fullchain.pem]] and sh.test[[-s run/certs/privkey.pem]] then
  io.write('<<< localhost certificate already generated, skipping\n')
else
  sh('mkcert', '-install')
  sh('mkcert',
    '-cert-file', 'run/certs/fullchain.pem',
    '-key-file', 'run/certs/privkey.pem',
    'localhost', '127.0.0.1', '::1')
end

io.write('>>> root password\n')
sh('mkdir', '-p', 'run/secrets')
if sh.test[[-s run/secrets/pgroot_pwd]] then
  io.write('<<< root password already generated, skipping\n')
else
  genpwd('pgroot_pwd', 'svirt_sandbox_file_t')
end
io.write('>>> pgpass file\n')
if sh.test[[-s run/secrets/pgpass]] then
  io.write('<<< pgpass already generated, skipping\n')
else
  sh.cmd('echo', '-n', 'localhost:5432:postgres:postgres:'):redirect('run/secrets/pgpass')
  sh.cmd('cat', 'run/secrets/pgroot_pwd'):redirect('run/secrets/pgpass')
  sh('chmod', '0600', 'run/secrets/pgpass')
end
io.write('>>> csrf auth key\n')
if sh.test[[-s run/secrets/csrf_key]] then
  io.write('<<< csrf key already generated, skipping\n')
else
  genpwd('csrf_key')
end

io.write('>>> environment variables\n')
if sh.test[[-s ./.envrc]] then
  io.write('<<< envrc already generated, skipping\n')
else
  sh.cmd('echo', [[
export PGPASSFILE=`pwd`/run/secrets/pgpass
export PGHOST=localhost
export PGPORT=5432
export PGCONNECT_TIMEOUT=10
export PGUSER=postgres
export PGDATABASE=postgres

export LUAWEB_CSRFKEY=`cat run/secrets/csrf_key`
  ]]):redirect('./.envrc')
end

io.write('>>> lua dependencies\n')
local luaver = (sh.cmd('lua', '-v') |
                sh.cmd('cut', '-d', ' ', '-f2') |
                sh.cmd('cut', '-d', '.', '-f1,2')):output()
-- TODO: luarocks-fetch-gitrec must be installed in standard location,
-- i.e. via luarocks install.
local rocksfile = 'luaweb-git-1.rockspec'
sh.cmd('echo', string.format([[
package = %q
build = {
  type = 'builtin'
}
dependencies = {
  -- TODO: double-check that list
  "lua ~> %s",
  "basexx	0.4.1-1",
  "binaryheap	0.4-1",
  "compat53	0.8-1",
  "cqueues	20200726.53-0",
  "cqueues-pgsql	0.1-0",
  "fifo	0.2-0",
  "http	0.3-0",
  "inspect	3.1.1-0",
  "lpeg	1.0.2-1",
  "lpeg_patterns	0.5-0",
  "lua-resty-template 2.0-1",
  "luabenchmark	0.10.0-1",
  "luacov	0.14.0-1",
  "luafn	0.1-1",
  "luaossl	20200709-0",
  "luapgsql	1.6.1-1",
  "luaposix	35.0-1",
  "luashell	0.4-1",
  "luaunit	3.3-1",
  "net-url	0.9-1",
  "optparse	1.4-1",
  "process 1.9.0-1",
  "tcheck	0.1-1",
  "xpgsql	0.4-1",
}
source = {
  url = '...'
}
version = 'git-1'
]], 'luaweb', luaver)):redirect(rocksfile, true)
-- install luaossl first as it requires special parameters
sh('llrocks', 'install', 'luaossl', 'CFLAGS=-DHAVE_EVP_KDF_CTX=1 -fPIC')
sh('llrocks', 'install', '--only-deps', rocksfile)

io.write('>>> starting database\n')
sh('docker-compose', 'up', '-d')

io.write[[
All done!

Once the database is ready for connections, you may run the tests.

Make sure to allow direnv to apply the generated .envrc file by
running `direnv allow .`!
]]
