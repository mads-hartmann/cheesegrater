open! Core
open! Async

(* Basic information systemd exposes for a unit, as reported by
   [systemctl show]. *)
type service =
  { name : string
  ; description : string
  ; load_state : string
  ; active_state : string
  ; sub_state : string
  ; unit_file_state : string
  ; main_pid : string
  ; active_since : string
  }

type t = { services : unit -> (service list, string) Result.t Deferred.t }

(* The systemd units this configuration deploys (see nixos/modules). *)
let deployed_units = [ "affineur.service"; "nixos-auto-upgrade.service" ]
