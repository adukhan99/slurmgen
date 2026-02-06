# slurmgen

slurmgen is a type-safe SLURM header generator written in OCaml.
It converts structured S-expressions into valid #SBATCH directives, using the OCaml type system to enforce correctness and prevent malformed headers.

Instead of hand-editing SLURM scripts (and discovering mistakes at queue time), you describe your job declaratively and let slurmgen guarantee that the output is well-formed.

# useage
After cloning, run with: ```dune exec slurmgen "[S-exp]"```
S-expressions are formatted without toplevel parentheses, e.g. ```"(nodes 4)(partition gpu)"``` is valid

# roadmap
1. Implement full type checking of input
2. Add option to load S-exp from file
3. Allow second and third options to enable cli tag generation, the absence of certain options, and the creation of custom options
