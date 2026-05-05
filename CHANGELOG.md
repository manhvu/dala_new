<!--
SPDX-FileCopyrightText: 2024 Dala contributors <https://github.com/manhvu/dala/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](https://conventionalcommits.org) for commit guidelines.

<!-- changelog -->

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
