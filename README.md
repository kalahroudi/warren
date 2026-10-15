# Warren

A light, native macOS menu bar app that runs your local web projects. Add a site from GitHub, a starter template or a blank project, and Warren installs the runtimes and services it needs, gives it a local domain, and can share it with a public link. Agents can drive it through MCP.

**Status:** early development. Nothing is released yet. The plan lives in [`specs/ROADMAP.md`](specs/ROADMAP.md).

## Principles

- **Light:** native Swift, small idle footprint.
- **Native first:** runtimes and services run as native binaries. Containers are an optional driver.
- **Disposable dependencies:** anything regenerable can be reclaimed and restored from your lockfile.
- **Open source:** the app, the service catalog and the Relay server are all open. A hosted Relay exists for people who do not want to run their own.

## Build

Requires macOS 14+ and the Xcode command line tools.

```sh
brew install just
just setup   # checks toolchain, installs SwiftLint and SwiftFormat
just check   # format, lint, license headers, build, tests
just dev     # builds and launches a development Warren.app
```

## Contribute

Warren is built spec-first: one spec is one pull request. Read [`CONTRIBUTING.md`](CONTRIBUTING.md) and [`specs/000-process.md`](specs/000-process.md).

## License

The app, core and catalog are [Apache-2.0](LICENSE).
