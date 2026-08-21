# SPDX-FileCopyrightText: 2024 Dala contributors <https://github.com/manhvu/dala/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule DalaNew.LiveViewGenerator do
  @moduledoc """
  Generates a LiveView-wrapped Dala project.

  This module owns everything specific to the `--liveview` path:

    1. Runs `mix phx.new` as a subprocess
    2. Patches `mix.exs` to add the dala / dala_dev dependencies
    3. Copies the native Android/iOS boilerplate, skipping Phoenix-owned files
       (see `DalaNew.ProjectGenerator.liveview_phoenix_owned?/3`)
    4. Applies the Dala bridge patches (DalaHook, dala-bridge element,
       DalaScreen, dala.exs, Erlang bootstrap, port alignment, notes starter app)

  On failure the partially-created project directory is removed so a retry
  doesn't hit "Directory already exists".
  """

  alias DalaNew.{LiveViewPatcher, ProjectGenerator}

  @doc """
  Generates a LiveView project at `dest_dir/<app_name>`.

  Returns `{:ok, project_dir}` or `{:error, reason}`.
  """
  @spec generate(String.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def generate(app_name, dest_dir \\ ".", opts \\ []) do
    project_dir = Path.join(Path.expand(dest_dir), app_name)

    if File.exists?(project_dir) do
      {:error, "Directory already exists: #{project_dir}"}
    else
      # Mark this as a liveview generation so copy_native_boilerplate skips
      # files Phoenix's `mix phx.new` already created (mix.exs, config/, etc.).
      liveview_opts = Keyword.put(opts, :liveview, true)

      result =
        with :ok <- run_phx_new(app_name, dest_dir),
             :ok <- patch_mix_exs(project_dir, opts),
             :ok <- copy_native_boilerplate(app_name, project_dir, liveview_opts) do
          apply_liveview_patches(app_name, project_dir, opts)
        end

      case result do
        :ok ->
          {:ok, project_dir}

        {:error, reason} ->
          # Remove the half-generated project so a retry doesn't hit
          # "Directory already exists".
          File.rm_rf!(project_dir)
          {:error, reason}
      end
    end
  end

  # ── phx.new + boilerplate ─────────────────────────────────────────────────────

  defp run_phx_new(app_name, dest_dir) do
    mix = System.find_executable("mix")

    if mix do
      abs_dest = Path.expand(dest_dir)

      args = [
        "phx.new",
        app_name,
        "--no-install",
        "--no-dashboard",
        "--no-mailer",
        "--no-ecto"
      ]

      Mix.shell().info("Running mix phx.new #{app_name} in #{abs_dest}...")

      case System.cmd(mix, args, cd: abs_dest, stderr_to_stdout: true) do
        {_output, 0} ->
          :ok

        {output, exit_code} ->
          {:error, "mix phx.new failed (exit #{exit_code}):\n#{output}"}
      end
    else
      {:error, "mix executable not found in PATH"}
    end
  end

  defp patch_mix_exs(project_dir, opts) do
    path = Path.join(project_dir, "mix.exs")

    if File.exists?(path) do
      a = ProjectGenerator.assigns(Path.basename(project_dir), opts)
      content = File.read!(path)
      patched = LiveViewPatcher.inject_deps(content, a.dala_dep, a.dala_dev_dep)
      File.write!(path, patched)
      Mix.shell().info([:green, "* patch ", :reset, path, " (added dala deps)"])
      :ok
    else
      {:error, "mix.exs not found in #{project_dir}"}
    end
  end

  defp copy_native_boilerplate(app_name, project_dir, opts) do
    templates_root = ProjectGenerator.templates_root()
    static_root = ProjectGenerator.static_root()
    a = ProjectGenerator.assigns(app_name, opts)
    no_ios = Keyword.get(opts, :no_ios, false)
    no_android = Keyword.get(opts, :no_android, false)

    templates_root
    |> ProjectGenerator.find_templates()
    |> Enum.filter(&ProjectGenerator.platform_included?(&1, templates_root, no_ios, no_android))
    |> Enum.reject(&liveview_phoenix_owned?(&1, templates_root, opts))
    |> Enum.each(fn template_path ->
      rel = Path.relative_to(template_path, templates_root)
      dest_rel = ProjectGenerator.expand_path(rel, a)
      dest = Path.join(project_dir, dest_rel)
      File.mkdir_p!(Path.dirname(dest))
      content = EEx.eval_file(template_path, Map.to_list(a))
      File.write!(dest, content)
      Mix.shell().info([:green, "* create ", :reset, dest])

      if dest_rel in ProjectGenerator.executable_files(), do: File.chmod!(dest, 0o755)
    end)

    # Copy static files (gradlew, wrapper jars, iOS assets, etc.)
    static_root
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.reject(&File.dir?/1)
    |> Enum.filter(&ProjectGenerator.platform_included?(&1, static_root, no_ios, no_android))
    |> Enum.reject(&liveview_phoenix_owned?(&1, static_root, opts))
    |> Enum.each(fn src ->
      rel = Path.relative_to(src, static_root)
      dest = Path.join(project_dir, rel)
      File.mkdir_p!(Path.dirname(dest))
      File.copy!(src, dest)

      if rel in ProjectGenerator.executable_static(),
        do: File.chmod!(dest, 0o755)
    end)

    :ok
  end

  @doc """
  When generating a LiveView project, `mix phx.new` already produced its own
  mix.exs, config/, lib/<app>/, lib/<app>_web/, .gitignore, and assets/ — and
  those are the *correct* versions for a Phoenix app (with gettext,
  telemetry_metrics, etc.). The native template's same-named files are
  written for the bare-Dala path and would clobber Phoenix's, leaving the
  project unable to compile.

  When `:liveview` is true in opts, this predicate returns true for any
  template path that Phoenix already owns, so the copy step skips it. Files
  that are unique to Dala (dala.exs, src/<app>.erl, android/, ios/) still get
  emitted normally.

  Public for testing — guards against the regression where a new template
  path lands in the native tree without being added to the LiveView
  blocklist.
  """
  @spec liveview_phoenix_owned?(String.t(), String.t(), keyword()) :: boolean()
  def liveview_phoenix_owned?(path, root, opts) do
    if Keyword.get(opts, :liveview, false) do
      rel = Path.relative_to(path, root)

      cond do
        rel == "mix.exs.eex" -> true
        rel == ".gitignore.eex" -> true
        rel == ".tool-versions.eex" -> true
        String.starts_with?(rel, "config/") -> true
        # Native-template `lib/app_name/` includes sample screens (audio, camera,
        # webview, etc.) that are Dala-native UI — they don't make sense in a
        # LiveView project where the UI is HTML/HEEx, and they collide with
        # Phoenix's own lib/<app>/ contents. Skip the whole subtree; the
        # LiveView-specific DalaScreen file is generated by apply_liveview_patches.
        String.starts_with?(rel, "lib/app_name/") -> true
        # priv/repo/migrations is added explicitly by apply_liveview_patches when
        # ecto_sqlite3 is wired up — skip the native template's version.
        String.starts_with?(rel, "priv/") -> true
        true -> false
      end
    else
      false
    end
  end

  # ── Bridge patches ────────────────────────────────────────────────────────────

  defp apply_liveview_patches(app_name, project_dir, opts) do
    module_name = Macro.camelize(app_name)
    a = ProjectGenerator.assigns(app_name, opts)
    port = a.liveview_port

    with :ok <- patch_app_js(project_dir),
         :ok <- patch_root_html(project_dir, app_name),
         # 3. Generate lib/<app>/dala_screen.ex
         :ok <- generate_dala_screen(project_dir, app_name, module_name, port),
         # 4. Generate lib/<app>/dala_app.ex (BEAM entry point for LiveView mode)
         :ok <- generate_dala_live_app(project_dir, app_name, module_name, port),
         # 5. Generate src/<app>.erl (Erlang bootstrap, calls DalaApp.start/0)
         :ok <- generate_erlang_entry(project_dir, app_name, module_name),
         # 6. Patch mix.exs to include src/ in erlc_paths
         :ok <- patch_mix_exs_erlc(project_dir),
         # 7. Write dala.exs with liveview_port
         :ok <- write_dala_exs(project_dir, a.dala_exs_dala_dir, a.dala_exs_elixir_lib, port),
         # 7b. Patch Phoenix's config files so `mix phx.server` uses the same
         #     port as the on-device runtime in dala_app.ex.
         :ok <- patch_config_ports(project_dir, port),
         # 8. Write .gitignore entry for dala.exs (append if file exists)
         :ok <- patch_gitignore(project_dir),
         # 9. Generate the notes starter app: Repo, Note schema, Notes context,
         #    migration, three LiveViews, and patch router + application.ex + configs.
         :ok <- inject_ecto_sqlite3_dep(project_dir),
         :ok <- patch_config_for_ecto(project_dir, app_name, module_name),
         :ok <- generate_notes_app(project_dir, app_name, module_name),
         # 10. Overwrite ios/build.sh with the LiveView-specific version
         :ok <- overwrite_liveview_build_sh(project_dir, app_name, module_name) do
      :ok
    end
  end

  defp patch_app_js(project_dir) do
    path = Path.join([project_dir, "assets", "js", "app.js"])

    if File.exists?(path) do
      content = File.read!(path)
      patched = LiveViewPatcher.inject_dala_hook(content)
      File.write!(path, patched)
      Mix.shell().info([:green, "* patch ", :reset, path, " (added DalaHook)"])
      :ok
    else
      {:error, "assets/js/app.js not found in #{project_dir} — phx.new output may have changed"}
    end
  end

  defp patch_root_html(project_dir, app_name) do
    web_name = app_name <> "_web"

    candidates = [
      Path.join([project_dir, "lib", web_name, "components", "layouts", "root.html.heex"]),
      Path.join([project_dir, "lib", web_name, "templates", "layout", "root.html.heex"])
    ]

    path = Enum.find(candidates, &File.exists?/1)

    if path do
      content = File.read!(path)
      patched = LiveViewPatcher.inject_dala_bridge_element(content)
      File.write!(path, patched)
      Mix.shell().info([:green, "* patch ", :reset, path, " (added dala-bridge element)"])
      :ok
    else
      {:error, "root.html.heex not found in #{project_dir} — phx.new output may have changed"}
    end
  end

  defp generate_dala_screen(project_dir, app_name, module_name, port) do
    dir = Path.join([project_dir, "lib", app_name])
    path = Path.join(dir, "dala_screen.ex")
    File.mkdir_p!(dir)
    File.write!(path, LiveViewPatcher.dala_screen_content(module_name, port))
    Mix.shell().info([:green, "* create ", :reset, path])
    :ok
  end

  defp write_dala_exs(project_dir, dala_exs_dala_dir, dala_exs_elixir_lib, port) do
    path = Path.join(project_dir, "dala.exs")

    File.write!(
      path,
      LiveViewPatcher.dala_exs_content(dala_exs_dala_dir, dala_exs_elixir_lib, port)
    )

    Mix.shell().info([:green, "* create ", :reset, path])
    :ok
  end

  defp generate_dala_live_app(project_dir, app_name, module_name, port) do
    content = LiveViewPatcher.dala_live_app_content(module_name, app_name, port)

    path = Path.join([project_dir, "lib", app_name, "dala_app.ex"])
    File.write!(path, content)
    Mix.shell().info([:green, "* create ", :reset, path])
    :ok
  end

  defp inject_ecto_sqlite3_dep(project_dir) do
    path = Path.join(project_dir, "mix.exs")

    if File.exists?(path) do
      content = File.read!(path)

      unless String.contains?(content, "ecto_sqlite3") do
        patched =
          Regex.replace(
            ~r/(defp deps do\s*\[)/,
            content,
            ~s[\\1\n      {:ecto_sqlite3, "~> 0.18"},],
            global: false
          )

        if patched == content do
          Mix.shell().error(
            "WARNING: could not inject ecto_sqlite3 into #{path} — " <>
              "the `defp deps do [` pattern did not match. phx.new output may have changed."
          )
        else
          File.write!(path, patched)
          Mix.shell().info([:green, "* patch ", :reset, path, " (added ecto_sqlite3)"])
        end
      end

      :ok
    else
      {:error, "mix.exs not found in #{project_dir} — cannot inject ecto_sqlite3"}
    end
  end

  # phx.new emits Endpoint http port 4000 in dev.exs, 4002 in test.exs, and a
  # `PORT` env var defaulting to "4000" in runtime.exs. Dala's LiveView mode
  # derives a per-app port from the bundle id (see
  # `DalaNew.ProjectGenerator.liveview_port/1`), so host dev/test endpoints line
  # up with the on-device runtime and two installed apps don't collide. Warns
  # loudly when a pattern matches nothing — that usually means phx.new changed
  # its output format.
  defp patch_config_ports(project_dir, port) do
    test_port = port + 2

    [
      {"config/dev.exs", ~r/(port:\s*)/, "port: #{port}, ", "dev port → #{port}"},
      {"config/test.exs", ~r/(port:\s*)/, "port: #{test_port}, ", "test port → #{test_port}"},
      {"config/runtime.exs", ~r/System\.get_env\("PORT"\) \|\| "4000"/,
       "System.get_env(\"PORT\") || \"#{port}\"", "runtime PORT default 4000 → #{port}"}
    ]
    |> Enum.map(&apply_port_patch(project_dir, &1))
    |> Enum.find(:ok, fn
      :ok -> false
      {:error, _} = err -> err
    end)
  end

  defp apply_port_patch(project_dir, {rel, find, replace, label}) do
    path = Path.join(project_dir, rel)

    if File.exists?(path) do
      content = File.read!(path)
      patched = Regex.replace(find, content, replace, global: false)

      cond do
        patched != content ->
          File.write!(path, patched)
          Mix.shell().info([:green, "* patch ", :reset, path, " (#{label})"])
          :ok

        String.contains?(content, replace) ->
          # Already patched (idempotent re-run).
          :ok

        true ->
          Mix.shell().error(
            "WARNING: port patch did not match in #{path} (#{label}) — " <>
              "phx.new output may have changed; fix the port manually."
          )

          :ok
      end
    else
      {:error, "#{rel} not found in #{project_dir} — cannot patch ports"}
    end
  end

  defp patch_config_for_ecto(project_dir, app_name, module_name) do
    config_exs = Path.join([project_dir, "config", "config.exs"])
    dev_exs = Path.join([project_dir, "config", "dev.exs"])

    if File.exists?(config_exs) do
      content = File.read!(config_exs)

      unless String.contains?(content, "ecto_repos") do
        ecto_config = """

        config :#{app_name},
          ecto_repos: [#{module_name}.Repo],
          generators: [timestamp_type: :utc_datetime]
        """

        patched =
          String.replace(content, "import_config", ecto_config <> "\nimport_config",
            global: false
          )

        if patched == content do
          Mix.shell().error(
            "WARNING: could not add ecto_repos to #{config_exs} — " <>
              "no `import_config` line found."
          )
        else
          File.write!(config_exs, patched)

          Mix.shell().info([
            :green,
            "* patch ",
            :reset,
            config_exs,
            " (added ecto_repos)"
          ])
        end
      end
    end

    if File.exists?(dev_exs) do
      content = File.read!(dev_exs)

      unless String.contains?(content, "#{module_name}.Repo") do
        repo_config = """

        config :#{app_name}, #{module_name}.Repo,
          database: Path.expand("../priv/repo/#{app_name}_dev.db", __DIR__),
          pool_size: 5
        """

        File.write!(dev_exs, content <> repo_config)
        Mix.shell().info([:green, "* patch ", :reset, dev_exs, " (added Repo dev config)"])
      end
    end

    :ok
  end

  defp generate_notes_app(project_dir, app_name, module_name) do
    live_dir = Path.join([project_dir, "lib", "#{app_name}_web", "live"])
    lib_dir = Path.join([project_dir, "lib", app_name])
    migrations_dir = Path.join([project_dir, "priv", "repo", "migrations"])
    File.mkdir_p!(live_dir)
    File.mkdir_p!(lib_dir)
    File.mkdir_p!(migrations_dir)

    write = fn path, content ->
      File.write!(path, content)
      Mix.shell().info([:green, "* create ", :reset, path])
    end

    write.(
      Path.join(lib_dir, "repo.ex"),
      LiveViewPatcher.repo_content(module_name, app_name)
    )

    write.(Path.join(lib_dir, "note.ex"), LiveViewPatcher.note_content(module_name))

    write.(
      Path.join(lib_dir, "notes.ex"),
      LiveViewPatcher.notes_content(module_name, app_name)
    )

    write.(
      Path.join(migrations_dir, "20260424000000_create_notes.exs"),
      LiveViewPatcher.migration_content(app_name)
    )

    write.(
      Path.join(live_dir, "notes_list_live.ex"),
      LiveViewPatcher.notes_list_live_content(module_name, app_name)
    )

    write.(
      Path.join(live_dir, "note_editor_live.ex"),
      LiveViewPatcher.note_editor_live_content(module_name, app_name)
    )

    write.(
      Path.join(live_dir, "about_live.ex"),
      LiveViewPatcher.about_live_content(module_name, app_name)
    )

    patch_router_for_notes(project_dir, app_name, module_name)
    patch_application_ex_for_repo(project_dir, app_name, module_name)
  end

  defp patch_router_for_notes(project_dir, app_name, _module_name) do
    web_name = app_name <> "_web"
    path = Path.join([project_dir, "lib", web_name, "router.ex"])

    notes_routes =
      ~s[live "/", NotesListLive\n    live "/notes/:id", NoteEditorLive\n    live "/about", AboutLive]

    if File.exists?(path) do
      content = File.read!(path)

      patched =
        Regex.replace(
          ~r/get\s+"\/",\s+PageController,\s+:home/,
          content,
          notes_routes,
          global: false
        )

      patched =
        if patched == content do
          # Fallback: replace any existing live "/" route
          Regex.replace(~r/live\s+"\/",\s+\w+/, content, notes_routes, global: false)
        else
          patched
        end

      if patched != content do
        File.write!(path, patched)
        Mix.shell().info([:green, "* patch ", :reset, path, " (notes routes)"])
      else
        Mix.shell().error(
          "WARNING: could not patch notes routes into #{path} — " <>
            "neither the PageController route nor an existing live \"/\" route matched."
        )
      end
    else
      Mix.shell().error(
        "WARNING: #{path} not found — notes routes were not added. " <>
          "Add them manually: #{notes_routes}"
      )
    end

    :ok
  end

  defp patch_application_ex_for_repo(project_dir, app_name, module_name) do
    path = Path.join([project_dir, "lib", app_name, "application.ex"])

    if File.exists?(path) do
      content = File.read!(path)

      unless String.contains?(content, "#{module_name}.Repo") do
        patched =
          String.replace(
            content,
            "#{module_name}Web.Endpoint",
            "#{module_name}.Repo,\n      #{module_name}Web.Endpoint",
            global: false
          )

        if patched == content do
          Mix.shell().error(
            "WARNING: could not add Repo to supervision tree in #{path} — " <>
              "`#{module_name}Web.Endpoint` not found."
          )
        else
          File.write!(path, patched)

          Mix.shell().info([
            :green,
            "* patch ",
            :reset,
            path,
            " (added Repo to supervision tree)"
          ])
        end
      end
    else
      Mix.shell().error(
        "WARNING: #{path} not found — Repo was not added to the supervision tree."
      )
    end

    :ok
  end

  defp overwrite_liveview_build_sh(project_dir, app_name, module_name) do
    path = Path.join([project_dir, "ios", "build.sh"])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, LiveViewPatcher.liveview_build_sh_content(module_name, app_name))
    File.chmod!(path, 0o755)
    Mix.shell().info([:green, "* create ", :reset, path, " (LiveView build.sh)"])
    :ok
  end

  defp generate_erlang_entry(project_dir, app_name, module_name) do
    dir = Path.join(project_dir, "src")
    path = Path.join(dir, "#{app_name}.erl")
    File.mkdir_p!(dir)
    File.write!(path, LiveViewPatcher.erlang_entry_content(module_name, app_name))
    Mix.shell().info([:green, "* create ", :reset, path])
    :ok
  end

  defp patch_mix_exs_erlc(project_dir) do
    # Phoenix projects don't compile .erl files by default. We need to add:
    #   erlc_paths: ["src"]
    # to the project/0 function so the Erlang bootstrap is compiled.
    path = Path.join(project_dir, "mix.exs")

    if File.exists?(path) do
      content = File.read!(path)

      if String.contains?(content, "erlc_paths") do
        Mix.shell().info("  * skip #{path} (erlc_paths already set)")
      else
        patched =
          Regex.replace(
            ~r/(def project do\s*\[)/,
            content,
            "\\1\n      erlc_paths: [\"src\"],\n      erlc_options: [:debug_info],",
            global: false
          )

        if patched == content do
          Mix.shell().error(
            "WARNING: could not add erlc_paths to #{path} — " <>
              "`def project do [` pattern did not match."
          )
        else
          File.write!(path, patched)

          Mix.shell().info([
            :green,
            "* patch ",
            :reset,
            path,
            " (added erlc_paths: [\"src\"])",
            :reset
          ])
        end
      end

      :ok
    else
      {:error, "mix.exs not found in #{project_dir} — cannot add erlc_paths"}
    end
  end

  defp patch_gitignore(project_dir) do
    path = Path.join(project_dir, ".gitignore")

    if File.exists?(path) do
      content = File.read!(path)

      unless String.contains?(content, "dala.exs") do
        File.write!(path, content <> "\n# Dala local config\ndala.exs\n")
        Mix.shell().info([:green, "* patch ", :reset, path, " (added dala.exs)"])
      end

      :ok
    else
      Mix.shell().error(
        "WARNING: #{path} not found — dala.exs will not be gitignored. Add it manually."
      )

      :ok
    end
  end
end
