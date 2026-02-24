# slurmgen

slurmgen is a type-safe SLURM header generator written in OCaml.
It converts structured S-expressions into valid #SBATCH directives, using the OCaml type system to enforce correctness and prevent malformed headers.

Instead of hand-editing SLURM scripts (and discovering mistakes at queue time), you describe your job declaratively and let slurmgen guarantee that the output is well-formed.

# useage
After cloning, run with: 
```dune exec slurmgen -- "(S-exp)"``` 
or with -f to read from a file as in -f "./test.sexp"
or with -d to use a custom default config.sexp as the base header
Toplevel S-expressions are valid, as are nested S-expressions.

# altering options
Addition of new options is supported via the `(new (KEY val...))` syntax.
Removal of options is supported via the `(rm KEY)` syntax.

# roadmap
1. Ensure type checking is deeply robust, even for custom options
2. More deeply integrate with slurm to allow for more advanced features