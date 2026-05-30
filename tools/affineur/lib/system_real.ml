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

(* The aggregate CPU line in /proc/stat: "cpu user nice system idle iowait ...".
   We take two samples a short interval apart and report the percentage of time
   the CPU was busy between them. *)
let read_cpu_line () =
  let%map contents = try_with (fun () -> Reader.file_contents "/proc/stat") in
  match contents with
  | Error _ -> None
  | Ok s ->
    String.split_lines s
    |> List.find ~f:(fun line -> String.is_prefix line ~prefix:"cpu ")
    |> Option.bind ~f:(fun line ->
      let fields =
        String.split line ~on:' '
        |> List.filter ~f:(fun f -> not (String.is_empty f))
      in
      match fields with
      | _cpu :: rest ->
        let nums = List.filter_map rest ~f:Int.of_string_opt in
        if List.length nums >= 5 then Some nums else None
      | [] -> None)
;;

let read_cpu_percent () =
  let totals nums = List.fold nums ~init:0 ~f:( + ) in
  let idle nums =
    (* idle is field 4 (index 3), iowait is field 5 (index 4). *)
    match nums with
    | _ :: _ :: _ :: idle :: iowait :: _ -> idle + iowait
    | _ -> 0
  in
  let%bind first = read_cpu_line () in
  let%bind () = Clock.after (Time_float.Span.of_ms 200.) in
  let%map second = read_cpu_line () in
  match first, second with
  | Some a, Some b ->
    let total_delta = totals b - totals a in
    let idle_delta = idle b - idle a in
    if total_delta <= 0
    then 0
    else (
      let busy = total_delta - idle_delta in
      Int.of_float (Float.round_nearest (100. *. Float.of_int busy /. Float.of_int total_delta)))
  | _ -> 0
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

let create () : System.t =
  let info () =
    let%bind uptime = read_uptime () in
    let%bind cpu_percent = read_cpu_percent () in
    let%bind cpu_model, cpu_cores = read_cpu_model () in
    let%map disks_result = read_disks () in
    match disks_result with
    | Error msg -> Error msg
    | Ok disks -> Ok { System.uptime; cpu_percent; cpu_model; cpu_cores; disks }
  in
  { System.info }
;;
