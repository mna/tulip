local M = {}

-- Reads the full content of path and returns the string. On error,
-- returns nil and the error message.
function M.read_file(path)
  -- TODO: open once, keep open
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
  local fd, err = io.open('/dev/urandom')
  if not fd then return nil, err end

  local raw, err2 = fd:read(len)
  fd:close()
  if not raw then return nil, err2 end

  if #raw ~= len then
    return nil, 'failed to generate random token of the requested length'
  end
  return raw
end

return M
