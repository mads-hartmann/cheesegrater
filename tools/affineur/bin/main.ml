open Core
open Async
open Cohttp_async

let version = Version.version

let json_response ~status body =
  let headers = Cohttp.Header.of_list [ ("content-type", "application/json") ] in
  Server.respond_string ~status ~headers body

let handler ~body:_ _sock req =
  let path = Uri.path (Request.uri req) in
  match (Request.meth req, path) with
  | `GET, "/health" ->
    let body = {|{"status":"ok"}|} in
    json_response ~status:`OK body
  | `GET, "/version" ->
    let body = Printf.sprintf {|{"version":"%s"}|} version in
    json_response ~status:`OK body
  | _ ->
    json_response ~status:`Not_found {|{"error":"not found"}|}

let () =
  let port =
    Sys.getenv "PORT"
    |> Option.map ~f:Int.of_string
    |> Option.value ~default:8080
  in
  let _server =
    Server.create
      ~on_handler_error:`Raise
      (Tcp.Where_to_listen.of_port port)
      handler
  in
  printf "affineur listening on port %d\n%!" port;
  never_returns (Scheduler.go ())
