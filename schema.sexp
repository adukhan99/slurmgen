;; schema.sexp — defines the known SLURM fields and their types.
;;
;; Each entry has the form:  (field NAME TYPE)
;;
;; Field names MUST match the actual --option-name used by sbatch
;; (hyphens, not underscores).
;;
;; Supported types:
;;   string            — any string value
;;   int               — a positive integer
;;   size              — memory/size with optional unit suffix: K M G T
;;                       e.g.  16G  512M  4096  (unitless = MB per SLURM)
;;   email             — validated e-mail address
;;   time              — (HH MM SS) triple, rendered as HH:MM:SS
;;   (enum A B C …)   — one of the listed values (case-insensitive input)
;;
;; Add, remove, or edit entries to match your cluster.  No recompilation needed.

;; ── Accounting / scheduling ───────────────────────────────────────────────
(field account          string)
(field partition        string)
(field qos              string)

;; ── Job identity ──────────────────────────────────────────────────────────
(field job-name         string)
(field comment          string)

;; ── Walltime ──────────────────────────────────────────────────────────────
(field time             time)

;; ── Node / task layout ────────────────────────────────────────────────────
(field nodes            int)
(field ntasks           int)
(field ntasks-per-node  int)
(field cpus-per-task    int)

;; ── Memory ────────────────────────────────────────────────────────────────
;;   Use 'mem' for per-node memory, or 'mem-per-cpu' for per-CPU memory.
;;   These are mutually exclusive in SLURM.
(field mem              size)
(field mem-per-cpu      size)

;; ── Generic resources (GPUs etc.) ─────────────────────────────────────────
;;   Format: <type>:<count>  e.g.  gpu:2   gpu:a100:1
(field gres             string)
(field gres-flags       string)

;; ── Output / error files ──────────────────────────────────────────────────
;;   Supports SLURM filename patterns: %j (jobid), %x (jobname), %N (node)
(field output           string)
(field error            string)

;; ── Mail notifications ────────────────────────────────────────────────────
;;   mail-type: multiple values can be combined as a comma-separated string
;;   (use type string and write e.g. "BEGIN,END") or pick one value here.
;;   Full enum per the SLURM 23.x docs:
(field mail-type        (enum NONE BEGIN END FAIL REQUEUE
                              TIME_LIMIT TIME_LIMIT_90 TIME_LIMIT_80 TIME_LIMIT_50
                              ARRAY_TASKS STAGE_OUT INVALID_DEPEND ANY_INVALID_DEPEND
                              ALL))
(field mail-user        email)
