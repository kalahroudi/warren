# Security policy

Warren runs commands, manages local services and can expose sites to the internet, so security reports matter.

## Reporting a vulnerability

Please do not open a public issue. Use GitHub's private vulnerability reporting on this repository (Security tab, "Report a vulnerability").

Include what you found, how to reproduce it, and the Warren version. We aim to acknowledge reports within 3 working days.

## Scope

In scope: the app, the helper daemon, the CLI, the MCP server, the service catalog, update delivery, and the Relay server.

Of particular interest: running untrusted repository code without consent, privilege escalation through the helper, unsigned or tampered updates, and exposure of local services beyond what the user shared.
