# Local DNS

For the proxy to serve `https://acme.test`, the name has to point at this Mac. Warren does that with a managed copy of [CoreDNS](https://coredns.io) listening on loopback, plus small macOS resolver files that send only your domains to it.

```sh
just warren dns install      # download CoreDNS 1.14.7, verify its SHA-256
just warren dns status       # zones, resolver files, and whether macOS resolves each domain
just warren dns start        # run in the background, now and at every login
just warren dns stop         # stop it and remove it from login
just warren dns logs         # the DNS server's log (-f follows it)
just warren dns run          # run in the foreground for debugging; Ctrl-C stops it
just warren dns sync         # apply added or removed sites (a running server reloads by itself)
just warren dns enable       # write the resolver files (shows them, asks, needs your password)
just warren dns disable      # remove the resolver files Warren wrote
```

Use `--port N` to change the DNS port (default 5354). `start` remembers it. Adding or removing a site updates a running DNS server by itself. `start` installs a launch agent (`dev.warren.dns`) the same way the proxy does.

## Which domains need what

| Domain | What happens |
|---|---|
| `*.localhost` | Nothing. macOS already resolves it to this Mac. |
| `*.test`, `*.internal` | One zone for the whole TLD and one resolver file, once. Every site under it works afterwards with no further password. |
| Any other domain, such as `acme.dev` | A zone for exactly that domain and its subdomains, and one resolver file for it. Other names under the same TLD are untouched. |
| `*.local` | Rejected. macOS reserves it for Bonjour. Use `.test`. |

## What it touches

- Files under `~/Warren` (`bin`, `data`, `run`). The DNS server runs as you, on `127.0.0.1` and `::1` only, never on your network.
- **`/etc/resolver` only when you run `warren dns enable`.** Each file looks like this and is marked as Warren's:

  ```
  # Managed by Warren
  nameserver 127.0.0.1
  port 5354
  ```

  Warren never changes a file in that directory it did not write. If one already exists for a zone, `enable` stops and says which. `warren dns disable` removes only Warren's files.
- Names outside your zones get no answer from Warren (REFUSED), so it can never answer for a real domain you did not ask about.

## Trying it end to end

```sh
just warren site add ~/Sites/acme          # with domains = ["acme.test"] and [run] port in .warren.toml
just warren dns install
just warren dns start
# in a second terminal:
just warren dns enable                     # asks for your admin password
just warren dns status                     # acme.test -> resolves to this Mac
```

Then run the proxy (`docs/proxy.md`) and open `https://acme.test`.

`WARREN_RESOLVER_DIR` points the resolver-file commands at another directory, which then needs no password. It is for testing.
