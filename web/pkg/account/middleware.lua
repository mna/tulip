local fn = require 'fn'
local xerror = require 'web.xerror'
local xtable = require 'web.xtable'

local M = {}

-- TODO: potential configuration options:
-- * error handlers for each middleware
-- * login fail handler
-- * session cookie name
-- * session remember-me and token duration (TTL)

function M.signup(req, res, nxt, errh)
  local app = req.app
  local body, err = req:decode_body()
  if not body then
    return errh(req, res, nxt, err)
  end

  local email = body.email
  local pwd, pwd2 = body.password, body.password2
  local groups = body.groups
  local ok; ok, err = xerror.inval((pwd2 or pwd) == pwd,
    'passwords do not match', 'password')
  if not ok then
    return errh(req, res, nxt, err)
  end
  local gnames
  if groups then
    gnames = fn.reduce(function(cumul, name)
      table.insert(cumul, name)
      return cumul
    end, {}, string.gmatch(groups, '[^,%s]+'))
  end

  local acct; acct, err = app:create_account(email, pwd, gnames)
  if not acct then
    return errh(req, res, nxt, err)
  end
  req.locals.account = acct

  nxt()
end

function M.login(req, res, nxt, errh, failh, cfg)
  local app = req.app
  local body, err = req:decode_body()
  if not body then
    return errh(req, res, nxt, err)
  end

  local email = body.email
  local pwd = body.password or '' -- ensure a pwd validation is always done
  local persist = (body.rememberme and body.rememberme ~= '')

  local acct; acct, err = app:account(email, pwd)
  if not acct then
    if xerror.is(err, 'EINVAL') then
      return failh(req, res, nxt, err)
    else
      return errh(req, res, nxt, err)
    end
  end
  req.locals.account = acct

  local tok; tok, err = app:token{
    type = 'session',
    ref_id = acct.id,
    max_age = cfg.session_ttl,
  }
  if not tok then
    return errh(req, res, nxt, err)
  end
  req.locals.session_id = tok

  -- TODO: generate a token and store it securely (signed) in a
  -- cookie. Reuse the csrf cookie logic for that.

  nxt()
end

function M.check_session(req, _, nxt)
  local ck = req.cookies['ssn']
  if ck then
    -- TODO: decode validating signature, to get the session id (token).
    -- TODO: validate that the session id (token) is still valid, get its account id.
    -- TODO: load the account corresponding to the token's ref_id
    -- req.locals.session_id = <token>
    -- req.locals.account = acct
  end
  nxt()
end

function M.logout(req, res, nxt)
  local ck = req.cookies['ssn']
  if ck then
    -- TODO: delete the session's token
    -- TODO: delete cookie on the response
  end
  req.locals.session_id = nil
  req.locals.account = nil
  nxt()
end

function M.delete(req, res, nxt)
  local app = req.app
  local acct = req.locals.account
  if not acct then
    -- error
  end

  -- TODO: decode_body can error
  local body = req.decoded_body or req:decode_body()
  local pwd = body.password or ''

  local ok, err = app:db(function(conn)
    assert(app:account(acct.id, pwd, conn))
    assert(acct:delete(conn))
    return true
  end)
  if not ok then
    -- error
  end

  -- TODO: clear session cookie and token
  req.locals.session_id = nil
  req.locals.account = nil

  nxt()
end

function M.setpwd(req, _, nxt)
  local app = req.app
  local acct = req.locals.account
  if not acct then
    -- error
  end

  -- TODO: decode_body can error
  local body = req.decoded_body or req:decode_body()

  local oldpwd = body.old_password or ''
  local newpwd, newpwd2 = body.new_password, body.new_password2
  if newpwd2 and newpwd ~= newpwd2 then
    -- error
  end

  -- validate old (current) password before changing
  local ok, err = app:db(function(conn)
    assert(app:account(acct.id, oldpwd, conn))
    assert(acct:change_pwd(newpwd, conn))
    return true
  end)
  if not ok then
    -- error
  end

  nxt()
end

function M.authz(req, res, nxt)
  local routeargs = req.routeargs
  if routeargs.allow or routeargs.deny then
    local acct = req.locals.account
    local acctset = xtable.toset(acct and acct.groups)
    local allowset = xtable.toset(routeargs.allow)

    -- TODO: if is in allowset, or allow * and acct exists, or allow ?
    -- then allow access.

    -- TODO: if not allowed by allowset, check if denied by denyset,
    -- otherwise allow access.
  end
  nxt()
end

return M
