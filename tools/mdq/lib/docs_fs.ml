open! Core
open! Async

let index_file = "index.md"

(* Turn the folder paths given on the command line into [Docs.root]s.

   A single folder is mounted at ["/"]. Several folders are mounted under
   ["/<basename>"] so they live side by side; the top level then lists the
   folders themselves. Duplicate basenames are disambiguated with a numeric
   suffix so each mount point stays unique. *)
let roots_of_paths paths : Docs.root list =
  let single = List.length paths = 1 in
  let used = String.Table.create () in
  let unique_name base =
    let rec pick candidate n =
      if Hashtbl.mem used candidate
      then pick (sprintf "%s-%d" base n) (n + 1)
      else (
        Hashtbl.set used ~key:candidate ~data:();
        candidate)
    in
    pick base 1
  in
  List.map paths ~f:(fun path ->
    let fs_path = Filename_unix.realpath path in
    let base = Filename.basename fs_path in
    let name = unique_name base in
    let url_base = if single then "/" else "/" ^ name in
    { Docs.name; url_base; fs_path })
;;

(* Split a URL path into clean segments, dropping empties and rejecting any
   traversal attempt. Returns [None] if a [.] or [..] segment is present. *)
let segments_of_path path =
  let raw = String.split path ~on:'/' |> List.filter ~f:(fun s -> not (String.is_empty s)) in
  if List.exists raw ~f:(fun s -> String.( = ) s "." || String.( = ) s "..")
  then None
  else Some raw
;;

(* Match the leading segment(s) against a root, returning the root and the
   segments relative to it. A single root (mounted at ["/"]) swallows every
   path; multiple roots are selected by their first segment. *)
let select_root (roots : Docs.root list) segments =
  match roots with
  | [ single ] -> Some (single, segments)
  | _ ->
    (match segments with
     | [] -> None
     | prefix :: rest ->
       List.find_map roots ~f:(fun root ->
         if String.( = ) root.Docs.url_base ("/" ^ prefix) then Some (root, rest) else None))
;;

(* Join a URL base with extra segments into a normalized URL path. *)
let join_url base segments =
  match segments with
  | [] -> base
  | _ ->
    let suffix = String.concat ~sep:"/" segments in
    if String.( = ) base "/" then "/" ^ suffix else base ^ "/" ^ suffix
;;

let strip_md name = String.chop_suffix name ~suffix:".md" |> Option.value ~default:name

(* Read just the frontmatter [type] and [tags] of a markdown file. Used to
   annotate listing entries and to find pages matching a tag/type query. *)
let read_meta fs_file =
  let%map md = Reader.file_contents fs_file in
  let frontmatter, _body = Frontmatter.split md in
  let type_ = Frontmatter.items frontmatter ~key:"type" in
  let tags = Frontmatter.items frontmatter ~key:"tags" in
  type_, tags
;;

let render_page ~fallback fs_file =
  let%map md = Reader.file_contents fs_file in
  let frontmatter, body = Frontmatter.split md in
  (* A [title] field in the frontmatter wins; otherwise fall back to the first
     H1 in the body, then to the file name. *)
  let title =
    match Frontmatter.find frontmatter ~key:"title" with
    | Some title when not (String.is_empty (String.strip title)) -> title
    | _ -> Markdown.title ~fallback body
  in
  Docs.Page { title; frontmatter; html = Markdown.to_html body }
;;

(* List a directory: subdirectories first, then markdown files (excluding the
   index, which is served as the directory itself), both sorted by name. *)
let render_listing ~(root : Docs.root) ~rel_segments ~title fs_dir =
  let base_url = join_url root.Docs.url_base rel_segments in
  let%bind names = Sys.ls_dir fs_dir in
  let names = List.sort names ~compare:String.compare in
  let%map entries =
    Deferred.List.filter_map names ~how:`Sequential ~f:(fun name ->
      let child = Filename.concat fs_dir name in
      match%bind Sys.is_directory child with
      | `Yes ->
        return
          (Some
             { Docs.name
             ; path = join_url base_url [ name ]
             ; kind = Docs.Dir
             ; type_ = []
             ; tags = []
             })
      | `No | `Unknown ->
        if String.( = ) name index_file || not (String.is_suffix name ~suffix:".md")
        then return None
        else (
          let stem = strip_md name in
          let%map type_, tags = read_meta child in
          Some
            { Docs.name = stem
            ; path = join_url base_url [ stem ]
            ; kind = Docs.Page
            ; type_
            ; tags
            }))
  in
  Docs.Listing { title; entries }
;;

