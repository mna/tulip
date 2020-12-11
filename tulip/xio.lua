local base64 = require 'base64'
local rand = require 'openssl.rand'

-- ensure the CSPRNG is seeded
assert(rand.ready(), 'failed to seed CSPRNG')

local BASE64_URLSAFE = {
  ['+'] = '.',
  ['/'] = '_',
  ['='] = '-',
  ['.'] = '+',
  ['_'] = '/',
  ['-'] = '=',
}

local M = {}

-- Reads the full content of path and returns the string. On error,
-- returns nil and the error message.
function M.read_file(path)
  local fd, err = io.open(path)
  if not fd then return nil, err end

  local s, err2 = fd:read('a')
  fd:close()
  if not s then return nil, err2 end
  return s
end

-- Generates a random token of the specified length.
function M.random(len)
  return rand.bytes(len)
end

-- Generates a uniform random integer between [0, n-1]. If n is omitted,
-- the interval is [0,2^64−1].
function M.randomint(n)
  return rand.uniform(n)
end

-- Encodes s into a base64 string, using URL-safe characters.
function M.b64encode(s)
  return string.gsub(base64.encode(s), '[%+/=]', BASE64_URLSAFE)
end

-- Decodes s which is a base64-encoded string using URL-safe
-- characters. Returns nil if it was not properly encoded.
function M.b64decode(s)
  s = string.gsub(s, '[%._%-]', BASE64_URLSAFE)
  local ok, v = pcall(base64.decode, s)
  if not ok then return end
  return v
end

return M
