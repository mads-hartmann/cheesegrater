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
      justify-content: space-between;
      align-items: flex-start;
      gap: 1.5rem;
      flex-wrap: wrap;
      padding: 1.25rem 1.5rem;
      margin-bottom: 1rem;
      border: 1px solid var(--border);
      border-radius: 6px;
    }
    .service .info { min-width: 16rem; }
    .service .name-row { display: flex; align-items: center; gap: 0.6rem; }
    .service .dot {
      width: 0.55rem;
      height: 0.55rem;
      border-radius: 50%;
      text-shadow: 0 0 5px currentColor, 0 0 10px currentColor;
    }
    .service .name { font-weight: 700; color: var(--foreground); }
    .service .desc { margin-top: 0.4rem; color: var(--muted-foreground); }
    .service .badge {
      align-self: center;
      padding: 0.25rem 0.75rem;
      border: 1px solid currentColor;
      border-radius: 4px;
      white-space: nowrap;
    }
    .service .details { flex: 1; min-width: 14rem; align-self: center; }
    .service .details .label { color: var(--terminal-cyan); }
    .service .details .value { color: var(--muted-foreground); }

    .state-active { color: var(--terminal-green); }
    .state-failed { color: var(--terminal-red); }
    .state-inactive { color: var(--muted-foreground); }
    .state-other { color: var(--terminal-amber); }

    .dot.state-active { background: var(--terminal-green); color: var(--terminal-green); }
    .dot.state-failed { background: var(--terminal-red); color: var(--terminal-red); }
    .dot.state-inactive { background: var(--muted-foreground); color: var(--muted-foreground); }
    .dot.state-other { background: var(--terminal-amber); color: var(--terminal-amber); }

    .service.bg-active { background: rgba(74, 222, 128, 0.04); }
    .service.bg-failed { background: rgba(239, 68, 68, 0.05); border-color: rgba(239, 68, 68, 0.35); }
    .service.bg-inactive { background: rgba(255, 255, 255, 0.02); }
    .service.bg-other { background: rgba(212, 160, 23, 0.05); border-color: rgba(212, 160, 23, 0.35); }

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
    table.df td.bar-cell { width: 99%; white-space: normal; }
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

let detail_pair label value =
  sprintf
    {|<span class="label">%s</span><span class="value">%s</span>|}
    (escape label)
    (escape value)
;;

let render_service
  { Systemd.name
  ; description
  ; load_state
  ; active_state
  ; sub_state
  ; unit_file_state
  ; main_pid
  ; active_since
  }
  =
  let sc = state_class active_state in
  let state_label = sprintf "%s (%s)" active_state sub_state in
  let pid_since =
    let parts =
      List.concat
        [ (if String.( <> ) main_pid "0"
           then [ detail_pair "PID " (main_pid ^ "  ") ]
           else [])
        ; (if String.is_empty active_since
           then []
           else [ detail_pair "since " active_since ])
        ]
    in
    String.concat parts
  in
  let details =
    String.concat
      [ pid_since
      ; (if String.is_empty pid_since then "" else "<br>")
      ; detail_pair "load: " (load_state ^ "  ")
      ; {|<span class="value">· </span>|}
      ; detail_pair "file: " unit_file_state
      ]
  in
  sprintf
    {|<div class="service bg-%s">
      <div class="info">
        <div class="name-row"><span class="dot state-%s"></span><span class="name">%s</span></div>
        <div class="desc">%s</div>
      </div>
      <span class="badge state-%s">%s</span>
      <div class="details">%s</div>
    </div>|}
    sc
    sc
    (escape name)
    (escape description)
    sc
    (escape state_label)
    details
;;

let render_services = function
  | Error msg -> error_block msg
  | Ok services -> String.concat (List.map services ~f:render_service)
;;

let render_disk_row { System.mount; size; used; avail; use_percent } =
  sprintf
    {|<tr><td class="dim">  %s</td><td class="num bright">%s</td><td class="num bright">%s</td><td class="num bright">%s</td><td class="bar-cell">%s</td><td class="num bright">%s%%</td></tr>|}
    (escape mount)
    (escape size)
    (escape used)
    (escape avail)
    (progress_bar ~percent:use_percent ~width_chars:28)
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
      {|<tr><th>MOUNT</th><th class="num">SIZE</th><th class="num">USED</th><th class="num">AVAIL</th><th>USE%</th><th></th></tr>|}
    in
    let rows = String.concat (List.map disks ~f:render_disk_row) in
    let per_core_bars =
      String.concat
        (List.mapi cpu_per_core ~f:(fun i percent ->
           labeled_bar ~label:(sprintf "cpu%d" i) ~percent))
    in
    let { System.total; used; free; use_percent = mem_use_percent } = memory in
    String.concat
      [ prompt_line "uptime --pretty"
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
      ; section_header "SYSTEM RESOURCES"
      ; render_system system_info
      ; section_header "RECENT COMMITS"
      ; render_commits commits
      ; footer
      ]
  in
  html_response ~status:`OK (page_shell ~main)
;;

let handler git systemd system ~body:_ _sock req =
  let path = Uri.path (Request.uri req) in
  match Request.meth req, path with
  | `GET, "/" -> handle_index git systemd system
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
