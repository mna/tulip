local crypto = require 'web.crypto'
local fn = require 'fn'
local handler = require 'web.handler'
local xerror = require 'web.xerror'
local xtable = require 'web.xtable'

local MAX_COOKIE_LEN = 4096

local function save_b64_token_in_cookie(b64_tok, cfg, res)
  local encoded = crypto.encode(cfg.auth_key,
    b64_tok,
    cfg.cookie_name)
  if #encoded > MAX_COOKIE_LEN then return end

  handler.set_cookie(res, {
    name = cfg.cookie_name,
    value = encoded,
    ttl = cfg.cookie_max_age,
    domain = cfg.domain,
    path = cfg.path,
    insecure = not cfg.secure,
    allowjs = not cfg.http_only,
    same_site = cfg.same_site,
  })
  return true
end

local function read_b64_token_from_cookie(ck, cfg)
  if not ck or ck == '' then return end
  if #ck > MAX_COOKIE_LEN then return end
  return crypto.decode(cfg.auth_key,
    cfg.cookie_max_age,
    ck,
    cfg.cookie_name)
end

local M = {}

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

function M.login(req, res, nxt, errh, cfg)
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
    return errh(req, res, nxt, err)
  end
  req.locals.account = acct

  local tok; tok, err = app:token{
    type = cfg.token_type,
    ref_id = acct.id,
    max_age = cfg.token_max_age,
  }
  if not tok then
    return errh(req, res, nxt, err)
  end
  req.locals.session_id = tok

  -- store the token securely (signed) in a cookie
  local ckcfg = xtable.merge({}, cfg)
  if not persist then
    ckcfg.cookie_max_age = nil
  end
  local ok; ok, err = xerror.inval(
    save_b64_token_in_cookie(tok, ckcfg, res), 'encoded cookie is too long')
  if not ok then
    return errh(req, res, nxt, err)
  end

  nxt()
end

function M.check_session(req, res, nxt, errh, cfg)
  local app = req.app

  local ck = req.cookies[cfg.cookie_name]
  if ck then
    local tok = read_b64_token_from_cookie(ck, cfg)

    if tok then
      local ok, id_or_err = app:token({
        type = cfg.token_type,
      }, nil, tok)

      if ok then
        local acct, err = app:account(id_or_err)
        if not acct then
          -- if account does not exist, then not authenticated
          if not xerror.is(err, 'EINVAL') then
            return errh(req, res, nxt, err)
          end
        else
          req.locals.session_id = tok
          req.locals.account = acct
        end
      else
        -- getting the token failed - if this is a DB failure, treat as
        -- an error, otherwise if session is now invalid, continue as
        -- if it wasn't there.
        if not xerror.is(id_or_err, 'EINVAL') then
          return errh(req, res, nxt, id_or_err)
        end
      end
    end
  end

  nxt()
end

function M.logout(req, res, nxt, errh, cfg)
  local app = req.app

  local ck = req.cookies[cfg.cookie_name]
  if ck then
    local tok = read_b64_token_from_cookie(ck, cfg)

    if tok then
      -- delete the token
      local ok, err = app:token({
        type = cfg.token_type,
        delete = true,
      }, nil, tok)
      if (not ok) and (not xerror.is(err, 'EINVAL')) then
        return errh(req, res, nxt, err)
      end
    end

    -- delete the cookie
    handler.set_cookie(res, {
      name = cfg.cookie_name,
      ttl = -1,
      domain = cfg.domain,
      path = cfg.path,
      insecure = not cfg.secure,
      allowjs = not cfg.http_only,
      same_site = cfg.same_site,
    })
  end
  req.locals.session_id = nil
  req.locals.account = nil

  nxt()
end

function M.delete(req, res, nxt, errh, cfg)
  local app = req.app

  local acct, err = xerror.inval(req.locals.account, 'no current account')
  if not acct then
    return errh(req, res, nxt, err)
  end

  local body; body, err = req:decode_body()
  if not body then
    return errh(req, res, nxt, err)
  end
  local pwd = body.password or ''

  local ok; ok, err = app:db(function(conn)
    -- validate the password
    xerror.must(app:account(acct.id, pwd, conn))
    xerror.must(acct:delete(conn))
    return true
  end)
  if not ok then
    return errh(req, res, nxt, err)
  end

  -- clear session cookie and token
  if req.cookies[cfg.cookie_name] then
    handler.set_cookie(res, {
      name = cfg.cookie_name,
      ttl = -1,
      domain = cfg.domain,
      path = cfg.path,
      insecure = not cfg.secure,
      allowjs = not cfg.http_only,
      same_site = cfg.same_site,
    })
    -- TODO: delete all tokens for this account id
    -- TODO: schema issue: same user can have multiple active sessions
  end
  req.locals.session_id = nil
  req.locals.account = nil

  nxt()
end

