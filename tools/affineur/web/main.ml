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
end

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
    ~attrs:[ Vdom.Attr.style Style.container ]
    [ Vdom.Node.h1 [ Vdom.Node.text "cheesegrater" ]
    ; Vdom.Node.p
        ~attrs:[ Vdom.Attr.style Style.subtitle ]
        [ Vdom.Node.text ("Last pulled: " ^ last_pulled) ]
    ; Vdom.Node.h2 [ Vdom.Node.text "Recent commits" ]
    ; Vdom.Node.table
        ~attrs:[ Vdom.Attr.style Style.table ]
        commit_rows
    ]
;;

let component graph =
  let data, set_data =
    Bonsai.state
      (None : (Commits_response.t, string) Result.t option)
      ~sexp_of_model:[%sexp_of: opaque]
      ~equal:phys_equal
      graph
  in
  let on_activate =
    let%arr set_data in
    let open Effect.Let_syntax in
    let%bind result = fetch_commits () in
    set_data (Some result)
  in
  let () = Bonsai.Edge.lifecycle ~on_activate graph in
  let%arr data in
  match data with
  | None ->
    Vdom.Node.div
      ~attrs:[ Vdom.Attr.style Style.container ]
      [ Vdom.Node.text "Loading..." ]
  | Some (Error msg) ->
    Vdom.Node.div
      ~attrs:[ Vdom.Attr.style (Css_gen.color (`Name "red")) ]
      [ Vdom.Node.text ("Error: " ^ msg) ]
  | Some (Ok response) -> view_commits response
;;

let () = Bonsai_web.Start.start component
