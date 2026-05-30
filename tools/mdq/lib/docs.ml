open! Core
open! Async

(* A folder of markdown passed on the command line.

   [name] is the display name (the folder's basename).
   [url_base] is where the folder is mounted: ["/"] when a single folder is
   served, or ["/<name>"] when several are served side by side.
   [fs_path] is the absolute path to the folder on disk. *)
type root =
  { name : string
  ; url_base : string
  ; fs_path : string
  }

type entry_kind =
  | Dir
  | Page

(* An item shown in a directory listing. [path] is the URL the SPA navigates
   to, not the on-disk path. *)
type entry =
  { name : string
  ; path : string
  ; kind : entry_kind
  }

(* The result of resolving a URL path against the configured roots. *)
type content =
  | Page of
      { title : string
      ; frontmatter : Frontmatter.t
      ; html : string
      }
  | Listing of
      { title : string
      ; entries : entry list
      }
  | Not_found

type t =
  { roots : unit -> root list
  ; resolve : string -> content Deferred.t
  }
