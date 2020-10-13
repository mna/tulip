local tcheck = require 'tcheck'

local function make_token(cfg)
  local lookup_types
  if cfg.allowed_types then
    lookup_types = {}
    for _, typ in ipairs(cfg.allowed_types) do
      lookup_types[typ] = true
    end
  end

  return function(app, t, db, tok)
    db = db or app:db()
    if tok then
      -- validate the token
    else
      -- generate a token
      if lookup_types and not lookup_types[t.typ] then
        error(string.format('token type %q is invalid', t.typ))
      end
    end
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
-- ok, err = App:token(t[, db[, tok]])
--   * t: table = a table with the following fields:
--     * t.typ: string = the type of the token (e.g. resetpwd)
--     * t.refid: number = the reference id of the token (e.g. user id)
--     * t.max_age: number = number of seconds before token expires
--   * db: connection = optional database connection to use
--   * tok: string = if provided, validates that token, otherwise
--     generate a new token.
function M.register(cfg, app)
  tcheck({'table', 'web.App'}, cfg, app)
  app.token = make_token(cfg)
end

return M
