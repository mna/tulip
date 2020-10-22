local sh = require 'shell'

local function get_domain(domain, opts)
  -- assume the part before the first dot is the subdomain
  local sub, main = string.match(domain, '^([^%.]+)%.(.+)$')
  local out = assert(sh.cmd(
    'doctl', 'compute', 'domain', 'records', 'list',
    main, '--no-header', '--format', 'ID,Type,Data,Name'
  ):output())
end

local function create_node(domain, opts)

end

local function get_node(domain, opts)

end

return function(domain, opts)
  local node
  if opts.create then
    node = create_node(domain, opts)
  else
    node = get_node(domain, opts)
  end

  local inspect = require 'inspect'
  print(inspect(node))
end
