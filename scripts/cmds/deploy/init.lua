local fn = require 'fn'
local inspect = require 'inspect'
local sh = require 'shell'
local imguserdata = require 'scripts.cmds.deploy.imguserdata'

local function log(s, ...)
  local msg = string.format(s, ...)
  io.write(msg)
  if not string.match(msg, '\n$') then
    io.flush()
  end
end

local function get_domain(domain)
  -- assume the part before the first dot is the subdomain
  local sub, main = string.match(domain, '^([^%.]+)%.(.+)$')

  -- check if the domain exists
  log('> get domain %s...', main)
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
  log(' ok\n')
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
    '--size', SIZE, '--user-data', imguserdata, '--wait',
  }
  if key_ids then
    table.insert(args, '--ssh-keys')
    table.insert(args, key_ids)
  end
  if tags then
    table.insert(args, '--tag-names')
    table.insert(args, tags)
  end
  log('> create image node %s...', name)
  assert(sh.cmd(table.unpack(args)):output())
  log(' ok\n')

  -- get this droplet's id
  log('> get image node id of %s...', name)
  local out = sh.cmd('doctl', 'compute', 'droplet', 'list', '--format', 'ID,Name,Public IPv4', '--no-header'):output()
  local base_id, base_ip
  for id, nm, ip in string.gmatch(out, '%f[^%s\0](%S+)%s+(%S+)%s+(%S+)') do
    if nm == name then
      base_id = id
      base_ip = ip
      break
    end
  end
  assert(base_id, 'could not find base node used to create image')
  log(' ok\n')

  io.write(string.format(
    [[
> base node for %s is being configured, you may inspect its progress by running:
    $ doctl compute ssh %s
  and follow the configuration progress by running:
    $ journalctl -fu cloud-final

  Note that it will reboot after configuration, you should check that after the
  reboot everything is running correctly, e.g. by running:
    $ systemctl status

  You should extract the generated secrets and store them securely:
    $ mkdir -p ./run/secrets/%s
    $ scp root@%s:/opt/secrets/* ./run/secrets/%s/

Press ENTER when ready to continue.
]], name, base_id, name, base_ip, name))
  io.read('l')

  if not sh('doctl', 'compute', 'droplet-action', 'shutdown', base_id, '--wait') then
    error(string.format('failed to shutdown base image node %s (id=%s), delete it manually', name, base_id))
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
  log('> get image %s...', image)
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
  log(' ok\n')
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

  log('> get node associated with IP address %s...', dom_obj.A.ip)
  local out = assert(sh.cmd('doctl', 'compute', 'droplet', 'list',
    '--format', 'ID,Name,Public IPv4', '--no-header'):output())

  for id, name, ip4 in string.gmatch(out, '%f[^%s\0](%S+)%s+(%S+)%s+(%S+)') do
    if ip4 == dom_obj.A.ip then
      log(' ok\n')
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
