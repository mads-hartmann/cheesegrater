open Core
open Async
open Cohttp_async
open Mdq_lib

let version = Version.version

let json_response ~status body =
  let headers = Cohttp.Header.of_list [ "content-type", "application/json" ] in
  Server.respond_string ~status ~headers body
;;

let html_response ~status body =
  let headers = Cohttp.Header.of_list [ "content-type", "text/html; charset=utf-8" ] in
  Server.respond_string ~status ~headers body
;;

(* Escape text for safe interpolation into HTML element content and double
   quoted attribute values. The page body produced by cmarkit is already
   sanitized HTML and is emitted verbatim; everything we template ourselves
   (titles, entry names, hrefs) goes through this. *)
let escape s =
  String.concat_map s ~f:(function
    | '&' -> "&amp;"
    | '<' -> "&lt;"
    | '>' -> "&gt;"
    | '"' -> "&quot;"
    | '\'' -> "&#39;"
    | c -> String.of_char c)
;;

(* The browse URL for a frontmatter [key]/[value] pair, e.g. clicking the
   [intro] tag goes to [/-/browse?key=tags&value=intro]. The [/-/] prefix is
   reserved so it never collides with a served folder, and both parts are
   percent-encoded for safe use in the query string. *)
let browse_href ~key ~value =
  sprintf "/-/browse?key=%s&value=%s" (Uri.pct_encode key) (Uri.pct_encode value)
;;

(* Render a list of frontmatter values as links to their browse pages, e.g. the
   [tags] field becomes a row of clickable tags. [css_class] selects the pill
   styling (["tag"] for tags, ["tag type"] to set the [type] apart). *)
let render_meta_links ~key ~css_class items =
  List.map items ~f:(fun value ->
    sprintf
      {|<a class="%s" href="%s">%s</a>|}
      css_class
      (escape (browse_href ~key ~value))
      (escape value))
  |> String.concat ~sep:" "
;;

