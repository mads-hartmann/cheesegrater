# affineur

> An affineur is a highly skilled specialist who ages and matures cheese from its young, raw state to its peak flavor, texture, and aroma.

An HTTP server built with OCaml using the Jane Street stack (Async, Core, cohttp-async).

## Endpoints

- `GET /health` — returns `200 OK` with `{"status":"ok"}`
- `GET /version` — returns `200 OK` with `{"version":"<version>"}`

## Development

Requires [devenv](https://devenv.sh/).

```bash
devenv shell   # enter the dev environment
dune build     # compile
dune exec bin/main.exe  # run locally
```
