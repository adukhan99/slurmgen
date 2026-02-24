open Base
open Stdio

type mail_option =
  | ALL
  | BEGIN
  | END
  | FAIL
  | NONE
[@@deriving sexp]

type slurm_config =
  { account          : string
  ; nodes            : int
  ; ntasks_per_node  : int
  ; cpus_per_task    : int
  ; mem              : int
  ; partition        : string
  ; time             : int * int * int
  ; job_name         : string
  ; mail_type        : mail_option
  ; mail_user        : string
  }
[@@deriving sexp]

type slurm_extra_entry =
  { key   : string
  ; value : Sexplib.Sexp.t
  }

type slurm_job =
  { config  : slurm_config
  ; extra   : slurm_extra_entry list
  ; removes : string list
  }

(* The set of field names that belong to [slurm_config].  Used to prevent
   (new ...) overrides from shadowing base fields. *)
let known_fields =
  Set.of_list
    (module String)
    [ "account"; "nodes"; "ntasks_per_node"; "cpus_per_task"
    ; "mem"; "partition"; "time"; "job_name"; "mail_type"; "mail_user"
    ]

let default : slurm_config =
  { account         = "SLURMACC"
  ; nodes           = 1
  ; ntasks_per_node = 1
  ; cpus_per_task   = 1
  ; mem             = 16
  ; partition       = "nodes"
  ; time            = (48, 0, 0)
  ; job_name        = "DFLT"
  ; mail_type       = ALL
  ; mail_user       = "example@uni.edu"
  }

(* Apply [overrides] (a list of [(key value)] sexps) on top of [defaults]
   (a record-shaped sexp), replacing matching keys in place. *)
let patch_sexp defaults overrides =
  let override_map =
    List.filter_map overrides ~f:(function
      | Sexplib.Sexp.List [ Atom k; v ] -> Some (k, v)
      | _ -> None)
  in
  match defaults with
  | Sexplib.Sexp.List fields ->
    let patch_field = function
      | Sexplib.Sexp.List [ Atom k; v ] ->
        let v' =
          Option.value (List.Assoc.find override_map ~equal:String.equal k) ~default:v
        in
        Sexplib.Sexp.List [ Atom k; v' ]
      | other -> other
    in
    Sexplib.Sexp.List (List.map fields ~f:patch_field)
  | _ -> defaults

(* Convert a [(key value)] or [(key (a b c))] sexp into a "#SBATCH --key=value\n"
   string.  Returns [None] for any sexp that doesn't match either shape. *)
let sexp_to_kv = function
  | Sexplib.Sexp.List [ Atom k; Atom v ] ->
    Some (Printf.sprintf "#SBATCH --%s=%s\n" k v)
  | Sexplib.Sexp.List [ Atom k; Sexplib.Sexp.List vs ] ->
    let v =
      List.filter_map vs ~f:(function Sexplib.Sexp.Atom s -> Some s | _ -> None)
      |> String.concat ~sep:":"
    in
    Some (Printf.sprintf "#SBATCH --%s=%s\n" k v)
  | _ -> None

(* Unwrap a single-element list that itself contains a record-shaped list,
   which is the shape produced by [Sexp.load_sexps] on a file that holds
   one top-level record.  Falls through to the raw list otherwise. *)
let unwrap_sexp_list = function
  | [ Sexplib.Sexp.List (Sexplib.Sexp.List _ :: _ as inner) ] -> inner
  | raw -> raw

(* Split an override list into:
     - [base_overrides] : sexps that patch [slurm_config] fields
     - [extras]         : extra [#SBATCH] entries from [(new KEY val...)] forms
     - [removes]        : keys to suppress from the final output

   Raises [Failure] if a [(new ...)] key shadows a known base field. *)
let partition_overrides overrides =
  let rec loop base extra removes = function
    | [] -> List.rev base, List.rev extra, List.rev removes
    | Sexplib.Sexp.List [ Sexp.Atom "new"; Sexp.List (Sexp.Atom k :: vs) ] :: rest ->
      if Set.mem known_fields k then
        failwith
          (Printf.sprintf
             "Error: '%s' is a base config field; use (%s ...) directly instead." k k)
      else
        let entry = { key = k; value = Sexplib.Sexp.List (Sexp.Atom k :: vs) } in
        loop base (entry :: extra) removes rest
    | Sexplib.Sexp.List [ Sexp.Atom "rm"; Sexp.Atom k ] :: rest ->
      loop base extra (k :: removes) rest
    | other :: rest ->
      loop (other :: base) extra removes rest
  in
  loop [] [] [] overrides

let die fmt = Printf.ksprintf (fun msg -> eprintf "%s\n" msg; Stdlib.exit 1) fmt

(* True when [field] is a sexp record entry whose key is NOT [key].
   Used to filter out removed fields before rendering. *)
let field_has_different_key key = function
  | Sexplib.Sexp.List (Atom k :: _) -> not (String.equal k key)
  | _ -> true

let run input_str from_file use_default_config =
  let raw_overrides =
    (if from_file then Sexplib.Sexp.load_sexps input_str
     else Sexplib.Sexp.of_string_many input_str)
    |> unwrap_sexp_list
  in
  let base_overrides, extras, removes =
    match partition_overrides raw_overrides with
    | exception Failure msg -> die "%s" msg
    | result -> result
  in
  let base_default_sexp = sexp_of_slurm_config default in
  let default_sexp, total_removes =
    if use_default_config then begin
      let cfg_overrides =
        Sexplib.Sexp.load_sexps "config.sexp"
        |> unwrap_sexp_list
      in
      let cfg_base, _, cfg_removes =
        match partition_overrides cfg_overrides with
        | exception Failure msg -> die "%s" msg
        | result -> result
      in
      patch_sexp base_default_sexp cfg_base, cfg_removes @ removes
    end else
      base_default_sexp, removes
  in
  let config =
    let patched = patch_sexp default_sexp base_overrides in
    match slurm_config_of_sexp patched with
    | exception exn -> die "%s" (Exn.to_string exn)
    | cfg -> cfg
  in
  let job = { config; extra = extras; removes = total_removes } in
  let keep field =
    List.for_all job.removes ~f:(fun k -> field_has_different_key k field)
  in
  let base_header =
    match sexp_of_slurm_config job.config with
    | Sexplib.Sexp.List fields ->
      fields
      |> List.filter ~f:keep
      |> List.filter_map ~f:sexp_to_kv
      |> String.concat ~sep:""
    | _ -> assert false
  in
  let extra_header =
    job.extra
    |> List.filter ~f:(fun e -> not (List.mem job.removes e.key ~equal:String.equal))
    |> List.filter_map ~f:(fun e -> sexp_to_kv e.value)
    |> String.concat ~sep:""
  in
  print_string (base_header ^ extra_header ^ "\n")

let () =
  let open Cmdliner in
  let input_str =
    let doc = "S-expression string or filename (if -f is used)." in
    Arg.(required & pos 0 (some string) None & info [] ~docv:"INPUT" ~doc)
  in
  let from_file =
    let doc = "Interpret the input argument as a filename." in
    Arg.(value & flag & info [ "f"; "file" ] ~doc)
  in
  let use_default_config =
    let doc =
      "Read config.sexp from the current directory and apply it as \
       the default configuration before any other overrides."
    in
    Arg.(value & flag & info [ "d"; "default-config" ] ~doc)
  in
  let cmd =
    let doc = "Generate SLURM headers from S-expressions." in
    let info = Cmd.info "slurmgen" ~doc in
    Cmd.v info Term.(const run $ input_str $ from_file $ use_default_config)
  in
  Stdlib.exit (Cmd.eval cmd)
