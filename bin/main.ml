open Base
open Stdio
open Sexplib

type mail_option = 
  | ALL 
  | BEGIN 
  | END 
  | FAIL 
  | NONE
  [@@deriving sexp]

type slurm_config = {
  account : string;
  nodes : int;
  ntasks_per_node : int;
  cpus_per_task : int;
  mem : int;
  partition : string;
  time : int * int * int;
  job_name : string;
  mail_type : mail_option;
  mail_user : string
} [@@deriving sexp]

let default = {
  account = "SLURMACC";
  nodes = 1;
  ntasks_per_node = 1;
  cpus_per_task = 1;
  mem = 16;
  partition = "nodes";
  time = (48, 0, 0);
  job_name = "DFLT";
  mail_type = ALL;
  mail_user = "example@uni.edu"
}

let patch_sexp defaults overrides =
  let override_map =
    List.filter_map overrides ~f:(function
      | Sexp.List [Atom k; v] -> Some (k, v)
      | _ -> None)
  in
  let replace (k, v) =
    match List.Assoc.find override_map ~equal:String.equal k with
    | Some v' -> (k, v')
    | None -> (k, v)
  in
  match defaults with
  | Sexp.List fields ->
      Sexp.List (List.map fields ~f:(function
        | Sexp.List [Atom k; v] -> Sexp.List (let k', v' = replace (k, v) in [Atom k'; v'])
        | other -> other))
  | _ -> defaults


let sexp_to_kv = function
  | Sexp.List [Atom k; Atom v] ->
      Some (Printf.sprintf "#SBATCH --%s=%s\n" k v)
  | Sexp.List (Atom k :: Sexp.List vs :: []) ->
      let v =
        vs
        |> List.map ~f:(function Sexp.Atom s -> s | _ -> "")
        |> String.concat ~sep:":"
      in
      Some (Printf.sprintf "#SBATCH --%s=%s\n" k v)
  | _ -> None
    


let run input_str from_file =
  let overrides =
    let raw =
      if from_file
      then Sexp.load_sexps input_str
      else Sexp.of_string_many input_str
    in
    match raw with
      | [Sexp.List (Sexp.List _ :: _ as inner)] -> inner
      | [Sexp.List [Sexp.Atom _; _]] -> raw
      | _ -> raw
  in
  let default_sexp =
    sexp_of_slurm_config default
  in
  let final_sexp =
    let patched_sexp = patch_sexp default_sexp overrides in
    try
      let config = slurm_config_of_sexp patched_sexp in
      sexp_of_slurm_config config
    with exn ->
      Stdio.eprintf "%s\n" (Exn.to_string exn);
      Stdlib.exit 1
  in
  let header =
    match final_sexp with
    | Sexp.List fields ->
        fields
        |> List.filter_map ~f:sexp_to_kv
        |> String.concat ~sep:""
    | _ -> ""
  in
  printf "%s\n" header

let () =
  let open Cmdliner in
  let input_str =
    let doc = "S-expression string or filename (if -f is used)." in
    Arg.(required & pos 0 (some string) None & info [] ~docv:"INPUT" ~doc)
  in
  let from_file =
    let doc = "Interpret the input argument as a filename." in
    Arg.(value & flag & info ["f"; "file"] ~doc)
  in
  let cmd =
    let doc = "Generate SLURM headers from S-expressions" in
    let info = Cmd.info "slurmgen" ~doc in
    Cmd.v info Term.(const run $ input_str $ from_file)
  in
  Stdlib.exit (Cmd.eval cmd)

