open! Core
open! Async

(* CPU readings wander between calls so the live-refreshing dashboard visibly
   updates during local development. A random walk (rather than a fresh random
   value each time) keeps successive readings close, mimicking real CPU load
   instead of jumping erratically. Each per-core value walks independently. *)
let walk ref_cell =
  let delta = Random.int 11 - 5 in
  ref_cell := Int.max 1 (Int.min 99 (!ref_cell + delta));
  !ref_cell
;;

let cpu = ref 23
let per_core = List.map [ 12; 47; 8; 63; 31; 5; 88; 19 ] ~f:ref

let create () : System.t =
  let info () =
    return
      (Ok
         { System.uptime = "up 14 days, 7 hours, 23 minutes"
         ; cpu_percent = walk cpu
         ; cpu_per_core = List.map per_core ~f:walk
         ; cpu_model = "AMD Ryzen 7 5800X"
         ; cpu_cores = 8
         ; memory =
             { System.total = "31Gi"; used = "9.4Gi"; free = "18Gi"; use_percent = 31 }
         ; disks =
             [ { System.mount = "/"
               ; size = "256G"
               ; used = "89G"
               ; avail = "167G"
               ; use_percent = 35
               }
             ; { mount = "/home"
               ; size = "1.0T"
               ; used = "612G"
               ; avail = "388G"
               ; use_percent = 61
               }
             ; { mount = "/nix/store"
               ; size = "256G"
               ; used = "142G"
               ; avail = "114G"
               ; use_percent = 55
               }
             ; { mount = "/var/log"
               ; size = "50G"
               ; used = "12G"
               ; avail = "38G"
               ; use_percent = 24
               }
             ]
         })
  in
  { System.info }
;;
