package = "tulip"
build = {
  type = 'builtin'
}
dependencies = {
  "lua >= 5.3, < 5.5",

  "mna/lua-cjson 62fe2246ccb15139476e5a03648633ed69404250-2",
  "mna/luaossl	20200709-1",
  "mna/luapgsql	1.6.1-1",
  "mna/luaunit	3.3-1",

  "argon2 3.0.1-1",
  "base64 1.5-2",
  "basexx	0.4.1-1",
  "binaryheap	0.4-1",
  "compat53	0.8-1",
  "cqueues 20200726.54-0",
  "cqueues-pgsql	0.1-0",
  "fifo	0.2-0",
  "http	0.3-0",
  "inspect	3.1.1-0",
  "lpeg	1.0.2-1",
  "lpeg_patterns	0.5-0",
  "lua-resty-template 2.0-1",
  "lua-resty-tsort 1.0-1",
  "lua-zlib 1.2-1",
  "luabenchmark	0.10.0-1",
  "luacov	0.14.0-2",
  "luafn	0.2-1",
  "luaposix	35.0-1",
  "luashell	0.4-1",
  "net-url	0.9-1",
  "optparse	1.4-1",
  "process 1.9.0-1",
  "tcheck	0.1-1",
  "xpgsql	0.5-1",
}
source = {
   url = "git+ssh://git@git.sr.ht/~mna/tulip"
}
description = {
   homepage = "Lua web framework based on lua-http and PostgreSQL.",
   license = "BSD"
}
version = 'git-1'

