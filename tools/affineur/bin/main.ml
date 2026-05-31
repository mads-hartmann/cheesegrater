open Core
open Async
open Cohttp_async
open Affineur_lib

let version = Version.version

let json_response ~status body =
  let headers = Cohttp.Header.of_list [ ("content-type", "application/json") ] in
  Server.respond_string ~status ~headers body
;;

let html_response body =
  let headers = Cohttp.Header.of_list [ ("content-type", "text/html; charset=utf-8") ] in
  Server.respond_string ~status:`OK ~headers body
;;

let js_response body =
  let headers =
    Cohttp.Header.of_list [ ("content-type", "application/javascript; charset=utf-8") ]
  in
  Server.respond_string ~status:`OK ~headers body
;;

(* Respond with HTTP 500 and a clear, valid-JSON error body. The message is
   also logged to stderr (captured by journald) because Async_js.Http on the
   browser client discards the response body for non-2xx statuses; the log is
   therefore the reliable place to diagnose failures, while the body still
   helps non-browser clients such as curl. Yojson handles escaping so messages
   containing quotes or newlines (e.g. git errors) stay valid JSON. *)
let error_response ~endpoint msg =
  eprintf "[affineur] %s failed: %s\n%!" endpoint msg;
  let body = Yojson.Basic.to_string (`Assoc [ "error", `String msg ]) in
  json_response ~status:`Internal_server_error body
;;

let handle_api_commits (source : Git.t) =
  let%bind last_pulled = source.last_pulled () in
  let%bind commits_result = source.recent_commits () in
  match commits_result with
  | Error msg -> error_response ~endpoint:"/api/commits" msg
  | Ok commits ->
    let commits_json =
      List.map commits ~f:(fun { Git.sha; message } ->
        `Assoc [ "sha", `String sha; "message", `String message ])
    in
    let json =
      `Assoc [ "last_pulled", `String last_pulled; "commits", `List commits_json ]
    in
    json_response ~status:`OK (Yojson.Basic.to_string json)
;;

