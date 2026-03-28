# spec_checker

Elixir typespec checker and BEAM spec extractor. Verifies that functions have `@spec` annotations and extracts type signatures from compiled bytecode. Builds as a standalone escript (`check_specs`) that works with any Elixir project.

## Quick start

```bash
git clone https://github.com/jlecount/spec_checker.git
cd spec_checker
mix deps.get
mix spec_checker.install --dir ~/.local/bin
```

The `--dir` argument can be any directory on your PATH. If omitted, the escript is built but not copied.

Verify it works:

```bash
check_specs --help
```

## Check mode

Verify that all functions in source files have `@spec` annotations. Parses source via AST — no compilation needed. Functions with `@impl` (any form) are exempt.

```bash
check_specs lib/**/*.ex
```

```json
{
  "status": "pass",
  "total_missing": 0,
  "missing": [],
  "errors": []
}
```

When specs are missing:

```json
{
  "status": "fail",
  "total_missing": 2,
  "missing": [
    {"file": "lib/accounts.ex", "name": "get_user", "arity": 1, "kind": "def", "line": 12},
    {"file": "lib/accounts.ex", "name": "hash_password", "arity": 1, "kind": "defp", "line": 34}
  ],
  "errors": []
}
```

## Dump mode

Extract type signatures from compiled BEAM files. Reads bytecode directly — reflects what Dialyzer sees, not source comments. Resolves behaviour callback specs by searching sibling ebin directories.

```bash
check_specs --dump _build/dev/lib/my_app/ebin
check_specs --dump _build/dev/lib/my_app/ebin MyApp.Accounts
```

```json
{
  "status": "pass",
  "total_specs": 3,
  "specs": [
    {"module": "MyApp.Accounts", "name": "get_user", "arity": 1,
     "signature": "get_user(Ecto.UUID.t()) :: User.t() | nil",
     "source": "module"},
    {"module": "MyApp.Worker", "name": "perform", "arity": 1,
     "signature": "perform(Oban.Job.t()) :: :ok | {:error, term()}",
     "source": "behaviour", "behaviour": "Oban.Worker"}
  ]
}
```

## Text output

Add `--format text` to either mode for human-readable output:

```bash
check_specs --format text lib/**/*.ex
check_specs --dump --format text _build/dev/lib/my_app/ebin > specs.txt
```

## For AI agents

The primary use case is giving coding agents fast, token-efficient access to module APIs without reading source files.

Workflow:
1. Run `check_specs --dump` to get type signatures for modules you need to call
2. Write code using the type contracts
3. Run `check_specs` on changed files to verify all new functions have specs

Generate a greppable spec reference:

```bash
check_specs --dump --format text _build/dev/lib/my_app/ebin > specs.txt
grep "Accounts\." specs.txt
```

## Requirements

- Elixir 1.17+
- Erlang/OTP 27+
