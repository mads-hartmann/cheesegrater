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

let json_escape s = String.substr_replace_all s ~pattern:{|"|} ~with_:{|\"|}

let handle_api_commits (source : Git.t) =
  let%bind last_pulled = source.last_pulled () in
  let%bind commits_result = source.recent_commits () in
  match commits_result with
  | Error msg ->
    let body = Printf.sprintf {|{"error":"%s"}|} msg in
    json_response ~status:`Internal_server_error body
  | Ok commits ->
    let commits_json =
      List.map commits ~f:(fun { Git.sha; message } ->
        Printf.sprintf {|{"sha":"%s","message":"%s"}|} sha (json_escape message))
      |> String.concat ~sep:","
    in
    let body =
      Printf.sprintf
        {|{"last_pulled":"%s","commits":[%s]}|}
        last_pulled
        commits_json
    in
    json_response ~status:`OK body
;;

let handle_api_services (source : Systemd.t) =
  let%bind services_result = source.services () in
  match services_result with
  | Error msg ->
    let body = Printf.sprintf {|{"error":"%s"}|} (json_escape msg) in
    json_response ~status:`Internal_server_error body
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
          Printf.sprintf
            {|{"name":"%s","description":"%s","load_state":"%s","active_state":"%s","sub_state":"%s","unit_file_state":"%s","main_pid":"%s","active_since":"%s"}|}
            (json_escape name)
            (json_escape description)
            (json_escape load_state)
            (json_escape active_state)
            (json_escape sub_state)
            (json_escape unit_file_state)
            (json_escape main_pid)
            (json_escape active_since))
      |> String.concat ~sep:","
    in
    let body = Printf.sprintf {|{"services":[%s]}|} services_json in
    json_response ~status:`OK body
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
