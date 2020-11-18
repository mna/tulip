#!/usr/bin/env -S llrocks run

local cjson = require 'cjson'
local handler = require 'web.handler'
local xpgsql = require 'xpgsql'

local function send_pubsub(req, res, nxt)
  local app = req.app
  local ok, err = app:pubsub('a', nil, {x=1})
  if ok then
    res:write{status = 204}
  else
    res:write{status = 500, body = err}
  end
  nxt()
end

local function list_jobs(req, res, nxt)
  local app = req.app
  local rows = assert(app:db(function(c)
    return xpgsql.models(assert(c:query[[
      SELECT
        jobid,
        jobname,
        schedule,
        command
      FROM
        cron.job
      ORDER BY
        jobname
    ]]))
  end))
  res:write{
    status = 200,
    content_type = 'application/json',
    body = setmetatable(rows, cjson.array_mt),
  }
  nxt()
end

local function list_messages(req, res, nxt)
  local app = req.app
  local msg_type = req.pathargs[1]
  local stmt = string.format([[
    SELECT
      id,
      attempts,
      max_attempts,
      max_age,
      queue,
      payload,
      first_created
    FROM
      web_pkg_mqueue_%s
  ]], msg_type)

  if msg_type == 'pending' or msg_type == 'active' or
    msg_type == 'dead' then
    local rows = assert(app:db(function(c)
      return xpgsql.models(assert(c:query(stmt)))
    end))
    res:write{
      status = 200,
      content_type = 'application/json',
      body = setmetatable(rows, cjson.array_mt),
    }
  else
    res:write{
      status = 400,
      content_type = 'text/plain',
      body = string.format('invalid message type: %s', msg_type),
    }
  end
  nxt()
end

local M = {}

if string.match(arg[0], '/serve%.lua') then
  os.execute('./scripts/run_server.lua scripts.serve config')
  return
end

function M.config()
  return {
    log = {level = 'debug'},

    server = {
      host = '127.0.0.1',
      port = 0,
      reuseaddr = true,
      reuseport = true,

      limits = {
        connection_timeout = 10,
        idle_timeout = 60, -- keepalive?
        max_active_connections = 1000,
        read_timeout = 20,
        write_timeout = 20,
      },

      tls = {
        required = true,
        protocol = 'TLS',
        certificate_path = 'run/certs/fullchain.pem',
        private_key_path = 'run/certs/privkey.pem',
      },
    },

    database = {
      connection_string = '',
    },

    routes = {
      {method = 'GET', pattern = '^/hello', handler = handler.write{status = 200, body = 'hello, Martin!'}},
      {method = 'GET', pattern = '^/fail', handler = function() error('this totally fails') end},
      {method = 'GET', pattern = '^/pub/(.+)$', handler = handler.dir('scripts')},
      {method = 'GET', pattern = '^/json', handler = handler.write{
        status = 200,
        content_type = 'application/json',
        body = {
          name = 'Martin',
          msg = 'Hi!',
        },
      }},
      {method = 'GET', pattern = '^/url', handler = handler.write{
        status = 200,
        content_type = 'application/x-www-form-urlencoded',
        body = {
          name = 'Martin',
          msg = 'Hi!',
          teeth = 12,
        },
      }},
      {method = 'GET', pattern = '^/pubsub', handler = send_pubsub},
      {method = 'GET', pattern = '^/jobs', handler = list_jobs},
      {method = 'GET', pattern = '^/messages/([^/]+)', handler = list_messages},
    },

    middleware = {
      'log',
      'metrics',
      handler.recover(function(_, res, err) res:write{status = 500, body = tostring(err)} end),
      'reqid',
      'csrf',
      'routes',
    },

    reqid = {size = 12, header = 'x-request-id'},

    json = {
      encoder = {
        allow_invalid_numbers = false,
        number_precision = 4,
        max_depth = 100,
        sparse_array = {
          convert_excessive = true, -- convert excessively sparse arrays to dict instead of failing
          ratio = 2,
          safe = 10,
        },
      },
      decoder = {
        allow_invalid_numbers = false,
        max_depth = 100,
      },
    },

    urlenc = {},

    csrf = {
      auth_key = os.getenv('LUAWEB_CSRFKEY'),
      max_age = 3600 * 12, -- 12 hours, validity of token
      http_only = true,
      secure = true,
      same_site = 'lax', -- one of 'strict', 'lax', or 'none'
    },

    cron = {
      jobs = {
        startup = '10 * * * *',
      },
    },
    token = {},
    mqueue = {},
    pubsub = {
      listeners = {
        a = {function(n) print('>>> ', n.channel, n.payload) end},
      },
    },
    sendgrid = {
      from = os.getenv('LUAWEB_TEST_FROMEMAIL'),
      api_key = os.getenv('LUAWEB_TEST_SENDGRIDKEY'),
    },
    metrics = {
      host = '127.0.0.1',
      port = 8125,
      write_timeout = 5,
      middleware = {
        counter = {},
        timer = {},
      },
    },
  }
end

return M
