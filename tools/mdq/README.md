# mdq

> Short for "markdown query" — a small browser for folders of markdown.

An HTTP server built with OCaml using the Jane Street stack (Async, Core,
cohttp-async). It serves one or more folders of markdown files as
server-rendered HTML: a sidebar lists the folders, directories render as
listings, and `.md` files render to HTML with
[cmarkit](https://erratique.ch/software/cmarkit). There is no client-side
JavaScript — each request returns a complete page.

## Usage

```bash
mdq <folder> [<folder> ...]
```

Folders may also be supplied via the `DOCS_PATHS` environment variable
(colon-separated), which is how the systemd unit configures them.

### Routing

- A **single** folder is mounted at the site root (`/`).
- **Several** folders are each mounted under their basename (`/docs`,
  `/notes`, …), and `/` lists the folders.
- A directory containing `index.md` renders that file, mirroring the
  `index.html` heuristic of a static server; otherwise it renders a listing of
  its subfolders and markdown files.
- The folder structure maps directly onto URL paths. Both the clean URL
  (`/installation`) and the explicit file (`/installation.md`) resolve to the
  same page, so relative links inside a rendered document work.

Path traversal (`..`) is rejected, and the markdown is rendered with cmarkit's
safe renderer (raw HTML blocks and unsafe link schemes are stripped).

### Frontmatter

A page may begin with a YAML frontmatter block fenced by `---` lines:

```markdown
---
title: Getting started
tags: [docs, intro]
---

# Body starts here
```

The block must start on the first line and is closed by the next `---` (or
`...`). Its fields are parsed and shown as a metadata table above the rendered
body. A `title` field, if present, sets the page title (otherwise the title is
the first `# H1`, then the file name). A malformed or unterminated block is
left as ordinary markdown rather than failing the page.

### Browsing by type and tags

The `type` and `tags` frontmatter fields are treated specially so a folder of
markdown can be navigated as a small knowledge base:

- In a **directory listing**, each page shows its `type` and `tags` next to the
  title as pills.
- In a **rendered page**, the `type` and `tags` rows in the metadata table are
  links.
- Clicking any of these opens a **browse page** (`/-/browse?key=<field>&value=<value>`)
  listing every page across all served folders whose `type` or `tags` contains
  that value. Matching is case-insensitive, and list values (`tags: [a, b]`)
  are matched per element.

## Endpoints

- `GET /` and any other path — the rendered page or directory listing for that
  URL (a `404` page if nothing resolves)
- `GET /-/browse?key=<tags|type>&value=<value>` — a listing of every page whose
  `tags` or `type` frontmatter contains `value`
- `GET /health` — returns `200 OK` with `{"status":"ok"}`
- `GET /version` — returns `200 OK` with `{"version":"<version>"}`

## Architecture

- `bin/` — Native OCaml server (Async + cohttp-async). Resolves the request
  path, renders the page or listing, and returns a complete HTML document
  (layout, sidebar, and inline CSS).
- `lib/` — `docs.ml` defines the content types; `docs_fs.ml` resolves URL
  paths against the configured folders (index heuristic, listings, traversal
  guard) and walks the tree to answer `type`/`tags` queries; `markdown.ml`
  wraps cmarkit; `frontmatter.ml` splits and parses the optional YAML
  frontmatter block, keeping list values as individual items so they can be
  queried and linked.

If client-side behavior is ever needed, add a separate static script and
reference it from the page shell in `bin/main.ml`.

## Environment variables

| Variable | Default | Description |
|-----------|---------|-------------|
| `PORT` | `8080` | Port to listen on |
| `DOCS_PATHS` | — | Colon-separated folders to serve (alternative to argv) |

## Development

Requires [devenv](https://devenv.sh/).

```bash
devenv shell                   # enter the dev environment
dune build bin/main.exe        # compile the server
dune exec bin/main.exe -- ../../docs
```
