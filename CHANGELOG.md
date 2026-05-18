<!--
SPDX-FileCopyrightText: 2024 Dala contributors <https://github.com/manhvu/dala/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](https://conventionalcommits.org) for commit guidelines.

<!-- changelog -->

## [Unreleased]

## [v0.2.0](https://github.com/manhvu/dala/compare/v0.1.1...v0.2.0)

### Features:

* Update dala dependency version to `~> 0.2.0`
* Update dala_dev dependency version to `~> 0.2.0`
* Add `jason` dependency to generated projects (required by upstream dala)
* Add `generators: [timestamp_type: :utc_datetime]` to generated config
* Update `Dala.Audio` → `Dala.Media.Audio` in audio_screen template
* Update `Dala.Camera` → `Dala.Media.Camera` in camera_screen template
* Update `Dala.Haptic` → `Dala.Hardware.Haptic` in home_screen template
* Add haptic feedback on theme switch in home_screen template
* Update `Dala.Socket.push_screen/3` calls to always pass `%{}` params
* Update `Dala.Storage.Storage.write/2` return match to `{:ok, _path}`
* Update cookie env var to `<app>_DIST_COOKIE` pattern in app template
* Update AGENTS.md with new module renames and API changes
* Update `.tool-versions.eex` with dala version comment

### Breaking Changes:

* `Dala.Socket.push_screen/3` now requires 3 arguments (params no longer optional)
* `Dala.Audio` module moved to `Dala.Media.Audio`
* `Dala.Camera` module moved to `Dala.Media.Camera`
* `Dala.Haptic` module moved to `Dala.Hardware.Haptic`

## [v0.1.1]

### Breaking Changes:

* Remove `Dala.Sigil` and `~dala` sigil from all screen templates — helpers now use `Dala.UI.*` function calls directly

## [v0.0.3](https://github.com/manhvu/dala/compare/v0.0.2...v0.0.3) (2025-05-06)

### Features:

* Update dala dependency version to `~> 0.0.3`
* Update Elixir version to `1.19.5-otp-28` in `.tool-versions.eex`

### Bug Fixes:

* Fix screen templates to use correct Spark DSL syntax (`screen do name :atom ... end`)
* Fix screen templates to use `render/1` with `Dala.UI.*` functions for complex screens
  (Spark DSL `screen` block only accepts registered entities, not arbitrary function calls)
* Fix `~MOB` sigil → `~dala` sigil in home_screen template
* Fix `Dala.UI.*` prop name mismatches: `keyboard` → `keyboard_type`, `min`/`max` → `min_value`/`max_value`,
  `content_mode` → `resize_mode`, `weight` → `fill_width` (weight not in UI API)
* Fix `MOB_SIM_RUNTIME_DIR` → `DALA_SIM_RUNTIME_DIR` in iOS build.sh comment
* Remove invalid `align` prop from `Dala.UI.column` calls (silently dropped by Map.take)
* Remove invalid `weight` prop from `Dala.UI.button` and `Dala.UI.camera_preview` calls

### Cleanup:

* Delete leftover `mob.exs.eex` template (renamed to `dala.exs.eex`)
* Delete leftover `priv/static/mob.new/` directory (renamed to `priv/static/dala.new/`)
* Delete leftover `MobBridge.kt.eex`, `MobNode.kt.eex`, `MobScannerActivity.kt.eex` templates
* Update AGENTS.md with current template approach and prop name gotchas

## [v0.1.31](https://github.com/manhvu/dala/compare/v0.1.30...v0.1.31) (2024-01-02)

### Features:

* Update all screen templates to use new Spark DSL style from `dala` repo
* Templates now use `screen "name" do ... end` blocks instead of separate `mount/3` and `render/1` functions
* Update `dala` dependency version to `~> 0.0.2` and `dala_dev` to `~> 0.0.3`
* Update Elixir version requirement to `~> 1.19` in generated projects

### Improvements:

* Simplify template code by leveraging Spark DSL automatic render/1 generation
* Update AGENTS.md with documentation about Spark DSL template style

## [v0.1.30](https://github.com/manhvu/dala/compare/v0.1.29...v0.1.30) (2024-01-01)

### Improvements:

* Apply Igniter-style project structure and documentation
* Add SPDX license headers to source files
* Improve mix.exs with better docs, aliases, and dialyzer support
* Update README with badges and structured sections for end-users and contributors
* Add CHANGELOG.md following conventional commits
* Add groups_for_modules for documentation
