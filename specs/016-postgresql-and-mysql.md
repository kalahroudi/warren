# 016 · PostgreSQL and MySQL

Status: Draft · Phase 4 · Depends on: 004, 011, 012, 014, 015 · Amends: 011 (the service step of a plan becomes real)

## Goal

A project that needs PostgreSQL or MySQL gets one with a click. Warren downloads the server, creates a database for the site, starts it, and the site's migration step runs against it. From the Services page a user can also install, start, stop and remove a database server without any project, and copy its connection details. Nothing runs until asked, and nothing starts at login.

## Non-goals

- Redis, Mailpit, MinIO (017) and the catalog as data (018). This spec adds two services using the `ServiceDriver` from 015, written so 018 can move their facts into data without changing the driver.
- Containers (019).
- MariaDB. It has no official macOS binaries (see Prior art). It can be added through the catalog later.
- A database browser (037 onward).
- Backups and snapshots (041). Data lives in one folder per server, which is what 041 will copy.
- Extensions beyond what the upstream build contains (PostGIS, pgvector).
- Upgrading a server's data in place across major versions. Majors install side by side instead.

## App surface

- **Services page** (today a preview): PostgreSQL and MySQL rows, each with the installed versions, a state (*Stopped*, *Starting*, *Running*, *Stopped unexpectedly*), **Start**, **Stop**, **Logs**, **Copy connection string**, and **Install another version** from a short list. **Remove** deletes the program; the data is kept unless the user also ticks "Delete its data", which names the folder and size and asks once more.
- **Site page:** the Setup card's "Start PostgreSQL" step (011 left it waiting for this spec) now does the work: installs the server if missing, starts it, creates the site's database, and offers to fill the `DB_*` or `DATABASE_URL` variables in `.env` through 014's editor. The migration step then runs as before.
- **Popover:** a Start/Stop control on each installed server, next to the site rows. Nothing else; install and setup notices stay in the wizard.
- **Approval:** installing a server downloads a program. The step shows the download size and source, and runs when the user presses the plan's Run, as for runtimes (007). Creating a database and writing `.env` need no extra approval; the user chose the plan.
- **CLI** (additional): `warren service list|install|start|stop|remove|logs|connection <id> [--json]`, `warren service db create|drop|list <id> <name>`.
- **MCP** (020 to 022): `list_services` and `get_service_connection` are read tools; `start_service`, `stop_service`, `install_service` and `create_database` are write tools and ask first. Nothing is built here.

## Prior art

To be completed by a survey before the build; what the first look found is below. The survey checks license, macOS arm64 and x86_64 support, whether the archive is relocatable, signed or notarized, size, maintenance, and publishes checksums.

| Option | First verdict |
|---|---|
| **zonkyio/embedded-postgres-binaries** (Apache-2.0, on Maven Central, darwin arm64 and amd64 for 14 and later, plain archives of upstream builds) | **Leading candidate for PostgreSQL.** Small, versions side by side, checksums available. Risks: one maintainer set, no extensions, only listed majors. |
| **Postgres.app "direct binary" zip** (PostgreSQL license, universal, includes common extensions) | Fallback for PostgreSQL if the first is not good enough, or if extensions matter. Larger. |
| **Homebrew bottles** | Rejected: bottles are tied to Homebrew's prefix and relocate poorly. |
| **EnterpriseDB installers** | Rejected: an installer with a GUI and a system-wide layout. |
| **MySQL Community Server tar archive from Oracle** (GPLv2, ARM64 and x86_64 archives) | **Leading candidate for MySQL.** Official. Verify the tar archive is still offered for the current macOS and that it runs from any folder. Large. |
| **MariaDB** | Not used: no official macOS binaries. |
| **Building our own** (as 008 does for PHP, with a pinned workflow and SHA-256) | Held in reserve. Only if no upstream archive passes the survey. |
| **`pg_ctl`, `initdb`, `mysqld --initialize-insecure`, `pg_isready`, `mysqladmin ping`** | **Used** for creating, starting, stopping and readiness. No custom database code. |
| **launchd through `NativeDriver`** (015) | **Used** for supervision, as for sites. |

## Behavior

**Installing.** Download the pinned archive into `~/.warren/cache`, verify its SHA-256, unpack to `~/.warren/data/services/<kind>/<version>/` (the program), and create the data folder on first start. The pinned versions and checksums live in the repo, like the runtime tools. Deleting the program folder is always safe: it is downloaded again on demand.

**Instances.** One instance per kind and major version, with the id `postgres-17` or `mysql-8.4`. Its data is `~/.warren/data/services/<kind>/<id>/data`. A site names the one it wants in `.warren.toml` (`[services] postgres = "17"`); without a version Warren picks the newest installed, else proposes the newest supported.

