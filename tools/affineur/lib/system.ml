open! Core
open! Async

(* A single filesystem mount as reported by [df -h]. *)
type mount =
  { mount : string
  ; size : string
  ; used : string
  ; avail : string
  ; use_percent : int
  }

(* Basic system resource information for the dashboard:
   how long the host has been up, current CPU load, and disk usage. *)
type info =
  { uptime : string
  ; cpu_percent : int
  ; cpu_model : string
  ; cpu_cores : int
  ; disks : mount list
  }

type t = { info : unit -> (info, string) Result.t Deferred.t }
