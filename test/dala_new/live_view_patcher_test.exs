# SPDX-FileCopyrightText: 2024 Dala contributors <https://github.com/manhvu/dala/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule DalaNew.LiveViewPatcherTest do
  use ExUnit.Case, async: true

  alias DalaNew.LiveViewPatcher

  # ── inject_dala_hook/1 ─────────────────────────────────────────────────────────

  describe "inject_dala_hook/1" do
    @sample_app_js """
    import "phoenix_html"
    import {Socket} from "phoenix"
    import {LiveSocket} from "phoenix_live_view"
    import topbar from "../vendor/topbar"

    let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
    let liveSocket = new LiveSocket("/live", Socket, {
      longPollFallbackMs: 2500,
      params: {_csrf_token: csrfToken}
    })

    liveSocket.connect()
    window.liveSocket = liveSocket
    """

    test "injects DalaHook definition after last import" do
      result = LiveViewPatcher.inject_dala_hook(@sample_app_js)
      assert result =~ "const DalaHook ="
      # DalaHook should appear after the import block
      assert String.split(result, "const DalaHook")
             |> List.last()
             |> String.contains?("import topbar") == false
    end

    test "registers DalaHook in LiveSocket hooks option" do
      result = LiveViewPatcher.inject_dala_hook(@sample_app_js)
      assert result =~ "hooks: {DalaHook}"
    end

    test "is idempotent — does not double-inject if DalaHook already present" do
      once = LiveViewPatcher.inject_dala_hook(@sample_app_js)
      twice = LiveViewPatcher.inject_dala_hook(once)
      assert once == twice
    end

    test "injects pushEvent-based send function" do
      result = LiveViewPatcher.inject_dala_hook(@sample_app_js)
      assert result =~ "pushEvent(\"dala_message\", data)"
    end

    test "injects handleEvent-based onMessage function" do
      result = LiveViewPatcher.inject_dala_hook(@sample_app_js)
      assert result =~ "handleEvent(\"dala_push\", handler)"
    end

    test "handles LiveSocket with existing hooks: {} key" do
      content = """
      import {LiveSocket} from "phoenix_live_view"
      let liveSocket = new LiveSocket("/live", Socket, {hooks: {}})
      liveSocket.connect()
      """

      result = LiveViewPatcher.inject_dala_hook(content)
      assert result =~ "hooks: {DalaHook}"
      refute result =~ "hooks: {}"
    end

    test "handles LiveSocket with existing hooks containing other hooks" do
      content = """
      import {LiveSocket} from "phoenix_live_view"
      let liveSocket = new LiveSocket("/live", Socket, {hooks: {OtherHook}})
      liveSocket.connect()
      """

      result = LiveViewPatcher.inject_dala_hook(content)
      assert result =~ "DalaHook"
      assert result =~ "OtherHook"
    end
  end

  # ── inject_dala_bridge_element/1 ───────────────────────────────────────────────

  describe "inject_dala_bridge_element/1" do
    @sample_root_html """
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
      </head>
      <body class="bg-white">
        {@inner_content}
      </body>
    </html>
    """

    test "injects dala-bridge div after opening body tag" do
      result = LiveViewPatcher.inject_dala_bridge_element(@sample_root_html)
      assert result =~ ~s(id="dala-bridge")
      assert result =~ ~s(phx-hook="DalaHook")
    end

    test "bridge element appears before inner_content" do
      result = LiveViewPatcher.inject_dala_bridge_element(@sample_root_html)

      assert String.split(result, "dala-bridge")
             |> List.first()
             |> String.contains?("inner_content") == false
    end

    test "is idempotent — does not double-inject" do
      once = LiveViewPatcher.inject_dala_bridge_element(@sample_root_html)
      twice = LiveViewPatcher.inject_dala_bridge_element(once)
      assert once == twice
      # Only one dala-bridge element
      count = String.split(twice, "dala-bridge") |> length()
      # original + one bridge element
      assert count == 2
    end

    test "preserves body tag attributes" do
      result = LiveViewPatcher.inject_dala_bridge_element(@sample_root_html)
      assert result =~ ~s(<body class="bg-white">)
    end
  end

  # ── inject_deps/3 ─────────────────────────────────────────────────────────────

  describe "inject_deps/3" do
    @sample_mix_exs """
    defmodule MyApp.MixProject do
      use Mix.Project

      defp deps do
        [
          {:phoenix, "~> 1.7"},
          {:ecto, "~> 3.0"}
        ]
      end
    end
    """

    test "injects dala dep into deps function" do
      result =
        LiveViewPatcher.inject_deps(
          @sample_mix_exs,
          ~s({:dala, "~> 0.2"}),
          ~s({:dala_dev, "~> 0.2", only: :dev})
        )

      assert result =~ ~s({:dala, "~> 0.2"})
    end

    test "injects dala_dev dep into deps function" do
      result =
        LiveViewPatcher.inject_deps(
          @sample_mix_exs,
          ~s({:dala, "~> 0.2"}),
          ~s({:dala_dev, "~> 0.2", only: :dev})
        )

      assert result =~ ~s({:dala_dev, "~> 0.2", only: :dev})
    end

    test "preserves existing deps" do
      result =
        LiveViewPatcher.inject_deps(
          @sample_mix_exs,
          ~s({:dala, "~> 0.2"}),
          ~s({:dala_dev, "~> 0.2", only: :dev})
        )

      assert result =~ ~s({:phoenix, "~> 1.7"})
      assert result =~ ~s({:ecto, "~> 3.0"})
    end

    test "is idempotent — does not double-inject if :dala already present" do
      once =
        LiveViewPatcher.inject_deps(
          @sample_mix_exs,
          ~s({:dala, "~> 0.2"}),
          ~s({:dala_dev, "~> 0.2", only: :dev})
        )

      twice =
        LiveViewPatcher.inject_deps(
          once,
          ~s({:dala, "~> 0.2"}),
          ~s({:dala_dev, "~> 0.2", only: :dev})
        )

      assert once == twice
    end
  end

  # ── dala_live_app_content/4 ────────────────────────────────────────────────────

  describe "dala_live_app_content/4" do
    @secret "testSecretKeyBase1234567890abcdefghijklmnopqrstuvwxyz"
    @salt "testSalt"

    defp live_app_content,
      do: LiveViewPatcher.dala_live_app_content("MyApp", "my_app", @secret, @salt)

    test "contains correct module name" do
      assert live_app_content() =~ "defmodule MyApp.DalaApp"
    end

    test "calls Application.ensure_all_started with app name" do
      assert live_app_content() =~ "ensure_all_started(:my_app)"
    end

    test "calls Dala.Screen.start_root with DalaScreen" do
      assert live_app_content() =~ "Dala.Screen.start_root"
      assert live_app_content() =~ "MyApp.DalaScreen"
    end

    test "installs Dala.Platform.NativeLogger" do
      assert live_app_content() =~ "Dala.Platform.NativeLogger.install()"
    end

    test "starts Erlang distribution" do
      assert live_app_content() =~ "Dala.Connectivity.Dist.ensure_started"
    end

    test "sets Application.put_env for :dala liveview_port" do
      assert live_app_content() =~ "Application.put_env(:dala, :liveview_port"
    end

    test "sets Application.put_env for endpoint with Bandit adapter" do
      content = live_app_content()
      assert content =~ "Application.put_env(:my_app, MyAppWeb.Endpoint"
      assert content =~ "adapter: Bandit.PhoenixAdapter"
    end

    test "endpoint config includes port from liveview_port env" do
      assert live_app_content() =~ "port: liveview_port"
    end

    test "endpoint config defaults to port 4200" do
      assert live_app_content() =~ "Application.get_env(:dala, :liveview_port, 4200)"
    end

    test "starts Dala.Ui.NativeView.Registry" do
      assert live_app_content() =~ "Dala.Ui.NativeView.Registry.start_link()"
    end

    test "embeds secret_key_base" do
      assert live_app_content() =~ "secret_key_base: \"#{@secret}\""
    end

    test "embeds signing_salt" do
      assert live_app_content() =~ "signing_salt: \"#{@salt}\""
    end
  end

  # ── erlang_entry_content/2 ────────────────────────────────────────────────────

  describe "erlang_entry_content/2" do
    test "has correct module declaration" do
      content = LiveViewPatcher.erlang_entry_content("MyApp", "my_app")
      assert content =~ "-module(my_app)."
    end

    test "exports start/0" do
      content = LiveViewPatcher.erlang_entry_content("MyApp", "my_app")
      assert content =~ "-export([start/0])."
    end

    test "calls DalaApp module" do
      content = LiveViewPatcher.erlang_entry_content("MyApp", "my_app")
      assert content =~ "'Elixir.MyApp.DalaApp':start()"
    end

    test "starts compiler, elixir, logger applications" do
      content = LiveViewPatcher.erlang_entry_content("MyApp", "my_app")
      assert content =~ "application:start(compiler)"
      assert content =~ "application:start(elixir)"
      assert content =~ "application:start(logger)"
    end
  end

  # ── dala_screen_content/1 ──────────────────────────────────────────────────────

  describe "dala_screen_content/1" do
    test "contains DalaScreen module" do
      content = LiveViewPatcher.dala_screen_content("MyApp")
      assert content =~ "defmodule MyApp.DalaScreen"
    end

    test "uses Dala.Spark.Dsl" do
      content = LiveViewPatcher.dala_screen_content("MyApp")
      assert content =~ "use Dala.Spark.Dsl"
    end

    test "renders a webview with local Phoenix URL" do
      content = LiveViewPatcher.dala_screen_content("MyApp")
      assert content =~ "webview"
      assert content =~ "http://127.0.0.1:4200/"
    end
  end

  # ── page_live_content/2 ───────────────────────────────────────────────────────

  describe "page_live_content/2" do
    test "uses correct web module" do
      content = LiveViewPatcher.page_live_content("MyApp", "my_app")
      assert content =~ "defmodule MyAppWeb.PageLive"
      assert content =~ "use MyAppWeb, :live_view"
    end

    test "has mount/3 assigning pong false" do
      content = LiveViewPatcher.page_live_content("MyApp", "my_app")
      assert content =~ "def mount"
      assert content =~ ":pong, false"
    end

    test "has ping handle_event that sets pong true" do
      content = LiveViewPatcher.page_live_content("MyApp", "my_app")
      assert content =~ ~s(handle_event("ping")
      assert content =~ ":pong, true"
    end

    test "template references app name in instructions" do
      content = LiveViewPatcher.page_live_content("MyApp", "my_app")
      assert content =~ "my_app_web/live/page_live.ex"
    end
  end

  # ── liveview_build_sh_content/2 ───────────────────────────────────────────────

  describe "liveview_build_sh_content/2" do
    defp build_sh, do: LiveViewPatcher.liveview_build_sh_content("MyApp", "my_app")

    test "is a bash script" do
      assert String.starts_with?(build_sh(), "#!/bin/bash")
    end

    test "copies all compiled deps with a glob loop" do
      assert build_sh() =~ "for lib_dir in _build/dev/lib/*/ebin"
    end

    test "crypto shim exports pbkdf2_hmac/5" do
      assert build_sh() =~ "pbkdf2_hmac/5"
    end

    test "crypto shim exports exor/2" do
      assert build_sh() =~ "exor/2"
    end

    test "crypto shim implements hmac_md5 using erlang:md5" do
      assert build_sh() =~ "hmac_md5"
      assert build_sh() =~ "erlang:md5"
    end

    test "xor_bytes uses recursive zip pattern" do
      assert build_sh() =~ "xor_bytes(A, B) -> xor_bytes(A, B, [])."
    end

    test "copies ssl from host OTP" do
      assert build_sh() =~ "Copying ssl from host OTP"
      assert build_sh() =~ "ssl.app"
    end

    test "builds and deploys Phoenix static assets" do
      content = build_sh()
      assert content =~ "mix assets.build"
      assert content =~ "priv/static"
    end

    test "spot-check verifies DalaApp and DalaScreen beams" do
      content = build_sh()
      assert content =~ "Elixir.MyApp.DalaApp.beam"
      assert content =~ "Elixir.MyApp.DalaScreen.beam"
    end

    test "uses app_name in BEAMS_DIR" do
      assert build_sh() =~ "OTP_ROOT/my_app"
    end

    test "uses module_name in swiftc module-name flag" do
      assert build_sh() =~ "-module-name MyApp"
    end

    test "honors DALA_SIM_RUNTIME_DIR env var (regression: must not hardcode /tmp)" do
      # Native template at priv/templates/dala.new/ios/build.sh.eex respects
      # DALA_SIM_RUNTIME_DIR with ~/.dala/runtime/ios-sim default; the LV path
      # used to hardcode /tmp/otp-ios-sim, so `mix dala.deploy --native` synced
      # OTP into ~/.dala/runtime/ios-sim while build.sh wrote /tmp/otp-ios-sim
      # — the two halves disagreed and the simulator never saw fresh BEAMs.
      content = build_sh()
      assert content =~ ~s(RUNTIME_DIR="${DALA_SIM_RUNTIME_DIR:-$HOME/.dala/runtime/ios-sim}")

      refute content =~ "/tmp/otp-ios-sim",
             "build.sh hardcodes /tmp/otp-ios-sim — should use $BEAMS_DIR"
    end

    test "all runtime-dir uses go through $BEAMS_DIR" do
      # Check that BEAMS_DIR is set and used in copy operations
      content = build_sh()
      assert content =~ ~s(BEAMS_DIR="$OTP_ROOT/my_app")
      assert content =~ ~s(cp "$lib_dir"/* "$BEAMS_DIR/")
      assert content =~ ~s($BEAMS_DIR/dala_logo_dark.png)
      assert content =~ ~s($BEAMS_DIR/dala_logo_light.png)
      assert content =~ ~s($BEAMS_DIR/priv/)
    end
  end

  # ── dala_exs_content/2 ─────────────────────────────────────────────────────────

  describe "dala_exs_content/2" do
    test "contains dala_dir config" do
      content = LiveViewPatcher.dala_exs_content(~s("/path/to/dala"), ~s("/path/to/elixir/lib"))
      assert content =~ "dala_dir:"
    end

    test "contains elixir_lib config" do
      content = LiveViewPatcher.dala_exs_content(~s("/path/to/dala"), ~s("/path/to/elixir/lib"))
      assert content =~ "elixir_lib:"
    end

    test "contains liveview_port: 4200 (avoids conflict with host phx.server on 4000)" do
      content = LiveViewPatcher.dala_exs_content(~s("/path/to/dala"), ~s("/path/to/elixir/lib"))
      assert content =~ "liveview_port: 4200"
    end

    test "starts with import Config" do
      content = LiveViewPatcher.dala_exs_content(~s("/path/to/dala"), ~s("/path/to/elixir/lib"))
      assert content =~ "import Config"
    end
  end

  # ── dala_live_app_content/4 — Ecto additions ───────────────────────────────────

  describe "dala_live_app_content/4 ecto additions" do
    defp live_app do
      LiveViewPatcher.dala_live_app_content("MyApp", "my_app", "secret", "salt")
    end

    test "starts ecto_sqlite3 before the app" do
      content = live_app()
      assert content =~ "ensure_all_started(:ecto_sqlite3)"
      ecto_part = String.split(content, "ensure_all_started(:ecto_sqlite3)") |> List.last()
      refute ecto_part |> String.contains?("ensure_all_started(:MyApp)")
    end

    test "runs Ecto.Migrator after app start" do
      content = live_app()
      assert content =~ "Ecto.Migrator.with_repo(MyApp.Repo"
      assert content =~ "Ecto.Migrator.run"
      assert content =~ ":up, all: true"
    end

    test "has migrations_dir/0 that reads DALA_BEAMS_DIR" do
      content = live_app()
      assert content =~ "defp migrations_dir"
      assert content =~ "DALA_BEAMS_DIR"
    end
  end

  # ── repo_content/2 ────────────────────────────────────────────────────────────

  describe "repo_content/2" do
    defp repo, do: LiveViewPatcher.repo_content("MyApp", "my_app")

    test "has correct module name and otp_app" do
      assert repo() =~ "defmodule MyApp.Repo"
      assert repo() =~ "otp_app: :my_app"
      assert repo() =~ "Ecto.Adapters.SQLite3"
    end

    test "init/2 reads DALA_DATA_DIR" do
      assert repo() =~ "DALA_DATA_DIR"
      assert repo() =~ "app.db"
    end

    test "init/2 sets pool_size: 1" do
      assert repo() =~ "pool_size: 1"
    end
  end

  # ── note_content/1 ────────────────────────────────────────────────────────────

  describe "note_content/1" do
    test "has correct module and schema" do
      content = LiveViewPatcher.note_content("MyApp")
      assert content =~ "defmodule MyApp.Note"
      assert content =~ ~s(schema "notes")
      assert content =~ "field :title"
      assert content =~ "field :body"
    end
  end

  # ── notes_content/2 ───────────────────────────────────────────────────────────

  describe "notes_content/2" do
    defp notes, do: LiveViewPatcher.notes_content("MyApp", "my_app")

    test "has correct module and alias" do
      assert notes() =~ "defmodule MyApp.Notes"
      assert notes() =~ "alias MyApp.{Repo, Note}"
    end

    test "has list/0, get/1, create/0, update/2, delete/1" do
      content = notes()
      assert content =~ "def list"
      assert content =~ "def get(id)"
      assert content =~ "def create"
      assert content =~ "def update(id"
      assert content =~ "def delete(id)"
    end

    test "seeds on first load" do
      assert notes() =~ "maybe_seed"
      assert notes() =~ "Welcome to Dala"
    end
  end

  # ── migration_content/0 ───────────────────────────────────────────────────────

  describe "migration_content/1" do
    test "creates notes table with title and body" do
      content = LiveViewPatcher.migration_content("my_app")
      assert content =~ "MyApp.Repo.Migrations.CreateNotes"
      assert content =~ "create table(:notes)"
      assert content =~ "add :title"
      assert content =~ "add :body"
    end
  end

  # ── notes_list_live_content/2 ─────────────────────────────────────────────────

  describe "notes_list_live_content/2" do
    defp nll, do: LiveViewPatcher.notes_list_live_content("MyApp", "my_app")

    test "correct module and alias" do
      assert nll() =~ "defmodule MyAppWeb.NotesListLive"
      assert nll() =~ "alias MyApp.Notes"
    end

    test "mounts with notes list" do
      assert nll() =~ "Notes.list()"
    end

    test "handles new_note, open, delete events" do
      content = nll()
      assert content =~ ~s("new_note")
      assert content =~ ~s("open")
      assert content =~ ~s("delete")
    end
  end

  # ── note_editor_live_content/2 ────────────────────────────────────────────────

  describe "note_editor_live_content/2" do
    defp nel, do: LiveViewPatcher.note_editor_live_content("MyApp", "my_app")

    test "correct module and alias" do
      assert nel() =~ "defmodule MyAppWeb.NoteEditorLive"
      assert nel() =~ "alias MyApp.Notes"
    end

    test "mounts with note by id" do
      assert nel() =~ ~s(%{"id" => id})
      assert nel() =~ "Notes.get(id)"
    end

    test "handles update_note event" do
      assert nel() =~ ~s("update_note")
      assert nel() =~ "Notes.update"
    end

    test "has word count" do
      assert nel() =~ "word_count"
      assert nel() =~ "count_words"
    end
  end

  # ── about_live_content/2 ──────────────────────────────────────────────────────

  describe "about_live_content/2" do
    defp about, do: LiveViewPatcher.about_live_content("MyApp", "my_app")

    test "correct module" do
      assert about() =~ "defmodule MyAppWeb.AboutLive"
    end

    test "shows OTP release and Elixir version" do
      content = about()
      assert content =~ "system_info(:otp_release)"
      assert content =~ "System.version()"
    end

    test "shows notes count via Notes.list()" do
      assert about() =~ "MyApp.Notes.list() |> length()"
    end

    test "handles name editing events" do
      content = about()
      assert content =~ ~s("edit_name")
      assert content =~ ~s("save_name")
    end
  end
end
