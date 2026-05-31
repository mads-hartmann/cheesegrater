open Core
open Async
open Cohttp_async
open Affineur_lib

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
   quoted attribute values. Everything we template (commit messages, service
   names, system fields) is data we don't control, so it all goes through this. *)
let escape s =
  String.concat_map s ~f:(function
    | '&' -> "&amp;"
    | '<' -> "&lt;"
    | '>' -> "&gt;"
    | '"' -> "&quot;"
    | '\'' -> "&#39;"
    | c -> String.of_char c)
;;

(* Current wall-clock time in UTC, formatted like "2026-05-31 14:03:07 UTC".
   Rendered into the system section on every SSE tick, so a client watching the
   stream sees it advance once per second — a visible heartbeat. *)
let utc_now () =
  let now = Time_ns.now () in
  Time_ns.to_string_iso8601_basic now ~zone:Time_float.Zone.utc
  |> String.substr_replace_all ~pattern:"T" ~with_:" "
  |> fun s ->
  (* Drop the sub-second and offset suffix, keep "YYYY-MM-DD HH:MM:SS". *)
  (match String.lsplit2 s ~on:'.' with
   | Some (head, _) -> head
   | None -> s)
  ^ " UTC"
;;

(* Retro CRT terminal theme. Ported from the previous Bonsai SPA's HTML shell
   and inline styles so the server-rendered page keeps the same look: green
   phosphor text on a near-black background, scanline overlay, and a few accent
   colours for state and SHAs. *)
let style =
  {|
    :root {
      --background: oklch(0.08 0.01 240);
      --foreground: oklch(0.85 0.15 142);
      --secondary-foreground: oklch(0.7 0.12 142);
      --muted-foreground: oklch(0.55 0.08 142);
      --border: oklch(0.25 0.05 142);
      --terminal-green: oklch(0.75 0.2 142);
      --terminal-amber: oklch(0.7 0.18 80);
      --terminal-red: oklch(0.6 0.2 25);
      --terminal-cyan: oklch(0.7 0.12 200);
      --scanline: rgba(0, 0, 0, 0.1);
    }

    * { box-sizing: border-box; }

    html, body {
      margin: 0;
      background: var(--background);
      color: var(--foreground);
      font-family: "JetBrains Mono", "Geist Mono", ui-monospace, "SF Mono", Menlo, Consolas, monospace;
      font-size: 15px;
      line-height: 1.6;
      -webkit-font-smoothing: antialiased;
    }

    .crt-overlay {
      pointer-events: none;
      position: fixed;
      inset: 0;
      background: repeating-linear-gradient(
        0deg,
        transparent,
        transparent 2px,
        var(--scanline) 2px,
        var(--scanline) 4px
      );
      z-index: 100;
    }

    @keyframes flicker {
      0%, 100% { opacity: 1; }
      50% { opacity: 0.98; }
    }
    .crt-flicker { animation: flicker 0.15s infinite; }

    .page {
      max-width: 56rem;
      margin: 0 auto;
      padding: 3rem 2rem;
      color: var(--terminal-green);
    }

    h1.title {
      font-size: 2.25rem;
      font-weight: 700;
      margin: 0.5rem 0 0 0;
      color: var(--terminal-green);
      text-shadow: 0 0 5px var(--terminal-green), 0 0 10px var(--terminal-green);
    }

    .section-header {
      display: flex;
      align-items: center;
      gap: 0.75rem;
      margin: 2.5rem 0 1.5rem 0;
    }
    .section-header span {
      font-weight: 700;
      font-size: 1.25rem;
      letter-spacing: 0.12em;
      color: var(--terminal-green);
      text-shadow: 0 0 5px var(--secondary-foreground), 0 0 10px var(--secondary-foreground);
    }

    .service {
      display: flex;
      align-items: center;
      gap: 0.6rem;
      margin-bottom: 0.75rem;
    }
    .service .dot {
      width: 0.55rem;
      height: 0.55rem;
      border-radius: 50%;
      text-shadow: 0 0 5px currentColor, 0 0 10px currentColor;
    }
    .service .name { font-weight: 700; color: var(--foreground); }

    .state-active { color: var(--terminal-green); }
    .state-failed { color: var(--terminal-red); }
    .state-inactive { color: var(--muted-foreground); }
    .state-other { color: var(--terminal-amber); }

    .dot.state-active { background: var(--terminal-green); color: var(--terminal-green); }
    .dot.state-failed { background: var(--terminal-red); color: var(--terminal-red); }
    .dot.state-inactive { background: var(--muted-foreground); color: var(--muted-foreground); }
    .dot.state-other { background: var(--terminal-amber); color: var(--terminal-amber); }

    .prompt { margin-top: 1.25rem; }
    .prompt .sigil { color: var(--terminal-cyan); }
    .prompt .cmd { color: var(--muted-foreground); }

    .output { padding-left: 1.25rem; margin-top: 0.25rem; }
    .bright { color: var(--foreground); }
    .dim { color: var(--muted-foreground); }

    .bar { white-space: pre; letter-spacing: -1px; }
    .bar .track-edge { color: var(--muted-foreground); }
    .bar .filled { color: var(--terminal-green); text-shadow: 0 0 5px var(--secondary-foreground), 0 0 10px var(--secondary-foreground); }
    .bar .empty { color: var(--border); }

    table.df { border-collapse: collapse; width: 100%; }
    table.df td { padding: 0.35rem 0.75rem 0.35rem 0; white-space: nowrap; }
    table.df td.num { text-align: right; }
    table.df th {
      text-align: left;
      padding: 0 0.75rem 0.35rem 0;
      letter-spacing: 0.05em;
      color: var(--muted-foreground);
      font-weight: 400;
    }
    table.df th.num { text-align: right; }
    .df-wrap { padding-left: 1.25rem; margin-top: 0.5rem; }

    .commit {
      display: flex;
      align-items: baseline;
      gap: 1.5rem;
      padding: 0.6rem 0;
      border-bottom: 1px solid var(--border);
    }
    .commit .sha { font-weight: 700; min-width: 5rem; color: var(--terminal-amber); }
    .commit .msg { color: var(--foreground); }
    .commits-wrap { padding-left: 1.25rem; margin-top: 0.5rem; }

    .footer { text-align: center; margin: 4rem 0 2rem 0; color: var(--muted-foreground); }
    .footer .name { font-weight: 700; color: var(--terminal-green); }

    .error { padding: 0.5rem 0; color: var(--terminal-red); }
  |}
