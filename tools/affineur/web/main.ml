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
    (* The server returns git failures as a 200 with an "error" field rather
       than a non-2xx status (whose body the client cannot read). Surface it. *)
    (match json |> member "error" with
     | `String msg -> failwith msg
     | _ -> ());
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
    (* The server returns failures as a 200 with an "error" field rather than a
       non-2xx status (whose body the client cannot read). Surface it. *)
    (match json |> member "error" with
     | `String msg -> failwith msg
     | _ -> ());
    { services = json |> member "services" |> to_list |> List.map ~f:Service.of_json }
  ;;
end

let fetch_commits =
  Effect.of_deferred_fun (fun () ->
    let open Async_kernel in
    let%map.Deferred result = Async_js.Http.get "/api/commits" in
    match result with
    | Error err -> Error (Error.to_string_hum err)
    | Ok body ->
      (try Ok (Commits_response.of_json_string body) with
       | exn -> Error (Exn.to_string exn)))
;;

let fetch_services =
  Effect.of_deferred_fun (fun () ->
    let open Async_kernel in
    let%map.Deferred result = Async_js.Http.get "/api/services" in
    match result with
    | Error err -> Error (Error.to_string_hum err)
    | Ok body ->
      (try Ok (Services_response.of_json_string body) with
       | exn -> Error (Exn.to_string exn)))
;;

module Style = struct
  let container =
    Css_gen.concat
      [ Css_gen.font_family [ "system-ui"; "sans-serif" ]
      ; Css_gen.padding ~top:(`Rem 2.) ~left:(`Rem 2.) ~right:(`Rem 2.) ()
      ; Css_gen.max_width (`Rem 50.)
      ]
  ;;

  let subtitle = Css_gen.color (`Name "#666")

  let sha =
    Css_gen.concat
      [ Css_gen.font_family [ "monospace" ]
      ; Css_gen.padding ~right:(`Rem 1.) ()
      ; Css_gen.color (`Name "#6f42c1")
      ]
  ;;

  let table =
    Css_gen.concat
      [ Css_gen.border_collapse `Collapse
      ; Css_gen.create ~field:"width" ~value:"100%"
      ]
  ;;

  let row =
    Css_gen.concat
      [ Css_gen.padding ~top:(`Px 4) ~bottom:(`Px 4) ()
      ; Css_gen.create ~field:"border-bottom" ~value:"1px solid #eee"
      ]
  ;;

  let service_name =
    Css_gen.concat
      [ Css_gen.font_family [ "monospace" ]; Css_gen.padding ~right:(`Rem 1.) () ]
  ;;

  let muted = Css_gen.color (`Name "#999")

  let badge ~bg ~fg =
    Css_gen.concat
      [ Css_gen.create ~field:"display" ~value:"inline-block"
      ; Css_gen.padding ~top:(`Px 2) ~bottom:(`Px 2) ~left:(`Px 8) ~right:(`Px 8) ()
      ; Css_gen.create ~field:"border-radius" ~value:"4px"
      ; Css_gen.create ~field:"font-size" ~value:"0.85rem"
      ; Css_gen.background_color (`Name bg)
      ; Css_gen.color (`Name fg)
      ]
  ;;

  (* Colour the active-state badge: green for active, grey for inactive,
     red for failed, amber for anything else. *)
  let badge_for_active_state = function
    | "active" -> badge ~bg:"#e6f4ea" ~fg:"#137333"
    | "inactive" -> badge ~bg:"#f1f3f4" ~fg:"#5f6368"
    | "failed" -> badge ~bg:"#fce8e6" ~fg:"#c5221f"
    | _ -> badge ~bg:"#fef7e0" ~fg:"#b06000"
  ;;
end

let error_text msg =
  Vdom.Node.p
    ~attrs:[ Vdom.Attr.style (Css_gen.color (`Name "red")) ]
    [ Vdom.Node.text ("Error: " ^ msg) ]
;;

let loading_text = Vdom.Node.p ~attrs:[ Vdom.Attr.style Style.subtitle ] [ Vdom.Node.text "Loading..." ]

let view_commits { Commits_response.last_pulled; commits } =
  let commit_rows =
    List.map commits ~f:(fun { Commit.sha; message } ->
      Vdom.Node.tr
        ~attrs:[ Vdom.Attr.style Style.row ]
        [ Vdom.Node.td
            ~attrs:[ Vdom.Attr.style Style.sha ]
            [ Vdom.Node.text (String.prefix sha 7) ]
        ; Vdom.Node.td [ Vdom.Node.text message ]
        ])
  in
  Vdom.Node.div
    [ Vdom.Node.p
        ~attrs:[ Vdom.Attr.style Style.subtitle ]
        [ Vdom.Node.text ("Last pulled: " ^ last_pulled) ]
    ; Vdom.Node.h2 [ Vdom.Node.text "Recent commits" ]
    ; Vdom.Node.table ~attrs:[ Vdom.Attr.style Style.table ] commit_rows
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
  (* Show the active/sub state together (e.g. "active (running)"), which is the
     summary systemctl prints at the top of `systemctl status`. *)
  let state_label = Printf.sprintf "%s (%s)" active_state sub_state in
  let detail_bits =
    List.filter_opt
      [ (if String.( <> ) main_pid "0" then Some ("PID " ^ main_pid) else None)
      ; (if String.is_empty active_since then None else Some ("since " ^ active_since))
      ; Some ("load: " ^ load_state)
      ; Some ("file: " ^ unit_file_state)
      ]
  in
  Vdom.Node.tr
    ~attrs:[ Vdom.Attr.style Style.row ]
    [ Vdom.Node.td
        ~attrs:[ Vdom.Attr.style Style.service_name ]
        [ Vdom.Node.div [ Vdom.Node.text name ]
        ; Vdom.Node.div ~attrs:[ Vdom.Attr.style Style.muted ] [ Vdom.Node.text description ]
        ]
    ; Vdom.Node.td
        [ Vdom.Node.span
            ~attrs:[ Vdom.Attr.style (Style.badge_for_active_state active_state) ]
            [ Vdom.Node.text state_label ]
        ]
    ; Vdom.Node.td
        ~attrs:[ Vdom.Attr.style Style.muted ]
        [ Vdom.Node.text (String.concat ~sep:" · " detail_bits) ]
    ]
;;

let view_services { Services_response.services } =
  Vdom.Node.div
    [ Vdom.Node.h2 [ Vdom.Node.text "Services" ]
    ; Vdom.Node.table
        ~attrs:[ Vdom.Attr.style Style.table ]
        (List.map services ~f:view_service)
    ]
;;

let section ~view = function
  | None -> loading_text
  | Some (Error msg) -> error_text msg
  | Some (Ok response) -> view response
;;

let fetch_section fetch graph =
  let data, set_data =
    Bonsai.state
      None
      ~sexp_of_model:[%sexp_of: opaque]
      ~equal:phys_equal
      graph
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
  let%arr commits and services in
  Vdom.Node.div
    ~attrs:[ Vdom.Attr.style Style.container ]
    [ Vdom.Node.h1 [ Vdom.Node.text "cheesegrater" ]
    ; section ~view:view_services services
    ; section ~view:view_commits commits
    ]
;;

let () = Bonsai_web.Start.start component