function M.init_vemail(req, res, nxt, errh, cfg)
  local app = req.app

  local acct, err = xerror.inval(req.locals.account, 'no current account')
  if not acct then
    return errh(req, res, nxt, err)
  end

  -- TODO: should be in a transaction (token + mqueue)

  -- generate a new base64-encoded token
  local tok; tok, err = app:token({
    type = cfg.token_type,
    ref_id = acct.id,
    max_age = cfg.token_max_age,
    once = true,
  })
  if not tok then
    return errh(req, res, nxt, err)
  end

  -- hmac-encode it
  local encoded = crypto.encode(cfg.auth_key, tok, acct.email)
  local ok; ok, err = app:mqueue({
    max_attempts = cfg.max_attempts,
    max_age = cfg.queue_max_age,
    queue = cfg.queue_name,
  }, nil, xtable.merge({}, cfg.payload, {
    email = acct.email,
    encoded_token = encoded,
  }))
  if not ok then
    return errh(req, res, nxt, err)
  end

  nxt()
end

function M.vemail(req, res, nxt, errh, cfg)
  local app = req.app

  local enc_tok, err = xerror.inval(req.url.query and req.url.query.t, 'no token')
  if not enc_tok then
    return errh(req, res, nxt, err)
  end
  local email; email, err = xerror.inval(req.url.query and req.url.query.e, 'no email')
  if not email then
    return errh(req, res, nxt, err)
  end

  -- hmac-decode the token
  local tok; tok, err = xerror.inval(crypto.decode(cfg.auth_key,
    cfg.token_max_age, enc_tok, email), 'invalid token')
  if not tok then
    return errh(req, res, nxt, err)
  end

  -- load the corresponding account
  local acct; acct, err = app:account(email)
  if not acct then
    return errh(req, res, nxt, err)
  end

  -- validate the token
  local ok; ok, err = app:token({
    type = cfg.token_type,
    ref_id = acct.id,
  }, nil, tok)
  if not ok then
    return errh(req, res, nxt, err)
  end

  -- all good, mark the email as verified
  ok, err = app:db(function(conn)
    return xerror.must(acct:verify_email(conn))
  end)
  if not ok then
    return errh(req, res, nxt, err)
  end

  nxt()
end

function M.setpwd(req, res, nxt, errh)
  local app = req.app

  local acct, err = xerror.inval(req.locals.account, 'no current account')
  if not acct then
    return errh(req, res, nxt, err)
  end

  local body; body, err = req:decode_body()
  if not body then
    return errh(req, res, nxt, err)
  end

  local oldpwd = body.old_password or ''
  local newpwd, newpwd2 = body.new_password, body.new_password2
  local ok; ok, err = xerror.inval((newpwd2 or newpwd) == newpwd,
    'passwords do not match', 'password')
  if not ok then
    return errh(req, res, nxt, err)
  end

  -- validate old (current) password before changing
  -- TODO: then delete all sessions for that account id
  ok, err = app:db(function(conn)
    xerror.must(app:account(acct.id, oldpwd, conn))
    xerror.must(acct:change_pwd(newpwd, conn))
    return true
  end)
  if not ok then
    return errh(req, res, nxt, err)
  end

  nxt()
end

function M.init_resetpwd(req, res, nxt, errh, cfg)
  local app = req.app

  -- get the email of the account from the form
  local body, err = req:decode_body()
  if not body then
    return errh(req, res, nxt, err)
  end

  local email = body.email
  local acct; acct, err = app:account(email)
  if not acct then
    return errh(req, res, nxt, err)
  end

  -- TODO: should be in a transaction (token + mqueue)

  -- generate a new base64-encoded token
  local tok; tok, err = app:token({
    type = cfg.token_type,
    ref_id = acct.id,
    max_age = cfg.token_max_age,
    once = true,
  })
  if not tok then
    return errh(req, res, nxt, err)
  end

  -- hmac-encode it
  local encoded = crypto.encode(cfg.auth_key, tok, acct.email)
  local ok; ok, err = app:mqueue({
    max_attempts = cfg.max_attempts,
    max_age = cfg.queue_max_age,
    queue = cfg.queue_name,
  }, nil, xtable.merge({}, cfg.payload, {
    email = acct.email,
    encoded_token = encoded,
  }))
  if not ok then
    return errh(req, res, nxt, err)
  end

  nxt()
end

function M.resetpwd(req, res, nxt, errh, cfg)
  local app = req.app

  -- decode the form body to get the new password
  local body, err = app:decode_body()
  if not body then
    return errh(req, res, nxt, err)
  end

  local newpwd, newpwd2 = body.new_password, body.new_password2
  local ok; ok, err = xerror.inval((newpwd2 or newpwd) == newpwd,
    'passwords do not match', 'password')
  if not ok then
    return errh(req, res, nxt, err)
  end

  -- get the encoded token and email address
  local enc_tok; enc_tok, err = xerror.inval(req.url.query and req.url.query.t or body.t, 'no token')
  if not enc_tok then
    return errh(req, res, nxt, err)
  end
  local email; email, err = xerror.inval(req.url.query and req.url.query.e or body.e, 'no email')
  if not email then
    return errh(req, res, nxt, err)
  end

  -- hmac-decode the token
  local tok; tok, err = xerror.inval(crypto.decode(cfg.auth_key,
    cfg.token_max_age, enc_tok, email), 'invalid token')
  if not tok then
    return errh(req, res, nxt, err)
  end

  -- load the corresponding account
  local acct; acct, err = app:account(email)
  if not acct then
    return errh(req, res, nxt, err)
  end

  -- validate the token
  ok, err = app:token({
    type = cfg.token_type,
    ref_id = acct.id,
  }, nil, tok)
  if not ok then
    return errh(req, res, nxt, err)
  end

  -- all good, change password
  -- TODO: then delete all sessions for that account id
  ok, err = app:db(function(conn)
    return xerror.must(acct:change_pwd(newpwd, conn))
  end)
  if not ok then
    return errh(req, res, nxt, err)
  end

  nxt()
