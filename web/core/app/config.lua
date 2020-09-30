-- Some packages may register middleware functions to their name,
-- and if so the middleware can be referred to in routes' handlers
-- with a string value of the full package name (e.g. 'web.pkg.static').
--
-- Some packages may register App-level middleware functions, meaning
-- that it will be called for each request handled by the App prior
-- to going through the Mux. The Mux supports per-route middleware
-- that may wrap specific routes' handlers.
--
-- Running an App basically means starting an http(s) server with the
-- App instance as its entry-point middleware, after the translation
-- of lua-http server/stream arguments to request/response/next triplet.
--
-- Built-in packages can have a short name in the App's config, the
-- 'web.pkg.' prefix is automatically added to find a package.
-- Third-party packages need to be fully named.

return {
  locals = {
    -- dictionary of key-values local to this application, e.g.
    -- the app name, a user-visible title, description, contact
    -- email address, etc.
  },

  -- automatically uses the server package
  server = {
    host = '127.0.0.1',
    port = 12345,
    reuseaddr = true,
    reuseport = true,
    -- path = '/unix/socket/path',
    limits = {
      connection_timeout = 10,
      idle_timeout = 60, -- keepalive?
      max_active_connections = 1000,
      read_timeout = 20,
      write_timeout = 20,
    },
    tls = {
      required = true,
      protocol = 'TLSv1_2',
      certificate_path = '/path/to/cert',
      private_key_path = '/path/to/key',
    },
  },

  -- automatically uses the mux package
  routes = {
    no_such_method = function() end,
    not_found = function() end,
    {method = 'GET', pattern = '^/$', handler = function() end},
  },

  -- automatically uses the database package, which includes the
  -- migrator.
  database = {
    connection_string = '',
    migrations = {
      {
        package = 'package_name';
        -- array part contains actualy migrations for this package
        [[
          CREATE TABLE '...'
        ]],
      },
    },
  },

  -- automatically uses the template package
  template = {
    root_path = '/tpl',
  },

  ['third.party.pkg'] = {
    -- config for that package
  },
}
