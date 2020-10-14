local cjson = require 'cjson'
local request = require 'http.request'
local tcheck = require 'tcheck'

local BASE_URL = 'https://sendgrid.com/v3'

local function make_email(cfg)
  local default_from = cfg.from
  local key = cfg.api
  return function(app, t)
    tcheck({'*', 'table'}, app, t)
  end
end

local M = {}

-- The sendgrid package registers an app:email method that uses
-- the sendgrid provider to send emails.
--
-- Config:
--   * from: string = default sender email.
--   * api_key: string = sendgrid API key.
--
-- b, err = App:email(t)
--   > t: table = a table with the following fields:
--     * t.from: string|nil = sender email
--     * t.to: array[string] = recipient emails
--     * t.cc: array[string]|nil = CC recipient emails
--     * t.bcc: array[string]|nil = BCC recipient emails
--     * t.subject: string = email subject
--     * t.body: string = email body
--     * t.content_type: string|nil = body MIME type, defaults to
--       text/plain.
--   < b: bool|nil = true on success, nil on error.
--   < err: string|nil = error message if b is nil.
function M.register(cfg, app)
  tcheck({'table', 'web.App'}, cfg, app)
  app.email = make_email(cfg)
end

return M
