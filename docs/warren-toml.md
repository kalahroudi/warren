# `.warren.toml`

An optional file at the root of a project that tells Warren how to run it. Without it, Warren uses defaults and, in later specs, what it detects from the project. Schema version 1.

```toml
name = "acme-store"
domains = ["acme.test", "shop.localhost"]

[runtime]
node = "22"

[run]
command = "pnpm dev"
port = 3000

[services]
postgres = "17"
```

| Key | Type | Default | Notes |
|---|---|---|---|
| `name` | string | folder name | Display name |
| `domains` | array of strings | `["<id>.test"]` | Lowercase, at least two labels, unique across sites |
| `[runtime]` `<name>` | string | none | Runtime and version, for example `node = "22"` |
| `[run]` `command` | string | none | Command that starts the dev server |
| `[run]` `port` | integer 1 to 65535 | none | Port the server listens on |
| `[services]` `<name>` | string | none | Service and version, for example `postgres = "17"` |

Unknown keys and tables are ignored with a warning, so newer files still load. Wrong types and syntax errors are reported with a line number, and the site still lists with default settings.

Supported TOML subset: comments, `[tables]`, strings, integers, booleans, and single-line arrays of strings.

## CLI

```sh
just warren site add ~/Sites/acme-store
just warren site list --json
just warren site show acme-store
just warren site remove acme-store   # never deletes project files
```

State lives in `~/Warren` (override with `WARREN_HOME`).
