local fn = require 'fn'
local inspect = require 'inspect'
local process = require 'process'
local sh = require 'shell'
local userdata = require 'scripts.cmds.deploy.userdata'

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

local function get_ssh_keys(list)
  local names = {}
  for name in string.gmatch(list, '([^,]+)') do
    names[name] = true
  end

  local out = assert(sh.cmd(
    'doctl', 'compute', 'ssh-key', 'list',
    '--no-header', '--format', 'ID,Name,FingerPrint'
  ):output())

  local ar = {}
  for id, name, fp in string.gmatch(out, '%f[^%s\0](%S+)%s+(%S+)%s+(%S+)') do
    if names[name] then
      table.insert(ar, {id = id, name = name, fingerprint = fp})
    end
  end
  return ar
end

local function create_image(dom_obj, region, opts)
  local SIZE = 's-1vcpu-1gb'
  local BASE_IMAGE = 'fedora-32-x64'

  local key_ids
  if opts.ssh_keys then
    -- ssh key ids need to be comma-separated
    local keys = get_ssh_keys(opts.ssh_keys)
    key_ids = table.concat(fn.reduce(function(cumul, _, v)
      table.insert(cumul, v.id)
      return cumul
    end, {}, ipairs(keys)), ',')
  end
  if (not key_ids) or key_ids == '' then
    error('at least one ssh key must be provided to prevent password-based login')
  end

  local tags
  if opts.tags then
    tags = opts.tags -- tags need to be comma-separated
  end

  -- DigitalOcean doesn't prevent creation of nodes with the same name.
  -- Add the current epoch to help make it unique.
  local name = string.gsub(dom_obj.domain, '%.', '-') .. '.base.' .. os.time()
  local args = {
    'doctl', 'compute', 'droplet', 'create', name,
    '--image', BASE_IMAGE, '--region', region,
    '--size', SIZE, '--user-data', userdata, '--wait',
  }
  if key_ids then
    table.insert(args, '--ssh-keys')
    table.insert(args, key_ids)
  end
  if tags then
    table.insert(args, '--tag-names')
    table.insert(args, tags)
  end
  assert(sh(table.unpack(args)))

  -- get this droplet's id
  local out = sh.cmd('doctl', 'compute', 'droplet', 'list', '--format', 'ID,Name', '--no-header'):output()
  local base_id
  for id, nm in string.gmatch(out, '%f[^%s\0](%S+)%s+(%S+)') do
    if nm == name then
      base_id = id
      break
    end
  end
  assert(base_id, 'could not find base node used to create image')

  error(string.format('done creating base node, id=%s', base_id))

  -- TODO: actually, grab the generated passwords/secrets before shutdown? how?
  -- TODO: shutdown the node at the end of the userdata

  local status = 'active'
  local start = os.time()
  while status ~= 'off' and os.difftime(os.time(), start) < 1000 do
    process.sleep(10)
    status = sh.cmd('doctl', 'compute', 'droplet', 'get', base_id, '--format', 'Status', '--no-header'):output()
  end
  if status ~= 'off' then
    error(string.format(
      'failed to shutdown base image node %s (id=%s) to take snapshot, delete it manually', name, base_id))
  end

  if not sh('doctl', 'compute', 'droplet-action', 'snapshot', base_id, '--snapshot-name', name, '--wait') then
    error(string.format('failed to create snapshot image of node %s (id=%s), delete it manually', name, base_id))
  end
  if not sh('doctl', 'compute', 'droplet', 'delete', base_id, '--force') then
    error(string.format('failed to destroy base image node %s (id=%s), delete it manually', name, base_id))
  end
end

local function get_image(image)
  -- validate that the image is valid and warn if it is a public
  -- one (unlikely to be secured and ready to run the app)
  local out = sh.cmd('doctl', 'compute', 'image', 'get', image, '--format', 'Public', '--no-header'):output()
  if not out then
    error('image does not exist')
  elseif out ~= 'false' then
    io.write(string.format(
      'image %s is public, it is probably not secure nor fitting to deploy on this, continue anyway? [y/N]',
      image))
    local res = io.read('l')
    if not string.match(res, '^%s*[yY]') then
      error('canceled by user')
    end
  end
  return image
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
    image = create_image(dom_obj, region, opts)
  else
    image = get_image(image)
  end

  -- ssh key(s) is required, otherwise the droplet is created with
  -- a root password, insecure.
  local key_ids
  if opts.ssh_keys then
    -- ssh key ids need to be comma-separated
    local keys = get_ssh_keys(opts.ssh_keys)
    key_ids = table.concat(fn.reduce(function(cumul, _, v)
      table.insert(cumul, v.id)
      return cumul
    end, {}, ipairs(keys)), ',')
  end
  if (not key_ids) or key_ids == '' then
    error('at least one ssh key must be provided to prevent password-based login')
  end

  local tags
  if opts.tags then
    tags = opts.tags -- tags need to be comma-separated
  end

  -- DigitalOcean doesn't prevent creation of nodes with the same name.
  -- Add the current epoch to help make it unique.
  local name = string.gsub(dom_obj.domain, '%.', '-') .. '.' .. os.time()
  local args = {
    'doctl', 'compute', 'droplet', 'create', name,
    '--image', image, '--region', region,
    '--size', size, '--wait',
  }
  if key_ids then
    table.insert(args, '--ssh-keys')
    table.insert(args, key_ids)
  end
  if tags then
    table.insert(args, '--tag-names')
    table.insert(args, tags)
  end
  assert(sh(table.unpack(args)))
end

local function get_node(dom_obj)
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
    node = get_node(dom_obj)
    assert(node, string.format('no node exists for IP address %s', dom_obj.A.ip))
  end

  print(inspect(dom_obj))
  print(inspect(node))
end
