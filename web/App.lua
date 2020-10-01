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
  -- TODO: first go through app-level middlewares, then mux, which
  -- should just be another app-level middleware (the last?).
end

-- levels:
--   d: debug = 1
--   e: error = 1000
--   i: info = 10
--   w: warning = 100
local LOGLEVELS = {
  d = 1,
  debug = 1,
  e = 1000,
  error = 1000,
  i = 10,
  info = 10,
  w = 100,
  warning = 100,
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
