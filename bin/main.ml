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
  partition : string; [@key "p"]
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

let validate_mail_type str =
  match String.uppercase str with
  | "ALL" -> ALL
  | "BEGIN" -> BEGIN
  | "END" -> END
  | "FAIL" -> FAIL
  | "NONE" -> NONE
  | _ -> failwith ("Invalid mail-type: " ^ str)

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
    

let () =
  let argv = Sys.get_argv () in
  let overrides =
    if Array.length argv > 1
    then Sexp.of_string_many argv.(1)
    else []
  in
  let default_sexp =
    sexp_of_slurm_config default
  in
  let final_sexp =
    patch_sexp default_sexp overrides
  in
  let header =
    match final_sexp with
    | Sexp.List fields ->
        fields
        |> List.filter_map ~f:sexp_to_kv
        |> String.concat ~sep:""
    | _ -> ""
  in
  Stdio.printf "%s\n" header

