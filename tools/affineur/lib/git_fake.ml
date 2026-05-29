open! Core
open! Async

let create () : Git.t =
  let last_pulled () = return "2025-05-29T12:00:00.000000Z" in
  let recent_commits () =
    return
      (Ok
         [ { Git.sha = "d72efc9a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e"
           ; message = "affineur: fix binary name in systemd service"
           }
         ; { sha = "555ced1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d"
           ; message = "configuration: import auto-upgrade module"
           }
         ; { sha = "916c1f4a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e"
           ; message = "ci: limit push trigger to main branch"
           }
         ; { sha = "10d9893b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f"
           ; message = "Add affineur OCaml HTTP server"
           }
         ; { sha = "af9478bc4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a"
           ; message = "Merge pull request #6 from mads-hartmann/docs/update-agents-md"
           }
         ])
  in
  { last_pulled; recent_commits }
;;
