# Importing a repository

**Add site → From GitHub** clones a repository into a new folder, registers it as a site, and runs its setup plan.

## The address

Paste `acme/shop`, `github.com/acme/shop`, `https://github.com/acme/shop` (a `/tree/<branch>` address picks that branch), `git@github.com:acme/shop.git`, or another host's `https://` or `ssh://` Git address. Warren looks the repository up (no download) and fills the branch menu. Addresses that could run a command or read your disk (`ext::`, `file:`, local paths, anything starting with `-`, `git://`, plain `http://`) are refused.

**Pick from my repos** lists your repositories when the [GitHub CLI](https://cli.github.com) (`gh`) is installed and signed in. Warren does not sign in to GitHub and stores no token: private repositories use the sign-in your Git already has (the macOS Keychain, the GitHub CLI, or an SSH key in your agent). If that fails, the window says how to fix it.

Every Git call uses `GIT_ALLOW_PROTOCOL=https:ssh`, `GIT_TERMINAL_PROMPT=0` and `ssh -o BatchMode=yes`, so a failed sign-in is an error instead of a hidden prompt. Git comes from the Command Line Tools; if they are missing the window says to run `xcode-select --install`.

## What happens

1. The folder is created (default `~/Sites/<repo>`) and the site is registered.
2. The clone runs as the first step, with Git's progress. Nothing from the repository runs.
3. The project's setup plan is built and run, with the usual approval of each command that runs code from it.

## Values needed

After `.env` is created from `.env.example`, a sheet asks for the variables the example leaves empty or fills with a placeholder (`YOUR_KEY`, `<token>`, `changeme`). Names that look secret (`KEY`, `SECRET`, `TOKEN`, `PASSWORD`, `DSN`) get a hidden field. Warren offers **Use https://site.test** for URL variables like `APP_URL`, and **Generate** for auth and session secrets (`AUTH_SECRET`, `NEXTAUTH_SECRET`, `SESSION_SECRET`, `JWT_SECRET`, …). Third-party keys are never generated.

Values go into the project's `.env` and nowhere else: not Warren's logs, not its settings, not a process environment. **Skip** keeps the placeholders and is remembered, so the plan does not ask again until the example gains a new variable. A note appears if `.env` is not in the project's `.gitignore`.

## Command line

```sh
warren repo list [--json]
warren site clone <repo> [name] [--branch <b>] [--location <folder>] [--domain <name>] [--yes]
```

Values are asked one by one in the terminal (secret ones without echo on a terminal; Enter skips). `--yes` approves the commands after printing them and skips every value.
