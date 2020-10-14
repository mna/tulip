local tcheck = require 'tcheck'
local token = require 'web.pkg.token.token'

local function make_token(cfg)
  local lookup_types
  if cfg.allowed_types then
    lookup_types = {}
    for _, typ in ipairs(cfg.allowed_types) do
      lookup_types[typ] = true
    end
  end

  return function(app, t, db, tok)
    local close = not db
    db = db or app:db()

    local v, err
    if tok then
      -- validate the token
      v, err = token.validate(t, db, tok)
    else
      -- generate a token
      if lookup_types and not lookup_types[t.type] then
        -- TODO: error or return nil, err?
        error(string.format('token type %q is invalid', t.type))
      end
      v, err = token.generate(t, db)
    end
    if close then db:close() end
    return v, err
  end
end

local M = {}

-- The token package registers an App:token method that either
-- generates a one-time secret token, or validates such a token.
--
-- Requires: a database package
-- Config:
--   * allowed_types: array of string = if set, only those types
--     will be allowed for the tokens.
--
-- v, err = App:token(t[, db[, tok]])
--   > t: table = a table with the following fields:
--     * t.type: string = the type of the token (e.g. resetpwd)
--     * t.refid: number = the reference id of the token (e.g. user id)
--     * t.max_age: number = number of seconds before token expires
--   > db: connection = optional database connection to use
--   > tok: string = if provided, validates that token, otherwise
--     generate a new token.
--   < v: bool|string|nil = if tok is provided, returns a boolean
--     that indicates if the token is valid, otherwise returns a
--     string that is the base64-encoded generated token. Is
--     nil on error.
--   < err: string|nil = error message if v is nil.
function M.register(cfg, app)
  tcheck({'table', 'web.App'}, cfg, app)
  app.token = make_token(cfg)

  local db = app.config.database
  if not db then
    error('no database registered')
  end
  db.migrations = db.migrations or {}
  table.insert(db.migrations, {
    package = 'web.pkg.token';
    table.unpack(token.migrations)
  })
end

return M
