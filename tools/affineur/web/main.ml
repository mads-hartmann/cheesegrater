open! Core
open! Bonsai_web.Cont
open Bonsai.Let_syntax

module Commit = struct
  type t =
    { sha : string
    ; message : string
    }

  let of_json json =
    let open Yojson.Basic.Util in
    { sha = json |> member "sha" |> to_string
    ; message = json |> member "message" |> to_string
    }
  ;;
end

module Commits_response = struct
  type t =
    { last_pulled : string
    ; commits : Commit.t list
    }

  let of_json_string s =
    let json = Yojson.Basic.from_string s in
    let open Yojson.Basic.Util in
    { last_pulled = json |> member "last_pulled" |> to_string
    ; commits = json |> member "commits" |> to_list |> List.map ~f:Commit.of_json
    }
  ;;
end

module Service = struct
  type t =
    { name : string
    ; description : string
    ; load_state : string
    ; active_state : string
    ; sub_state : string
    ; unit_file_state : string
    ; main_pid : string
    ; active_since : string
    }

  let of_json json =
    let open Yojson.Basic.Util in
    { name = json |> member "name" |> to_string
    ; description = json |> member "description" |> to_string
    ; load_state = json |> member "load_state" |> to_string
    ; active_state = json |> member "active_state" |> to_string
    ; sub_state = json |> member "sub_state" |> to_string
    ; unit_file_state = json |> member "unit_file_state" |> to_string
    ; main_pid = json |> member "main_pid" |> to_string
    ; active_since = json |> member "active_since" |> to_string
    }
  ;;
end

module Services_response = struct
  type t = { services : Service.t list }

  let of_json_string s =
    let json = Yojson.Basic.from_string s in
    let open Yojson.Basic.Util in
    { services = json |> member "services" |> to_list |> List.map ~f:Service.of_json }
  ;;
end

module Mount = struct
  type t =
    { mount : string
    ; size : string
    ; used : string
    ; avail : string
    ; use_percent : int
    }

  let of_json json =
    let open Yojson.Basic.Util in
    { mount = json |> member "mount" |> to_string
    ; size = json |> member "size" |> to_string
    ; used = json |> member "used" |> to_string
    ; avail = json |> member "avail" |> to_string
    ; use_percent = json |> member "use_percent" |> to_int
    }
  ;;
end

module Memory = struct
  type t =
    { total : string
    ; used : string
    ; free : string
    ; use_percent : int
    }

  let of_json json =
    let open Yojson.Basic.Util in
    { total = json |> member "total" |> to_string
    ; used = json |> member "used" |> to_string
    ; free = json |> member "free" |> to_string
    ; use_percent = json |> member "use_percent" |> to_int
    }
  ;;
end

module System_response = struct
  type t =
    { uptime : string
    ; cpu_percent : int
    ; cpu_per_core : int list
    ; cpu_model : string
    ; cpu_cores : int
    ; memory : Memory.t
    ; disks : Mount.t list
    }

  let of_json_string s =
    let json = Yojson.Basic.from_string s in
    let open Yojson.Basic.Util in
    { uptime = json |> member "uptime" |> to_string
    ; cpu_percent = json |> member "cpu_percent" |> to_int
    ; cpu_per_core = json |> member "cpu_per_core" |> to_list |> List.map ~f:to_int
    ; cpu_model = json |> member "cpu_model" |> to_string
    ; cpu_cores = json |> member "cpu_cores" |> to_int
    ; memory = json |> member "memory" |> Memory.of_json
    ; disks = json |> member "disks" |> to_list |> List.map ~f:Mount.of_json
    }
  ;;
end

let fetch_json url of_json_string =
  Effect.of_deferred_fun (fun () ->
    let open Async_kernel in
    let%map.Deferred result = Async_js.Http.get url in
    match result with
    | Error err -> Error (Error.to_string_hum err)
    | Ok body ->
      (try Ok (of_json_string body) with
       | exn -> Error (Exn.to_string exn)))
;;

let fetch_commits = fetch_json "/api/commits" Commits_response.of_json_string
let fetch_services = fetch_json "/api/services" Services_response.of_json_string
let fetch_system = fetch_json "/api/system" System_response.of_json_string

