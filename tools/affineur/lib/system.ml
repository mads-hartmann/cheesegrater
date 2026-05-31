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

(* Memory usage as reported by [free -h]: human-readable totals plus the
   percentage of total memory in use. *)
type memory =
  { total : string
  ; used : string
  ; free : string
  ; use_percent : int
  }

(* Basic system resource information for the dashboard: how long the host has
   been up, aggregate and per-core CPU load, memory usage, and disk usage.
   [cpu_per_core] holds the busy percentage of each logical core, in the order
   reported by /proc/stat. *)
type info =
  { uptime : string
  ; cpu_percent : int
  ; cpu_per_core : int list
  ; cpu_model : string
  ; cpu_cores : int
  ; memory : memory
  ; disks : mount list
  }

type t = { info : unit -> (info, string) Result.t Deferred.t }
