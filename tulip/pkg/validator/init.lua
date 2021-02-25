local tcheck = require 'tcheck'
local xerror = require 'tulip.xerror'
local xstring = require 'tulip.xstring'

local MAXBYTES_PER_UTF8 = 6

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

  if vals.trim_ws then
    s = xstring.trim(s)
    len = #s
  end
  if vals.normalize_ws then
    s = xstring.normalizews(s)
    len = #s
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
  return true, s
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
  return true, i
end

local function validate_boolean(raw, key, vals)
  if (vals.true_value == nil) and (vals.false_value == nil) then
    return true, raw ~= nil and raw ~= false
  end

  if vals.true_value then
    if vals.true_value == raw then
      return true, true
    elseif vals.false_value == nil then
      -- no false value, so everything else is false
      return true, false
    end
  end
  if vals.false_value then
    if vals.false_value == raw then
      return true, false
    elseif vals.true_value == nil then
      -- no true value, so everything else is true
      return true, true
    end
  end
  -- both true and false values are set and raw is neither
  return xerror.inval(nil, 'value is not one of the true/false values', key, raw)
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
  boolean = validate_boolean,
}

local function validate(_, t, schema)
  local vt = {}
  for k, v in pairs(schema) do
    local raw = value_at_path(t, k)

    local fn = TYPE_VALIDATORS[v.type]
    if not fn then
      xerror.throw('invalid validation type: %s', v.type)
    end
    local ok, err_or_val = fn(raw, k, v)
    if not ok then
      return nil, err_or_val
    end
    vt[k] = err_or_val
  end
  return true, vt
end

local function req_validate(req, schema, force_ct)
  local app = req.app
  local body, err = req:decode_body(force_ct)
  if not body then
    return nil, err
  end
  return app:validate(body, schema)
end

local function middleware(req, _, nxt)
  req.validate = req_validate
  nxt()
end

local M = {}

-- The validator package registers an App:validate method and a middleware
-- that registers a Request:validate method. Those methods provide basic
-- but often sufficiently powerful validation of simple values.
--
-- Config:
--
-- Methods:
--
-- ok, err|vt = App:validate(t, schema)
--
--   Validates the table t based on the schema definition.
--
--   > t: table = the table to validate
--   > schema: table = the schema definition, see below for details.
--   < ok: boolean = true on success
--   < err: Error|nil = if ok is falsy, the EINVAL error, with the field
--     and value set to the field that failed validation.
--   < vt: table = if ok is true, vt contains the flattened validated
--     values under the same keys as the keys or paths in schema. E.g.
--     if schema as "name" and "user.birth.country" as keys, then vt
--     would have their validated values under vt["name"] and
--     vt["user.birth.country"] (flattened under that exact key).
--     Validated values can be slightly different from the raw ones
--     (e.g. converted to another type, normalized).
--
--   The schema is a dictionary where the key is a key name or path in t
--   (e.g. "email" or "user.age"), and the value is a table that defines
--   the validations to apply to that field. Possible fields on that
--   validations table are:
--
--   * type: string = the type of that value, fails if it is not of that
--     type if present ('integer', 'string', 'boolean')
--   * min, max: number = the minimum and maximum value for integers, or
--     the minimum and maximum length in bytes for strings.
--   * mincp, maxcp: number = the minimum and maximum number of codepoints
--     for utf-8 strings. Fails if the string is not valid utf8.
--   * trim_ws: boolean = for strings, if true, trims leading and trailing
--     whitespace. This happens after the validation for min/max bytes,
--     but before validation of min/max codepoints, so that a trim is not
--     attempted on an exaggerately long string (via the bytes validation), but
--     one can still require a minimum number of code points to be present
--     after trim.
--   * normalize_ws: boolean = for strings, if true, all spaces are normalized
--     prior to validation for control characters, so that tabs and newlines
--     are turned into standard spaces.
--   * allow_cc: boolean = for strings, if true, allows control characters.
--     By default, control characters raise an error.
--   * required: boolean = fails if the value is not present (nil).
--   * pattern: string = if set, strings must match this pattern.
--   * enum: array = if set, value must match one of those values (can be
--     of any type, must match the type of the field to possibly succeed).
--
--   Booleans are a bit different, none of the previous schema validations
--   apply to them. By default, they follow Lua's definition of true/false,
--   so unless the value is nil or false, it is true. But the following
--   schema fields can alter the result of the validation:
--   * true_value: any = if set, only this value is considered true,
--     everything else is false unless false_value is set.
--   * false_value: any = if set, only this value is considered false,
--     everything else is true unless true_value is set.
--   If both are set, then any value that isn't one of those two is
--   considered invalid (basically, this is like an enum for booleans,
--   with the added semantics that one means true, the other false).
--
-- ok, err|vt = Request:validate(schema[, force_ct])
--
--   Validates the decoded body of the Request based on schema. The
--   behaviour is the same as App:validate. This is registered by the
--   middleware, which must be enabled for that extension to be installed.
--   If force_ct is provided, it is passed to the call to Request:decode_body.
--
-- Middleware:
--
-- * tulip.pkg.validator
--
--   Must be added before any handler that needs to call Request:validate,
--   as it registers that extension. Not registered if the middleware
--   package is not registered (does not raise an error, as some apps may
--   use App:validator without the need for the middleware).
--
function M.register(cfg, app)
  tcheck({'table', 'tulip.App'}, cfg, app)
  app.validate = validate

  if app:has_package('tulip.pkg.middleware') then
    app:register_middleware('tulip.pkg.validator', middleware)
  end
end

return M
