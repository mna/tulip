local inspect = require 'inspect'
local sh = require 'shell'

local function get_domain(domain)
  -- assume the part before the first dot is the subdomain
  local sub, main = string.match(domain, '^([^%.]+)%.(.+)$')

  -- check if the domain exists
  local ok = (sh.cmd('doctl', 'compute', 'domain', 'list', '--no-header', '--format', 'Domain') |
    sh.cmd('grep', string.format('^%s$', main))):exec()
  if not ok then
    return
  end

  local out = assert(sh.cmd(
    'doctl', 'compute', 'domain', 'records', 'list',
    main, '--no-header', '--format', 'ID,Type,Data,Name'
  ):output())

  local o = {domain = domain, subdomain = sub}
  for id, typ, data, name in string.gmatch(out, '%f[^%s\0](%S+)%s+(%S+)%s+(%S+)%s+(%S+)') do
    if name == sub and (typ == 'A' or typ == 'AAAA') then
      o[typ] = {id = id, ip = data}
    end
  end
  return o
end

local function create_image(dom_obj, opts)

end

local function create_node(dom_obj, opts)
  local parts = {}
  for s in string.gmatch(opts.create, '([^:]+)') do
    table.insert(parts, s)
  end
  if #parts < 2 or #parts > 3 then
    error('invalid --create value, want REGION:SIZE or REGION:SIZE:IMAGE')
  end

  local region, size, image = table.unpack(parts)
  if not image then
    image = create_image(dom_obj, opts)
  end

  -- TODO: resolve ssh keys, prepare tag names format

  -- TODO: how to name the node? This would likely be the same name as an existing
  -- deployment for the same domain...
  local name = string.gsub(dom_obj.domain, '%.', '-')
  assert(sh('doctl', 'compute', 'droplet', 'create', name,
    '--image', image,
    '--region', region,
    '--size', size,
    '--wait'))
end

local function get_node(dom_obj, opts)
  if not dom_obj.A then
    error('domain is not associated to any node')
  end

  local out = assert(sh.cmd('doctl', 'compute', 'droplet', 'list',
    '--format', 'ID,Name,Public IPv4', '--no-header'):output())

  for id, name, ip4 in string.gmatch(out, '%f[^%s\0](%S+)%s+(%S+)%s+(%S+)') do
    if ip4 == dom_obj.A.ip then
      return {id = id, name = name, ip4 = ip4}
    end
  end
end

return function(domain, opts)
  local dom_obj = get_domain(domain)
  assert(dom_obj, 'domain does not exist')

  local node
  if opts.create then
    node = create_node(dom_obj, opts)
  else
    node = get_node(dom_obj, opts)
    assert(node, string.format('no node exists for IP address %s', dom_obj.A.ip))
  end

  print(inspect(dom_obj))
  print(inspect(node))
end
