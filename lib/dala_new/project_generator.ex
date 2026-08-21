# SPDX-FileCopyrightText: 2024 Dala contributors <https://github.com/manhvu/dala/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule DalaNew.ProjectGenerator do
  @executable_files ["ios/build.sh"]
  @executable_static ["android/gradlew"]

  @moduledoc """
    Generates a new Dala project from EEx templates in `priv/templates/dala.new/`.

    ## Naming conventions

    Given `app_name = "my_cool_app"` and the default bundle prefix:
    - `module_name`  → `"MyCoolApp"`
    - `display_name` → `"MyCoolApp"`
    - `bundle_id`    → `"com.example.my_cool_app"`
    - `java_package` → `"com.example.my_cool_app"`
    - `lib_name`     → `"mycoolapp"` (no underscores, for `System.loadLibrary`)
    - `java_path`    → `"com/example/my_cool_app"` (for directory structure)

  ## Bundle prefix

  The reverse-DNS prefix for the bundle ID defaults to `com.example`, the
  universal "must change before shipping" placeholder. Override at generation
  time with the `DALA_BUNDLE_PREFIX` env var:

      DALA_BUNDLE_PREFIX=net.acme mix dala.new my_cool_app
      # → bundle_id = "net.acme.my_cool_app"

  We deliberately do **not** use `com.dala` — that's our reverse-DNS namespace,
    and Apple/Google enforce ownership at submission time, so a project that
    ships with `com.dala.*` would have to be renamed before reaching either store.
  """

  def templates_root, do: :dala_new |> :code.priv_dir() |> Path.join("templates/dala.new")
  def static_root, do: :dala_new |> :code.priv_dir() |> Path.join("static/dala.new")

  # Reverse-DNS prefix for the generated bundle id. Honors DALA_BUNDLE_PREFIX
  # (typical value: "com.acme" or "net.you"); defaults to "com.example", the
  # universal "must change before shipping" placeholder. Never defaults to
  # "com.dala" — Apple and Google enforce reverse-DNS ownership at App Store
  # / Play Store submission, so apps generated with our namespace would have
  # to be renamed before reaching either store.
  @spec bundle_prefix() :: String.t()
  def bundle_prefix do
    case System.get_env("DALA_BUNDLE_PREFIX") do
      nil -> "com.example"
      "" -> "com.example"
      raw -> String.trim(raw)
    end
  end

  @doc """
  Returns the EEx template assigns map for `app_name`.

  Options:
  - `:local` — when `true`, generates `path:` deps pointing to local dala/dala_dev
    repos instead of hex version constraints. Paths are resolved from the
    `DALA_DIR` and `DALA_DEV_DIR` environment variables, falling back to
    `../dala` and `../dala_dev` relative to the generated project location.
  """
  @spec assigns(String.t(), keyword()) :: map()
  def assigns(app_name, opts \\ []) do
    module_name = Macro.camelize(app_name)
    display_name = module_name
    bundle_prefix = bundle_prefix()
    bundle_id = "#{bundle_prefix}.#{app_name}"
    java_package = bundle_id
    lib_name = String.replace(app_name, "_", "")
    java_path = String.replace(bundle_id, ".", "/")
    liveview_port = liveview_port(bundle_id)

    # JNI method name segment: dots→underscores, then underscores→_1
    # e.g. "com.dala.test_app" → "com_dala_test_1app"
    jni_package =
      java_package
      |> String.replace("_", "_1")
      |> String.replace(".", "_")

    {dala_dep, dala_dev_dep, dala_exs_dala_dir, dala_exs_elixir_lib} = resolve_deps(opts)

    %{
      app_name: app_name,
      module_name: module_name,
      display_name: display_name,
      bundle_id: bundle_id,
      java_package: java_package,
      jni_package: jni_package,
      lib_name: lib_name,
      java_path: java_path,
      dala_dep: dala_dep,
      dala_dev_dep: dala_dev_dep,
      dala_exs_dala_dir: dala_exs_dala_dir,
      dala_exs_elixir_lib: dala_exs_elixir_lib,
      liveview_port: liveview_port
    }
  end

  # Derive a per-app LiveView port from the bundle id so two installed Dala
  # LiveView apps don't collide on the hardcoded 4200 (dala/issues.md #4).
  # Deterministic per app: host `mix phx.server`, config patches, and the
  # on-device endpoint all derive the same port. Base 4200 keeps the first
  # generated app on the historical default.
  @spec liveview_port(String.t()) :: pos_integer()
  def liveview_port(bundle_id) do
    4200 + :erlang.phash2(bundle_id, 100)
  end

  @doc """
  Generates a new project at `dest_dir/<app_name>` from the bundled templates.

  Returns `{:ok, project_dir}` or `{:error, reason}`.
  """
  @spec generate(String.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def generate(app_name, dest_dir \\ ".", opts \\ []) do
    project_dir = Path.join(dest_dir, app_name)

    if File.exists?(project_dir) do
      {:error, "Directory already exists: #{project_dir}"}
    else
      File.mkdir_p!(project_dir)

      try do
        a = assigns(app_name, opts)
        render_templates(a, project_dir, opts)
        copy_static(project_dir, opts)
        {:ok, project_dir}
      rescue
        e ->
          File.rm_rf!(project_dir)
          {:error, "Generation failed: #{Exception.message(e)}"}
      end
    end
  end

  @doc """
  Generates a LiveView-wrapped Dala project at `dest_dir/<app_name>`.

  Delegates to `DalaNew.LiveViewGenerator.generate/3`, which owns the whole
  `--liveview` pipeline (phx.new subprocess, boilerplate copy with the
  Phoenix-owned blocklist, and bridge patches).
  """
  @spec liveview_generate(String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def liveview_generate(app_name, dest_dir \\ ".", opts \\ []) do
    DalaNew.LiveViewGenerator.generate(app_name, dest_dir, opts)
  end

  @doc """
  Delegates to `DalaNew.LiveViewGenerator.liveview_phoenix_owned?/3` (kept here
  for back-compat — tests and external callers reference this module).
  """
  @spec liveview_phoenix_owned?(String.t(), String.t(), keyword()) :: boolean()
  def liveview_phoenix_owned?(path, root, opts) do
    DalaNew.LiveViewGenerator.liveview_phoenix_owned?(path, root, opts)
  end

  # ── Dep resolution ────────────────────────────────────────────────────────────

  defp resolve_deps(opts) do
    if opts[:local] do
      dala_dir = resolve_local_path("DALA_DIR", "dala")
      dala_dev_dir = resolve_local_path("DALA_DEV_DIR", "dala_dev")
      elixir_lib = :code.lib_dir(:elixir) |> to_string() |> Path.dirname() |> Path.expand()

      dala_dep = ~s({:dala,     path: "#{dala_dir}"})
      dala_dev_dep = ~s({:dala_dev, path: "#{dala_dev_dir}", only: :dev, runtime: false})
      dala_exs_dala_dir = inspect(dala_dir)
      dala_exs_elixir_lib = inspect(elixir_lib)

      {dala_dep, dala_dev_dep, dala_exs_dala_dir, dala_exs_elixir_lib}
    else
      dala_dep = ~s({:dala,     "~> 0.8.0"})
      dala_dev_dep = ~s({:dala_dev, "~> 0.8.0", only: :dev, runtime: false})
      dala_exs_dala_dir = "Path.join(File.cwd!(), \"deps/dala\")"

      # Resolve from the running Elixir installation at generation time rather
      # than baking a machine-specific default (e.g. a mise path) into dala.exs.
      elixir_lib = :code.lib_dir(:elixir) |> to_string() |> Path.dirname() |> Path.expand()
      dala_exs_elixir_lib = inspect(elixir_lib)

      {dala_dep, dala_dev_dep, dala_exs_dala_dir, dala_exs_elixir_lib}
    end
  end

  defp resolve_local_path(env_var, sibling_name) do
    cond do
      path = System.get_env(env_var) ->
        Path.expand(path)

      File.dir?(sibling = Path.expand("./#{sibling_name}")) ->
        sibling

      File.dir?(sibling = Path.expand("../#{sibling_name}")) ->
        sibling

      true ->
        Mix.raise("""
        Could not find local #{sibling_name} directory.
        Set #{env_var} env var or ensure #{sibling_name} exists alongside your project:
          export #{env_var}=/path/to/#{sibling_name}
        """)
    end
  end

  @doc "File names (relative to project root) that must be emitted executable."
  def executable_files, do: @executable_files

  @doc "Static file names (relative to project root) that must be emitted executable."
  def executable_static, do: @executable_static

  # ── private ──────────────────────────────────────────────────────────────

  defp render_templates(assigns, project_dir, opts) do
    no_ios = Keyword.get(opts, :no_ios, false)
    no_android = Keyword.get(opts, :no_android, false)

    templates_root()
    |> find_templates()
    |> Enum.filter(&platform_included?(&1, templates_root(), no_ios, no_android))
    |> Enum.each(fn template_path ->
      rel = Path.relative_to(template_path, templates_root())
      dest_rel = expand_path(rel, assigns)
      dest = Path.join(project_dir, dest_rel)
      File.mkdir_p!(Path.dirname(dest))
      content = EEx.eval_file(template_path, Map.to_list(assigns))
      File.write!(dest, content)
      if dest_rel in @executable_files, do: File.chmod!(dest, 0o755)
    end)
  end

  # Decide whether a template/static file should be emitted given the platform
  # exclusion flags. Files outside android/ and ios/ are always included
  # (lib/, mix.exs, etc.). Files under android/ are excluded when no_android,
  # likewise ios/ when no_ios.
  def platform_included?(path, root, no_ios, no_android) do
    rel = Path.relative_to(path, root)

    cond do
      String.starts_with?(rel, "android/") -> not no_android
      String.starts_with?(rel, "ios/") -> not no_ios
      true -> true
    end
  end

  def find_templates(dir) do
    Path.wildcard(Path.join(dir, "**/*.eex"), match_dot: true)
  end

  defp copy_static(project_dir, opts) do
    no_ios = Keyword.get(opts, :no_ios, false)
    no_android = Keyword.get(opts, :no_android, false)

    static_root()
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.reject(&File.dir?/1)
    |> Enum.filter(&platform_included?(&1, static_root(), no_ios, no_android))
    |> Enum.each(fn src ->
      rel = Path.relative_to(src, static_root())
      dest = Path.join(project_dir, rel)
      File.mkdir_p!(Path.dirname(dest))
      File.copy!(src, dest)
      if rel in @executable_static, do: File.chmod!(dest, 0o755)
    end)
  end

  # Replace `__app_name__` / `__java_path__` placeholder tokens in directory
  # segments and strip the .eex extension. Distinct tokens (rather than the
  # bare substring "app_name") so a template path that merely contains the
  # app name can't be corrupted.
  def expand_path(rel, assigns) do
    rel
    |> String.replace("__app_name__", assigns.app_name)
    |> String.replace("__java_path__", assigns.java_path)
    |> strip_eex()
  end

  defp strip_eex(path) do
    if String.ends_with?(path, ".eex") do
      String.slice(path, 0..-5//1)
    else
      path
    end
  end
end
