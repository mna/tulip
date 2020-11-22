local fn = require 'fn'

local M = {}

function M.signup(req, _, nxt)
  local app = req.app
  -- TODO: decode_body can error
  local body = req.decoded_body or req:decode_body()

  local email = body.email
  local pwd, pwd2 = body.password, body.password2
  local groups = body.groups
  if pwd2 and pwd ~= pwd2 then
    -- error
  end
  local gnames
  if groups then
    gnames = fn.reduce(function(cumul, name)
      table.insert(cumul, name)
      return cumul
    end, {}, string.gmatch(groups, '[^,%s]+'))
  end

  local acct, err = app:create_account(email, pwd, gnames)
  if not acct then
    -- error
  end
  req.locals.account = acct

  nxt()
end

function M.login(req, res, nxt)
end

return M
