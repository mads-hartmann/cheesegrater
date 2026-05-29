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

let handle_api_commits (source : Git.t) =
  let%bind last_pulled = source.last_pulled () in
  let%bind commits_result = source.recent_commits () in
  (* Return git failures as 200 with an "error" field rather than a 500.
     Async_js.Http on the client discards the response body for non-2xx
     statuses, so a 500 surfaces only as a generic "Request failed (code 500)"
     and hides the underlying git error. Yojson handles escaping so error
     messages containing quotes or newlines still produce valid JSON. *)
  let json =
    match commits_result with
    | Error msg -> `Assoc [ "error", `String msg ]
    | Ok commits ->
      let commits_json =
        List.map commits ~f:(fun { Git.sha; message } ->
          `Assoc [ "sha", `String sha; "message", `String message ])
      in
      `Assoc [ "last_pulled", `String last_pulled; "commits", `List commits_json ]
  in
  json_response ~status:`OK (Yojson.Basic.to_string json)
;;

let handle_api_services (source : Systemd.t) =
  let%bind services_result = source.services () in
  (* See handle_api_commits: return failures as 200 with an "error" field and
     build JSON via Yojson so all fields are correctly escaped. *)
  let json =
    match services_result with
    | Error msg -> `Assoc [ "error", `String msg ]
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
      `Assoc [ "services", `List services_json ]
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
  <style>
    body { margin: 0; background: #fafafa; }
  </style>
</head>
<body>
  <div id="app"></div>
  <script src="/main.js"></script>
</body>
</html>|}
;;

let handler source systemd ~body:_ _sock req =
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

let () =
  let port =
    Sys.getenv "PORT"
    |> Option.map ~f:Int.of_string
    |> Option.value ~default:8080
  in
  let source = create_git_source () in
  let systemd = create_systemd_source () in
  let _server =
    Server.create
      ~on_handler_error:`Raise
      (Tcp.Where_to_listen.of_port port)
      (handler source systemd)
  in
  printf "affineur listening on port %d\n%!" port;
  never_returns (Scheduler.go ())
