# spec_checker

A command-line tool that checks your Elixir code for missing `@spec` annotations and can extract a complete type reference from your compiled project. Install once, use from any project.

## Install

```bash
git clone https://github.com/jlecount/spec_checker.git
cd spec_checker
mix deps.get
mix spec_checker.install --dir ~/.local/bin
```

`--dir` can be any directory on your PATH. If omitted, the escript is built but not copied.

## Examples

**Are all my functions specced?**

```bash
$ check_specs lib/**/*.ex
{"status":"pass","total_missing":0,"missing":[],"errors":[]}
```

**Which functions am I missing specs for?**

```bash
$ check_specs lib/accounts.ex
{"status":"fail","total_missing":2,"missing":[
  {"file":"lib/accounts.ex","name":"get_user","arity":1,"kind":"def","line":12},
  {"file":"lib/accounts.ex","name":"hash_password","arity":1,"kind":"defp","line":34}
],"errors":[]}
```

**What's the full type API for a module?**

```bash
$ check_specs --dump _build/dev/lib/my_app/ebin MyApp.Accounts
{"status":"pass","total_specs":3,"specs":[
  {"module":"MyApp.Accounts","name":"get_user","arity":1,
   "signature":"get_user(Ecto.UUID.t()) :: User.t() | nil","source":"module"},
  {"module":"MyApp.Accounts","name":"create_user","arity":2,
   "signature":"create_user(map(), keyword()) :: {:ok, User.t()} | {:error, Changeset.t()}",
   "source":"module"}
]}
```

**What about callback functions?** Behaviour specs are resolved automatically:

```bash
$ check_specs --dump _build/dev/lib/my_app/ebin MyApp.Worker
{"status":"pass","total_specs":1,"specs":[
  {"module":"MyApp.Worker","name":"perform","arity":1,
   "signature":"perform(Oban.Job.t()) :: :ok | {:error, term()}",
   "source":"behaviour","behaviour":"Oban.Worker"}
]}
```

**Human-readable output?** Add `--format text`:

```bash
$ check_specs --format text lib/accounts.ex
Functions missing @spec annotations:

  lib/accounts.ex
    def get_user/1 (line 12)
    defp hash_password/1 (line 34)

2 functions missing @spec.
```

```bash
$ check_specs --dump --format text _build/dev/lib/my_app/ebin MyApp.Accounts
MyApp.Accounts.get_user/1 :: get_user(Ecto.UUID.t()) :: User.t() | nil
MyApp.Accounts.create_user/2 :: create_user(map(), keyword()) :: {:ok, User.t()} | {:error, Changeset.t()}
```

## How it works

**Check mode** (default) parses source files via the Elixir AST. No compilation needed. Functions with `@impl` (any form) are exempt since their type contract lives on the behaviour.

**Dump mode** (`--dump`) reads compiled `.beam` files directly — the same bytecode Dialyzer checks. It searches sibling ebin directories to resolve callback specs from behaviour modules.

Output is JSON by default (for tooling and AI agents). `--format text` gives greppable one-line-per-function output.

## For AI agents

Look up a module's API before reading its source:

```bash
check_specs --dump _build/dev/lib/my_app/ebin MyApp.Accounts
```

Generate a greppable reference for the whole project:

```bash
check_specs --dump --format text _build/dev/lib/my_app/ebin > specs.txt
grep "Accounts\." specs.txt
```

Verify your work before committing:

```bash
check_specs lib/my_app/accounts.ex lib/my_app/worker.ex
```

## Requirements

- Elixir 1.14+
- Erlang/OTP 25+

Dump mode uses `Code.Typespec`, an undocumented Elixir API. It has been stable across many releases but could change without deprecation notice.