;;

(* The only client-side JavaScript on the page: a custom element that subscribes
   to a Server-Sent Events stream and swaps each pushed HTML fragment into place.
   Rendering stays on the server (no duplicated markup or styling in JS); the
   server decides when to push and the client just listens.

   Usage: <live-system src="/events/system">...</live-system>
   The initial children are the server-rendered fragment, so the section is
   fully populated before any JS runs and degrades gracefully if JS is off.

   EventSource is opened in [connectedCallback] and closed in
   [disconnectedCallback], so the connection never outlives the element. It also
   reconnects automatically on transient network errors, and the last pushed
   content stays in place until the next message arrives. *)
let app_js =
  {|"use strict";
customElements.define("live-system", class extends HTMLElement {
  connectedCallback() {
    const src = this.getAttribute("src");
    if (!src) return;
    this.es = new EventSource(src);
    this.es.onmessage = (e) => { this.innerHTML = e.data; };
    // On error the browser retries automatically; keep the current content.
  }
  disconnectedCallback() {
    if (this.es) this.es.close();
  }
});
|}
;;

(* Encode an HTML fragment as the body of a single SSE "message" event. Each
   line of the payload needs its own "data:" prefix, and a blank line
   terminates the event. The browser rejoins the data lines with "\n", which is
   why we split on newlines here. *)
let sse_event html =
  let data_lines =
    String.split_lines html |> List.map ~f:(fun line -> "data: " ^ line)
  in
  String.concat ~sep:"\n" data_lines ^ "\n\n"
;;

let js_response ~status body =
  let headers =
    Cohttp.Header.of_list [ "content-type", "application/javascript; charset=utf-8" ]
  in
  Server.respond_string ~status ~headers body
;;

let page_shell ~main =
  sprintf
    {|<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>cheesegrater</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;700&display=swap" rel="stylesheet">
  <style>%s</style>
</head>
<body class="crt-flicker">
  <div class="page">%s</div>
  <div class="crt-overlay"></div>
  <script src="/app.js" defer></script>
</body>
</html>|}
    style
    main
;;

