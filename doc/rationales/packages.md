# Packages

The framework is built as a combination of packages being imported by means of the App's configuration. Each top-level key in the configuration table must resolve to a package (a Lua module) to `require`, and a package must adhere to a certain structure.

## Lifecycle

This is how an App resolves packages:

1. In undefined order (`pairs` call on the configuration table), the top-level keys are `require`d as Lua modules. Packages that don't contain any dot are first tried as `tulip.pkg.<name>`, and if that fails, they are required as defined.
2. All `require`d packages (full) names are stored in a lookup table of defined, or "imported", packages. If a package's exported table defines a `replaces` field, it is also stored in that table as "defined", so that a package like e.g. `my.app.messagequeue` can be used as a drop-in replacement for `tulip.pkg.mqueue`, and any package that depends on `mqueue` will accept it as a fulfilled dependency.
  * Also, if the package has an `app` field, then the fields under that table are added on the app's instance.
3. Once all packages have been `require`d and the lookup table has been filled, each package's dependencies are checked. If a package has a `requires` field, it must be an array of strings that define package names that need to be defined. If any dependency is missing for a package, an error is thrown.
4. Then, each package's `register` function is called with its package-specific configuration and the `App` instance. That function should throw any error it encounters.
5. Finally, when `App:run` is called, each defined package's `activate` function is called - if it exists - to make last-minute preparation before the app is started. Again, any error it encounters should be thrown. It receives the `App` instance and the `cqueue` instance that the app will use as arguments.

With this two-step approach (between `register` and `activate`), packages can register string names as middleware in the `register` step, and resolve them to actual functions in the `activate` step, regardless of the order the packages are defined/processed.

## Configuration

Packages should *never* depend on other package's configuration, so that drop-in replacements can work even though their configuration is under a different name (and may be completely different in structure).

To enforce this, both the package's `register` and `activate` functions should have a similar signature expecting `(cfg, app)` (with the `cqueues` instance added as third argument for `activate`), and `cfg` in that case should be the configuration of that particular package.

A special case must be made to be able to register DB migrations from other packages - in that case, it should work in a similar way to `register_middleware`, i.e. the `App` instance should provide a means to do this without referring to another package's configuration.
