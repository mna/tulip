local function bash()
  return [[#!/usr/bin/env bash

set -euo pipefail
]]
end

local function stop()
  return [[
# stop both the DB and app services
systemctl stop app
systemctl stop postgresql
]]
end

local function install(tag)
  return string.format([[
if [ -d "/opt/app" ]; then
  rm -rf /opt/app.bak
  mv -T /opt/app /opt/app.bak
fi

mkdir -p /opt/app
curl -o /tmp/%s.tar.gz "https://git.sr.ht/~mna/luaweb/archive/%s.tar.gz"
cd /tmp
tar --strip-components=1 --directory /opt/app -xzf %s.tar.gz
rm -f /tmp/%s.tar.gz
]], tag, tag, tag, tag)
end

local function luadeps()
  return [[
cd /opt/app
luarocks install --only-deps *.rockspec
]]
end

return function(tag)
  return table.concat{
    bash(),
    stop(),
    install(tag),
    luadeps(),
  }
end
