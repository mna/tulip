local function bash()
  return [[#!/usr/bin/env bash

set -euo pipefail
]]
end

local function stop()
  return [[
# stop both the DB and app services
# TODO: create app service in base image?
# systemctl stop app
systemctl stop postgresql
]]
end

local function install(tag)
  return string.format([[
mkdir -p /opt/app
curl -o /tmp/%s.tar.gz "https://git.sr.ht/~mna/luaweb/archive/%s.tar.gz"
cd /tmp
tar -xzf %s.tar.gz
mv %s/* /opt/app/
]], tag, tag, tag, tag)
end

return function(tag)
  return table.concat{
    bash(),
    stop(),
    install(tag),
  }
end
