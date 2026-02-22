# slurmgen

slurmgen is a type-safe SLURM header generator written in OCaml.
It converts structured S-expressions into valid #SBATCH directives, using the OCaml type system to enforce correctness and prevent malformed headers.

Instead of hand-editing SLURM scripts (and discovering mistakes at queue time), you describe your job declaratively and let slurmgen guarantee that the output is well-formed.

# useage
After cloning, run with: 
```dune exec slurmgen -- "(S-exp)"``` 
or using -f to read from a file as in -f "./test.sexp"
or with -d to use a custom default config.sexp as the base header
Toplevel S-expressions are valid, as are nested S-expressions.

# roadmap
1. Implement full type checking of input
2. Allow second and third options to enable cli tag generation, the absence of certain options, and the creation of custom options
