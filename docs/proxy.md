# Local HTTPS proxy

Warren serves your sites at `https://<domain>` through a managed copy of [Caddy](https://caddyserver.com), forwarding to the port in each site's `.warren.toml` (`[run] port`). Caddy's built-in local certificate authority issues the certificates.

```sh
just warren proxy install     # download Caddy 2.11.7, verify its SHA-512
just warren proxy status      # what is installed, running, and routed
just warren proxy start       # run in the background, now and at every login
just warren proxy stop        # stop it and remove it from login
just warren proxy logs        # the proxy's log (-f follows it)
just warren proxy run         # run in the foreground for debugging; Ctrl-C stops it
just warren proxy reload      # apply added or removed sites without a restart
just warren proxy trust       # trust Warren's root certificate (asks first, needs your password)
just warren proxy untrust     # undo that
```

Use `--http-port` and `--https-port` to run on other ports, for example `8080` and `8443` while testing. `start` remembers them, so `reload`, `status` and the app use the same ports. Adding or removing a site updates a running proxy by itself.

`start` installs a launch agent (`~/Library/LaunchAgents/dev.warren.proxy.plist`) so launchd keeps the proxy running, restarts it if it stops, and starts it at login. `stop` removes it.

## What it touches

- Files only under `~/Warren` (`bin`, `data`, `run`). The admin socket is `~/Warren/run/caddy.sock`, mode 0600; nothing listens on TCP 2019.
- **Your system trust store only when you run `warren proxy trust`.** Warren never lets Caddy install its root by itself. The root certificate can issue certificates for any name, and its key lives in `~/Warren/data/caddy` (mode 0700). `warren proxy untrust` removes the trust.
- Ports 80 and 443 on all addresses (macOS only allows unprivileged processes to bind low ports that way). Every route answers loopback clients only; other machines on your network get a 403.

## Names

Names such as `acme.test` need to resolve to your machine. That arrives with the local DNS spec (006). Until then, add the name to `/etc/hosts`, or test with `curl --resolve acme.test:443:127.0.0.1 --cacert ~/Warren/data/caddy/pki/authorities/local/root.crt https://acme.test/`.
