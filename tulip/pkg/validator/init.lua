local tcheck = require 'tcheck'
local xerror = require 'tulip.xerror'
local xstring = require 'tulip.xstring'

local MWPREFIX = 'tulip.pkg.validator'
local MAXBYTES_PER_UTF8 = 6

local function default_errh(_, res, _, err)
  res:write{
    status = 400,
    body = 'Bad Request - ' .. tostring(err),
    content_type = 'text/plain',
  }
end

local function validate_string(raw, key, vals)
  if raw == nil then
    if vals.required then
      return xerror.inval(nil, 'required field is missing', key, raw)
    else
      return true
    end
  end

  local s = tostring(raw)
  local len = #s
  if vals.min and len < vals.min then
    return xerror.inval(nil,
      string.format('value is too short: %d < %d', len, vals.min), key, s)
  end
  if vals.max and len > vals.max then
    return xerror.inval(nil,
      string.format('value is too long: %d > %d', len, vals.max), key, s)
  end

  if vals.maxcp and len > (MAXBYTES_PER_UTF8 * vals.maxcp) then
    -- optimization to not have to scan the whole utf8 string
    return xerror.inval(nil,
      string.format('value has too many utf8 codepoints: +%d > %d', len, vals.maxcp), key, s)
  end

  -- count the utf8 codepoints, failing if the string is invalid utf8
  local cplen, failat = utf8.len(s)
  if not cplen then
    return xerror.inval(nil,
      string.format('invalid utf8 encoding at byte %d', failat), key, s)
  end
  if vals.mincp and cplen < vals.mincp then
    return xerror.inval(nil,
      string.format('value has too little utf8 codepoints: %d < %d', cplen, vals.mincp), key, s)
  end
  if vals.maxcp and cplen > vals.maxcp then
    return xerror.inval(nil,
      string.format('value has too many utf8 codepoints: %d > %d', cplen, vals.maxcp), key, s)
  end

  if vals.normalize_ws then
    s = xstring.normalizews(s)
  end

  if not vals.allow_cc then
    -- loop through all codepoints and fail if there are any control chars
    for p, c in utf8.codes(s) do
      if c <= 0x1f or (c >= 0x7f and c <= 0x9f) then
        return xerror.inval(nil,
          string.format('value contains a control character at byte %d', p), key, s)
      end
    end
  end

  if vals.pattern and not string.match(s, vals.pattern) then
    return xerror.inval(nil,
      string.format('value does not match pattern %s', vals.pattern), key, s)
  end

  if vals.enum then
    for _, en in ipairs(vals.enum) do
      if s == en then
        goto done
      end
    end
    return xerror.inval(nil, 'value is not one of the accepted enums', key, s)
  end

  ::done::
  return true
end

local function validate_integer(raw, key, vals)
  if raw == nil then
    if vals.required then
      return xerror.inval(nil, 'required field is missing', key, raw)
    else
      return true
    end
  end

  local i = math.tointeger(raw)
  if not i then
    return xerror.inval(nil, 'value is not an integer', key, raw)
  end

  if vals.min and i < vals.min then
    return xerror.inval(nil,
      string.format('value is too small: %d < %d', i, vals.min), key, i)
  end
  if vals.max and i > vals.max then
    return xerror.inval(nil,
      string.format('value is too big: %d > %d', i, vals.max), key, i)
  end

  if vals.enum then
    for _, en in ipairs(vals.enum) do
      if i == en then
        goto done
      end
    end
    return xerror.inval(nil, 'value is not one of the accepted enums', key, i)
  end

  ::done::
  return true
end

local function value_at_path(t, path)
  local raw = t[path]
  local dot = string.find(path, '.')
  if raw == nil and dot then
    raw = t[string.sub(path, 1, dot - 1)]
    if raw then
      return value_at_path(raw, string.sub(path, dot + 1))
    end
  end
  return raw
end

local TYPE_VALIDATORS = {
  string = validate_string,
  integer = validate_integer,
}

local function validate(_, t, schema)
  for k, v in pairs(schema) do
    local raw = value_at_path(t, k)

    local fn = TYPE_VALIDATORS[v.type]
    if not fn then
      xerror.throw('invalid validation type: %s', v.type)
    end
    local ok, err = fn(raw, k, v)
    if not ok then
      return nil, err
    end
  end
  return true
end

local function make_middleware(schema, errh)
  errh = errh or default_errh

  return function(req, res, nxt)
    local app = req.app
    local body = req:decode_body()
    local ok, err = app:validate(body, schema)
    if not ok then
      errh(req, res, nxt, err)
      return
    end
    nxt()
  end
end

local M = {}

-- The validator package registers an App:validate method and middleware
-- that validates the request's body.
--
-- Config:
--
-- * error_handler: function = middleware function to call on validation
--   error, gets called with (req, res, nxt, err). Default: reply with 400,
--   body contains error message.
--
-- * middleware: Table where each key is converted to a middleware with the
--   name tulip.pkg.validator:<key>. The value of the key is a table that
--   corresponds to the validation configuration to be passed to App:validate
--   with the request's decoded body.
--
-- Methods:
--
-- ok, err = App:validate(t, schema)
--
--   Validates the table t based on the schema definition.
--
--   > t: table = the table to validate
--   > schema: table = the schema definition, see below for details.
--   < ok: boolean = true on success
--   < err: Error|nil = if ok is falsy, the EINVAL error, with the field
--     and value set to the field that failed validation.
--
--   The schema is a dictionary where the key is a key name or path in t
--   (e.g. "email" or "user.age"), and the value is a table that defines
--   the validations to apply to that field. Possible fields on that
--   validations table are:
--
--   * type: string = the type of that value, fails if it is not of that
--     type if present ('integer', 'string')
--   * min, max: number = the minimum and maximum value for integers, or
--     the minimum and maximum length in bytes for strings.
--   * mincp, maxcp: number = the minimum and maximum number of codepoints
--     for utf-8 strings. Fails if the string is not valid utf8.
--   * normalize_ws: boolean = for strings, if true, all spaces are normalized
--     prior to validation for control characters, so that tabs and newlines
--     are turned into standard spaces.
--   * allow_cc: boolean = for strings, if true, allows control characters.
--     By default, control characters raise an error.
--   * required: boolean = fails if the value is not present (nil).
--   * pattern: string = if set, strings must match this pattern.
--   * enum: array = if set, value must match one of those values (can be
--     of any type, must match the type of the field to possibly succeed).
function M.register(cfg, app)
  tcheck({'table', 'tulip.App'}, cfg, app)
  app.validate = validate

  if cfg.middleware then
    xerror.must(app:has_package('tulip.pkg.middleware'))
    for k, v in pairs(cfg.middleware) do
      app:register_middleware(MWPREFIX .. ':' .. k, make_middleware(v, cfg.error_handler))
    end
  end
end

return M
