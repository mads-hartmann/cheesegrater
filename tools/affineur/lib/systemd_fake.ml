open! Core
open! Async

let create () : Systemd.t =
  let services () =
    return
      (Ok
         [ { Systemd.name = "affineur.service"
           ; description = "affineur HTTP server"
           ; load_state = "loaded"
           ; active_state = "active"
           ; sub_state = "running"
           ; unit_file_state = "enabled"
           ; main_pid = "1234"
           ; active_since = "Thu 2025-05-29 12:00:01 UTC"
           }
         ; { name = "nixos-auto-upgrade.service"
           ; description = "NixOS auto-upgrade from local checkout of main"
           ; load_state = "loaded"
           ; active_state = "failed"
           ; sub_state = "failed"
           ; unit_file_state = "linked"
           ; main_pid = "0"
           ; active_since = ""
           }
         ])
  in
  { Systemd.services }
;;
