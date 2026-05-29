open! Core
open! Async

(* Properties we ask [systemctl show] to report. Keep in sync with the fields
   parsed in [parse_show] below. *)
let properties =
  [ "Id"
  ; "Description"
  ; "LoadState"
  ; "ActiveState"
  ; "SubState"
  ; "UnitFileState"
  ; "MainPID"
  ; "ActiveEnterTimestamp"
  ]
;;

(* [systemctl show] prints one [Key=Value] pair per line. Parse them into a
   string map so we can look up the properties we care about. *)
let parse_show output =
  String.split_lines output
  |> List.filter_map ~f:(fun line ->
    match String.lsplit2 line ~on:'=' with
    | Some (key, value) -> Some (key, value)
    | None -> None)
  |> String.Map.of_alist_reduce ~f:(fun _ v -> v)
;;

let service_of_map ~fallback_name map =
  let get key ~default =
    match Map.find map key with
    | Some "" | None -> default
    | Some v -> v
  in
  let name = get "Id" ~default:fallback_name in
  { Systemd.name
  ; description = get "Description" ~default:name
  ; load_state = get "LoadState" ~default:"unknown"
  ; active_state = get "ActiveState" ~default:"unknown"
  ; sub_state = get "SubState" ~default:"unknown"
  ; unit_file_state = get "UnitFileState" ~default:"unknown"
  ; main_pid = get "MainPID" ~default:"0"
  ; active_since = get "ActiveEnterTimestamp" ~default:""
  }
;;

let show_unit ~systemctl unit =
  let%map result =
    Process.run
      ~prog:systemctl
      ~args:
        ([ "show"; unit; "--no-pager" ]
         @ List.map properties ~f:(fun p -> "--property=" ^ p))
      ()
  in
  match result with
  | Error err -> Error (Error.to_string_hum err)
  | Ok output -> Ok (service_of_map ~fallback_name:unit (parse_show output))
;;

let create ?(systemctl = "systemctl") ?(units = Systemd.deployed_units) () : Systemd.t =
  let services () =
    let%map results = Deferred.List.map ~how:`Sequential units ~f:(show_unit ~systemctl) in
    match Result.all results with
    | Ok services -> Ok services
    | Error msg -> Error msg
  in
  { Systemd.services }
;;