end

function M.init_changeemail(req, res, nxt, errh, cfg)
  local app = req.app

  local acct, err = xerror.inval(req.locals.account, 'no current account')
  if not acct then
    return errh(req, res, nxt, err)
  end

  -- get the new email
  local body; body, err = req:decode_body()
  if not body then
    return errh(req, res, nxt, err)
  end

  -- best-effort to catch this early
  local new_email = body.new_email
  local exist = app:account(new_email)
  if exist then
    return errh(req, res, nxt,
      xerror.inval(nil, 'an account for that email already exists'))
  end

  -- TODO: should be in a transaction (token + mqueue)

  -- generate a new base64-encoded token
  local tok; tok, err = app:token({
    type = cfg.token_type,
    ref_id = acct.id,
    max_age = cfg.token_max_age,
    once = true,
  })
  if not tok then
    return errh(req, res, nxt, err)
  end

  -- hmac-encode it
  local encoded = crypto.encode(cfg.auth_key, tok, acct.email, new_email)
  local ok; ok, err = app:mqueue({
    max_attempts = cfg.max_attempts,
    max_age = cfg.queue_max_age,
    queue = cfg.queue_name,
  }, nil, xtable.merge({}, cfg.payload, {
    old_email = acct.email,
    new_email = new_email,
    encoded_token = encoded,
  }))
  if not ok then
    return errh(req, res, nxt, err)
  end

  nxt()
end

function M.changeemail(req, res, nxt, errh, cfg)
  local app = req.app

  local enc_tok, err = xerror.inval(req.url.query and req.url.query.t, 'no token')
  if not enc_tok then
    return errh(req, res, nxt, err)
  end
  local old_email; old_email, err = xerror.inval(req.url.query and req.url.query.oe, 'no old email')
  if not old_email then
    return errh(req, res, nxt, err)
  end
  local new_email; new_email, err = xerror.inval(req.url.query and req.url.query.ne, 'no new email')
  if not new_email then
    return errh(req, res, nxt, err)
  end

  -- hmac-decode the token
  local tok; tok, err = xerror.inval(crypto.decode(cfg.auth_key,
    cfg.token_max_age, enc_tok, old_email, new_email), 'invalid token')
  if not tok then
    return errh(req, res, nxt, err)
  end

  -- load the corresponding account
  local acct; acct, err = app:account(old_email)
  if not acct then
    return errh(req, res, nxt, err)
  end

  -- validate the token
  local ok; ok, err = app:token({
    type = cfg.token_type,
    ref_id = acct.id,
  }, nil, tok)
  if not ok then
    return errh(req, res, nxt, err)
  end

  -- all good, change the email for that account
  -- TODO: then delete all existing sessions for that account id
  ok, err = app:db(function(conn)
    return xerror.must(acct:change_email(new_email, conn))
  end)
  if not ok then
    return errh(req, res, nxt, err)
  end

  nxt()
end

function M.authz(req, res, nxt, denyh)
  local routeargs = req.routeargs
  if routeargs.allow or routeargs.deny then
    local allowset = xtable.toset(routeargs.allow)
    if allowset['?'] then
      -- ? means allow everyone, authenticated or not
      return nxt()
    end

    local acct = req.locals.account
    if acct and allowset['*'] then
      -- * means allow anyone authenticated
      return nxt()
    end
    if acct and acct.verified and allowset['@'] then
      -- @ means allow anyone authenticated and verified
      return nxt()
    end

    local acctset = xtable.toset(acct and acct.groups)
    local allowinter = xtable.setinter(allowset, acctset)
    if next(allowinter) then
      -- account has one allowed group, so it is allowed
      return nxt()
    end

    -- not allowed by allowset, check if denied by denyset.
    local denyset = xtable.toset(routeargs.deny)
    if denyset['?'] then
      -- deny access to everyone, authenticated or not
      return denyh(req, res, nxt)
    end
    if acct and denyset['*'] then
      -- deny access to anyone authenticated
      return denyh(req, res, nxt)
    end
    if acct and acct.verified and denyset['@'] then
      -- deny access to anyone authenticated and verified
      return denyh(req, res, nxt)
    end
    local denyinter = xtable.setinter(denyset, acctset)
    if next(denyinter) then
      -- account has one denied group, so deny access
      return denyh(req, res, nxt)
    end
  end
  nxt()
end

return M
