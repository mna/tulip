local rand = require 'openssl.rand'

-- ensure the CSPRNG is seeded
assert(rand.ready(), 'failed to seed CSPRNG')

local M = {}

-- Reads the full content of path and returns the string. On error,
-- returns nil and the error message.
function M.read_file(path)
  local fd, err = assert(io.open(path))
  if not fd then return nil, err end

  local s, err2 = fd:read('a')
  fd:close()
  if not s then return nil, err2 end
  return s
end

-- Generates a random token of the specified length. Returns nil and
-- the error message on error.
function M.random(len)
  return rand.bytes(len)
end

return M
