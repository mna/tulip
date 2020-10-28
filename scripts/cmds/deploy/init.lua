local fn = require 'fn'
local sh = require 'shell'
local imgsh = require 'scripts.cmds.deploy.image_script'

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

  local o = {domain = domain, subdomain = sub, maindomain = main}
  for id, typ, data, name in string.gmatch(out, '%f[^%s\0](%S+)%s+(%S+)%s+(%S+)%s+(%S+)') do
    if name == sub and (typ == 'A' or typ == 'AAAA') then
      o[typ] = {id = id, ip = data}
    end
  end
  log(' ok\n')
  return o
end

-- assign the domain to this node
local function set_domain(dom_obj, node)
  -- if the domain is already mapped to an ip address, update it
  local out = assert(sh.cmd('doctl', 'compute', 'domain', 'records', 'list',
    dom_obj.maindomain, '--format', 'ID,Type', '--no-header'):output())
  local rec_id = string.match(out, '%f[^%s\0](%S+)%s+A')
  if rec_id then
    log('> update domain A record of %s to %s...', dom_obj.domain, node.ip4)
    assert(sh.cmd('doctl', 'compute', 'domain', 'records', 'update',
      dom_obj.maindomain, '--record-name', dom_obj.subdomain,
      '--record-id', rec_id, '--record-ttl', 120, '--record-type', 'A',
      '--record-data', node.ip4):output())
  else
    log('> create domain A record of %s to %s...', dom_obj.domain, node.ip4)
    assert(sh.cmd('doctl', 'compute', 'domain', 'records', 'create',
      dom_obj.maindomain, '--record-name', dom_obj.subdomain,
      '--record-ttl', 120, '--record-type', 'A',
      '--record-data', node.ip4):output())
  end
  log(' ok\n')
end

local function set_project(project, node)
  log('> assign node to project %s...', project)

  local out = assert(sh.cmd('doctl', 'projects', 'list',
    '--format', 'ID,Name', '--no-header'):output())
  local proj_id
  for id, nm in string.gmatch(out, '%f[^%s\0](%S+)%s+(%S+)') do
    if nm == project then
      proj_id = id
      break
    end
  end
  assert(proj_id, 'could not find project')

  assert(sh.cmd('doctl', 'projects', 'resources', 'assign',
    proj_id, '--resource', 'do:droplet:' .. node.id):output())

  log(' ok\n')
end

local function set_firewall(firewall, node)
  log('> assign firewall %s to node...', firewall)

  local out = assert(sh.cmd('doctl', 'compute', 'firewall', 'list',
    '--format', 'ID,Name', '--no-header'):output())
  local fw_id
  for id, nm in string.gmatch(out, '%f[^%s\0](%S+)%s+(%S+)') do
    if nm == firewall then
      fw_id = id
      break
    end
  end
  assert(fw_id, 'could not find firewall')

  assert(sh.cmd('doctl', 'compute', 'firewall', 'add-droplets',
    fw_id, '--droplet-ids', node.id):output())

  log(' ok\n')
end

local function get_ssh_keys(list)
  local names = {}
  for name in string.gmatch(list, '([^,]+)') do
    names[name] = true
  end

  log('> get ssh key id(s)...')
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
  log(' ok\n')
  return ar
end

