open! Core

(* Render a CommonMark string to an HTML fragment.

   [safe:true] tells cmarkit to drop raw HTML blocks and unsafe link schemes
   (e.g. [javascript:]). The fragment is injected verbatim into the SPA via
   virtual_dom's [inner_html], so the markdown source is the only thing we
   trust here; keeping the renderer safe prevents a doc author (or a stray
   file on disk) from injecting script into the page. *)
let to_html md =
  (* [strict:false] enables the GFM extensions docs commonly use: tables,
     strikethrough, task lists, and footnotes. *)
  let doc = Cmarkit.Doc.of_string ~strict:false md in
  Cmarkit_html.of_doc ~safe:true doc
;;

(* Derive a page title from markdown: the first ATX/Setext H1 if present,
   otherwise the supplied fallback (usually the file name). *)
let title ~fallback md =
  let from_atx line =
    match String.lsplit2 (String.lstrip line) ~on:' ' with
    | Some ("#", rest) -> Some (String.strip rest)
    | _ -> None
  in
  String.split_lines md |> List.find_map ~f:from_atx |> Option.value ~default:fallback
;;
