# affineur

> An affineur is a highly skilled specialist who ages and matures cheese from its young, raw state to its peak flavor, texture, and aroma.

An HTTP server built with OCaml using the Jane Street stack (Async, Core,
cohttp-async). It serves a server-rendered HTML dashboard for the cheesegrater
host: systemd service status, system resources, and the most recent commits.
There is no client-side JavaScript — each request returns a complete page.

## Endpoints

- `GET /` — the dashboard: systemd service status, system resources (uptime, CPU, disks), and recent commits
- `GET /health` — returns `200 OK` with `{"status":"ok"}`
- `GET /version` — returns `200 OK` with `{"version":"<version>"}`

## Architecture

- `bin/` — Native OCaml server (Async + cohttp-async). On each request to `/`
  it reads the data sources and renders a complete HTML document (layout,
  inline CSS, and the CRT terminal styling).
- `lib/` — Data sources behind the dashboard. `git_*` reads commit history;
  `systemd_*` reads unit status via `systemctl show`; `system_*` reads host
  resources (uptime, CPU, disks). Each has a `real` implementation and a `fake`
  one (selected with `AFFINEUR_DATA_SOURCE=fake`) for local development.

The systemd source runs `systemctl show <unit>` for each deployed unit and
parses the `Key=Value` output. It reports the basic information systemd
exposes: load/active/sub state, unit-file state, main PID, and the active-since
timestamp.

If client-side behavior is ever needed, add a separate static script and
reference it from the page shell in `bin/main.ml`.

## Environment variables

| Variable | Default | Description |
|-----------|---------|-------------|
| `PORT` | `8080` | Port to listen on |
| `REPO_PATH` | `/etc/nixos` | Path to the cheesegrater git repo |
| `AFFINEUR_DATA_SOURCE` | — | Set to `fake` to use built-in sample data |

## Development

Requires [devenv](https://devenv.sh/).

```bash
devenv shell                   # enter the dev environment
dune build bin/main.exe        # compile the server
AFFINEUR_DATA_SOURCE=fake dune exec bin/main.exe  # run locally with sample data
```
