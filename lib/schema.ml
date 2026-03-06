open Base

(* ─── Types ─────────────────────────────────────────────────────────── *)

(** The types a field can have — checked at runtime. *)
type field_type =
  | T_string
  | T_int
  | T_size          (** memory/size: <int>[K|M|G|T]  e.g. 16G, 512M *)
  | T_email
  | T_time          (** (HH MM SS) triple *)
  | T_enum of string list

(** A runtime value, tagged with its type. *)
type field_value =
  | V_string of string
  | V_int    of int
  | V_size   of string     (** validated size string, e.g. "16G" *)
  | V_email  of string     (** already validated *)
  | V_time   of int * int * int
  | V_enum   of string

(** One entry in the schema. *)
type entry = {
  name  : string;
  ftype : field_type;
}

(** A loaded schema: the ordered list of entries + a name→entry lookup. *)
type t = {
  entries : entry list;
  lookup  : (string, entry, String.comparator_witness) Map.t;
}

(* ─── Email validation ──────────────────────────────────────────────── *)

let email_re =
  Str.regexp
    {|^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z][A-Za-z0-9]*$|}

let validate_email s =
  if Str.string_match email_re s 0
  then Ok s
  else Error (Printf.sprintf "Invalid e-mail address: %S" s)

(* ─── Size validation (e.g. 16G, 512M, 1T, 2048) ───────────────────── *)

let size_re = Str.regexp {|^[0-9]+[KMGTkmgt]?$|}

let validate_size s =
  if Str.string_match size_re s 0
  then Ok (String.uppercase s)
  else Error (Printf.sprintf
    "Invalid size %S — expected an integer with optional unit suffix K/M/G/T \
     (e.g. 16G, 512M, 4096)" s)

(* ─── Parsing the schema file ───────────────────────────────────────── *)

(** Parse a type specifier sexp into a [field_type].
    Accepted shapes:
    - [string], [int], [email], [time]
    - [(enum ALL BEGIN END FAIL NONE)] *)
let field_type_of_sexp = function
  | Sexplib.Sexp.Atom "string"  -> Ok T_string
  | Sexplib.Sexp.Atom "int"     -> Ok T_int
  | Sexplib.Sexp.Atom "size"    -> Ok T_size
  | Sexplib.Sexp.Atom "email"   -> Ok T_email
  | Sexplib.Sexp.Atom "time"    -> Ok T_time
  | Sexplib.Sexp.List (Sexplib.Sexp.Atom "enum" :: opts) ->
    let names =
      List.filter_map opts ~f:(function
        | Sexplib.Sexp.Atom s -> Some s
        | _ -> None)
    in
    if List.is_empty names
    then Error "enum type requires at least one variant"
    else Ok (T_enum names)
  | other ->
    Error (Printf.sprintf "Unknown type specifier: %s"
             (Sexplib.Sexp.to_string other))

(** Parse one [(field NAME TYPE)] sexp. *)
let entry_of_sexp = function
  | Sexplib.Sexp.List [ Sexplib.Sexp.Atom "field";
                         Sexplib.Sexp.Atom name;
                         type_sexp ] ->
    (match field_type_of_sexp type_sexp with
     | Ok ftype -> Ok { name; ftype }
     | Error e  -> Error (Printf.sprintf "Field '%s': %s" name e))
  | other ->
    Error (Printf.sprintf "Malformed schema entry: %s"
             (Sexplib.Sexp.to_string other))

(** Load a schema from a list of sexps (the contents of schema.sexp). *)
let of_sexps sexps =
  let entries_result =
    List.fold sexps ~init:(Ok []) ~f:(fun acc sexp ->
      match acc, entry_of_sexp sexp with
      | Ok es, Ok e   -> Ok (e :: es)
      | Error e, _    -> Error e
      | _, Error e     -> Error e)
  in
  match entries_result with
  | Error e -> Error e
  | Ok rev_entries ->
    let entries = List.rev rev_entries in
    let lookup =
      List.fold entries
        ~init:(Map.empty (module String))
        ~f:(fun m e -> Map.set m ~key:e.name ~data:e)
    in
    Ok { entries; lookup }

(** Load a schema from a file. *)
let load_file path =
  try
    let sexps = Sexplib.Sexp.load_sexps path in
    of_sexps sexps
  with
  | Sys_error msg -> Error (Printf.sprintf "Cannot read schema: %s" msg)

(* ─── Value validation ──────────────────────────────────────────────── *)

(** Validate a sexp value against a schema entry. *)
let validate_value (entry : entry) (sexp : Sexplib.Sexp.t) : (field_value, string) Result.t =
  match entry.ftype, sexp with
  | T_int, Sexplib.Sexp.Atom s ->
    (match Int.of_string_opt s with
     | Some n -> Ok (V_int n)
     | None ->
       Error (Printf.sprintf "Field '%s': expected int, got %S" entry.name s))
  | T_string, Sexplib.Sexp.Atom s ->
    Ok (V_string s)
  | T_size, Sexplib.Sexp.Atom s ->
    (match validate_size s with
     | Ok v  -> Ok (V_size v)
     | Error e -> Error (Printf.sprintf "Field '%s': %s" entry.name e))
  | T_email, Sexplib.Sexp.Atom s ->
    (match validate_email s with
     | Ok addr -> Ok (V_email addr)
     | Error e -> Error (Printf.sprintf "Field '%s': %s" entry.name e))
  | T_time, Sexplib.Sexp.List [ Sexplib.Sexp.Atom h;
                                  Sexplib.Sexp.Atom m;
                                  Sexplib.Sexp.Atom s ] ->
    (match Int.of_string_opt h, Int.of_string_opt m, Int.of_string_opt s with
     | Some hh, Some mm, Some ss -> Ok (V_time (hh, mm, ss))
     | _ ->
       Error (Printf.sprintf
                "Field '%s': expected (INT INT INT) for time, got %s"
                entry.name (Sexplib.Sexp.to_string sexp)))
  | T_enum opts, Sexplib.Sexp.Atom s ->
    let s_up = String.uppercase s in
    if List.mem opts s_up ~equal:String.equal
    then Ok (V_enum s_up)
    else Error (Printf.sprintf "Field '%s': expected one of [%s], got %S"
                  entry.name (String.concat ~sep:", " opts) s)
  | _, _ ->
    Error (Printf.sprintf "Field '%s': type mismatch (got %s)"
             entry.name (Sexplib.Sexp.to_string sexp))

(* ─── Field-type description (for error messages / help) ────────────── *)

let describe_type = function
  | T_string  -> "string"
  | T_int     -> "int"
  | T_size    -> "size (e.g. 16G, 512M)"
  | T_email   -> "email"
  | T_time    -> "time (H M S)"
  | T_enum vs -> Printf.sprintf "enum(%s)" (String.concat ~sep:"|" vs)
