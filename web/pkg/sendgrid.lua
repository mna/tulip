local cjson = require('cjson').new()
local request = require 'http.request'
local tcheck = require 'tcheck'

local BASE_URL = 'https://api.sendgrid.com/v3'

local function make_email(cfg)
  local default_from = cfg.from
  local key = cfg.api_key

  return function(app, t)
    tcheck({'*', 'table'}, app, t)

    local recipients = {}
    if t.to then
      recipients.to = {}
      for _, to in ipairs(t.to) do
        table.insert(recipients.to, {email = to})
      end
    end
    if t.cc then
      recipients.cc = {}
      for _, cc in ipairs(t.cc) do
        table.insert(recipients.cc, {email = cc})
      end
    end
    if t.bcc then
      recipients.bcc = {}
      for _, bcc in ipairs(t.bcc) do
        table.insert(recipients.bcc, {email = bcc})
      end
    end

    local payload = {
      personalizations = {recipients},
      from = {email = t.from or default_from},
      subject = t.subject,
      content = {
        {
          type = t.content_type or 'text/plain',
          value = t.body,
        },
      },
    }

    local req = request.new_from_uri(BASE_URL .. '/mail/send')
    req.headers:upsert(':method', 'POST')
    req.headers:append('authorization', string.format('Bearer %s', key))
    req.headers:append('content-type', 'application/json')

    local body = cjson.encode(payload)
    req:set_body(body)

    local hdrs, res = req:go(t.timeout)
    if not hdrs then
      return nil, res
    end
    if tonumber(hdrs:get(':status')) >= 400 then
      return nil, res:get_body_as_string(t.timeout)
    end
    return true
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
--     * t.timeout: integer|nil = timeout of request in seconds
--   < b: bool|nil = true on success, nil on error.
--   < err: string|nil = error message if b is nil.
function M.register(cfg, app)
  tcheck({'table', 'web.App'}, cfg, app)
  app.email = make_email(cfg)
end

return M