-- creates a node to configure a new image, takes a snapshot of the node then
-- destroys it and returns the id of the snapshot, ready to use in a node creation.
local function create_image(dom_obj, region, opts)
  local SIZE = 's-1vcpu-1gb'
  local BASE_IMAGE = 'fedora-32-x64'

  if opts.ssh_keys and not opts.key_ids then
    -- ssh key ids need to be comma-separated
    local keys = get_ssh_keys(opts.ssh_keys)
    opts.key_ids = table.concat(fn.reduce(function(cumul, _, v)
      table.insert(cumul, v.id)
      return cumul
    end, {}, ipairs(keys)), ',')
  end
  if (not opts.key_ids) or (opts.key_ids == '') then
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
    '--image', BASE_IMAGE, '--region', region, '--ssh-keys', opts.key_ids,
    '--size', SIZE, '--user-data', imgsh, '--wait',
  }
  if tags then
    table.insert(args, '--tag-names')
    table.insert(args, tags)
  end
  log('> create base image node %s...', name)
  assert(sh.cmd(table.unpack(args)):output())
  log(' ok\n')

  -- get this droplet's id
  log('> get base image node id of %s...', name)
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
> base node for %s is being configured...
  You may inspect its progress by running:
    $ doctl compute ssh %s
  and follow the configuration progress by running:
    $ journalctl -fu cloud-final

  Note that it will reboot after configuration, you should check that
  after the reboot everything is running correctly, e.g. by running:
    $ systemctl status

  You should extract the generated secrets locally and store them
  securely:
    $ mkdir -p ./run/secrets/%s
    $ scp root@%s:/opt/secrets/* ./run/secrets/%s/

Press ENTER when ready to continue.
]], name, base_id, name, base_ip, name))
  io.read('l')

  log('> shutdown base image node %s...', name)
  if not sh.cmd('doctl', 'compute', 'droplet-action', 'shutdown', base_id, '--wait'):output() then
    error(string.format('failed to shutdown base image node %s (id=%s), delete it manually', name, base_id))
  end
  log(' ok\n')
  log('> create snapshot %s of base image node...', name)
  if not sh.cmd('doctl', 'compute', 'droplet-action', 'snapshot',
      base_id, '--snapshot-name', name, '--wait'):output() then
    error(string.format('failed to create snapshot image of node %s (id=%s), delete it manually', name, base_id))
  end
  log(' ok\n')
  log('> destroy base image node %s...', name)
  if not sh.cmd('doctl', 'compute', 'droplet', 'delete', base_id, '--force'):output() then
    error(string.format('failed to destroy base image node %s (id=%s), delete it manually', name, base_id))
  end
  log(' ok\n')

  log('> get snapshot id of %s...', name)
  local snapshot_id
  out = sh.cmd('doctl', 'compute', 'image', 'list', '--format', 'ID,Name', '--no-header'):output()
  for id, nm in string.gmatch(out, '%f[^%s\0](%S+)%s+(%S+)') do
    if nm == name then
      snapshot_id = id
      break
    end
  end
  assert(snapshot_id, 'could not find snapshot')
  log(' ok\n')

  return snapshot_id
end

-- returns the image ID of the image corresponding to the provided name/slug.
local function get_image(image)
  -- validate that the image is valid and warn if it is a public
  -- one (unlikely to be secured and ready to run the app)
  log('> get image %s...', image)
  local out = (
    sh.cmd('doctl', 'compute', 'image', 'list', '--format', 'ID,Name,Public', '--public') |
    sh.cmd('grep', '--fixed-strings', ' ' .. image .. ' ')):output()
  local id, _, pub = string.match(out, '%f[^%s\0](%S+)%s+(%S+)%s+(%S+)')
  if not id then
    error('image does not exist')
  elseif pub ~= 'false' then
    print('\n', out, id, pub)
    io.write(string.format(
      'image %s is public, it is probably not secure nor fitting to deploy on this, continue anyway? [y/N]',
      image))
    local res = io.read('l')
    if not string.match(res, '^%s*[yY]') then
      error('canceled by user')
    end
  end
  log(' ok\n')
  return id
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
  local image_id
  if not image then
    image_id = create_image(dom_obj, region, opts)
  else
    image_id = get_image(image)
  end
  assert(image_id, 'could not get image id')

  -- ssh key(s) is required, otherwise the droplet is created with
  -- a root password, insecure.
  if opts.ssh_keys and not opts.key_ids then
    -- ssh key ids need to be comma-separated
    local keys = get_ssh_keys(opts.ssh_keys)
    opts.key_ids = table.concat(fn.reduce(function(cumul, _, v)
      table.insert(cumul, v.id)
      return cumul
    end, {}, ipairs(keys)), ',')
  end
  if (not opts.key_ids) or (opts.key_ids == '') then
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
    '--image', image_id, '--region', region,
    '--ssh-keys', opts.key_ids, '--size', size, '--wait',
    '--format', 'ID,Name,Public IPv4', '--no-header',
  }
  if tags then
    table.insert(args, '--tag-names')
    table.insert(args, tags)
  end
  log('> create node %s based on image id %s...', name, image_id)
  local out = assert(sh.cmd(table.unpack(args)):output())
  local id, _, ip4 = string.match(out, '%f[^%s\0](%S+)%s+(%S+)%s+(%S+)')
  log(' ok\n')
  return {id = id, name = name, ip4 = ip4}
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

local function deploy_code(tag, node)
  if not tag then
    -- get latest tag
    tag = assert(sh.cmd('git', 'describe', '--tags', '--abbrev=0'):output())
  end
  log('> deploy code at tag %s to %s...', tag, node.name)
  assert(sh.cmd('doctl', 'compute', 'ssh', node.id,
    '--ssh-command', '# TODO: get deploy script'):output())
  log(' ok\n')
end

local REQUIRES_CREATE = {
  'firewall',
  'project',
  'ssh_keys',
  'tags',
}

return function(domain, opts)
  if not opts.create then
    for _, arg in ipairs(REQUIRES_CREATE) do
      if opts[arg] then
        error(string.format('option %s requires --create', arg))
      end
    end
  end

  local dom_obj = get_domain(domain)
  assert(dom_obj, 'domain does not exist')

  local node
  if opts.create then
    node = create_node(dom_obj, opts)
    if opts.project then
      set_project(opts.project, node)
    end
    if opts.firewall then
      set_firewall(opts.firewall, node)
    end
  else
    node = get_node(dom_obj)
    assert(node, string.format('no node exists for IP address %s', dom_obj.A.ip))
  end

  if opts.with_db then
    -- TODO: step 2: install database from backup
  end

  if not opts.without_code then
    deploy_code(opts.with_code, node)
  end

  -- TODO: restart services, always. This means that running the
  -- command like this does nothing except restart services:
  -- $ deploy --without-code www.example.com

  if opts.create then
    -- activate the new node for that sub-domain
    set_domain(dom_obj, node)
  end
end
