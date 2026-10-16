# Running sites

Start, Stop and Restart are on the site's page and in the popover. The same from a terminal:

```sh
warren site start <site> [--yes]   # asks before running the project's start command
warren site stop <site>
warren site restart <site>
warren site status [<site>] [--json]
warren site logs <site> [-n 40] [--follow]
```

## What happens on Start

| Site | What Warren does |
|---|---|
| Node, Bun, Python server | Runs the start command (from `.warren.toml` `[run] command`, else the detected one) as a background job with the site's runtimes first on `PATH`, and the port passed the way the framework wants it. Ready when the port answers. |
| PHP (Laravel, Symfony, WordPress, plain) | Starts one PHP-FPM for the site on a socket in `~/Warren/run`, using the site's PHP. The proxy sends `.php` requests to it. It holds no worker processes while idle. |
| Static files | Switches the site's route on. There is nothing to run. |

The first Start of a command shows it and asks. Tick **Trust this project** to stop being asked for that exact command.

## Ports

`run.port` in `.warren.toml` is used as written, and Start fails if another program holds it, naming the program. Without it, Warren picks a free port between 4100 and 4999 and keeps it for the site (`~/Warren/state/ports.json`).

## Where things are

- Jobs are launchd jobs named `dev.warren.site.<id>` (`dev.warren.php.<id>` for FPM), loaded from `~/Warren/run/`. They are not installed in `~/Library/LaunchAgents`, so nothing starts at login.
- Sites keep running when Warren quits.
- The log is `~/Warren/logs/site-<id>.log`, emptied at each start.
- A server that exits on its own is not restarted. The site shows **Stopped unexpectedly** with the end of the log; fix the cause and Start again.
- A site that is not running answers `https://<name>.test` with a plain "not running" page instead of a certificate error.

## For services

`ServiceDriver` is the interface databases and other services will use (specs 016 to 018). `NativeDriver` runs a program as the same kind of job; a container driver (019) implements the same interface.
