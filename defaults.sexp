;; defaults.sexp — starting-point values for common SLURM fields.
;;
;; Field names must match those in schema.sexp (hyphens, not underscores).
;;
;; Only fields that should have a default value need to be listed here.
;; Fields omitted here simply won't appear in the header unless the user
;; supplies a value via config.sexp or the CLI.
;;
;; Override any of these in config.sexp (with -d) or on the CLI.

;; ── Job identity ──────────────────────────────────────────────────────────
(job-name         myjob)

;; ── Walltime ──────────────────────────────────────────────────────────────
;; 1 hour is the most universally safe default across HPC clusters
(time             (1 0 0))

;; ── Node / task layout ────────────────────────────────────────────────────
(nodes            1)
(ntasks           1)
(cpus-per-task    1)

;; ── Memory ────────────────────────────────────────────────────────────────
;; 4G is a reasonable single-task default; units are always explicit
(mem              4G)

;; ── Mail notifications ────────────────────────────────────────────────────
;; NONE by default — users opt in to notifications
(mail-type        NONE)