**Starting.** `NativeDriver` runs the job from 015:

- PostgreSQL: `initdb` on first start (UTF-8, `--auth=trust` for loopback and the Unix socket, user `postgres`), then `postgres -D <data> -c listen_addresses=127.0.0.1 -c port=N -c unix_socket_directories=<run>`. Ready when `pg_isready` succeeds.
- MySQL: `mysqld --initialize-insecure` on first start, then `mysqld --datadir <data> --bind-address=127.0.0.1 --port=N --socket=<run> --mysqlx=OFF`. Ready when `mysqladmin ping` succeeds. User `root` with no password, reachable only from this Mac.

**Ports.** The default (5432, 3306) when free; otherwise the next free port in 5433 to 5499 or 3307 to 3399, kept for the instance, as for sites (015). Two versions of a kind never fight for a port. Listening is loopback only.

**Stopping.** `bootout` as in 015 (SIGTERM first, which both servers treat as a clean shutdown, and the plist's exit timeout is raised to 30 seconds for databases so a flush is not cut off). A crash is reported, not restarted, as for sites.

**Databases for sites.** The plan's service step creates a database named after the site's id (`CREATE DATABASE` if missing, safe to run again) and records it. `DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD` and `DATABASE_URL` are offered to 014's env editor, filling only variables the example file lists. Warren never overwrites a value the user set.

**Removal.** Removing a site does not delete its database. The Services page offers "Drop database" and "Delete data" with the size, behind a confirmation.

**Weight.** Nothing runs at login or idle. A running PostgreSQL holds about 30 to 60 MB; MySQL about 300 to 450 MB (to be measured and written back here). Installed programs are about 40 to 60 MB (PostgreSQL) and a few hundred MB (MySQL); both are disposable and shown in storage (029).

## Acceptance criteria

1. The Services page lists PostgreSQL and MySQL with real state, in place of the preview.
2. Installing a version downloads the pinned archive, verifies its checksum, and a wrong checksum is refused with a plain message.
3. A first start creates the data folder and reaches *Running*; the second start reuses it.
4. Stop shuts the server down cleanly and leaves no listener; a killed server shows *Stopped unexpectedly*.
5. Two PostgreSQL versions (or PostgreSQL and MySQL) run side by side on different ports.
6. A busy default port moves the instance to the next free port and the connection details show the real one.
7. A site whose plan needs PostgreSQL gets the server installed, started and a database created from the Setup card, and a Laravel migration then succeeds against it.
8. `.env` variables are offered, never overwrite a set value, and the secrets rules of 014 apply.
9. Remove keeps the data by default; deleting data names the folder and size and asks to confirm.
10. Servers listen on loopback only (checked with `lsof`).
11. Nothing from this spec starts at login.
12. The CLI commands work and `--json` output is stable.
13. `./scripts/check.sh` passes; integration tests (opt-in, real downloads and servers) run both services on a real launchd job.

## Test plan

Unit tests for the pinned release table, checksum refusal, port choice, command lines and env offers, with a fake launchd and a stand-in server as in 015. Opt-in integration tests (`WARREN_INTEGRATION=1`) install and run the real servers and create a database. Manual: a real Laravel project with PostgreSQL and with MySQL, installing, migrating, stopping, and the Services page states, run on the real home as in earlier specs. Anything not run is left unticked.

## Rollout

Adds the service step's real behavior to 011's plan (the "arrives with the service manager" wait goes away for these two services only). New state under `data/services`. No migration for existing users: nothing is installed until asked. `docs/services.md` is added; `AGENTS.md` gets the CLI lines.

## Open questions

1. **Source of the PostgreSQL binaries:** the Zonky archives (leading), Postgres.app's zip, or our own pinned build like PHP (008). Decided by the survey; my recommendation is Zonky with Postgres.app as the fallback.
2. **Authentication:** passwordless on loopback (simplest, what dev tools expect) or a generated password per instance in the Keychain. My recommendation is passwordless on loopback, with the password option added once sharing a port off the Mac is possible.
3. **Which versions:** my recommendation is PostgreSQL 16, 17, 18 and MySQL 8.4 (LTS) at launch; older ones on request.
4. **MySQL size and memory:** if the tar archive is too heavy for the "light" goal, ship MySQL with a small config (reduced buffer pool and performance schema off) by default. Recommended.
5. **Database per site naming:** the site id (my recommendation), or a name chosen in the plan.
6. **Fill `.env` automatically** or only offer it. My recommendation is offer, with one button, as 014 does for other values.
