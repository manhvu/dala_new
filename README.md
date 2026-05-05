<!--
SPDX-FileCopyrightText: 2024 Dala contributors <https://github.com/manhvu/dala/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# DalaNew

[![CI](https://github.com/manhvu/dala/actions/workflows/elixir.yml/badge.svg)](https://github.com/manhvu/dala/actions/workflows/elixir.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Hex version badge](https://img.shields.io/hexpm/v/dala_new.svg)](https://hex.pm/packages/dala_new)
[![Hexdocs badge](https://img.shields.io/badge/docs-hexdocs-purple)](https://hexdocs.pm/dala_new)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/manhvu/dala)

Project generator for the [Dala](https://hexdocs.pm/dala) mobile framework. Installs a global `mix dala.new` command to generate native SwiftUI/Compose apps or LiveView-wrapped mobile projects.

Original repo [mob_new](https://github.com/GenericJam/mob_new)

## For end-users

### Installation

`dala_new` is a Mix archive — install it globally, not as a project dependency:

```bash
mix archive.install hex dala_new
```

### Usage

```bash
mix dala.new my_app
cd my_app
mix dala.install    # first-run setup: download OTP runtime, generate icons, write dala.exs
```

### Options

| Option | Description |
|--------|-------------|
| `--ios` | Generate iOS boilerplate only (skip `android/`) |
| `--android` | Generate Android boilerplate only (skip `ios/`) |
| `--liveview` | Wrap a Phoenix LiveView app in a Dala WebView (combines with `--ios` / `--android`) |
| `--no-install` | Skip `mix deps.get` after generation |
| `--dest DIR` | Create the project in DIR (default: current directory) |
| `--local` | Use `path:` deps pointing to local dala/dala_dev repos — see below |
| `--no-ios` | Alias for `--android` (skip iOS boilerplate) |
| `--no-android` | Alias for `--ios` (skip Android boilerplate) |

`mix dala.install`, `mix dala.deploy`, and `mix dala.doctor` detect the project's
platform set from on-disk layout, so a single-platform project skips the
absent platform's setup automatically (no Android OTP download, no iOS
toolchain check, etc.).

### Local development mode (`--local`)

> **This flag is for Dala framework contributors and library authors testing
> unpublished changes. It is not intended for app developers — use the standard
> `mix dala.new my_app` instead.**

#### Installing the local dala_new archive

When working on dala_new itself, build and force-install the archive to pick up your changes:

```bash
cd ~/code/dala_new && mix archive.build && mix archive.install $(ls dala_new-*.ez | tail -1) --force
```

Verify it's active:

```bash
mix archive        # dala_new should appear with the updated version
mix dala.new --help
```

If you are working on Dala itself and want to test your changes end-to-end
before publishing to Hex, pass `--local` to generate a project that depends on
your local checkouts instead of the published packages:

```bash
mix dala.new my_app --local
```

This generates `mix.exs` with `path:` deps:

```elixir
{:dala,     path: "/path/to/dala"},
{:dala_dev, path: "/path/to/dala_dev", only: :dev, runtime: false}
```

It also pre-fills `dala.exs` with your actual local paths so `mix dala.install`
skips the path configuration prompts and proceeds straight to OTP download and
icon generation.

**Path resolution** (in order):

1. `DALA_DIR` / `DALA_DEV_DIR` environment variables
2. `./dala` / `./dala_dev` in the current directory (e.g. running from `~/code`)
3. `../dala` / `../dala_dev` relative to the current directory

```bash
# If dala and dala_dev live alongside each other in ~/code:
cd ~/code
mix dala.new my_app --local   # auto-detects ~/code/dala and ~/code/dala_dev

# Or set explicitly from anywhere:
DALA_DIR=~/code/dala DALA_DEV_DIR=~/code/dala_dev mix dala.new my_app --local
```

## What gets generated

```
my_app/
├── mix.exs
├── lib/
│   └── my_app/
│       ├── app.ex           # Dala.App entry point
│       └── home_screen.ex   # starter screen
├── android/
│   ├── build.gradle
│   └── app/
│       └── src/main/
│           ├── AndroidManifest.xml
│           └── java/com/dala/my_app/MainActivity.java
└── ios/
    ├── beam_main.m
    └── Info.plist
```

## Next steps after generation

First deploy (builds the native app and installs it):

```bash
mix dala.deploy --native
```

Day-to-day (hot-pushes changed BEAMs, no native rebuild):

```bash
mix dala.deploy        # push + restart
mix dala.watch         # auto-push on file save
mix dala.connect       # open IEx connected to the running device node
```

## For contributors and library authors

### Building and installing locally

```bash
cd ~/code/dala_new
mix archive.build                          # produces dala_new-<version>.ez
mix archive.install dala_new-0.1.27.ez --force
mix archive                                # verify install
```

To publish a new version: bump `version:` in `mix.exs`, then
`mix hex.publish archive`.

### Testing

```bash
mix test                        # unit tests (fast)
mix test --include integration  # also runs `mix phx.new` subprocesses (~minute)
```

The integration tests generate real LV projects in tmp dirs to verify the
end-to-end output. Worth running locally before publishing a new version.

### Project structure

Templates live at `priv/templates/dala.new/`, rendered with EEx by
`DalaNew.ProjectGenerator`. The LiveView path additionally runs `mix phx.new`
as a subprocess and patches the result via `DalaNew.LiveViewPatcher`.

## Documentation

Full guide at [hexdocs.pm/dala](https://hexdocs.pm/dala), including [Getting Started](https://hexdocs.pm/dala/getting_started.html), screen lifecycle, components, navigation, and live debugging.
