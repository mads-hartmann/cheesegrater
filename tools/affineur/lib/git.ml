open! Core
open! Async

type commit =
  { sha : string
  ; message : string
  }

type t =
  { last_pulled : unit -> string Deferred.t
  ; recent_commits : unit -> (commit list, string) Result.t Deferred.t
  }
