open! Core
open! Async

let create ~repo_path : Git.t =
  let last_pulled () =
    let fetch_head = Filename.concat repo_path ".git/FETCH_HEAD" in
    let%map stat_result = try_with (fun () -> Unix.stat fetch_head) in
    match stat_result with
    | Ok stat ->
      Time_float_unix.to_string_iso8601_basic stat.mtime ~zone:Time_float.Zone.utc
    | Error _ -> "unknown"
  in
  let recent_commits () =
    let%map result =
      Process.run
        ~working_dir:repo_path
        ~prog:"git"
        ~args:[ "log"; "--oneline"; "-5"; "--format=%H %s" ]
        ()
    in
    match result with
    | Error err -> Error (Error.to_string_hum err)
    | Ok output ->
      let commits =
        String.split_lines output
        |> List.filter_map ~f:(fun line ->
          match String.lsplit2 line ~on:' ' with
          | Some (sha, message) -> Some { Git.sha; message }
          | None -> None)
      in
      Ok commits
  in
  { last_pulled; recent_commits }
;;
