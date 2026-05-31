open! Core
open! Async

let create () : System.t =
  let info () =
    return
      (Ok
         { System.uptime = "up 14 days, 7 hours, 23 minutes"
         ; cpu_percent = 23
         ; cpu_per_core = [ 12; 47; 8; 63; 31; 5; 88; 19 ]
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
