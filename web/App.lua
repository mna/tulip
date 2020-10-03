local handler = require 'web.handler'
local tcheck = require 'tcheck'

local function register_packages(app, cfg)
  local pkgs = {}
  for k, v in pairs(cfg) do
    -- if there is no '.' in the key, try first as 'web.pkg.<key>'
    local ok, pkg = false, nil
    if not string.find(k, '.', 1, true) then
      ok, pkg = pcall(require, 'web.pkg.' .. k)
    end
    if not ok then
      ok, pkg = pcall(require, k)
    end

    if not ok then
      error(string.format('package not found: %s', k))
    end

    table.insert(pkgs, pkg)
    pkg.register(v, app)
  end

  return pkgs
end

local App = {__name = 'web.App'}
App.__index = App

function App:__call(req, res, nxt)
  if not self.middleware then
    if nxt then nxt() end
    return
  end
  handler.chain_middleware(self.middleware, req, res, nxt)
end

local LOGLEVELS = {
  d = 1,    debug = 1,
  e = 1000, error = 1000,
  i = 10,   info = 10,
  w = 100,  warning = 100,
}

function App:log(lvl, t)
  local types = tcheck({'string|number', 'table'}, lvl, t)

  if types[1] == 'string' then
    lvl = LOGLEVELS[lvl] or 0
  end
  -- ignore if requested log level is higher
  if not self.log_level or lvl < self.log_level then return end

  -- log to all registered backends
  if self.loggers then
    t.level = lvl
    for _, l in ipairs(self.loggers) do
      l(t)
    end
  end
end

-- Register a middleware in the list of available middleware.
function App:register_middleware(name, mw)
  local mws = self._middleware or {}
  if mws[name] then
    error(string.format(
      'middleware %q is already registered', name))
  end
  mws[name] = mw
  self._middleware = mws
end

-- Get the registered middleware instance for that name, or nil if none.
function App:lookup_middleware(name)
  local mws = self._middleware
  if mws then return mws[name] end
end

-- Resolve any middleware referenced by name with the actual instance registered
-- for that name. Raises an error if a middleware name is unknown.
function App:resolve_middleware(mws)
  for i, mw in ipairs(mws) do
    local typ = type(mw)
    if typ == 'string' then
      local mwi = self:lookup_middleware(mw)
      if not mwi then
        error(string.format('no middleware registered for %q', mw))
      end
      mws[i] = mwi
    elseif typ == 'table' and mw.__name == 'web.App' then
      -- TODO: if mw is an App, activate it
    end
  end
end

-- TODO: must support "running" or initializing an App that is not
-- used as entrypoint (e.g. a sub-system handler). This needs to
-- happen either if used in the routes or in the top-level middleware.
function App:run()
  if type(self.log_level) == 'string' then
    self.log_level = LOGLEVELS[self.log_level]
  end

  for _, pkg in ipairs(self.packages) do
    if pkg.onrun then
      pkg.onrun(self)
    end
  end

  if not self.main then
    error('no main field registered by app')
  end
  return self:main()
end

return function (cfg)
  tcheck('table', cfg)

  local o = {config = cfg}
  setmetatable(o, App)

  -- require and register all config packages
  o.packages = register_packages(o, cfg)

  return o
end
