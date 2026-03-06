let () =
  (* Smoke-test: ensure the library modules are accessible *)
  let schema_sexps = [
    Sexplib.Sexp.of_string "(field account string)";
    Sexplib.Sexp.of_string "(field nodes int)";
    Sexplib.Sexp.of_string "(field mail_type (enum ALL BEGIN END FAIL NONE))";
    Sexplib.Sexp.of_string "(field mail_user email)";
    Sexplib.Sexp.of_string "(field time time)";
  ] in
  let schema = match Slurmgen.Schema.of_sexps schema_sexps with
    | Ok s -> s
    | Error e -> failwith e
  in

  (* Test: valid config *)
  let config_sexps = [
    Sexplib.Sexp.of_string "(account mylab)";
    Sexplib.Sexp.of_string "(nodes 4)";
    Sexplib.Sexp.of_string "(mail_type END)";
    Sexplib.Sexp.of_string "(mail_user test@example.com)";
    Sexplib.Sexp.of_string "(time (12 30 0))";
  ] in
  let config = match Slurmgen.Config.of_sexps ~schema config_sexps with
    | Ok c -> c
    | Error e -> failwith e
  in

  (* Test: rendering *)
  let rendered = Slurmgen.Config.render config in
  assert (String.length rendered > 0);
  Printf.printf "Render test passed.\n";

  (* Test: type error *)
  let bad_sexps = [
    Sexplib.Sexp.of_string "(nodes hello)";
  ] in
  (match Slurmgen.Config.of_sexps ~schema bad_sexps with
   | Ok _ -> failwith "Expected type error"
   | Error _ -> Printf.printf "Type-error test passed.\n");

  (* Test: merge precedence *)
  let base_sexps = [
    Sexplib.Sexp.of_string "(account base)";
    Sexplib.Sexp.of_string "(nodes 1)";
  ] in
  let override_sexps = [
    Sexplib.Sexp.of_string "(nodes 8)";
  ] in
  let base = match Slurmgen.Config.of_sexps ~schema base_sexps with
    | Ok c -> c | Error e -> failwith e in
  let overrides = match Slurmgen.Config.of_sexps ~schema override_sexps with
    | Ok c -> c | Error e -> failwith e in
  let merged = Slurmgen.Config.merge ~base ~overrides in
  let rendered_merged = Slurmgen.Config.render merged in
  assert (not (Str.string_match (Str.regexp {|.*nodes=1.*|}) rendered_merged 0));
  Printf.printf "Merge-precedence test passed.\n";

  (* Test: remove keys *)
  let after_rm = Slurmgen.Config.remove_keys merged ["account"] in
  let rendered_rm = Slurmgen.Config.render after_rm in
  assert (not (Str.string_match (Str.regexp {|.*account.*|}) rendered_rm 0));
  Printf.printf "Remove-keys test passed.\n";

  Printf.printf "All tests passed!\n"
