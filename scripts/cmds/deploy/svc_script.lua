local function bash()
  return [[#!/usr/bin/env bash

set -euo pipefail
]]
end

local function restart()
  return [[
systemctl restart postgresql
systemctl restart app
]]
end

return table.concat{
  bash(),
  restart(),
}
