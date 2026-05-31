open! Core
open! Async

(* Pretty uptime string, e.g. "up 14 days, 7 hours, 23 minutes". Falls back to
   computing from /proc/uptime if the `uptime` binary is unavailable. *)
let read_uptime () =
  let%bind result = Process.run ~prog:"uptime" ~args:[ "--pretty" ] () in
  match result with
  | Ok output -> return (String.strip output)
  | Error _ ->
    let%map contents = try_with (fun () -> Reader.file_contents "/proc/uptime") in
    (match contents with
     | Error _ -> "unknown"
     | Ok s ->
       (match String.split s ~on:' ' with
        | first :: _ ->
          (match Float.of_string_opt first with
           | Some seconds ->
             let total = Int.of_float seconds in
             let days = total / 86400 in
             let hours = total % 86400 / 3600 in
             let minutes = total % 3600 / 60 in
             Printf.sprintf "up %d days, %d hours, %d minutes" days hours minutes
           | None -> "unknown")
        | [] -> "unknown"))
;;

(* The CPU lines in /proc/stat. The first ("cpu ...") is the aggregate; the
   subsequent ("cpu0", "cpu1", ...) are per logical core. Each line is
   "user nice system idle iowait ...". We read them as an association list
   keyed by the cpu label so a single sample captures both the aggregate and
   every core. *)
let read_cpu_lines () =
  let%map contents = try_with (fun () -> Reader.file_contents "/proc/stat") in
  match contents with
  | Error _ -> []
  | Ok s ->
    String.split_lines s
    |> List.filter_map ~f:(fun line ->
      if not (String.is_prefix line ~prefix:"cpu") then None
      else (
        let fields =
          String.split line ~on:' ' |> List.filter ~f:(fun f -> not (String.is_empty f))
        in
        match fields with
        | label :: rest ->
          let nums = List.filter_map rest ~f:Int.of_string_opt in
          if List.length nums >= 5 then Some (label, nums) else None
        | [] -> None))
;;

(* Busy percentage between two /proc/stat samples for a single cpu line. *)
let busy_percent first second =
  let totals nums = List.fold nums ~init:0 ~f:( + ) in
  let idle nums =
    (* idle is field 4 (index 3), iowait is field 5 (index 4). *)
    match nums with
    | _ :: _ :: _ :: idle :: iowait :: _ -> idle + iowait
    | _ -> 0
  in
  let total_delta = totals second - totals first in
  let idle_delta = idle second - idle first in
  if total_delta <= 0
  then 0
  else (
    let busy = total_delta - idle_delta in
    Int.of_float (Float.round_nearest (100. *. Float.of_int busy /. Float.of_int total_delta)))
;;

(* Sample /proc/stat twice a short interval apart and report the aggregate busy
   percentage along with the per-core busy percentages (cpu0, cpu1, ... in
   order). *)
let read_cpu_usage () =
  let%bind first = read_cpu_lines () in
  let%bind () = Clock.after (Time_float.Span.of_ms 200.) in
  let%map second = read_cpu_lines () in
  let lookup label samples = List.Assoc.find samples label ~equal:String.equal in
  let percent_for label =
    match lookup label first, lookup label second with
    | Some a, Some b -> Some (busy_percent a b)
    | _ -> None
  in
  let aggregate = Option.value (percent_for "cpu") ~default:0 in
  (* Per-core labels are "cpu0", "cpu1", ...; keep only those, sorted by index. *)
  let core_labels =
    List.filter_map first ~f:(fun (label, _) ->
      match String.chop_prefix label ~prefix:"cpu" with
      | Some idx when not (String.is_empty idx) ->
        Option.map (Int.of_string_opt idx) ~f:(fun i -> i, label)
      | _ -> None)
    |> List.sort ~compare:(fun (a, _) (b, _) -> Int.compare a b)
    |> List.map ~f:snd
  in
  let per_core = List.filter_map core_labels ~f:percent_for in
  aggregate, per_core
;;

let read_cpu_model () =
  let%map contents = try_with (fun () -> Reader.file_contents "/proc/cpuinfo") in
  match contents with
  | Error _ -> "unknown", 0
  | Ok s ->
    let lines = String.split_lines s in
    let model =
      List.find_map lines ~f:(fun line ->
        match String.lsplit2 line ~on:':' with
        | Some (key, value) when String.is_prefix (String.strip key) ~prefix:"model name" ->
          Some (String.strip value)
        | _ -> None)
      |> Option.value ~default:"unknown"
    in
    let cores =
      List.count lines ~f:(fun line ->
        match String.lsplit2 line ~on:':' with
        | Some (key, _) -> String.equal (String.strip key) "processor"
        | None -> false)
    in
    model, cores
