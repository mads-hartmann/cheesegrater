# affineur

> An affineur is a highly skilled specialist who ages and matures cheese from its young, raw state to its peak flavor, texture, and aroma.

An HTTP server built with OCaml using the Jane Street stack (Async, Core,
cohttp-async). It serves a server-rendered HTML dashboard for the cheesegrater
host: systemd service status, system resources, and the most recent commits.
Rendering happens entirely on the server; the only client-side JavaScript is a
small custom element that subscribes to a Server-Sent Events stream to update
the system-resources section live.

## Endpoints

- `GET /` — the dashboard: systemd service status, system resources (uptime, CPU, disks), and recent commits
- `GET /app.js` — the `<live-system>` custom element that subscribes to the SSE stream
- `GET /events/system` — Server-Sent Events stream that pushes the re-rendered system-resources section once per second
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

The system-resources section updates live without a page reload. The page wraps
it in a `<live-system>` custom element (served at `/app.js`) that opens an
`EventSource` to `/events/system`. The server renders that section every second
and pushes it down the stream; the element swaps each fragment into place, so
the embedded UTC clock visibly advances each second. Rendering stays on the
server — the client only swaps in HTML it receives. The section's initial
markup is server-rendered, so it is populated before any JS runs and degrades
gracefully if JavaScript is disabled.

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
