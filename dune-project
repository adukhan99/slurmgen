(lang dune 3.21)

(name slurmgen)

(generate_opam_files true)

(source
 (github adukhan99/slurmgen))

(authors "Alex Dukhan <agdukhan@gmail.com>")

(maintainers "Alex Dukhan <agdukhan@gmail.com>")

(license LICENSE)

(documentation "")

(package
 (name slurmgen)
 (synopsis "Generate SLURM headers")
 (description
  "SLURM headers are often tedious and error-prone. This tool generates them based on S-expressions.")
 (depends ocaml)
 (tags
  ("slurm" "hpc" "header")))