;;

(* Parse `df -h` output into a list of mounts. Each data line looks like:
   "Filesystem Size Used Avail Use% Mounted-on". We key off the columns from
   the right since filesystem names can contain spaces. *)
let parse_df output =
  String.split_lines output
  |> List.tl
  |> Option.value ~default:[]
  |> List.filter_map ~f:(fun line ->
    let fields =
      String.split line ~on:' ' |> List.filter ~f:(fun f -> not (String.is_empty f))
    in
    match List.rev fields with
    | mount :: use_percent :: avail :: used :: size :: _ ->
      let use_percent =
        String.chop_suffix use_percent ~suffix:"%"
        |> Option.value ~default:use_percent
        |> Int.of_string_opt
        |> Option.value ~default:0
      in
      Some { System.mount; size; used; avail; use_percent }
    | _ -> None)
;;

let read_disks () =
  let%map result =
    Process.run
      ~prog:"df"
      ~args:
        [ "-h"
        ; "-x"
        ; "tmpfs"
        ; "-x"
        ; "devtmpfs"
        ; "-x"
        ; "squashfs"
        ; "-x"
        ; "overlay"
        ; "-x"
        ; "efivarfs"
        ]
      ()
  in
  match result with
  | Error err -> Error (Error.to_string_hum err)
  | Ok output -> Ok (parse_df output)
;;

(* Parse `free -h` output into total/used/free strings and a used percentage.
   The relevant line begins with "Mem:" and looks like:
   "Mem: <total> <used> <free> <shared> <buff/cache> <available>".
   The percentage is derived from total/used parsed via /proc/meminfo, since
   `free -h` only prints human-readable sizes. *)
let parse_free output =
  String.split_lines output
  |> List.find_map ~f:(fun line ->
    let fields =
      String.split line ~on:' ' |> List.filter ~f:(fun f -> not (String.is_empty f))
    in
    match fields with
    | label :: total :: used :: free :: _ when String.equal label "Mem:" ->
      Some (total, used, free)
    | _ -> None)
;;

(* Used-memory percentage from /proc/meminfo: (MemTotal - MemAvailable) /
   MemTotal. Falls back to 0 when the fields are unavailable. *)
let read_memory_percent () =
  let%map contents = try_with (fun () -> Reader.file_contents "/proc/meminfo") in
  match contents with
  | Error _ -> 0
  | Ok s ->
    let field name =
      String.split_lines s
      |> List.find_map ~f:(fun line ->
        match String.lsplit2 line ~on:':' with
        | Some (key, value) when String.equal (String.strip key) name ->
          String.strip value
          |> String.split ~on:' '
          |> List.hd
          |> Option.bind ~f:Int.of_string_opt
        | _ -> None)
    in
    (match field "MemTotal", field "MemAvailable" with
     | Some total, Some available when total > 0 ->
       let used = total - available in
       Int.of_float (Float.round_nearest (100. *. Float.of_int used /. Float.of_int total))
     | _ -> 0)
;;

let read_memory () =
  let%bind result = Process.run ~prog:"free" ~args:[ "-h" ] () in
  let%map use_percent = read_memory_percent () in
  match result with
  | Error err -> Error (Error.to_string_hum err)
  | Ok output ->
    (match parse_free output with
     | Some (total, used, free) ->
       Ok { System.total; used; free; use_percent }
     | None -> Error "could not parse free output")
;;

let create () : System.t =
  let info () =
    let%bind uptime = read_uptime () in
    let%bind cpu_percent, cpu_per_core = read_cpu_usage () in
    let%bind cpu_model, cpu_cores = read_cpu_model () in
    let%bind memory_result = read_memory () in
    let%map disks_result = read_disks () in
    match memory_result, disks_result with
    | Error msg, _ -> Error msg
    | _, Error msg -> Error msg
    | Ok memory, Ok disks ->
      Ok
        { System.uptime
        ; cpu_percent
        ; cpu_per_core
        ; cpu_model
        ; cpu_cores
        ; memory
        ; disks
        }
  in
  { System.info }
;;