(* Resolve URL segments within a root to page or listing content.

   Mirrors a static server's index heuristic:
   - a directory with [index.md] renders that file;
   - a directory without one renders a listing;
   - a bare path [foo] renders the file [foo.md].
*)
let resolve_in_root ~(root : Docs.root) ~rel_segments =
  let fs_target = List.fold rel_segments ~init:root.Docs.fs_path ~f:Filename.concat in
  match%bind Sys.is_directory fs_target with
  | `Yes ->
    let index = Filename.concat fs_target index_file in
    (match%bind Sys.file_exists index with
     | `Yes ->
       let fallback = if List.is_empty rel_segments then root.Docs.name else List.last_exn rel_segments in
       render_page ~fallback index
     | `No | `Unknown ->
       let title = if List.is_empty rel_segments then root.Docs.name else List.last_exn rel_segments in
       render_listing ~root ~rel_segments ~title fs_target)
  | `No | `Unknown ->
    (* Accept both the clean URL [foo] and an explicit [foo.md]. The latter is
       what relative links inside a rendered document point at, so honoring it
       keeps in-page navigation working. *)
    let md_file = if String.is_suffix fs_target ~suffix:".md" then fs_target else fs_target ^ ".md" in
    (match%bind Sys.file_exists md_file with
     | `Yes ->
       let fallback = List.last rel_segments |> Option.value ~default:root.Docs.name in
       render_page ~fallback md_file
     | `No | `Unknown -> return Docs.Not_found)
;;

(* Top-level listing of the configured folders, shown when more than one folder
   is served and the request is for ["/"]. *)
let roots_listing (roots : Docs.root list) =
  let entries =
    List.map roots ~f:(fun root ->
      { Docs.name = root.Docs.name
      ; path = root.Docs.url_base
      ; kind = Docs.Dir
      ; type_ = []
      ; tags = []
      })
  in
  Docs.Listing { title = "docs"; entries }
;;

(* Walk a root's tree and yield an [entry] for every markdown page (index
   files included), carrying its frontmatter type/tags. Directories are
   traversed but not themselves emitted — the query view lists pages, not
   folders. Used to build the tag/type browse pages. *)
let walk_pages (root : Docs.root) =
  let rec go ~fs_dir ~rel_segments =
    match%bind Sys.is_directory fs_dir with
    | `No | `Unknown -> return []
    | `Yes ->
      let%bind names = Sys.ls_dir fs_dir in
      let names = List.sort names ~compare:String.compare in
      let%map nested =
        Deferred.List.map names ~how:`Sequential ~f:(fun name ->
          let child = Filename.concat fs_dir name in
          match%bind Sys.is_directory child with
          | `Yes -> go ~fs_dir:child ~rel_segments:(rel_segments @ [ name ])
          | `No | `Unknown ->
            if not (String.is_suffix name ~suffix:".md")
            then return []
            else (
              let%map type_, tags = read_meta child in
              (* [index.md] represents its directory, so its clean URL is the
                 directory path; other files drop the [.md] suffix. *)
              let page_segments =
                if String.( = ) name index_file
                then rel_segments
                else rel_segments @ [ strip_md name ]
              in
              let display =
                match List.last page_segments with
                | Some s -> s
                | None -> root.Docs.name
              in
              [ { Docs.name = display
                ; path = join_url root.Docs.url_base page_segments
                ; kind = Docs.Page
                ; type_
                ; tags
                }
              ]))
      in
      List.concat nested
  in
  go ~fs_dir:root.Docs.fs_path ~rel_segments:[]
;;

(* Collect every page across all roots whose frontmatter field [key] contains
   [value] (case-insensitively), and present them as a listing. *)
let query_pages (roots : Docs.root list) ~key ~value =
  let wanted = String.lowercase (String.strip value) in
  let%map per_root = Deferred.List.map roots ~how:`Sequential ~f:walk_pages in
  let entries =
    List.concat per_root
    |> List.filter ~f:(fun (entry : Docs.entry) ->
      let field =
        match key with
        | "tags" -> entry.Docs.tags
        | "type" -> entry.Docs.type_
        | _ -> []
      in
      List.exists field ~f:(fun item ->
        String.equal (String.lowercase (String.strip item)) wanted))
  in
  let title = sprintf "%s: %s" key value in
  Docs.Listing { title; entries }
;;

let create ~paths : Docs.t =
  let roots = roots_of_paths paths in
  let resolve url_path =
    match segments_of_path url_path with
    | None -> return Docs.Not_found
    | Some segments ->
      (match select_root roots segments with
       | None ->
         (* No root matched. With multiple roots an empty path lists them;
            anything else is a miss. *)
         if List.is_empty segments then return (roots_listing roots) else return Docs.Not_found
       | Some (root, rel_segments) -> resolve_in_root ~root ~rel_segments)
  in
  let query ~key ~value = query_pages roots ~key ~value in
  { Docs.roots = (fun () -> roots); resolve; query }
;;
