open Base

(* ─── Types ─────────────────────────────────────────────────────────── *)

(** A validated configuration: an ordered map of field names to values.
    We keep a separate ordered list so the output preserves field order. *)
type t = {
  fields : (string, Schema.field_value, String.comparator_witness) Map.t;
  order  : string list;  (** insertion-order of field names *)
}

let empty = {
  fields = Map.empty (module String);
  order  = [];
}

(* ─── Building a config from sexps + schema ─────────────────────────── *)

(** Parse and validate a list of [(key value)] sexps against a schema.
    Returns a config or a list of errors. *)
let of_sexps ~(schema : Schema.t) (sexps : Sexplib.Sexp.t list)
  : (t, string) Result.t =
  let rec loop fields order errors = function
    | [] ->
      if List.is_empty errors
      then Ok { fields; order = List.rev order }
      else Error (String.concat ~sep:"\n" (List.rev errors))
    | Sexplib.Sexp.List [ Sexplib.Sexp.Atom k; v ] :: rest ->
      (match Map.find schema.lookup k with
       | None ->
         let err = Printf.sprintf "Unknown field '%s' (not in schema)" k in
         loop fields order (err :: errors) rest
       | Some entry ->
         (match Schema.validate_value entry v with
          | Ok fv ->
            let fields' = Map.set fields ~key:k ~data:fv in
            let order' =
              if Map.mem fields k then order  (* already present in order *)
              else k :: order
            in
            loop fields' order' errors rest
          | Error e ->
            loop fields order (e :: errors) rest))
    | other :: rest ->
      let err = Printf.sprintf "Malformed config entry: %s"
                  (Sexplib.Sexp.to_string other) in
      loop fields order (err :: errors) rest
  in
  loop (Map.empty (module String)) [] [] sexps

(** Load a config from a file, validating against the given schema. *)
let load_file ~schema path =
  try
    let sexps = Sexplib.Sexp.load_sexps path in
    (* Handle the common case where a file contains one top-level list
       wrapping the field entries, e.g. ((account FOO)(nodes 2)) *)
    let unwrapped = match sexps with
      | [ Sexplib.Sexp.List (Sexplib.Sexp.List _ :: _ as inner) ] -> inner
      | raw -> raw
    in
    of_sexps ~schema unwrapped
  with
  | Sys_error msg -> Error (Printf.sprintf "Cannot read config: %s" msg)

(** Merge two configs: values in [overrides] replace those in [base].
    New fields from [overrides] are appended to the end. *)
let merge ~(base : t) ~(overrides : t) : t =
  let fields =
    Map.merge_skewed base.fields overrides.fields
      ~combine:(fun ~key:_ _base_v override_v -> override_v)
  in
  (* Preserve base order, then append any new keys from overrides *)
  let new_keys =
    List.filter overrides.order ~f:(fun k -> not (Map.mem base.fields k))
  in
  let order = base.order @ new_keys in
  { fields; order }

(** Remove a list of keys from the config. *)
let remove_keys (cfg : t) (keys : string list) : t =
  let key_set = Set.of_list (module String) keys in
  let fields = Map.filter_keys cfg.fields ~f:(fun k -> not (Set.mem key_set k)) in
  let order = List.filter cfg.order ~f:(fun k -> not (Set.mem key_set k)) in
  { fields; order }

(* ─── Rendering ─────────────────────────────────────────────────────── *)

(** Render a single field value as the string that goes after the '='
    in an #SBATCH directive. *)
let render_value = function
  | Schema.V_string s -> s
  | Schema.V_int n    -> Int.to_string n
  | Schema.V_size s   -> s
  | Schema.V_email s  -> s
  | Schema.V_enum s   -> s
  | Schema.V_time (h, m, s) ->
    Printf.sprintf "%d:%02d:%02d" h m s

(** Render the full set of #SBATCH lines, respecting field order. *)
let render (cfg : t) : string =
  cfg.order
  |> List.filter_map ~f:(fun key ->
    match Map.find cfg.fields key with
    | None   -> None
    | Some v -> Some (Printf.sprintf "#SBATCH --%s=%s" key (render_value v)))
  |> String.concat ~sep:"\n"
  |> fun s -> s ^ "\n"
