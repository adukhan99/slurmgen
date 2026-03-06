open Base
open Stdio

(* ─── Helpers ───────────────────────────────────────────────────────── *)

let die fmt =
  Printf.ksprintf (fun msg -> eprintf "%s\n" msg; Stdlib.exit 1) fmt

(** Unwrap a single-element list that itself contains a record-shaped list,
    which is the shape produced by [Sexp.load_sexps] on a file that holds
    one top-level record.  Falls through to the raw list otherwise. *)
let unwrap_sexp_list = function
  | [ Sexplib.Sexp.List (Sexplib.Sexp.List _ :: _ as inner) ] -> inner
  | raw -> raw

(* ─── Override partitioning ─────────────────────────────────────────── *)

(** Split user-supplied sexps into:
    - [overrides] : [(key value)] pairs that patch existing fields
    - [removes]   : field names to suppress from the final output

    Unlike the old version, there is no special [new] form — every field is
    just [(key value)].  If the key is in the schema, great; if not, an
    error will surface at validation time. *)
let partition_overrides sexps =
  let rec loop overrides removes = function
    | [] -> List.rev overrides, List.rev removes
    | Sexplib.Sexp.List [ Sexplib.Sexp.Atom "rm"; Sexplib.Sexp.Atom k ] :: rest ->
      loop overrides (k :: removes) rest
    | other :: rest ->
      loop (other :: overrides) removes rest
  in
  loop [] [] sexps

(* ─── Locate config files ──────────────────────────────────────────── *)

(** Search order for a configuration file:
    1. Current directory
    2. [~/.config/slurmgen/]
    Returns [None] if not found anywhere. *)
let find_config_file name =
  let cwd_path = name in
  if Stdlib.Sys.file_exists cwd_path then Some cwd_path
  else
    match Stdlib.Sys.getenv_opt "HOME" with
    | Some home ->
      let xdg_path = Printf.sprintf "%s/.config/slurmgen/%s" home name in
      if Stdlib.Sys.file_exists xdg_path then Some xdg_path
      else None
    | None -> None

let require_config_file name =
  match find_config_file name with
  | Some path -> path
  | None ->
    die "Cannot find '%s'. Looked in:\n  - ./%s\n  - ~/.config/slurmgen/%s"
      name name name

(* ─── Main logic ────────────────────────────────────────────────────── *)

let run input_str from_file use_default_config schema_path defaults_path =
  (* 1. Load the schema *)
  let schema_file = match schema_path with
    | Some p -> p
    | None   -> require_config_file "schema.sexp"
  in
  let schema =
    match Slurmgen.Schema.load_file schema_file with
    | Ok s    -> s
    | Error e -> die "%s" e
  in

  (* 2. Load the defaults *)
  let defaults_file = match defaults_path with
    | Some p -> p
    | None   -> require_config_file "defaults.sexp"
  in
  let base_config =
    match Slurmgen.Config.load_file ~schema defaults_file with
    | Ok c    -> c
    | Error e -> die "In defaults: %s" e
  in

  (* 3. Optionally layer config.sexp on top of defaults *)
  let config_after_defaults =
    if use_default_config then begin
      match find_config_file "config.sexp" with
      | None ->
        eprintf "Warning: -d passed but no config.sexp found, using defaults only.\n";
        base_config
      | Some cfg_path ->
        match Slurmgen.Config.load_file ~schema cfg_path with
        | Ok cfg_overrides ->
          Slurmgen.Config.merge ~base:base_config ~overrides:cfg_overrides
        | Error e -> die "In config.sexp: %s" e
    end else
      base_config
  in

  (* 4. Parse the user's CLI / file overrides *)
  let raw_overrides =
    (if from_file then Sexplib.Sexp.load_sexps input_str
     else Sexplib.Sexp.of_string_many input_str)
    |> unwrap_sexp_list
  in
  let override_sexps, removes = partition_overrides raw_overrides in

  (* 5. Validate and merge the CLI overrides *)
  let cli_overrides =
    match Slurmgen.Config.of_sexps ~schema override_sexps with
    | Ok c    -> c
    | Error e -> die "%s" e
  in
  let final_config =
    Slurmgen.Config.merge ~base:config_after_defaults ~overrides:cli_overrides
  in

  (* 6. Remove any (rm ...) keys and render *)
  let after_removes = Slurmgen.Config.remove_keys final_config removes in
  let rendered = Slurmgen.Config.render after_removes in
  print_string rendered

(* ─── CLI ───────────────────────────────────────────────────────────── *)

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
      "Read config.sexp from the current directory (or ~/.config/slurmgen/) \
       and apply it as the default configuration before any other overrides."
    in
    Arg.(value & flag & info [ "d"; "default-config" ] ~doc)
  in
  let schema_path =
    let doc =
      "Path to schema.sexp. If not given, slurmgen looks in the current \
       directory and then ~/.config/slurmgen/."
    in
    Arg.(value & opt (some string) None & info [ "schema" ] ~docv:"FILE" ~doc)
  in
  let defaults_path =
    let doc =
      "Path to defaults.sexp. If not given, slurmgen looks in the current \
       directory and then ~/.config/slurmgen/."
    in
    Arg.(value & opt (some string) None & info [ "defaults" ] ~docv:"FILE" ~doc)
  in
  let cmd =
    let doc = "Generate SLURM headers from S-expressions." in
    let man = [
      `S Manpage.s_description;
      `P "slurmgen generates #SBATCH header blocks for SLURM job scripts.";
      `P "Fields and their types are defined in schema.sexp. \
          Default values come from defaults.sexp. Both files are looked \
          for in the current directory and then ~/.config/slurmgen/.";
      `P "Override any field on the command line with (key value) pairs. \
          Suppress a field with (rm key).";
      `S "EXAMPLES";
      `Pre "  slurmgen '(nodes 4)(mem 64)'";
      `Pre "  slurmgen -d '(partition gpu)(nodes 2)'";
      `Pre "  slurmgen -f overrides.sexp";
    ] in
    let info = Cmd.info "slurmgen" ~doc ~man in
    Cmd.v info Term.(const run $ input_str $ from_file $ use_default_config
                     $ schema_path $ defaults_path)
  in
  Stdlib.exit (Cmd.eval cmd)
