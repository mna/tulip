local tcheck = require 'tcheck'
local token = require 'web.pkg.token.token'
local xerror = require 'web.xerror'
local xtable = require 'web.xtable'

local function make_token(cfg)
  local lookup_types
  if cfg.allowed_types then
    lookup_types = xtable.toset(cfg.allowed_types)
  end

  return function(app, t, db, tok)
    tcheck({'*', 'table', 'table|nil', 'string|nil'}, app, t, db, tok)

    if lookup_types then
      local ok, err = xerror.inval(lookup_types[t.type],
        'token type is invalid', 'type', t.type)
      if not ok then
        return nil, err
      end
    end

    local close = not db
    db = db or app:db()
    return db:with(close, function()
      if tok then
        -- validate the token
        return token.validate(t, db, tok)
      else
        -- generate a token
        return token.generate(t, db)
      end
    end)
  end
end

local M = {}

-- The token package registers an App:token method that either
-- generates a one-time secret token, or validates such a token.
--
-- If the generated token has once set, then when it is validated,
-- its type and ref_id must match, and it must not be expired.
-- If it does not have once set, then when validated only its
-- type must match, and it must not be expired. The ref_id value
-- is returned as second value when the token is valid (if the first
-- returned value is true). This is because the not-once tokens
-- are typically used to associate a token with an id (e.g. session
-- tokens), while once tokens are used for extra validation so the
-- ref_id must be provided and must be associated with that token
-- (e.g. reset password, change email address tokens, where the
-- relevant user ID is known).
--
-- Requires: a database package
-- Config:
--   * allowed_types: array of string = if set, only those types
--     will be allowed for the tokens.
--
-- v, err = App:token(t[, db[, tok]])
--   > t: table = a table with the following fields:
--     * t.type: string = the type of the token (e.g. resetpwd)
--     * t.ref_id: number = the reference id of the token (e.g. user id)
--     * t.max_age: number = number of seconds before token expires
--     * t.once: boolean|nil = if true, generate a single-use token
--       that is deleted when validated. Otherwise the token stays
--       alive until expired (e.g. a session id token).
--       TODO: should support deleting before expiration, e.g. logout.
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
    xerror.throw('no database registered')
  end
  db.migrations = db.migrations or {}
  table.insert(db.migrations, {
    package = 'web.pkg.token';
    table.unpack(token.migrations)
  })
end

return M