(* Section header: uppercase glowing title, matching the SPA's section dividers. *)
let section_header title =
  sprintf {|<div class="section-header"><span>%s</span></div>|} (escape title)
;;

(* A shell prompt line: a cyan "$" followed by the dimmed command text. *)
let prompt_line cmd =
  sprintf
    {|<div class="prompt"><span class="sigil">$ </span><span class="cmd">%s</span></div>|}
    (escape cmd)
;;

let error_block msg = sprintf {|<div class="error">Error: %s</div>|} (escape msg)

(* An ASCII-style progress bar: [ filled empty ]. Mirrors the SPA's
   [progress_bar]: at least one filled block once percent > 0, clamped 0..100. *)
let progress_bar ~percent ~width_chars =
  let percent = Int.max 0 (Int.min 100 percent) in
  let filled = percent * width_chars / 100 in
  let filled = Int.max (if percent > 0 then 1 else 0) filled in
  let empty = width_chars - filled in
  sprintf
    {|<span class="bar"><span class="track-edge">[ </span><span class="filled">%s</span><span class="empty">%s</span><span class="track-edge"> ]</span></span>|}
    (String.make filled '#')
    (String.make empty '#')
;;

(* Map an active-state to the css suffix used to theme a service card, its
   status dot, and its badge. *)
let state_class = function
  | "active" -> "active"
  | "failed" -> "failed"
  | "inactive" -> "inactive"
  | _ -> "other"
;;

let render_service
  { Systemd.name
  ; description = _
  ; load_state = _
  ; active_state
  ; sub_state = _
  ; unit_file_state = _
  ; main_pid = _
  ; active_since = _
  }
  =
  let sc = state_class active_state in
  sprintf
    {|<div class="service"><span class="dot state-%s"></span><span class="name">%s</span></div>|}
    sc
    (escape name)
;;

let render_services = function
  | Error msg -> error_block msg
  | Ok services -> String.concat (List.map services ~f:render_service)
;;

let render_disk_row { System.mount; size; used; avail; use_percent } =
  sprintf
    {|<tr><td class="dim">  %s</td><td class="num bright">%s</td><td class="num bright">%s</td><td class="num bright">%s</td><td class="num bright">%s%%</td></tr>|}
    (escape mount)
    (escape size)
    (escape used)
    (escape avail)
    (Int.to_string use_percent)
;;

(* A labeled progress-bar row: a fixed-width label, an ASCII bar, and the
   percentage. Used for the aggregate CPU, each CPU core, and memory so they
   share the same "graphics". *)
let labeled_bar ~label ~percent =
  sprintf
    {|<div class="output"><span class="bright" style="display:inline-block;width:5rem">%s</span>%s<span class="bright" style="margin-left:1rem">%d%%</span></div>|}
    (escape label)
    (progress_bar ~percent ~width_chars:28)
    percent
;;

let render_system = function
  | Error msg -> error_block msg
  | Ok { System.uptime
       ; cpu_percent
       ; cpu_per_core
       ; cpu_model
       ; cpu_cores
       ; memory
       ; disks
       } ->
    let df_header =
      {|<tr><th>MOUNT</th><th class="num">SIZE</th><th class="num">USED</th><th class="num">AVAIL</th><th class="num">USE%</th></tr>|}
    in
    let rows = String.concat (List.map disks ~f:render_disk_row) in
    let per_core_bars =
      String.concat
        (List.mapi cpu_per_core ~f:(fun i percent ->
           labeled_bar ~label:(sprintf "cpu%d" i) ~percent))
    in
    let { System.total; used; free; use_percent = mem_use_percent } = memory in
    String.concat
      [ prompt_line "date -u"
      ; sprintf {|<div class="output"><span class="bright">%s</span></div>|} (escape (utc_now ()))
      ; prompt_line "uptime --pretty"
      ; sprintf {|<div class="output"><span class="bright">%s</span></div>|} (escape uptime)
      ; prompt_line "top -bn1 (press 1 for per-core)"
      ; labeled_bar ~label:"CPU" ~percent:cpu_percent
      ; per_core_bars
      ; sprintf
          {|<div class="output"><span class="dim">%s (%d cores)</span></div>|}
          (escape cpu_model)
          cpu_cores
      ; prompt_line "free -h"
      ; labeled_bar ~label:"MEM" ~percent:mem_use_percent
      ; sprintf
          {|<div class="output"><span class="dim">%s used / %s total · %s free</span></div>|}
          (escape used)
          (escape total)
          (escape free)
      ; prompt_line "df -h"
      ; sprintf {|<div class="df-wrap"><table class="df">%s%s</table></div>|} df_header rows
      ]
;;

(* The system section's inner HTML, rendered on its own so it can be returned
   both inside the full page and from the [/partials/system] endpoint that the
   client polls. *)
let system_section system_info =
  String.concat [ section_header "SYSTEM RESOURCES"; render_system system_info ]
;;

let render_commits = function
  | Error msg -> error_block msg
  | Ok commits ->
    let row { Git.sha; message } =
      sprintf
        {|<div class="commit"><span class="sha">%s</span><span class="msg">%s</span></div>|}
        (escape (String.prefix sha 7))
        (escape message)
    in
    let rows = String.concat (List.map commits ~f:row) in
    String.concat
      [ prompt_line "git log --oneline -5"
      ; sprintf {|<div class="commits-wrap">%s</div>|} rows
      ]
;;

let footer =
  {|<div class="footer"><span class="dim">[ </span><span class="name">cheesegrater</span><span class="dim"> :: home lab status :: </span><span class="name">nixos</span><span class="dim"> ]</span></div>|}
;;

let handle_index (git : Git.t) (systemd : Systemd.t) (system : System.t) =
  (* Each section degrades to an inline error block if its source fails, so a
     single failing data source never takes down the whole page. *)
  let%bind services = systemd.services () in
  let%bind system_info = system.info () in
  let%bind commits = git.recent_commits () in
  let main =
    String.concat
      [ {|<h1 class="title">cheesegrater</h1>|}
      ; section_header "SERVICES"
      ; render_services services
      (* System resources update live over SSE: the <live-system> element
         subscribes to /events/system and swaps in each pushed fragment. The
         initial children are the server-rendered section, so it is populated
         before any JS runs. *)
      ; sprintf
          {|<live-system src="/events/system">%s</live-system>|}
          (system_section system_info)
      ; section_header "RECENT COMMITS"
      ; render_commits commits
      ; footer
      ]
  in
  html_response ~status:`OK (page_shell ~main)
;;

(* Server-Sent Events stream of the system section. Every second we read the
   data source, render the section, and push it as one SSE message. The browser
   swaps it into the <live-system> element, so the embedded UTC clock visibly
   advances each second.

   The response body is a [Pipe] fed by a background loop. [Pipe.write_if_open]
   resolves only once the chunk is flushed, which paces the loop to the client:
   a slow or paused consumer applies backpressure rather than buffering without
   bound. When the client disconnects the pipe closes, [is_closed] becomes true,
   and the loop exits, ending the per-connection work. *)
let handle_events_system (system : System.t) =
  let headers =
    Cohttp.Header.of_list
      [ "content-type", "text/event-stream"
      ; "cache-control", "no-cache"
      ; "connection", "keep-alive"
      ]
  in
  let reader, writer = Pipe.create () in
  (* Producer loop: runs detached from the response so the headers are sent
     immediately and frames stream as they are produced. *)
  don't_wait_for
    (let rec loop () =
       if Pipe.is_closed writer
       then return ()
       else (
         let%bind system_info = system.info () in
         let frame = sse_event (system_section system_info) in
         let%bind () = Pipe.write_if_open writer frame in
         let%bind () = Clock.after (Time_float.Span.of_sec 1.) in
         loop ())
     in
     let%map () = loop () in
     Pipe.close writer);
  Server.respond_with_pipe ~headers reader
;;

let handler git systemd system ~body:_ _sock req =
  let path = Uri.path (Request.uri req) in
  match Request.meth req, path with
  | `GET, "/" -> handle_index git systemd system
  | `GET, "/app.js" -> js_response ~status:`OK app_js
  | `GET, "/events/system" -> handle_events_system system
  | `GET, "/health" -> json_response ~status:`OK {|{"status":"ok"}|}
  | `GET, "/version" ->
    json_response ~status:`OK (Printf.sprintf {|{"version":"%s"}|} version)
  | _ -> json_response ~status:`Not_found {|{"error":"not found"}|}
;;

let create_git_source () =
  match Sys.getenv "AFFINEUR_DATA_SOURCE" with
  | Some "fake" ->
    printf "data source: fake\n%!";
    Git_fake.create ()
  | _ ->
    let repo_path = Sys.getenv "REPO_PATH" |> Option.value ~default:"/etc/nixos" in
    printf "data source: git (%s)\n%!" repo_path;
    Git_real.create ~repo_path
;;

let create_systemd_source () =
  match Sys.getenv "AFFINEUR_DATA_SOURCE" with
  | Some "fake" -> Systemd_fake.create ()
  | _ -> Systemd_real.create ()
;;

let create_system_source () =
  match Sys.getenv "AFFINEUR_DATA_SOURCE" with
  | Some "fake" -> System_fake.create ()
  | _ -> System_real.create ()
;;

let () =
  let port =
    Sys.getenv "PORT" |> Option.map ~f:Int.of_string |> Option.value ~default:8080
  in
  let git = create_git_source () in
  let systemd = create_systemd_source () in
  let system = create_system_source () in
  (* Log per-connection errors instead of raising: a browser aborting a request
     mid-response closes the socket and surfaces as a writer exception; with
     [`Raise] that single broken connection would take down the whole server. *)
  let on_handler_error =
    `Call
      (fun _addr exn -> eprintf "[affineur] connection error: %s\n%!" (Exn.to_string exn))
  in
  let _server =
    Server.create
      ~on_handler_error
      (Tcp.Where_to_listen.of_port port)
      (handler git systemd system)
  in
  printf "affineur listening on port %d\n%!" port;
  never_returns (Scheduler.go ())
;;