let style =
  {|
    :root { --fg: #27272a; --muted: #71717a; --accent: #2563eb; --border: #e4e4e7; --bg: #fafafa; --side: #f4f4f5; }
    * { box-sizing: border-box; }
    body { margin: 0; background: var(--bg); color: var(--fg); font-family: system-ui, sans-serif; line-height: 1.6; }
    .layout { display: flex; min-height: 100vh; }
    .sidebar { width: 16rem; flex: 0 0 auto; background: var(--side); border-right: 1px solid var(--border); padding: 1.5rem 1.25rem; }
    .brand { font-family: monospace; font-weight: 600; font-size: 1.1rem; display: block; margin-bottom: 1rem; color: var(--fg); text-decoration: none; }
    .nav a { display: block; padding: 4px 0; color: #3f3f46; text-decoration: none; }
    .nav a:hover { color: var(--accent); }
    .main { flex: 1 1 auto; padding: 2rem 2.5rem; max-width: 52rem; }
    .muted { color: var(--muted); }
    .listing { list-style: none; padding: 0; }
    .listing li { padding: 4px 0; }
    .listing a { color: var(--accent); text-decoration: none; }
    .listing a:hover { text-decoration: underline; }
    .icon { color: #a1a1aa; padding-right: 0.5rem; }
    table { border-collapse: collapse; width: 100%; }
    th, td { text-align: left; padding: 6px 10px; border-bottom: 1px solid var(--border); }
    pre { background: #f4f4f5; padding: 1rem; border-radius: 6px; overflow-x: auto; }
    code { font-family: monospace; }
    pre code { background: none; }
    a { color: var(--accent); }
    .frontmatter { margin: 0 0 1.5rem; padding: 0.75rem 1rem; background: var(--side); border: 1px solid var(--border); border-radius: 6px; font-size: 0.9rem; }
    .frontmatter .fm-row { display: flex; gap: 0.5rem; padding: 2px 0; }
    .frontmatter dt { flex: 0 0 8rem; margin: 0; font-weight: 600; color: var(--muted); }
    .frontmatter dd { margin: 0; }
    .listing li { padding: 6px 0; }
    .entry-meta { display: inline-flex; flex-wrap: wrap; gap: 0.35rem; margin-left: 0.5rem; vertical-align: middle; }
    .tag { display: inline-block; padding: 1px 8px; border-radius: 999px; background: var(--side); border: 1px solid var(--border); color: var(--muted); font-size: 0.78rem; text-decoration: none; line-height: 1.5; }
    .tag:hover { color: var(--accent); border-color: var(--accent); text-decoration: none; }
    .tag.type { background: #eef2ff; border-color: #c7d2fe; color: #4338ca; }
  |}
;;

(* Sidebar navigation listing the configured folders. *)
let render_sidebar (roots : Docs.root list) =
  let links =
    List.map roots ~f:(fun { Docs.name; url_base; fs_path = _ } ->
      sprintf {|<a href="%s">%s</a>|} (escape url_base) (escape name))
    |> String.concat ~sep:"\n"
  in
  sprintf
    {|<nav class="sidebar">
      <a class="brand" href="/">mdq</a>
      <div class="nav">%s</div>
    </nav>|}
    links
;;

let page_shell ~title ~roots ~main =
  sprintf
    {|<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>%s</title>
  <style>%s</style>
</head>
<body>
  <div class="layout">
    %s
    <main class="main">%s</main>
  </div>
</body>
</html>|}
    (escape title)
    style
    (render_sidebar roots)
    main
;;

(* Render frontmatter as a definition list shown above the document body.
   Empty frontmatter (the common case) renders nothing, so pages without a
   metadata block look exactly as before. *)
let render_frontmatter (fields : Frontmatter.t) =
  match fields with
  | [] -> ""
  | _ ->
    let rows =
      List.map fields ~f:(fun { Frontmatter.key; value; items } ->
        (* [type] and [tags] become links to their browse pages so a reader can
           jump from a document to everything sharing that metadata. Every
           other field renders as its plain display string. *)
        let rendered =
          match key with
          | "type" -> render_meta_links ~key ~css_class:"tag type" items
          | "tags" -> render_meta_links ~key ~css_class:"tag" items
          | _ -> escape value
        in
        sprintf
          {|<div class="fm-row"><dt>%s</dt><dd>%s</dd></div>|}
          (escape key)
          rendered)
      |> String.concat ~sep:"\n"
    in
    sprintf {|<dl class="frontmatter">%s</dl>|} rows
;;

let render_listing ~title entries =
  let items =
    List.map entries ~f:(fun { Docs.name; path; kind; type_; tags } ->
      let icon =
        match kind with
        | Docs.Dir -> "\xF0\x9F\x93\x81"
        | Docs.Page -> "\xF0\x9F\x93\x84"
      in
      (* Show the page's type and tags next to its title, each linking to its
         browse page. Directories carry no metadata, so this is empty for them. *)
      let type_links = render_meta_links ~key:"type" ~css_class:"tag type" type_ in
      let tag_links = render_meta_links ~key:"tags" ~css_class:"tag" tags in
      let meta =
        match type_links, tag_links with
        | "", "" -> ""
        | _ ->
          sprintf
            {|<span class="entry-meta">%s</span>|}
            (String.concat
               ~sep:" "
               (List.filter [ type_links; tag_links ] ~f:(Fn.non String.is_empty)))
      in
      sprintf
        {|<li><span class="icon">%s</span><a href="%s">%s</a>%s</li>|}
        icon
        (escape path)
        (escape name)
        meta)
    |> String.concat ~sep:"\n"
  in
  let body =
    match entries with
    | [] -> {|<p class="muted">Empty.</p>|}
    | _ -> sprintf {|<ul class="listing">%s</ul>|} items
  in
  sprintf {|<h1>%s</h1>%s|} (escape title) body
;;

let handle_content (docs : Docs.t) path =
  let roots = docs.roots () in
  let%bind content = docs.resolve path in
  match content with
  | Docs.Page { title; frontmatter; html } ->
    (* cmarkit already renders the document's own [<h1>], so emit the body
       verbatim rather than prepending another heading. Any frontmatter is
       shown as a small metadata block above it. *)
    let main = render_frontmatter frontmatter ^ html in
    html_response ~status:`OK (page_shell ~title ~roots ~main)
  | Docs.Listing { title; entries } ->
    html_response ~status:`OK (page_shell ~title ~roots ~main:(render_listing ~title entries))
  | Docs.Not_found ->
    let main = {|<h1>Not found</h1><p class="muted">No such page.</p>|} in
    html_response ~status:`Not_found (page_shell ~title:"Not found" ~roots ~main)
;;

(* Browse pages: list every document whose [tags] or [type] frontmatter
   matches the requested value. The [key]/[value] come from the query string
   (e.g. [/-/browse?key=tags&value=intro]). An unknown [key] or a missing
   value yields an empty listing rather than an error. *)
let handle_browse (docs : Docs.t) uri =
  let roots = docs.roots () in
  let param name = Uri.get_query_param uri name in
  match param "key", param "value" with
  | Some key, Some value when not (String.is_empty value) ->
    let%bind content = docs.query ~key ~value in
    (match content with
     | Docs.Listing { title; entries } ->
       let main =
         match entries with
         | [] ->
           sprintf
             {|<h1>%s</h1><p class="muted">No pages match.</p>|}
             (escape title)
         | _ -> render_listing ~title entries
       in
       html_response ~status:`OK (page_shell ~title ~roots ~main)
     | _ ->
       let main = {|<h1>Not found</h1><p class="muted">No such page.</p>|} in
       html_response ~status:`Not_found (page_shell ~title:"Not found" ~roots ~main))
  | _ ->
    let main =
      {|<h1>Browse</h1><p class="muted">Provide a <code>key</code> (tags or type) and a <code>value</code>.</p>|}
    in
    html_response ~status:`Bad_request (page_shell ~title:"Browse" ~roots ~main)
;;

let handler docs ~body:_ _sock req =
  let uri = Request.uri req in
  let path = Uri.path uri in
  match Request.meth req, path with
  | `GET, "/health" -> json_response ~status:`OK {|{"status":"ok"}|}
  | `GET, "/version" ->
    json_response ~status:`OK (Printf.sprintf {|{"version":"%s"}|} version)
  | `GET, "/-/browse" -> handle_browse docs uri
  | `GET, _ -> handle_content docs path
  | _ -> json_response ~status:`Not_found {|{"error":"not found"}|}
;;

let () =
  let port =
    Sys.getenv "PORT" |> Option.map ~f:Int.of_string |> Option.value ~default:8080
  in
  (* Folders to serve are passed as positional arguments. Fall back to the
     DOCS_PATHS env var (colon-separated) so the systemd unit and the dev
     automation can configure them without an argv wrapper. *)
  let paths =
    match List.tl (Array.to_list (Sys.get_argv ())) with
    | Some (_ :: _ as args) -> args
    | _ ->
      (match Sys.getenv "DOCS_PATHS" with
       | Some s -> String.split s ~on:':' |> List.filter ~f:(Fn.non String.is_empty)
       | None -> [])
  in
  let paths = List.filter paths ~f:(Fn.non String.is_empty) in
  if List.is_empty paths
  then (
    eprintf "mdq: no folders given. Pass folder paths as arguments or via DOCS_PATHS.\n%!";
    Core_unix.exit_immediately 1);
  let docs = Docs_fs.create ~paths in
  List.iter (docs.roots ()) ~f:(fun { Docs.name; url_base; fs_path } ->
    printf "serving %s at %s (%s)\n%!" name url_base fs_path);
  (* Log per-connection errors instead of raising. A browser aborting a
     request mid-response closes the socket and surfaces as a writer
     exception; with [`Raise] that single broken connection would take down
     the whole server. *)
  let on_handler_error =
    `Call (fun _addr exn -> eprintf "[mdq] connection error: %s\n%!" (Exn.to_string exn))
  in
  let _server =
    Server.create ~on_handler_error (Tcp.Where_to_listen.of_port port) (handler docs)
  in
  printf "mdq listening on port %d\n%!" port;
  never_returns (Scheduler.go ())
;;
