# dala_new — Agent Instructions

**Read [`AGENTS.md`](AGENTS.md) first**, then [`~/code/dala/AGENTS.md`](../dala/AGENTS.md)
for the system view. They cover the three-repo topology, generator
gotchas (LV blocklist, eager template defaults, App ID name validation),
and cross-cutting pre-empt-failure rules. This file goes deeper on
archive-build mechanics.

> **Keep AGENTS.md up to date** when you change template structure, add
> to the LV blocklist, or hit a generator gotcha. Same commit, not a
> follow-up.

`dala_new` is a Mix archive — a self-contained `.ez` file that installs a global
Mix task (`mix dala.new`). It is **not** a regular dependency; it ships as a
`mix archive.install` package.

## Building and installing the archive locally

```bash
cd ~/code/dala_new
mix archive.build          # produces dala_new-<version>.ez in the current dir
mix archive.install dala_new-0.1.1.ez --force   # installs it globally
```

After installing, `mix dala.new` is available in any directory.

To verify the install:
```bash
mix archive                # lists installed archives — dala_new should appear
mix dala.new --help
```

To uninstall:
```bash
mix archive.uninstall dala_new
```

## Testing the full generator flow

```bash
mix dala.new /tmp/my_test_app
cd /tmp/my_test_app
mix dala.install
```

## Publishing to Hex

```bash
mix hex.publish archive    # publishes the .ez archive (not a library package)
```

## Key files

- `lib/mix/tasks/dala.new.ex` — `mix dala.new APP_NAME` task
- `lib/dala_new/project_generator.ex` — EEx template rendering
- `priv/templates/dala.new/` — project template files
- `mix.exs` — version lives here; bump before publishing

## Running tests

```bash
mix test
```

## Pre-commit checklist

Before committing changes, run **all three** in this order:

```bash
mix test            # full suite must pass (call out any pre-existing flake explicitly)
mix format          # apply Elixir formatting
mix credo --strict  # address new issues; pre-existing ones are tracked separately
```

When changing the EEx templates under `priv/templates/`, the unit tests
don't render them on a real device — generate a fresh project with
`mix dala.new /tmp/foo` and verify it builds before committing.
