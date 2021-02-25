# App methods

The App instance has a number of predefined methods on it. This document explains why some methods are predefined on the App (like `App:log` and `App:decode`) while others are extensions added by packages.

Although this discusses the App instance, a similar rationale applies to other extensions (e.g. `Request`).

The App instance has relatively few methods besides the lifecycle-related ones (`App:run`, `App:activate`) and the register/lookup/resolve mechanism. This is a design goal, to keep the App's core minimal and provide features via packages extensions. But the App also has `App:log`, `App:encode` and `App:decode`, which are *also* features implemented by packages.

The reason for this is in part pragmatism, because those methods are core to the behaviour of an application, but there's more than this - it makes sense for an App to have more than one encoder, decoder. Maybe less so for loggers, but the thing is with `App:log`, every package potentially needs to rely on this method to add its own logging, so instead of having each one have to require a logging package as dependency, it makes sense to have it predefined.

Having encode/decode predefined, but only as a "dispatcher" to specific encoders/decoders that can handle the mime type, also means that the Request/Response instances can rely on it without adding dependencies and without caring about if a specific encoder/decoder is registered, it just handles the error like any other error handling.

On the other hand, many other cases of method extensions would not make as much sense to live as predefined App methods: account, cron, database, metrics, etc. all add App extensions, but those are specific to those packages and would not benefit from being predeclared (i.e. it's highly unlikely that more than one would be required in the "small architecture" mindset of tulip, and nothing else or few other parts need to rely on those and when they do, the package dependencies mechanism is fine).
