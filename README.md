# spec_checker

Standalone Elixir typespec checker and BEAM spec extractor. Builds as an escript (`check_specs`) that can be installed globally and used from any Elixir project.

## Setup

Requires Elixir 1.17+ and Erlang/OTP 27+.

```bash
git clone <repo-url> ~/code/personal/spec_checker
cd spec_checker
mix deps.get
mix escript.build
cp check_specs ~/.local/bin/
```

## Usage

```bash
# Check mode: verify all functions have @spec annotations
check_specs lib/**/*.ex
check_specs --format text lib/my_app/server.ex

# Dump mode: extract specs from compiled BEAM files
check_specs --dump _build/dev/lib/my_app/ebin
check_specs --dump _build/dev/lib/my_app/ebin MyApp.Accounts
check_specs --dump --format text _build/dev/lib/my_app/ebin > specs.txt
```

Output is JSON by default. Use `--format text` for human-readable output.

Run `check_specs --help` for full usage and JSON schema documentation.

## Features

- AST-based source checking (no compilation required for check mode)
- Functions with `@impl` annotations (any form) are exempt from check mode
- BEAM spec extraction reads bytecode directly (reflects what Dialyzer sees)
- Dump mode resolves behaviour callback specs by searching sibling ebin directories
- Output identifies whether each spec comes from the module or a behaviour callback

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | All specs present (check) or dump completed |
| 1 | Missing specs found |
| 2 | Parse or read errors |
