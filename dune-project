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
 (depends
  (ocaml (>= 5.3))
  (base (>= v0.17))
  (sexplib (>= v0.17))
  (ppx_jane (>= v0.17))
  (cmdliner (>= 1.3))
  (odoc :with-doc))
 (tags
  ("slurm" "hpc" "header")))
