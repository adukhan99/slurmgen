# slurmgen

Generate `#SBATCH` headers for SLURM job scripts from S-expressions.

## Overview

`slurmgen` is a schema-driven SLURM header generator. Instead of hardcoding
which SLURM options exist, you define them in a **`schema.sexp`** file and
provide default values in **`defaults.sexp`**. This means slurmgen works on
*any* cluster, regardless of which SLURM options are available — just edit
the schema.

## Quick Start

```bash
# Generate headers with CLI overrides on top of defaults
slurmgen '(nodes 4)(mem 64)'

# Use a site config.sexp as an intermediate layer
slurmgen -d '(partition gpu)(nodes 2)'

# Read overrides from a file
slurmgen -f overrides.sexp

# Remove a field from the output
slurmgen '(nodes 4)(rm mail_user)'
```

## Configuration Files

slurmgen looks for configuration files in this order:
1. Current working directory
2. `~/.config/slurmgen/`

You can also specify paths explicitly with `--schema` and `--defaults`.

### `schema.sexp` — Field Definitions

Defines which fields exist and what type each one has:

```scheme
;; Supported types: string, int, email, time, (enum A B C ...)
(field account         string)
(field nodes           int)
(field ntasks_per_node int)
(field cpus_per_task   int)
(field mem             int)
(field partition       string)
(field time            time)
(field job_name        string)
(field mail_type       (enum ALL BEGIN END FAIL NONE))
(field mail_user       email)

;; Add cluster-specific fields:
(field mem_per_cpu     int)
(field gres            string)
(field qos             string)
```

### `defaults.sexp` — Default Values

Provides starting-point values. Only fields listed here get defaults:

```scheme
(account         SLURMACC)
(nodes           1)
(ntasks_per_node 1)
(cpus_per_task   1)
(mem             16)
(partition       nodes)
(time            (48 0 0))
(job_name        DFLT)
(mail_type       ALL)
(mail_user       example@uni.edu)
```

### `config.sexp` — Site/User Overrides (optional)

Used with `-d`. Overrides defaults before CLI arguments are applied:

```scheme
(account mylab)
(partition gpu)
(nodes 2)
```

## Override Precedence

```
defaults.sexp → config.sexp (-d) → CLI arguments
```

Later layers override earlier ones. Types are always checked against the schema.

## Type Checking

Every value — whether from defaults, config, or CLI — is validated against
the schema. Errors are reported with clear messages:

```
$ slurmgen '(nodes hello)'
Field 'nodes': expected int, got "hello"

$ slurmgen '(mail_type INVALID)'
Field 'mail_type': expected one of [ALL, BEGIN, END, FAIL, NONE], got "INVALID"

$ slurmgen '(nods 4)'
Unknown field 'nods' (not in schema)
```

## Building

```bash
opam install . --deps-only
dune build
dune runtest
```

## License

See [LICENSE](LICENSE).