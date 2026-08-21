# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0]

### Added

- `DalaNew.LiveViewGenerator` module — owns the entire `--liveview` generation
  pipeline (`mix phx.new` subprocess, native boilerplate copy with the
  Phoenix-owned blocklist, and Dala bridge patches). `ProjectGenerator` now
  delegates via `liveview_generate/3`.
- Per-app LiveView port derivation: `DalaNew.ProjectGenerator.liveview_port/1`
  computes `4200 + :erlang.phash2(bundle_id, 100)`. The port flows into
  `dala_screen.ex`, `dala.exs`, `dala_app.ex`, and the patched
  `config/{dev,test,runtime}.exs`, so two installed LiveView apps no longer
  collide on hardcoded port 4200 (tracked in dala/issues.md #4).
- Endpoint secrets (`secret_key_base`, `signing_salt`) are generated into
  gitignored `dala.exs`; `dala_app.ex` reads them via `Application.get_env`
  instead of embedding literals in committed source.
- Loud warnings when a regex patch matches nothing during LiveView generation
  (deps injection, port patches, `erlc_paths`, notes routes, Repo supervision,
  `ecto_repos`) — usually a signal that `phx.new` changed its output format.
- App-name validation rejects reserved words and consecutive/trailing
  underscores with actionable error messages.

### Changed

- `elixir_lib` in generated `dala.exs` is resolved from the running Elixir
  installation at generation time instead of baking in a machine-specific
  default path.
- Template placeholder directories renamed to distinct tokens:
  `lib/__app_name__/`, `src/__app_name__.erl.eex`,
  `android/.../java/__java_path__/`. Paths that merely contain the substring
  `app_name` can no longer be corrupted by substitution.
- Partially-generated project directories are removed on failure so a retry
  doesn't hit "Directory already exists".
- Missing required files during LiveView patching (`assets/js/app.js`,
  `root.html.heex`, `mix.exs`) are hard errors instead of silent skips.
- Fixed the `config/runtime.exs` port patch, which previously matched the wrong
  pattern and left Phoenix's default `PORT` fallback of 4000 in place.

### Fixed

- Duplicate `logo:` key in `mix.exs` docs config; pinned `dialyxir` to
  `"~> 1.4"` instead of an open version range.

## [0.3.2] - 2026-08-21

### Changed

- Template updates tracking recent changes in the dala framework.

## [0.3.1]

### Changed

- Template updates.

## [0.3.0]

### Changed

- Template updates.

## [0.2.1]

### Changed

- Updated logo for project & template, removed old docs.

## [0.2.0]

### Added

- New features.

## [0.1.1]

### Changed

- Updated test cases.

## [0.1.0]

### Changed

- Template updates.

## [0.0.6]

### Changed

- Template updates.

## [0.0.5]

### Removed

- Sigil style from template.

## [0.0.3]

### Changed

- Followed changes from Dala.

## [0.0.2]

### Changed

- Template updates.
