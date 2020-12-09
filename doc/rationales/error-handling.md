# Error Handling

There are two ways to indicate errors in Lua:

* raise/throw with `error(v)` (and maybe catch it with `pcall(...)`)
* return a falsy first value and an error message, possibly followed by an error code

The first option requires the use of `[x]pcall(...)` to handle, while the second option is trivial to turn into a raised error if needed, simply by calling `assert(...)`.

For a general purpose library, it is best to use return values and avoid raising errors, so that the caller can handle any errors as it sees fit. This is how most popular Lua libraries are built, and how the Lua standard library works in most cases.

However, for this project, I believe both approaches have their uses.

## Programming Errors

When an argument is provided that breaks the contract of the API (e.g. wrong type, invalid mode, etc.) in such a way that this call would *never* be valid (unlike, say, something that fails because a file does not exist, but would otherwise be valid if the file did exist), then that should fail *immediately* and *noisily*. In that case, throwing an error is the right approach.

This is also how the Lua standard library behaves when giving e.g. an invalid mode to `io.open` or passing an invalid type to `table.concat`.

## Configuration Errors

When a `tulip.App` is created with its configuration, if any configuration error occurs, it should fail *immediately* and *noisily*. This is due to invalid configuration - such as a missing package dependency. This is similar in spirit to "Programming Errors", but is mentioned explicitly due to it's slightly different context.

## Normal Errors

Any other situation should be considered a "normal" error, and as such the "falsy value" followed by the error (and maybe extra error information) should be used.

## Error Normalization

To allow better error-handling decisions to be made, the various types of errors and extra error values (such as error message + POSIX error number, or error message + postgresql-specific code and maybe SQL state code, etc.) should be converted to a self-contained Error instance. This is what the `tulip.xerror` package does - adding a category code to each error (e.g. 'EIO', 'EDB', 'ESQL') and storing extra information under well-defined field names.

This makes handling easier as after conversion, only `nil, err` need to be returned and handled, and the error has all the information required.

To that end, the `xerror` module also supports adding context to an error, so that context-specific "tags" can be applied to an error instance to make debugging or handling easier. That's what the `xerror.ctx(...)` function does, it sets a label that gets added to the error message when the error is printed, and optionally adds key-value data to the instance itself.

For example, an IO error on a file 'file.txt' could be handled like this:

```
function do_something()
  local f, err = xerror.io(io.open('file.txt'))
  if not f then
    return nil, xerror.ctx(err, 'do_something', {file = 'file.txt'})
  end
  -- ...
end
```

Printing the error adds the labels in reverse order (latest first), e.g. if another context was added in `call_something`:

```
call_something: do_something: file not found
```

The `xerror` module also provides helper functions to query the error type:

```
xerror.is(err, 'EDB')
xerror.is_sql_state(err, '42P01')
xerror.has_ctx(err, 'do_something')
```

## Error Handling in Middleware

Error handling in middleware is tricky. Some frameworks choose to have a distinct chain of middleware for the "happy path" and the "error path", but this makes it hard for an error in a reusable middleware to be handled differently in different scenarios (e.g. log and continue down the happy path vs fork to the error path).

Instead, and to give complete control to the framework user, explicit error handlers can be configured for each middleware (unless, of course, when it cannot error, such as the log or reqid middleware).

Note that those are functions that handle the error and return a value, not a middleware function. The return value indicates if the middleware where the error occurred should call the next in the chain or not. Error handlers have the signature `function(req, res, err)` and must return a truthful value to prevent calling next.

This should give sufficient control as the user can either write its own error response, handle the response and continue down the regular chain, or throw an error and (by doing so) trigger the recovery handler (if any is set up).

In most cases, this error handler should be optional and the default should be to throw. Note that with the recovery middleware, it is possible to build a "chain" of error middleware - simply raise again in a given recovery function, and that will trigger the next (parent) recovery middleware.

## Explicit Assertions

As mentioned earlier, there are valid places where we do want to throw errors. There are also places where it is idiomatic to do so, because we know we run in a `pcall`. That is the case of the `xpgsql` module, when calling `conn:with`, `conn:ensuretx` and `conn:tx` - and also in the `tulip.pkg.database` package, when a function is provided to `App:db`.

To prevent having `assert` calls everywhere in the code, making it hard to distinguish between valid and erroneous uses of those, the `xerror` module defines specific functions with a name that clearly indicates the intent, so that a code search for `assert` would rapidly identify improper uses.

* `xerror.throw(msg, ...)`: calls `error` with `string.format`.
* `xerror.must(cond[, err])`: same as `assert`.

