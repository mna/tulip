local cqueues = require 'cqueues'
local tcheck = require 'tcheck'
local xerror = require 'tulip.xerror'

local function register_packages(app, cfg)
  local pkgs = {}

  -- First, require the top-level keys that represent packages.
  for k, v in pairs(cfg) do
    local full_name

    -- if there is no '.' in the key, try first as 'tulip.pkg.<key>'
    local ok, pkg = false, nil
    if not string.find(k, '.', 1, true) then
      full_name = 'tulip.pkg.'..k
      ok, pkg = pcall(require, full_name)
    end
    if not ok then
      full_name = k
      ok, pkg = pcall(require, k)
    end

    if not ok then
      xerror.throw('package not found: %s: %s', k, pkg)
    end
    if pkgs[full_name] then
      xerror.throw('package already required: %s', full_name)
    end
    pkgs[full_name] = {
      package = pkg,
      defined_name = k,
      config = v,
    }

    if pkg.replaces then
      if pkgs[pkg.replaces] then
        xerror.throw('package %s replaces %s, which is already required', full_name, pkg.replaces)
      end
      pkgs[pkg.replaces] = true
    end

    if pkg.app then
      for appk, appv in pairs(pkg.app) do
        app[appk] = appv
      end
    end
  end
  app.packages = pkgs

  for _, v in pairs(pkgs) do
    if v ~= true then
      local pkg = v.package

      -- check fulfilled dependencies
      if pkg.requires then
        for _, dep in ipairs(pkg.requires) do
          if not pkgs[dep] then
            xerror.throw('package %s requires package %s', v.defined_name, dep)
          end
        end
      end

      -- register the package
      pkg.register(v.config, app)
    end
  end
end

-- Returns the __name of the metatable of o, or nil if none.
local function metatable_name(o)
  if type(o) == 'table' then
    local mt = getmetatable(o)
    return mt and mt.__name
  end
end

local LOGLEVELS = {
  d = 1,    debug = 1,
  e = 1000, error = 1000,
  i = 10,   info = 10,
  w = 100,  warning = 100,
}

local App = {__name = 'tulip.App'}
App.__index = App

-- Registers a name with a value in the collection identified by field.
-- If append is true and a value already exists for that name, then each
-- value in the array part of v is appended to the existing value.
-- Otherwise if append is false and a value already exists, an error
-- is thrown.
-- Internal method for extenders of App instance.
function App:_register(field, name, v, append)
  local coll = self[field] or {}
  if coll[name] then
    if append then
      local ar = coll[name]
      for _, vv in ipairs(v) do
        table.insert(ar, vv)
      end
    else
      if string.match(field, '^_') then
        field = string.sub(field, 2)
      end
      xerror.throw('%s: %q is already registered', field, name)
    end
  end
  coll[name] = v
  self[field] = coll
end

-- Lookup a name and return its registered value in the collection
-- identified by field. Internal method for extenders of App instance.
function App:_lookup(field, name)
  local coll = self[field]
  if not coll then return end

  if not string.find(name, '.', 1, true) then
    local v = coll['tulip.pkg.' .. name]
    if v then return v end
  end
  return coll[name]
end

-- Resolve the names registered in the coll array by replacing the names
-- with the values registered in the collection identified by field.
-- Internal method for extenders of App instance.
function App:_resolve(field, coll)
  for i, v in ipairs(coll) do
    local typ = type(v)
    if typ == 'string' then
      local vi = self:_lookup(field, v)
      if not vi then
        if string.match(field, '^_') then
          field = string.sub(field, 2)
        end
        xerror.throw('no %s registered for %q', field, v)
      end
      coll[i] = vi
    elseif metatable_name(v) == 'tulip.App' then
      v:activate()
    end
  end
end

-- Returns true if name is a registered package for this App instance.
-- If exact is true, this exact package must be registered (i.e. it must
-- not be a drop-in replacement for it).
-- Returns true if the package is registered, or nil and an error message
-- indicating that the package is not registered, so it can also be
-- called inside an xerror.must call.
function App:has_package(name, exact)
  local pkg = self.packages and self.packages[name]
  if pkg and (pkg ~= true or not exact) then
    return true
  end
  return nil, string.format('package %s is not registered', name)
