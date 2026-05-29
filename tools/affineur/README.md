# affineur

> An affineur is a highly skilled specialist who ages and matures cheese from its young, raw state to its peak flavor, texture, and aroma.

An HTTP server built with OCaml using the Jane Street stack (Async, Core, cohttp-async). Serves a [Bonsai](https://github.com/janestreet/bonsai/) SPA dashboard showing recent cheesegrater commits.

## Endpoints

- `GET /` — Bonsai SPA showing last pull time and recent commits
- `GET /api/commits` — JSON with last pull time and the 5 most recent commits
- `GET /health` — returns `200 OK` with `{"status":"ok"}`
- `GET /version` — returns `200 OK` with `{"version":"<version>"}`

## Architecture

- `bin/` — Native OCaml server (Async + cohttp-async). Serves the HTML shell, compiled JS, and the `/api/commits` endpoint which shells out to `git log`.
- `web/` — Bonsai SPA compiled to JavaScript via js_of_ocaml. Fetches `/api/commits` on load and renders the dashboard.

## Environment variables

| Variable | Default | Description |
|-----------|---------|-------------|
| `PORT` | `8080` | Port to listen on |
| `REPO_PATH` | `/etc/nixos` | Path to the cheesegrater git repo |
| `JS_PATH` | `./main.bc.js` | Path to the compiled Bonsai JS |

## Development

Requires [devenv](https://devenv.sh/).

```bash
devenv shell   # enter the dev environment
dune build     # compile server
dune build web/main.bc.js  # compile Bonsai frontend
dune exec bin/main.exe  # run locally
```
