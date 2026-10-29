# Kotlin PSI adapter

`kotlin_psi_parser.py` compiles `KotlinPsi.java` using the Android Studio JBR
and **only** cached Gradle artifacts: Kotlin compiler embeddable/stdlib 2.2.20,
annotations 13.0, and coroutines 1.8.0 (the compiler's runtime dependency).
`bootstrap_kotlin_tools.py` provisions the checksum-pinned jars listed in
`kotlin_artifacts.json`. No application dependency or lockfile changes.
Compilation and temporary source files live under the evidence root's `psi/`
(`TVPLAYER_EVIDENCE_ROOT` when set).

The adapter emits real PSI declaration selectors/tree/spans and Kotlin lexer
tokens with Unicode code-point offsets (Python string indices). Local declarations,
constructor properties, accessors, anonymous objects and init blocks are inventoried.
Signature parameters/type parameters belong to their owning declaration header.
Unknown declaration types and PSI syntax errors fail closed. Comments and every
line break outside literal/comment tokens are retained; literal contents are exact.

`check_tvplayer_boundaries.py` uses it to audit the TV player's collaborator
edges, Host interfaces and forbidden Flutter types.
