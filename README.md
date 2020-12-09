# luaweb

Lua web framework based on [lua-http][http] and [PostgreSQL][pg].

* Canonical repository: https://git.sr.ht/~mna/luaweb
* Issue tracker: https://todo.sr.ht/~mna/luaweb

## Description

Lua Web is a minimal and simple web framework that provides a lot with very little.
Using only Lua (currently 5.4) and the PostgreSQL database (currently 13), the
framework packs the following features:

* HTTP and HTTPS ✔
* HTTP/1.1 and HTTP/2 ✔
* Concurrent handling of requests ✔
* Message Queue-style (at-least-once) reliable asynchronous processing ✔
* Fire-and-forget (at-most-once) publish-subscribe mechanism ✔
* Statsd-compatible metrics collection ✔
* Cron-like scheduled processing ✔
* Hardened server with timeouts and connection capacity ✔
* SQL injection, XSS and CSRF protections ✔
* Template-based dynamic HTML page generation ✔
* Static file-based serving ✔
* Account registration, token-based validation and password reset ✔
* Secure user authentication with cookie-based session ✔
* User- and group-based authorization ✔
* Straightforward pattern-based routes handler multiplexer ✔
* Transactional database migrations runner ✔
* Efficient database access with connection pooling ✔
* Pluggable, extendable architecture ✔

## Development

Clone the project and install the required dependencies:

* libpq-devel (Fedora package)
* openssl and openssl-devel (Fedora package)
* libargon2-devel (Fedora package)
* postgresql-12.x (Fedora package, for the psql command)
* direnv (Fedora package, to manage environment variables)
* zlib-devel (Fedora package)
* mkcert (create certificates for localhost, https://github.com/FiloSottile/mkcert)
* llrocks (locally-installed Lua modules, https://git.sr.ht/~mna/llrocks)
* Docker and Docker Compose

Then you should be able to prepare the environment and install the Lua dependencies
by running the init script:

```
$ ./scripts/init.lua
```

To run tests and benchmarks (be sure to check the configuration section below):

```
$ llrocks run test/main.lua

# if there are benchmarks available:
$ llrocks run bench/*.lua
```

To view code coverage:

```
$ llrocks cover test/main.lua
```

Note that because some tests (e.g. the csrf middleware) run the server in a separate
process and only the client requests are made from the actual LuaUnit-executed process,
test coverage reports lower numbers than what is actually covered.

## Configuration

While the `scripts/init.lua` script sets up most of the required configuration, some
environment variables and secrets cannot be set automatically. Here's what the `.envrc`
file managed by `direnv` should contain:

* `PGPASSFILE`: init-generated
* `PGHOST`: init-generated
* `PGPORT`: init-generated
* `PGCONNECT_TIMEOUT`: init-generated
* `PGUSER`: init-generated
* `PGDATABASE`: init-generated
* `LUAWEB_CSRFKEY`: init-generated
* `LUAWEB_ACCOUNTKEY`: init-generated
* `LUAWEB_SENDGRIDKEY`: set to a valid Sendgrid API key
* `LUAWEB_TEST_FROMEMAIL`: set to a valid email address for tests
* `LUAWEB_TEST_TOEMAIL`: set to a valid email address for tests

## License

The [BSD 3-clause][bsd] license.

[bsd]: http://opensource.org/licenses/BSD-3-Clause
[http]: https://github.com/daurnimator/lua-http
[pg]: https://www.postgresql.org/
