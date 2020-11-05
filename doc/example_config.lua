local App = require 'web.App'

local app = App{
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

  worker = {
    queues = {'a', 'b'},
    idle_sleep = 1,
    max_idle_sleep = 60,
    max_concurrency = 5,
    dequeue_batch = 2,
  },

  -- automatically uses the middleware package, that registers app-wide
  -- web middleware, that is, func(req, res, nxt) signatures.
  middleware = {
    'routes',
  },

  -- wmiddleware is like middleware, but for worker queues. Those have
  -- the func(msg, nxt) signatures.
  wmiddleware = {
    'wroutes',
  },

  -- automatically uses the mux package, those are web middleware routes.
  -- func(req, res, nxt) signatures.
  routes = {
    no_such_method = function() end,
    not_found = function() end,
    {method = 'GET', pattern = '^/$', handler = function() end},
  },

  -- wroutes is like routes, but for worker queues. It maps a message to
  -- a handler based on the pattern. func(msg, nxt) signatures.
  wroutes = {
    not_found = function() end,
    {pattern = '^queue_name$', handler = function() end},
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

  -- log also registers a middleware and wmiddleware.
  log = {
    level = 'i',
  },

  ['third.party.pkg'] = {
    -- config for that package
  },

  cron = {
             -- ┌───────────── min (0 - 59)
             -- │ ┌────────────── hour (0 - 23)
             -- │ │ ┌─────────────── day of month (1 - 31)
             -- │ │ │ ┌──────────────── month (1 - 12)
             -- │ │ │ │ ┌───────────────── day of week (0 - 6) (0 to 6 are Sunday to
             -- │ │ │ │ │                  Saturday, or use names; 7 is also Sunday)
             -- │ │ │ │ │
             -- │ │ │ │ │
    job_name = '* * * * *',

    other_job = { schedule = '...', command = '...', max_attempts = 3, max_age = 30 },
  },

  -- metrics also registers a middleware and wmiddleware.
  metrics = {
    -- configures the server where to send UDP metric packets
    host = '127.0.0.1',
    port = 8125,
  },
}

assert(app:run())
