# Kotlin PSI adapter

`check_kotlin_moves.py` compiles `KotlinPsi.java` using the Android Studio JBR
and **only** cached Gradle artifacts: Kotlin compiler embeddable/stdlib 2.2.20,
annotations 13.0, and coroutines 1.8.0 (the compiler's runtime dependency).
No application dependency or lockfile changes; no network resolution.
Compilation, temporary source files and evidence live under the git common
directory's `refactor-evidence/tvplayer/p1/psi/`.

The adapter emits real PSI declaration selectors/tree/spans and Kotlin lexer
tokens with Unicode code-point offsets (Python string indices). Local declarations,
constructor properties, accessors, anonymous objects and init blocks are inventoried.
Signature parameters/type parameters belong to their owning declaration header.
Unknown declaration types and PSI syntax errors fail closed. Comments and every
line break outside literal/comment tokens are retained; literal contents are exact.
The Python checker partitions only explicitly split class bodies. All other
subtrees are compared whole and their descendant ownership is validated.
