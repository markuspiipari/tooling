# Tooling

This repository encloses a Swift Package Manager package of foundational Swift types for application and command line tool
development, created by the authors in the course of building such apps and tools.

As of right now:

- Everything here is experimental in status. A stable API is _not_ maintained in the `main` branch, that would be guaranteed to
  not change and break a build with warnings or errors.
  
- The main branch may only build with a specific, recent Xcode and Swift version, and only for macOS.

- The codebase is in a transition into structured concurrency (async/await). Some types are safe to use with it, others probably
  not be.

See LICENSE.md for the details of the MIT license. 
