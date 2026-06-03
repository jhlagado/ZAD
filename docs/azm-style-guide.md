# TECM8 AZM Style Guide

TECM8 Z80 source follows the style used by Tetro and the AZM manuals.

- Use lowercase dotted directives: `.org`, `.include`, `.equ`, `.db`, `.dw`,
  `.ds`.
- Use uppercase Z80 mnemonics and registers.
- Use PascalCase labels. Prefix callable routine entries with `@`, such as
  `@ParseProjectConfig:`.
- Keep branch labels globally unique by prefixing them with the routine name
  when needed, such as `ParseCfgPathLoop`.
- Put constants on the left with `.equ`. Use uppercase with underscores for
  constants, with clear prefixes for related groups such as `PROJECT_CFG_*`.
- Use PascalCase for routine entries, branch labels, data labels, type names,
  and enum names. Use lower camel case for fields and enum members when layout
  expressions benefit from it.
- Document routine contracts with AZMDoc `;!` comments for inputs, outputs, and
  clobbered registers.
- Keep routines small and explicit. Prefer simple byte scans and fixed buffers
  over clever parsing.
- Store strings and fixtures as `.db` data near the routine or proof that uses
  them.
