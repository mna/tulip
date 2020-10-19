local cqueues = require 'cqueues'
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

local function register_common(app, field, name, v)
  local coll = app[field] or {}
  if coll[name] then
    if string.match(field, '^_') then
      field = string.sub(field, 2)
    end
    error(string.format(
      '%s: %q is already registered', field, name))
  end
  coll[name] = v
  app[field] = coll
end

local function lookup_common(app, field, name)
  local coll = app[field]
  if not coll then return end

  if not string.find(name, '.', 1, true) then
    local v = coll['web.pkg.' .. name]
    if v then return v end
  end
  return coll[name]
end

-- Returns the __name of the metatable of o, or nil if none.
local function metatable_name(o)
  if type(o) == 'table' then
    local mt = getmetatable(o)
    return mt and mt.__name
  end
end

local App = {__name = 'web.App'}
App.__index = App

-- List of App functions (key) to package "generic" names (value)
-- to attach to the App and fail by default when called, to indicate
-- that a package should be registered to get this functionality.
local FAIL_PLACEHOLDERS = {
  db = 'database',
  email = 'email',
  mqueue = 'message queue',
  pubsub = 'pubsub',
  render = 'template',
  token = 'token',
}

for k, v in pairs(FAIL_PLACEHOLDERS) do
  App[k] = function()
    error(string.format('no %s package registered', v))
  end
end

-- The App itself can be used as a middleware function. This is the
-- initial handler called from the server package, and it calls the
-- chain of middleware enabled for the application.
function App:__call(req, res, nxt)
  if not self.middleware then
    if nxt then nxt() end
    return
  end
  handler.chain_middleware(self.middleware, req, res, nxt)
end

-- Encodes the table t to the specified mime type, using the
-- registered encoders. If no encoder supports this mime type,
-- returns nil, otherwise returns the encoded string.
function App:encode(t, mime)
  if self.encoders then
    for _, enc in pairs(self.encoders) do
      local s = enc(t, mime)
      if s then return s end
    end
  end
  error(string.format('no encoder registered for MIME type %q', mime))
end

-- Decodes the string s encoded as the specified mime type, using
-- the registered decoders. If no decoder supports this mime type,
-- returns nil, otherwise returns the decoded value.
function App:decode(s, mime)
  if self.decoders then
    for _, dec in pairs(self.decoders) do
      local t = dec(s, mime)
      if t ~= nil then return t end
    end
  end
  error(string.format('no decoder registered for MIME type %q', mime))
end

local LOGLEVELS = {
  d = 1,    debug = 1,
  e = 1000, error = 1000,
  i = 10,   info = 10,
  w = 100,  warning = 100,
}

-- Logs the t table at level lvl to all registered loggers.
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
    for _, l in pairs(self.loggers) do
      l(t)
    end
  end
end

-- Register a middleware in the list of available middleware.
function App:register_middleware(name, mw)
  tcheck({'*', 'string', 'table|function'}, self, name, mw)
  register_common(self, '_middleware', name, mw)
end

-- Get the registered middleware instance for that name, or nil if none.
function App:lookup_middleware(name)
  tcheck({'*', 'string'}, self, name)
  return lookup_common(self, '_middleware', name)
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
    elseif metatable_name(mw) == 'web.App' then
      -- if mw is an App, activate it
      mw:activate()
    end
  end
end

-- Register an encoder in the list of encoders.
function App:register_encoder(name, mw)
  tcheck({'*', 'string', 'table|function'}, self, name, mw)
  register_common(self, 'encoders', name, mw)
end

-- Get the registered encoder instance for that name, or nil if none.
function App:lookup_encoder(name)
  tcheck({'*', 'string'}, self, name)
  return lookup_common(self, 'encoders', name)
end

-- Register a decoder in the list of decoders.
function App:register_decoder(name, mw)
  tcheck({'*', 'string', 'table|function'}, self, name, mw)
  register_common(self, 'decoders', name, mw)
end

-- Get the registered decoder instance for that name, or nil if none.
function App:lookup_decoder(name)
  tcheck({'*', 'string'}, self, name)
  return lookup_common(self, 'decoders', name)
end

-- Register a logger in the list of loggers.
function App:register_logger(name, mw)
  tcheck({'*', 'string', 'table|function'}, self, name, mw)
  register_common(self, 'loggers', name, mw)
end

-- Get the registered logger instance for that name, or nil if none.
function App:lookup_logger(name)
  tcheck({'*', 'string'}, self, name)
  return lookup_common(self, 'loggers', name)
end

function App:activate(cq)
  tcheck({'web.App', 'userdata'}, self, cq)

  if type(self.log_level) == 'string' then
    self.log_level = LOGLEVELS[self.log_level]
  end

  for _, pkg in ipairs(self.packages) do
    if pkg.activate then
      pkg.activate(self, cq)
    end
  end

  -- special-case: if there is no middleware installed for the App,
  -- but there is a web.pkg.routes middleware registered, install
  -- it automatically.
  if not self.middleware then
    local mux = self:lookup_middleware('web.pkg.routes')
    if mux then
      self.middleware = {mux}
    end
  end
end

function App:run()
  local cq = cqueues.new()
  self:activate(cq)

  if not self.main then
    error('no main field registered by app')
  end
  return self:main(cq)
end

return function (cfg)
  tcheck('table', cfg)

  local o = {config = cfg}
  setmetatable(o, App)

  -- require and register all config packages
  o.packages = register_packages(o, cfg)

  return o
end