let handle_api_services (source : Systemd.t) =
  let%bind services_result = source.services () in
  match services_result with
  | Error msg -> error_response ~endpoint:"/api/services" msg
  | Ok services ->
    let services_json =
      List.map
        services
        ~f:(fun
             { Systemd.name
             ; description
             ; load_state
             ; active_state
             ; sub_state
             ; unit_file_state
             ; main_pid
             ; active_since
             }
           ->
          `Assoc
            [ "name", `String name
            ; "description", `String description
            ; "load_state", `String load_state
            ; "active_state", `String active_state
            ; "sub_state", `String sub_state
            ; "unit_file_state", `String unit_file_state
            ; "main_pid", `String main_pid
            ; "active_since", `String active_since
            ])
    in
    let json = `Assoc [ "services", `List services_json ] in
    json_response ~status:`OK (Yojson.Basic.to_string json)
;;

let handle_api_system (source : System.t) =
  let%bind info_result = source.info () in
  match info_result with
  | Error msg -> error_response ~endpoint:"/api/system" msg
  | Ok { System.uptime
       ; cpu_percent
       ; cpu_per_core
       ; cpu_model
       ; cpu_cores
       ; memory
       ; disks
       } ->
    let disks_json =
      List.map disks ~f:(fun { System.mount; size; used; avail; use_percent } ->
        `Assoc
          [ "mount", `String mount
          ; "size", `String size
          ; "used", `String used
          ; "avail", `String avail
          ; "use_percent", `Int use_percent
          ])
    in
    let cpu_per_core_json = List.map cpu_per_core ~f:(fun p -> `Int p) in
    let { System.total; used; free; use_percent = mem_use_percent } = memory in
    let memory_json =
      `Assoc
        [ "total", `String total
        ; "used", `String used
        ; "free", `String free
        ; "use_percent", `Int mem_use_percent
        ]
    in
    let json =
      `Assoc
        [ "uptime", `String uptime
        ; "cpu_percent", `Int cpu_percent
        ; "cpu_per_core", `List cpu_per_core_json
        ; "cpu_model", `String cpu_model
        ; "cpu_cores", `Int cpu_cores
        ; "memory", memory_json
        ; "disks", `List disks_json
        ]
    in
    json_response ~status:`OK (Yojson.Basic.to_string json)
;;

let index_html =
  {|<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>cheesegrater</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;700&display=swap" rel="stylesheet">
  <style>
    /* Retro CRT terminal theme tokens (ported from the Tailwind palette). */
    :root {
      --background: oklch(0.08 0.01 240);
      --foreground: oklch(0.85 0.15 142);
      --card: oklch(0.12 0.01 240);
      --card-foreground: oklch(0.85 0.15 142);
      --primary: oklch(0.75 0.2 142);
      --primary-foreground: oklch(0.08 0.01 240);
      --secondary: oklch(0.18 0.01 240);
      --secondary-foreground: oklch(0.7 0.12 142);
      --muted: oklch(0.15 0.01 240);
      --muted-foreground: oklch(0.55 0.08 142);
      --accent: oklch(0.65 0.18 80);
      --accent-foreground: oklch(0.08 0.01 240);
      --destructive: oklch(0.6 0.2 25);
      --destructive-foreground: oklch(0.95 0 0);
      --border: oklch(0.25 0.05 142);

      /* Custom retro colors */
      --terminal-green: oklch(0.75 0.2 142);
      --terminal-amber: oklch(0.7 0.18 80);
      --terminal-red: oklch(0.6 0.2 25);
      --terminal-cyan: oklch(0.7 0.12 200);
      --scanline: rgba(0, 0, 0, 0.1);
    }

    html, body {
      margin: 0;
      background: var(--background);
      color: var(--foreground);
      font-family: "JetBrains Mono", "Geist Mono", ui-monospace, "SF Mono", Menlo, Consolas, monospace;
      font-size: 15px;
      line-height: 1.6;
      -webkit-font-smoothing: antialiased;
    }

    /* CRT scanline overlay */
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

    /* Phosphor glow */
    .glow { text-shadow: 0 0 5px currentColor, 0 0 10px currentColor; }
    .glow-sm { text-shadow: 0 0 3px currentColor; }

    /* CRT flicker */
    @keyframes flicker {
      0%, 100% { opacity: 1; }
      50% { opacity: 0.98; }
    }
    .crt-flicker { animation: flicker 0.15s infinite; }
  </style>
</head>
<body class="crt-flicker">
  <div id="app"></div>
  <div class="crt-overlay"></div>
  <script src="/main.js"></script>
</body>
</html>|}
;;

let handler source systemd system ~body:_ _sock req =
  let path = Uri.path (Request.uri req) in
  match (Request.meth req, path) with
  | `GET, "/" ->
    html_response index_html
  | `GET, "/main.js" ->
    let js_path = Sys.getenv "JS_PATH" |> Option.value ~default:"./main.bc.js" in
    let%bind content = try_with (fun () -> Reader.file_contents js_path) in
    (match content with
     | Ok js -> js_response js
     | Error _ -> json_response ~status:`Not_found {|{"error":"js not found"}|})
  | `GET, "/api/commits" ->
    handle_api_commits source
  | `GET, "/api/services" ->
    handle_api_services systemd
  | `GET, "/api/system" ->
    handle_api_system system
  | `GET, "/health" ->
    let body = {|{"status":"ok"}|} in
    json_response ~status:`OK body
  | `GET, "/version" ->
    let body = Printf.sprintf {|{"version":"%s"}|} version in
    json_response ~status:`OK body
  | _ ->
    json_response ~status:`Not_found {|{"error":"not found"}|}
;;

let create_git_source () =
  match Sys.getenv "AFFINEUR_DATA_SOURCE" with
  | Some "fake" ->
    printf "data source: fake\n%!";
    Git_fake.create ()
  | _ ->
    let repo_path =
      Sys.getenv "REPO_PATH"
      |> Option.value ~default:"/etc/nixos"
    in
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
    Sys.getenv "PORT"
    |> Option.map ~f:Int.of_string
    |> Option.value ~default:8080
  in
  let source = create_git_source () in
  let systemd = create_systemd_source () in
  let system = create_system_source () in
  let _server =
    Server.create
      ~on_handler_error:`Raise
      (Tcp.Where_to_listen.of_port port)
      (handler source systemd system)
  in
  printf "affineur listening on port %d\n%!" port;
  never_returns (Scheduler.go ())
