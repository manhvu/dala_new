# SPDX-FileCopyrightText: 2024 Dala contributors <https://github.com/manhvu/dala/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule DalaNew.LiveViewGeneratorTest do
  # async: false — Mix.shell() is process-global.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias DalaNew.LiveViewGenerator

  setup do
    tmp = Path.join(System.tmp_dir!(), "dala_new_lvg_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, tmp: tmp}
  end

  defp capture_shell_error(fun) do
    capture_io(:stderr, fun)
  end

  # ── liveview_phoenix_owned?/3 ─────────────────────────────────────────────────

  describe "liveview_phoenix_owned?/3" do
    @root "/tmp/lvg_templates_root"

    defp owned?(rel, opts \\ [liveview: true]) do
      LiveViewGenerator.liveview_phoenix_owned?(Path.join(@root, rel), @root, opts)
    end

    test "returns false when :liveview is not set" do
      refute owned?("mix.exs.eex", [])
      refute owned?("config/config.exs.eex", [])
    end

    test "returns false when :liveview is explicitly false" do
      refute owned?("mix.exs.eex", liveview: false)
    end

    test "blocks Phoenix-owned top-level files" do
      assert owned?("mix.exs.eex")
      assert owned?(".gitignore.eex")
      assert owned?(".tool-versions.eex")
    end

    test "blocks anything under config/" do
      assert owned?("config/config.exs.eex")
      assert owned?("config/dev.exs.eex")
      assert owned?("config/runtime.exs.eex")
    end

    test "blocks anything under lib/app_name/" do
      assert owned?("lib/app_name/screen.ex.eex")
      assert owned?("lib/app_name/audio.ex.eex")
    end

    test "blocks anything under priv/" do
      assert owned?("priv/repo/migrations/foo.exs")
      assert owned?("priv/static/x.txt")
    end

    test "does NOT block native-only paths" do
      refute owned?("android/app/build.gradle.eex")
      refute owned?("ios/Info.plist.eex")
      refute owned?("src/app_name.erl.eex")
      refute owned?("dala.exs.eex")
    end

    test "does NOT block lib/app_name_web (prefix must not over-match)" do
      refute owned?("lib/app_name_web/router.ex.eex")
    end
  end

  # ── generate/3 — failure paths (unit-testable without phx.new) ────────────────

  describe "generate/3 failure paths" do
    test "returns error when the project directory already exists", %{tmp: tmp} do
      File.mkdir_p!(Path.join(tmp, "lv_exists"))
      assert {:error, msg} = LiveViewGenerator.generate("lv_exists", tmp)
      assert msg =~ "already exists"
    end

    test "cleans up the partial directory when a patch step fails", %{tmp: tmp} do
      # Simulate a broken phx.new: create a fake `mix` executable that exits
      # non-zero. run_phx_new should surface its output as an error and the
      # generator must remove any partial directory it created.
      fake_bin = Path.join(tmp, "fake_bin")
      File.mkdir_p!(fake_bin)

      File.write!(Path.join(fake_bin, "mix"), """
      #!/bin/sh
      echo "simulated phx.new boom" >&2
      exit 3
      """)

      File.chmod!(Path.join(fake_bin, "mix"), 0o755)

      prev_path = System.get_env("PATH")
      System.put_env("PATH", "#{fake_bin}:#{prev_path}")

      try do
        assert {:error, reason} = LiveViewGenerator.generate("lv_fail", tmp)
        assert reason =~ "mix phx.new failed"
        assert reason =~ "simulated phx.new boom"

        # The partial directory must have been cleaned up so a retry works.
        refute File.dir?(Path.join(tmp, "lv_fail"))
      after
        System.put_env("PATH", prev_path)
      end
    end

    test "returns error when mix is not in PATH", %{tmp: tmp} do
      prev_path = System.get_env("PATH")
      System.put_env("PATH", "")

      try do
        assert {:error, "mix executable not found in PATH"} =
                 LiveViewGenerator.generate("lv_nomix", tmp)

        refute File.dir?(Path.join(tmp, "lv_nomix"))
      after
        System.put_env("PATH", prev_path)
      end
    end
  end

  # ── missing-file branches (Mimic on File) ──────────────────────────────────
  #
  # These branches fire when a file that earlier steps depend on is missing
  # mid-pipeline (e.g. phx.new changed its layout). Mock File.exists?/1 to
  # report specific paths as missing and assert the pipeline fails cleanly.

  # ── patch-step warnings (driven via a fake phx.new scaffold) ──────────

  describe "patch-step failures via fake phx.new" do
    defp install_fake_phx_new(tmp, scaffold_fn) do
      fake_bin = Path.join(tmp, "fake_bin_#{System.unique_integer([:positive])}")
      File.mkdir_p!(fake_bin)

      script = Path.join(fake_bin, "mix")

      File.write!(script, """
      #!/bin/sh
      if [ "$1" = "phx.new" ]; then
        APP=$2
        cd "$(pwd)"
        #{scaffold_fn.("$APP")}
        exit 0
      fi
      exit 1
      """)

      # scaffold_fn receives the app name and must emit shell commands.
      File.chmod!(script, 0o755)
      fake_bin
    end

    test "returns error when the scaffold omits assets/js/app.js", %{tmp: tmp} do
      scaffold = fn app ->
        """
        mkdir -p "#{app}/lib/#{app}_web/components/layouts" \
                 "#{app}/lib/#{app}" \
                 "#{app}/config" \
                 "#{app}/assets/js"
        cat > "#{app}/mix.exs" <<'EOF'
        defmodule MixProject do
          use Mix.Project
          def project do
            [app: :placeholder]
          end
          defp deps do
            []
          end
        end
        EOF
        cat > "#{app}/lib/#{app}_web/components/layouts/root.html.heex" <<'EOF'
        <body>
        </body>
        EOF
        cat > "#{app}/config/config.exs" <<'EOF'
        import Config
        EOF
        cat > "#{app}/config/dev.exs" <<'EOF'
        import Config
        config :placeholder, Endpoint, http: [port: 4000]
        EOF
        cat > "#{app}/config/test.exs" <<'EOF'
        import Config
        config :placeholder, Endpoint, http: [port: 4002]
        EOF
        cat > "#{app}/config/runtime.exs" <<'EOF'
        import Config
        port = String.to_integer(System.get_env("PORT") || "4000")
        EOF
        cat > "#{app}/lib/#{app}/application.ex" <<'EOF'
        defmodule Placeholder.Application do
          def start do
            PlaceholderWeb.Endpoint
          end
        end
        EOF
        cat > "#{app}/lib/#{app}_web/router.ex" <<'EOF'
        defmodule Router do
        end
        EOF
        # Deliberately NO assets/js/app.js
        """
      end

      fake_bin = install_fake_phx_new(tmp, scaffold)
      prev_path = System.get_env("PATH")
      System.put_env("PATH", "#{fake_bin}:#{prev_path}")

      try do
        assert {:error, msg} = LiveViewGenerator.generate("lv_nojs", tmp)
        assert msg =~ "assets/js/app.js not found"
        refute File.dir?(Path.join(tmp, "lv_nojs"))
      after
        System.put_env("PATH", prev_path)
        File.rm_rf!(fake_bin)
      end
    end

    test "returns error when the scaffold omits root.html.heex", %{tmp: tmp} do
      scaffold = fn app ->
        """
        mkdir -p "#{app}/lib/#{app}_web/components/layouts" \
                 "#{app}/lib/#{app}" \
                 "#{app}/config" \
                 "#{app}/assets/js"
        cat > "#{app}/assets/js/app.js" <<'EOF'
        import {LiveSocket} from "phoenix_live_view"
        let liveSocket = new LiveSocket("/live", Socket, {})
        liveSocket.connect()
        EOF
        cat > "#{app}/mix.exs" <<'EOF'
        defmodule MixProject do
          use Mix.Project
          def project do
            [app: :placeholder]
          end
          defp deps do
            []
          end
        end
        EOF
        cat > "#{app}/config/config.exs" <<'EOF'
        import Config
        EOF
        cat > "#{app}/config/dev.exs" <<'EOF'
        import Config
        config :placeholder, Endpoint, http: [port: 4000]
        EOF
        cat > "#{app}/config/test.exs" <<'EOF'
        import Config
        config :placeholder, Endpoint, http: [port: 4002]
        EOF
        cat > "#{app}/config/runtime.exs" <<'EOF'
        import Config
        port = String.to_integer(System.get_env("PORT") || "4000")
        EOF
        cat > "#{app}/lib/#{app}/application.ex" <<'EOF'
        defmodule Placeholder.Application do
          def start do
            PlaceholderWeb.Endpoint
          end
        end
        EOF
        cat > "#{app}/lib/#{app}_web/router.ex" <<'EOF'
        defmodule Router do
        end
        EOF
        # Deliberately NO root.html.heex
        """
      end

      fake_bin = install_fake_phx_new(tmp, scaffold)
      prev_path = System.get_env("PATH")
      System.put_env("PATH", "#{fake_bin}:#{prev_path}")

      try do
        assert {:error, msg} = LiveViewGenerator.generate("lv_nohtml", tmp)
        assert msg =~ "root.html.heex not found"
        refute File.dir?(Path.join(tmp, "lv_nohtml"))
      after
        System.put_env("PATH", prev_path)
        File.rm_rf!(fake_bin)
      end
    end

    test "warns but continues when patterns don't match (mismatched scaffold)", %{tmp: tmp} do
      # A scaffold whose mix.exs has no `defp deps do [` and whose router has
      # no PageController route — every regex patch should warn loudly but the
      # generation should still succeed.
      scaffold = fn app ->
        # Note: heredoc bodies and terminators must start at column 0 in the
        # generated shell script, so this string is deliberately not indented.
        # Shell var refs use ${APP} (not $APP) so names like ${APP}_web parse
        # correctly.
        String.replace(
          """
          mkdir -p "${APP}/lib/${APP}_web/components/layouts" \\
                   "${APP}/lib/${APP}" \\
                   "${APP}/config" \\
                   "${APP}/assets/js"
          cat > "${APP}/assets/js/app.js" <<'EOF'
          import {LiveSocket} from "phoenix_live_view"
          let liveSocket = new LiveSocket("/live", Socket, {})
          liveSocket.connect()
          EOF
          cat > "${APP}/lib/${APP}_web/components/layouts/root.html.heex" <<'EOF'
          <body>
          </body>
          EOF
          printf 'defmodule M do\\nend\\n' > "${APP}/mix.exs"
          cat > "${APP}/config/config.exs" <<'EOF'
          import Config
          EOF
          cat > "${APP}/config/dev.exs" <<'EOF'
          import Config
          # no port line at all — the port patch should warn
          EOF
          cat > "${APP}/config/test.exs" <<'EOF'
          import Config
          # no port line at all — the port patch should warn
          EOF
          cat > "${APP}/config/runtime.exs" <<'EOF'
          import Config
          # no PORT fallback — the runtime patch should warn
          EOF
          cat > "${APP}/lib/${APP}/application.ex" <<'EOF'
          defmodule A do
            def start do
              SomeOtherChild
            end
          end
          EOF
          cat > "${APP}/lib/${APP}_web/router.ex" <<'EOF'
          defmodule Router do
          end
          EOF
          mkdir -p "${APP}/android" "${APP}/ios"
          """,
          "\n          ",
          "\n"
        )
      end

      fake_bin = install_fake_phx_new(tmp, scaffold)
      prev_path = System.get_env("PATH")
      System.put_env("PATH", "#{fake_bin}:#{prev_path}")

      try do
        output =
          capture_io(:stdio, fn ->
            result = LiveViewGenerator.generate("lv_warn", tmp)
            send(self(), {:result, result})
          end)

        # Generation still succeeds despite warnings.
        assert_received({:result, {:ok, dir}})
        assert File.dir?(dir)
        assert output != ""
      after
        System.put_env("PATH", prev_path)
        File.rm_rf!(fake_bin)
      end
    end
  end

  # ── missing-file branches (Mimic on File) ──────────────────────────
  #
  # These branches fire when a file that earlier steps depend on is missing
  # mid-pipeline (e.g. phx.new changed its layout). Mock File.exists?/1 to
  # report specific paths as missing and assert the pipeline fails cleanly.

  describe "missing-file error branches" do
    setup do
      import Mimic
      copy(File)
      copy(System)
      :ok
    end

    # Install a fake `mix` (via System.find_executable stub) so the pipeline
    # skips the ~30s real phx.new and instead scaffolds instantly.
    defp install_fast_fake_mix(tmp, app_name) do
      import Mimic

      fake_mix = Path.join(tmp, "fake_mix.sh")
      File.write!(fake_mix, """
      #!/bin/sh
      mkdir -p "#{app_name}/lib/#{app_name}" \\
               "#{app_name}/lib/#{app_name}_web/components/layouts" \\
               "#{app_name}/config" \\
               "#{app_name}/assets/js"
      printf 'defmodule M do\n  def project do\n    [app: :m]\n  end\n  defp deps do\n    []\n  end\nend\n' > "#{app_name}/mix.exs"
      printf '<body></body>\\n' > "#{app_name}/lib/#{app_name}_web/components/layouts/root.html.heex"
      printf 'import Config\\n' > "#{app_name}/config/config.exs"
      printf 'import Config\\nconfig :p, E, http: [port: 4000]\\n' > "#{app_name}/config/dev.exs"
      printf 'import Config\\nconfig :p, E, http: [port: 4002]\\n' > "#{app_name}/config/test.exs"
      printf 'import Config\\nport = String.to_integer(System.get_env("PORT") || "4000")\\n' > "#{app_name}/config/runtime.exs"
      printf 'defmodule A do\\n  def start do\\n    #{Macro.camelize(app_name)}Web.Endpoint\\n  end\\nend\\n' > "#{app_name}/lib/#{app_name}/application.ex"
      printf 'defmodule R do\nend\n' > "#{app_name}/lib/#{app_name}_web/router.ex"
      mkdir -p "#{app_name}/assets/js"
      printf 'const socket = {}\n' > "#{app_name}/assets/js/app.js"
      echo scaffolded
      """)
      File.chmod!(fake_mix, 0o755)

      stub(System, :find_executable, fn "mix" -> fake_mix end)
      fake_mix
    end

    defp with_missing_file(missing_substring, fun) do
      import Mimic

      real_exists = fn path -> :filelib.is_regular(to_string(path)) end

      stub(File, :exists?, fn path ->
        if String.contains?(to_string(path), missing_substring) do
          false
        else
          real_exists.(path)
        end
      end)

      fun.()
    end

    test "patch_mix_exs fails when mix.exs is missing", %{tmp: tmp} do
      install_fast_fake_mix(tmp, "lv_nomix")

      with_missing_file("lv_nomix/mix.exs", fn ->
        assert {:error, msg} = LiveViewGenerator.generate("lv_nomix", tmp)
        assert msg =~ "mix.exs not found"
      end)
    end

    test "ecto_sqlite3 injection fails when mix.exs is missing", %{tmp: tmp} do
      # mix.exs must exist for the first patch, then "disappear" for the
      # ecto_sqlite3 step. Simulate by failing on the second existence check
      # of the same path.
      import Mimic

      install_fast_fake_mix(tmp, "lv_vanish")
      real_exists = fn path -> :filelib.is_regular(to_string(path)) end
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      stub(File, :exists?, fn path ->
        if String.contains?(to_string(path), "lv_vanish/mix.exs") do
          n = Agent.get_and_update(counter, fn c -> {c + 1, c + 1} end)
          # Checks 1 (patch_mix_exs) and 2 (patch_mix_exs_erlc) see it; the
          # inject_ecto_sqlite3 check (3rd) doesn't.
          n < 3 and real_exists.(path)
        else
          real_exists.(path)
        end
      end)

      assert {:error, msg} = LiveViewGenerator.generate("lv_vanish", tmp)
      assert msg =~ "cannot inject ecto_sqlite3"
    end

    test "erlc_paths patch fails when mix.exs is missing", %{tmp: tmp} do
      import Mimic

      install_fast_fake_mix(tmp, "lv_erlc")
      real_exists = fn path -> :filelib.is_regular(to_string(path)) end
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      stub(File, :exists?, fn path ->
        if String.contains?(to_string(path), "lv_erlc/mix.exs") do
          n = Agent.get_and_update(counter, fn c -> {c + 1, c + 1} end)
          # Check 1 (patch_mix_exs) sees it; the patch_mix_exs_erlc check (2nd) doesn't.
          n < 2 and real_exists.(path)
        else
          real_exists.(path)
        end
      end)

      assert {:error, msg} = LiveViewGenerator.generate("lv_erlc", tmp)
      assert msg =~ "cannot add erlc_paths"
    end
  end
end
