-- Returns the __name of the metatable of o, or nil if none.
local function metatable_name(o)
  if type(o) == 'table' then
    local mt = getmetatable(o)
    return mt and mt.__name
  end
end

local Error = {__name = 'web.xerror.Error'}
Error.__index = Error

function Error:__tostring()
  return self.message
end

function Error.new(msg, code)
  local o = {message = msg, code = code}
  return setmetatable(o, Error)
end

local M = {}

-- Creates a converter function that converts any error into an
-- Error instance with code set to ecode. Any additional argument
-- is the name of the field where extra values in that position
-- are set on the Error instance (corresponding to the values after
-- the error message, which is always the second value after a
-- falsy first value indicating an error).
function M.converter(ecode, ...)
  local keys = table.pack(...)
  return function(first, msg, ...)
    if first then
      -- no error, passthrough
      return first, msg, ...
    end

    -- create the error
    local err = Error.new(msg, ecode)
    -- set any other extra value in the defined fields
    for i = 1, keys.n do
      local k = keys[i]
      if k then
        local v = select(i, ...)
        err[k] = v
      end
    end
    return first, err
  end
end

local DBKEYS = {'status_code', 'status', 'sql_state'}
-- Special converter for DB calls that either converts the error
-- to an ecode EDB or ESQL, depending if the error is in the
-- connection to the DB or in the execution of SQL.
function M.db(first, msg, ...)
  if first then
    -- no error, passthrough
    return first, msg, ...
  end

  local n = select('#', ...)
  -- create the error
  local err = Error.new(msg, n > 1 and 'ESQL' or 'EDB')
  -- set any other extra value in the defined fields
  for i = 1, n do
    local k = DBKEYS[i]
    if k then
      local v = select(i, ...)
      err[k] = v
    end
  end
  return first, err
end

-- Create an EIO converter for IO calls such as read/write to file
-- and sockets.
M.io = M.converter('EIO', 'errno')

-- Returns true if err is of any of the specified codes, false
-- otherwise.
function M.is(err, ...)
  if metatable_name(err) ~= Error.__name then
    return false
  end

  local n = select('#', ...)
  for i = 1, n do
    local ecode = select(i, ...)
    if ecode == err.code then
      return true
    end
  end
  return false
end

-- TODO: M.issqlstate, converter that adds a context to errors,
-- converter that adds an actual error message (e.g. for xpgsql.model)

return M