(* Terminal palette. The dashboard mimics a dark terminal: green phosphor text
   on a near-black background, with a few accent colours for state and SHAs.
   Values reference the retro CRT theme tokens defined in the HTML shell. *)
module Color = struct
  let green = "var(--terminal-green)"
  let green_bright = "var(--foreground)"
  let green_dim = "var(--secondary-foreground)"
  let muted = "var(--muted-foreground)"
  let faint = "var(--border)"
  let teal = "var(--terminal-cyan)"
  let amber = "var(--terminal-amber)"
  let red = "var(--terminal-red)"
end

module Css = Css_gen

let style l = Vdom.Attr.style (Css.concat l)
let s_color c = Css.color (`Name c)
let mono = Css.font_family [ "JetBrains Mono"; "ui-monospace"; "monospace" ]
let raw field value = Css.create ~field ~value
let text = Vdom.Node.text

(* Phosphor glow used for the title, section headers, and status dots. Matches
   the ported CRT theme's `.glow` (0 0 5px / 0 0 10px). *)
let glow color = raw "text-shadow" (Printf.sprintf "0 0 5px %s, 0 0 10px %s" color color)

(* Section header: uppercase title in glowing green, followed by a line
   that fills the rest of the row. *)
let section_header title =
  Vdom.Node.div
    ~attrs:
      [ style
          [ raw "display" "flex"
          ; raw "align-items" "center"
          ; raw "gap" "0.75rem"
          ; raw "margin" "2.5rem 0 1.5rem 0"
          ]
      ]
    [ Vdom.Node.span
        ~attrs:
          [ style
              [ raw "font-weight" "700"
              ; raw "font-size" "1.25rem"
              ; raw "letter-spacing" "0.12em"
              ; s_color Color.green
              ; glow Color.green_dim
              ]
          ]
        [ text title ]
    ]
;;

(* A shell prompt line: a teal/green "$" followed by the dimmed command text. *)
let prompt_line cmd =
  Vdom.Node.div
    ~attrs:[ style [ raw "margin-top" "1.25rem" ] ]
    [ Vdom.Node.span ~attrs:[ style [ s_color Color.teal ] ] [ text "$ " ]
    ; Vdom.Node.span ~attrs:[ style [ s_color Color.muted ] ] [ text cmd ]
    ]
;;

(* An ASCII-style progress bar: [ filled-blocks empty-blocks ]. The filled
   portion glows; the track is rendered with faint block characters. *)
let progress_bar ~percent ~width_chars =
  let percent = Int.max 0 (Int.min 100 percent) in
  let filled = percent * width_chars / 100 in
  let filled = Int.max (if percent > 0 then 1 else 0) filled in
  let empty = width_chars - filled in
  Vdom.Node.span
    ~attrs:[ style [ raw "white-space" "pre"; raw "letter-spacing" "-1px" ] ]
    [ Vdom.Node.span ~attrs:[ style [ s_color Color.muted ] ] [ text "[ " ]
    ; Vdom.Node.span
        ~attrs:[ style [ s_color Color.green; glow Color.green_dim ] ]
        [ text (String.make filled '#') ]
    ; Vdom.Node.span
        ~attrs:[ style [ s_color Color.faint ] ]
        [ text (String.make empty '#') ]
    ; Vdom.Node.span ~attrs:[ style [ s_color Color.muted ] ] [ text " ]" ]
    ]
;;

let view_header =
  Vdom.Node.div
    [ Vdom.Node.h1
        ~attrs:
          [ style
              [ mono
              ; raw "font-size" "2.25rem"
              ; raw "font-weight" "700"
              ; raw "margin" "0.5rem 0 0 0"
              ; s_color Color.green
              ; glow Color.green
              ]
          ]
        [ text "cheesegrater" ]
    ]
;;

(* Map an active-state to (accent colour, border colour, faint background)
   used to theme a service card and its status badge. *)
let service_theme = function
  | "active" -> Color.green, Color.faint, "rgba(74, 222, 128, 0.04)"
  | "failed" -> Color.red, "rgba(239, 68, 68, 0.35)", "rgba(239, 68, 68, 0.05)"
  | "inactive" -> Color.muted, Color.faint, "rgba(255,255,255,0.02)"
  | _ -> Color.amber, "rgba(212, 160, 23, 0.35)", "rgba(212, 160, 23, 0.05)"
;;

(* Render the "load: ... · file: ..." detail block on the right of a card,
   colouring the labels teal and the values dim. *)
let detail_pair label value =
  [ Vdom.Node.span ~attrs:[ style [ s_color Color.teal ] ] [ text label ]
  ; Vdom.Node.span ~attrs:[ style [ s_color Color.muted ] ] [ text value ]
  ]
;;

let view_service { Service.name
                 ; description
                 ; load_state
                 ; active_state
                 ; sub_state
                 ; unit_file_state
                 ; main_pid
                 ; active_since
                 }
  =
  let accent, border, bg = service_theme active_state in
  let state_label = Printf.sprintf "%s (%s)" active_state sub_state in
  (* Left-hand details: PID and "since" when present, joined by separators. *)
  let pid_since =
    List.concat
      [ (if String.( <> ) main_pid "0"
         then detail_pair "PID " (main_pid ^ "  ")
         else [])
      ; (if String.is_empty active_since
         then []
         else detail_pair "since " active_since)
      ]
  in
  let details =
    List.concat
      [ pid_since
      ; (if List.is_empty pid_since then [] else [ Vdom.Node.br () ])
      ; detail_pair "load: " (load_state ^ "  ")
      ; [ Vdom.Node.span ~attrs:[ style [ s_color Color.muted ] ] [ text "· " ] ]
      ; detail_pair "file: " unit_file_state
      ]
  in
  Vdom.Node.div
    ~attrs:
      [ style
          [ raw "display" "flex"
          ; raw "justify-content" "space-between"
          ; raw "align-items" "flex-start"
          ; raw "gap" "1.5rem"
          ; raw "flex-wrap" "wrap"
          ; raw "padding" "1.25rem 1.5rem"
          ; raw "margin-bottom" "1rem"
          ; raw "border" (Printf.sprintf "1px solid %s" border)
          ; raw "border-radius" "6px"
          ; raw "background" bg
          ]
      ]
    [ Vdom.Node.div
        ~attrs:[ style [ raw "min-width" "16rem" ] ]
        [ Vdom.Node.div
            ~attrs:
              [ style [ raw "display" "flex"; raw "align-items" "center"; raw "gap" "0.6rem" ] ]
            [ Vdom.Node.span
                ~attrs:
                  [ style
                      [ raw "width" "0.55rem"
                      ; raw "height" "0.55rem"
                      ; raw "border-radius" "50%"
                      ; raw "background" accent
                      ; glow accent
                      ]
                  ]
                []
            ; Vdom.Node.span
                ~attrs:[ style [ raw "font-weight" "700"; s_color Color.green_bright ] ]
                [ text name ]
            ]
        ; Vdom.Node.div
            ~attrs:[ style [ raw "margin-top" "0.4rem"; s_color Color.muted ] ]
            [ text description ]
        ]
    ; Vdom.Node.span
        ~attrs:
          [ style
              [ raw "align-self" "center"
              ; raw "padding" "0.25rem 0.75rem"
              ; raw "border" (Printf.sprintf "1px solid %s" accent)
              ; raw "border-radius" "4px"
              ; raw "white-space" "nowrap"
              ; s_color accent
              ]
          ]
        [ text state_label ]
    ; Vdom.Node.div
        ~attrs:[ style [ raw "flex" "1"; raw "min-width" "14rem"; raw "align-self" "center" ] ]
        details
    ]
;;

let view_services { Services_response.services } =
  Vdom.Node.div (List.map services ~f:view_service)
;;

(* Output line under a prompt, indented and in bright green. *)
let output_line nodes =
  Vdom.Node.div ~attrs:[ style [ raw "padding-left" "1.25rem"; raw "margin-top" "0.25rem" ] ] nodes
;;

let bright s = Vdom.Node.span ~attrs:[ style [ s_color Color.green_bright ] ] [ text s ]
let dim s = Vdom.Node.span ~attrs:[ style [ s_color Color.muted ] ] [ text s ]

(* A table cell with fixed alignment used by the df table. *)
let cell ~align ~color s =
  Vdom.Node.td
    ~attrs:
      [ style
          [ raw "text-align" align
          ; raw "padding" "0.35rem 0.75rem 0.35rem 0"
          ; raw "white-space" "nowrap"
          ; s_color color
          ]
      ]
    [ text s ]
;;

let view_disk_row { Mount.mount; size; used; avail; use_percent } =
  Vdom.Node.tr
    [ cell ~align:"left" ~color:Color.amber ("  " ^ mount)
    ; cell ~align:"right" ~color:Color.green_bright size
    ; cell ~align:"right" ~color:Color.green_bright used
    ; cell ~align:"right" ~color:Color.green_bright avail
    ; Vdom.Node.td
        ~attrs:[ style [ raw "padding" "0.35rem 0.75rem 0.35rem 0"; raw "width" "99%" ] ]
        [ progress_bar ~percent:use_percent ~width_chars:28 ]
    ; cell ~align:"right" ~color:Color.green_bright (Int.to_string use_percent ^ "%")
    ]
;;

let header_cell s =
  Vdom.Node.td
    ~attrs:
      [ style
          [ raw "text-align" "left"
          ; raw "padding" "0 0.75rem 0.35rem 0"
          ; raw "letter-spacing" "0.05em"
          ; s_color Color.muted
          ]
      ]
    [ text s ]
;;

(* A labeled progress-bar row: a fixed-width label, an ASCII bar, and the
   percentage. Used for the aggregate CPU, each CPU core, and memory so they
   share the same "graphics". *)
let labeled_bar ~label ~percent =
  output_line
    [ Vdom.Node.span
        ~attrs:
          [ style
              [ s_color Color.green_bright
              ; raw "display" "inline-block"
              ; raw "width" "5rem"
              ]
          ]
        [ text label ]
    ; progress_bar ~percent ~width_chars:28
    ; Vdom.Node.span
        ~attrs:[ style [ s_color Color.green_bright; raw "margin-left" "1rem" ] ]
        [ text (Int.to_string percent ^ "%") ]
    ]
;;

let view_system
  { System_response.uptime
  ; cpu_percent
  ; cpu_per_core
  ; cpu_model
  ; cpu_cores
  ; memory
  ; disks
  }
  =
  let df_header =
    Vdom.Node.tr
      [ header_cell "MOUNT"
      ; Vdom.Node.td ~attrs:[ style [ raw "text-align" "right"; raw "padding-right" "0.75rem"; s_color Color.muted ] ] [ text "SIZE" ]
      ; Vdom.Node.td ~attrs:[ style [ raw "text-align" "right"; raw "padding-right" "0.75rem"; s_color Color.muted ] ] [ text "USED" ]
      ; Vdom.Node.td ~attrs:[ style [ raw "text-align" "right"; raw "padding-right" "0.75rem"; s_color Color.muted ] ] [ text "AVAIL" ]
      ; Vdom.Node.td ~attrs:[ style [ s_color Color.muted ] ] [ text "USE%" ]
      ; Vdom.Node.td [ text "" ]
      ]
  in
  let per_core_bars =
    List.mapi cpu_per_core ~f:(fun i percent ->
      labeled_bar ~label:(Printf.sprintf "cpu%d" i) ~percent)
  in
  let mem = memory in
  Vdom.Node.div
    [ prompt_line "uptime --pretty"
    ; output_line [ bright uptime ]
    ; prompt_line "top -bn1 (press 1 for per-core)"
    ; labeled_bar ~label:"CPU" ~percent:cpu_percent
    ; Vdom.Node.div per_core_bars
    ; output_line [ dim (Printf.sprintf "%s (%d cores)" cpu_model cpu_cores) ]
    ; prompt_line "free -h"
    ; labeled_bar ~label:"MEM" ~percent:mem.Memory.use_percent
    ; output_line
        [ dim
            (Printf.sprintf
               "%s used / %s total · %s free"
               mem.Memory.used
               mem.Memory.total
               mem.Memory.free)
        ]
    ; prompt_line "df -h"
    ; Vdom.Node.div
        ~attrs:[ style [ raw "padding-left" "1.25rem"; raw "margin-top" "0.5rem" ] ]
        [ Vdom.Node.table
            ~attrs:
              [ style
                  [ raw "border-collapse" "collapse"
                  ; raw "width" "100%"
                  ; mono
                  ]
              ]
            (df_header :: List.map disks ~f:view_disk_row)
        ]
    ]
;;

let view_commits { Commits_response.last_pulled = _; commits } =
  let commit_row { Commit.sha; message } =
    Vdom.Node.div
      ~attrs:
        [ style
            [ raw "display" "flex"
            ; raw "align-items" "baseline"
            ; raw "gap" "1.5rem"
            ; raw "padding" "0.6rem 0"
            ; raw "border-bottom" (Printf.sprintf "1px solid %s" Color.faint)
            ]
        ]
      [ Vdom.Node.span
          ~attrs:[ style [ raw "font-weight" "700"; raw "min-width" "5rem"; s_color Color.amber ] ]
          [ text (String.prefix sha 7) ]
      ; Vdom.Node.span ~attrs:[ style [ s_color Color.green_bright ] ] [ text message ]
      ]
  in
  Vdom.Node.div
    [ prompt_line "git log --oneline -5"
    ; Vdom.Node.div
        ~attrs:[ style [ raw "padding-left" "1.25rem"; raw "margin-top" "0.5rem" ] ]
        (List.map commits ~f:commit_row)
    ]
;;

(* Footer: [ cheesegrater :: home lab status :: nixos ] centred and dimmed,
   with the first and last words highlighted. *)
let view_footer =
  Vdom.Node.div
    ~attrs:
      [ style
          [ raw "text-align" "center"
          ; raw "margin" "4rem 0 2rem 0"
          ; s_color Color.muted
          ]
      ]
    [ dim "[ "
    ; Vdom.Node.span ~attrs:[ style [ raw "font-weight" "700"; s_color Color.green ] ] [ text "cheesegrater" ]
    ; dim " :: home lab status :: "
    ; Vdom.Node.span ~attrs:[ style [ raw "font-weight" "700"; s_color Color.green ] ] [ text "nixos" ]
    ; dim " ]"
    ]
;;

let loading_text =
  Vdom.Node.div
    ~attrs:[ style [ raw "padding" "0.5rem 0"; s_color Color.muted ] ]
    [ text "Loading..." ]
;;

let error_text msg =
  Vdom.Node.div
    ~attrs:[ style [ raw "padding" "0.5rem 0"; s_color Color.red ] ]
    [ text ("Error: " ^ msg) ]
;;

let section ~view = function
  | None -> loading_text
  | Some (Error msg) -> error_text msg
  | Some (Ok response) -> view response
;;

let fetch_section fetch graph =
  let data, set_data =
    Bonsai.state None ~sexp_of_model:[%sexp_of: opaque] ~equal:phys_equal graph
  in
  let on_activate =
    let%arr set_data in
    let open Effect.Let_syntax in
    let%bind result = fetch () in
    set_data (Some result)
  in
  let () = Bonsai.Edge.lifecycle ~on_activate graph in
  data
;;

let component graph =
  let commits = fetch_section fetch_commits graph in
  let services = fetch_section fetch_services graph in
  let system = fetch_section fetch_system graph in
  let%arr commits and services and system in
  Vdom.Node.div
    ~attrs:
      [ style
          [ mono
          ; raw "max-width" "56rem"
          ; raw "margin" "0 auto"
          ; raw "padding" "3rem 2rem"
          ; s_color Color.green
          ]
      ]
    [ view_header
    ; section_header "SERVICES"
    ; section ~view:view_services services
    ; section_header "SYSTEM RESOURCES"
    ; section ~view:view_system system
    ; section_header "RECENT COMMITS"
    ; section ~view:view_commits commits
    ; view_footer
    ]
;;

let () = Bonsai_web.Start.start component
