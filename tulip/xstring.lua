local tcheck = require 'tcheck'
local time = require 'posix.time'

local M = {}

local function decode_single_header_value(h)
  -- first, trim any whitespace on either side
  h = M.trim(h)
  if h == '' then return end

  -- look for a semicolon separating metadata
  local semi = string.find(h, ';')
  if not semi then
    return {value = h}
  end

  local meta = M.trim(string.sub(h, semi + 1))
  local t = {value = M.trim(string.sub(h, 1, semi - 1))}

  -- each directive is semicolon-separated
  for dir in string.gmatch(meta, '([^;]+)') do
    dir = M.trim(dir)

    -- the metadata after the semicolon does not allow any whitespace between
    -- the key, the '=' and the value, but we'll be lenient on that.
    -- Multiple key-value pairs are separated by other semicolons, e.g.
    -- Content-Disposition: form-data; name="myFile"; filename="foo.txt"
    local k, v = string.match(dir, '([^=]+)=(.*)')
    if k and v then
      t[M.trim(k)] = M.trim(v)
    else
      -- for non key=value formats, keep the directive key and set its
      -- value to true.
      t[dir] = true
    end
  end
  return t
end

-- Turn pat into a case-insensitive pattern. It throws an error if pat contains
-- a set, which is not supported.
function M.ipat(pat)
  -- restriction: pat must not contain a [..] range.
  assert(not string.find(pat, '[', 1, true), 'pattern cannot contain a [set]')

  -- find an optional '%' (group 1) followed by any character (group 2)
  -- NOTE: must be in parens to return only the first value.
  return (string.gsub(pat, '(%%?)(.)', function(percent, letter)
    if percent ~= "" or not string.match(letter, '%a') then
      -- if the '%' matched, or `letter` is not a letter, return "as is"
      return percent .. letter
    else
      -- else, return a case-insensitive character class of the matched letter
      return string.format('[%s%s]', string.lower(letter), string.upper(letter))
    end
  end))
end

-- Escape s to return a valid file name, replacing potentially unsafe characters
-- with underscores.
function M.escapefile(s)
  return string.gsub(s, '([^%w%.]+)', '_')
end

-- Trim leading and trailing whitespace from s.
function M.trim(s)
  return string.gsub(s, '^%s*(.-)%s*$', '%1')
end

-- Ensure all whitespace in s is normalized to a single
-- space character.
function M.normalizews(s)
  return string.gsub(s, '%s+', ' ')
end

-- Make each first letter of each word in s uppercase, the rest
-- lowercase.
function M.capitalize(s)
  s = string.lower(s)
  return string.gsub(s, '%f[%g](%g)', function(c)
    return string.upper(c)
  end)
end

-- Parse a time in string RFC-3339 format to an epoch value. Return
-- nil and an error if s is not a valid RFC-3339 format.
function M.totime(s)
  local t, err = time.strptime(s, '%Y-%m-%d %H:%M:%S')
  if not t then
    return nil, err
  end
  -- convert PosixTm to os.time table
  local tt = {
    year = 1900 + t.tm_year,
    month = t.tm_mon + 1,
    day = t.tm_mday,
    hour = t.tm_hour,
    min = t.tm_min,
    sec = t.tm_sec,
  }
  return os.time(tt)
end

-- Decodes header value h into an array where each entry is a table
-- with a field "value" set to that entry's value, and an arbitrary
-- number of other fields corresponding to that header value's
-- directive (a semicolon-separated series of key=value after the
-- header's value). If a directive appears without a value (e.g. key
-- only), it is set as a key on the table with the value set to true.
--
-- It returns an array because headers can specify multiple values
-- using a comma-separated list.
--
-- For example (Accept):
--   text/html, application/xhtml+xml, application/xml;q=0.9, image/webp, */*;q=0.8
-- Would return:
--   {
--     {value = 'text/html'},
--     {value = 'application/xhtml+xml'},
--     {value = 'application/xml', q = '0.9'},
--     {value = 'image/webp', q = '0.9'},
--     {value = '*/*', q = '0.8'},
--   }
--
-- Another example (Content-Type):
--   multipart/form-data; boundary=something
-- Would return:
--   {
--     {value = 'multipart/form-data', boundary = 'something'},
--   }
--
-- Finally (Accept-Encoding):
--   deflate, gzip;q=1.0, *;q=0.5
-- Would return:
--   {
--     {value = 'deflate'},
--     {value = 'gzip', q = '1.0'},
--     {value = '*', q = '0.5'},
--   }
--
-- If the optional name parameter is provided, it is set as the field
-- name on the array itself, to keep track of what header this table
-- represents.
function M.decode_header(h, name)
  tcheck({'string', 'string|nil'}, h, name)

  local out = {name = name}
  for v in string.gmatch(h, '([^,]+)') do
    local t = decode_single_header_value(v)
    if t then
      table.insert(out, t)
    end
  end
  return out
end

-- Tests if header value h matches value v. If h is a string, it is first
-- decoded by calling decode_header. If v is a table, it is considered an array
-- of string values to test. If plain is falsy, v is considered a Lua pattern.
--
-- If at least one match is found, it returns a table that is an array of indices
-- where a match was found, in the decoded header's array. The second return
-- value is the decoded header's array. Returns nil if no match is found.
function M.header_value_matches(h, v, plain)

end

-- Tests if header value h has a directive d that matches value v. If h is a
-- string, it is first decoded by calling decode_header. If v is a table, it is
-- considered an array of string values to test. If plain is falsy, v is
-- considered a Lua pattern.
--
-- If at least one match is found, it returns a table that is an array of indices
-- where a match was found, in the decoded header's array. The second return
-- value is the decoded header's array. Returns nil if no match is found.
function M.header_directive_matches(h, d, v, plain)

end

return M
