local tcheck = require 'tcheck'
local xerror = require 'tulip.xerror'

local MWPREFIX = 'tulip.pkg.validator'

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

end

local function validate_boolean(raw, key, vals)

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
--     type if present ('integer', 'string', 'boolean')
--   * min, max: number = the minimum and maximum value for integers, or
--     the minimum and maximum length in bytes for strings.
--   * mincp, maxcp: number = the minimum and maximum number of codepoints
--     for utf-8 strings. Fails if the string is not valid utf8.
--   * allow_cc: boolean = for strings, if true, allows control characters.
--     By default, control characters raise an error.
--   * required: boolean = fails if the value is not present (nil).
--   * true_value: string = the value to consider as "true" for booleans.
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
