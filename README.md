# luaweb

Lua web framework based on [http][] and [PostgreSQL][pg].

* Canonical repository: https://git.sr.ht/~mna/luaweb
* Issue tracker: https://todo.sr.ht/~mna/luaweb

## Description

Lua Web is a minimal and simple web framework that provides a lot with very little.
Using only Lua (currently 5.3) and the PostgreSQL database (currently 12), the
framework packs the following features:

* HTTP and HTTPS ✔
* HTTP/1.1 and HTTP/2 ✔
* Concurrent handling of requests ✔
* Message Queue-style asynchronous processing
* Time series-style storage of metrics
* Cron-like scheduled processing
* Hardened server with timeouts and connection capacity
* SQL injection, XSS and CSRF protections ✔
* Template-based dynamic HTML page generation ✔
* Static file-based serving ✔
* Account registration, token-based validation and password reset
* Secure user authentication with cookie-based session
* User- and group-based authorization
* Straightforward pattern-based request multiplexer ✔
* Pluggable, extendable architecture ✔
* Transactional database migrations runner ✔

## Development

Clone the project and install the required dependencies:

* libpq-devel (Fedora package)
* openssl-devel (Fedora package)
* postgresql-12.x (Fedora package, for the psql command)
* direnv (Fedora package, to manage environment variables)
* mkcert (create certificates for localhost, https://github.com/FiloSottile/mkcert)
* llrocks (locally-installed Lua modules, https://git.sr.ht/~mna/llrocks)
* Docker and Docker Compose

Then you should be able to prepare the environment and install the Lua dependencies
by running the init script:

```
$ ./scripts/init.lua
```

To run tests and benchmarks:

```
$ llrocks run test/main.lua
$ llrocks run bench/*.lua
```

To view code coverage:

```
$ llrocks cover test/main.lua
```

Note that because some tests (e.g. the csrf middleware) run the server in a separate
process and only the client requests are made from the actual LuaUnit-executed process,
test coverage reports lower numbers than what is actually covered.

## License

The [BSD 3-clause][bsd] license.

[bsd]: http://opensource.org/licenses/BSD-3-Clause
[http]: https://github.com/daurnimator/lua-http
[pg]: https://www.postgresql.org/
