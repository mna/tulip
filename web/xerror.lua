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
  local parts = {}
  if self.labels then
    for i = #self.labels, 1, -1 do
      table.insert(parts, self.labels[i])
    end
    if #parts > 0 then
      -- so that a final ': ' is added after the last label
      table.insert(parts, '')
    end
  end
  return table.concat(parts, ': ') .. (self.message or '<error>')
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
-- otherwise. Codes can be patterns.
function M.is(err, ...)
  if metatable_name(err) ~= Error.__name then
    return false
  end

  local n = select('#', ...)
  for i = 1, n do
    local ecode = select(i, ...)
    if string.find(err.code, ecode) then
      return true
    end
  end
  return false
end

-- Returns true if err is an ESQL error with the sql_state field
-- set to any of the specified codes, false otherwise. Codes can
-- be patterns.
function M.is_sql_state(err, ...)
  if metatable_name(err) ~= Error.__name or err.code ~= 'ESQL' then
    return false
  end

  local n = select('#', ...)
  for i = 1, n do
    local state = select(i, ...)
    if string.find(err.sql_state, state) then
      return true
    end
  end
  return false
end

-- Adds context to the error. The label is a stack, so the last added
-- label is the first printed in the error message, followed by the
-- next, until the first that was added (labels are prepended to the
-- error message like this: last-label: next-label: first-label: message).
--
-- The attrs argument is a table where each key-value pair is added to
-- the error object if and only if it did not exist yet. This is because if
-- an attribute is already set, it is assumed that the call that set it
-- (which was closer to where the error originated) knew more about that
-- field, so it is not overwritten. It can be used to set new attributes
-- and default values (e.g. it can set the error message if there wasn't any).
function M.ctx(err, label, attrs)
  if metatable_name(err) ~= Error.__name then
    return err
  end

  local labels = err.labels or {}
  table.insert(labels, label)
  err.labels = labels

  for k, v in pairs(attrs) do
    if err[k] == nil then
      err[k] = v
    end
  end
  return err
end

-- Raises an error with msg, which can contain formatting verbs. Extra
-- arguments are provided to string.format.
function M.throw(msg, ...)
  return error(string.format(msg, ...))
end

return M