end

-- Encodes the table t to the specified mime type, using the
-- registered encoders. It panics if no encoder supports this mime type,
-- otherwise returns the encoded string or nil and an error.
function App:encode(t, mime)
  if self.encoders then
    for _, enc in pairs(self.encoders) do
      local s, err = enc(t, mime)
      if s or err then return s, err end
    end
  end
  xerror.throw('no encoder registered for MIME type %q', mime)
end

-- Decodes the string s encoded as the specified mime type, using
-- the registered decoders. It panics if no decoder supports this mime type,
-- otherwise returns the decoded value or nil and an error.
function App:decode(s, mime)
  if self.decoders then
    for _, dec in pairs(self.decoders) do
      local t, err = dec(s, mime)
      if t ~= nil or err then return t, err end
    end
  end
  xerror.throw('no decoder registered for MIME type %q', mime)
end

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

-- Register an encoder in the list of encoders. It panics if an encoder
-- is already registered for that name.
function App:register_encoder(name, enc)
  tcheck({'*', 'string', 'table|function'}, self, name, enc)
  self:_register('encoders', name, enc)
end

-- Get the registered encoder instance for that name, or nil if none.
function App:lookup_encoder(name)
  tcheck({'*', 'string'}, self, name)
  return self:_lookup('encoders', name)
end

-- Register a decoder in the list of decoders. It panics if a decoder is
-- already registered for that name.
function App:register_decoder(name, dec)
  tcheck({'*', 'string', 'table|function'}, self, name, dec)
  self:_register('decoders', name, dec)
end

-- Get the registered decoder instance for that name, or nil if none.
function App:lookup_decoder(name)
  tcheck({'*', 'string'}, self, name)
  return self:_lookup('decoders', name)
end

-- Register a finalizer in the list of finalizers. It panics if a finalizer
-- is already registered for that name.
function App:register_finalizer(name, fz)
  tcheck({'*', 'string', 'table|function'}, self, name, fz)
  self:_register('finalizers', name, fz)
end

-- Get the registered finalizer instance for that name, or nil if none.
function App:lookup_finalizer(name)
  tcheck({'*', 'string'}, self, name)
  return self:_lookup('finalizers', name)
end

-- Register a logger in the list of loggers. It panics if a logger is
-- already registered for that name.
function App:register_logger(name, lg)
  tcheck({'*', 'string', 'table|function'}, self, name, lg)
  self:_register('loggers', name, lg)
end

-- Get the registered logger instance for that name, or nil if none.
function App:lookup_logger(name)
  tcheck({'*', 'string'}, self, name)
  return self:_lookup('loggers', name)
end

-- Activates all packages registered by the app. Panics if activation
-- fails (that is, the activate function of packages should throw on
-- error). Receives the cqueue instance that will be used by the application.
function App:activate(cq)
  tcheck({'tulip.App', 'userdata|nil'}, self, cq)

  if type(self.log_level) == 'string' then
    self.log_level = LOGLEVELS[self.log_level]
  end

  for _, pkg in pairs(self.packages) do
    if pkg ~= true then
      local cfg = pkg.config
      pkg = pkg.package
      if pkg.activate then
        pkg.activate(cfg, self, cq)
      end
    end
  end
  return true
end

-- Runs the application, activating any registered package and
-- calling App:main. It returns the value(s) returned by App:main
-- and calls any registered finalizer before returning.
-- It panics if activation fails (that is, the activate method
-- of packages should throw an error if they fail to activate).
function App:run()
  local cq = cqueues.new()
  self:activate(cq)

  if not self.main then
    xerror.throw('no main field registered by app')
  end
  local res = table.pack(self:main(cq))
  if self.finalizers then
    for _, f in pairs(self.finalizers) do
      f(self)
    end
  end
  return table.unpack(res, 1, res.n)
end

-- Returns a function that creates an App instance for the
-- provided configuration.
return function (cfg)
  tcheck('table', cfg)

  local o = {config = cfg}
  setmetatable(o, App)

  -- require and register all config packages
  register_packages(o, cfg)

  return o
end
