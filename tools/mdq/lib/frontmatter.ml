open! Core

(* YAML frontmatter: an optional metadata block fenced by [---] lines at the
   very top of a markdown file, e.g.

   {v
   ---
   title: Getting started
   tags: [docs, intro]
   ---
   # Body starts here
   v}

   This mirrors the convention used by Jekyll, Hugo, and most static site
   generators. We parse the block into a list of fields and hand the remaining
   markdown body back to the caller untouched. *)

(* A single frontmatter field. [value] is a display string: scalars render as
   themselves, sequences and mappings are flattened to a compact one-line form
   so a listing can show them without committing to a nested layout. *)
type field =
  { key : string
  ; value : string
  }

type t = field list

(* Flatten a parsed YAML value to a single-line display string. Scalars pass
   through; sequences become [a, b, c]; mappings become [k: v, k: v]. This is
   only for presentation — the structure is not preserved. *)
let rec value_to_string (value : Yaml.value) =
  match value with
  | `Null -> ""
  | `Bool b -> Bool.to_string b
  | `Float f ->
    (* Render integers without a trailing [.] so [3] doesn't show as [3.]. *)
    if Float.equal (Float.round_down f) f && Float.is_finite f
    then Int.to_string (Float.to_int f)
    else Float.to_string f
  | `String s -> s
  | `A items -> String.concat ~sep:", " (List.map items ~f:value_to_string)
  | `O pairs ->
    String.concat
      ~sep:", "
      (List.map pairs ~f:(fun (k, v) -> sprintf "%s: %s" k (value_to_string v)))
;;

(* Turn a top-level YAML mapping into ordered fields. A non-mapping document
   (e.g. a bare scalar or list) has no named keys, so it yields no fields. *)
let fields_of_yaml (value : Yaml.value) : t =
  match value with
  | `O pairs -> List.map pairs ~f:(fun (key, v) -> { key; value = value_to_string v })
  | _ -> []
;;

(* If [md] opens with a [---] fence, split out the YAML block and return the
   parsed fields alongside the remaining body. Otherwise return no fields and
   the input unchanged.

   The opening fence must be the very first line. The block ends at the next
   line that is exactly [---] (or [...], YAML's document-end marker). An
   unterminated or unparseable block is treated as ordinary content rather than
   an error, so a stray [---] never blanks a page. *)
let split md : t * string =
  let lines = String.split_lines md in
  match lines with
  | first :: rest when String.equal (String.strip first) "---" ->
    let is_closing line =
      let s = String.strip line in
      String.equal s "---" || String.equal s "..."
    in
    (match List.findi rest ~f:(fun _ line -> is_closing line) with
     | None -> [], md
     | Some (idx, _) ->
       let yaml_lines = List.take rest idx in
       let body_lines = List.drop rest (idx + 1) in
       let yaml_src = String.concat ~sep:"\n" yaml_lines in
       let body = String.concat ~sep:"\n" body_lines in
       (match Yaml.of_string yaml_src with
        | Ok value -> fields_of_yaml value, body
        | Error _ -> [], md))
  | _ -> [], md
;;

(* The value of a field by key, if present. Used to let frontmatter override
   the derived page title. *)
let find (t : t) ~key =
  List.find_map t ~f:(fun field ->
    if String.equal field.key key then Some field.value else None)
;;
