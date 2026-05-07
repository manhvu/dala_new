# SPDX-FileCopyrightText: 2024 Dala contributors <https://github.com/manhvu/dala/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule Mix.Tasks.Dala.New do
  use Mix.Task

  @shortdoc "Create a new Dala mobile app project"

  @moduledoc """
    Creates a new Dala project with Android and iOS boilerplate.

        mix dala.new APP_NAME [--liveview] [--ios | --android] [--no-install] [--dest DIR] [--local]

    ## Platform selection

    By default the generator emits boilerplate for both Android and iOS. Pass
    one of the platform flags to scope it to a single platform:

        mix dala.new my_app --ios        # iOS only — no android/ directory generated
        mix dala.new my_app --android    # Android only — no ios/ directory generated
        mix dala.new my_app              # both (default)

    `--no-ios` and `--no-android` are equivalent inverse forms (kept for
    back-compat). `mix dala.install`, `mix dala.deploy`, and `mix dala.doctor`
    detect the project's platform set from on-disk layout, so a single-platform
    project skips the absent platform's setup automatically.

  ## Options

    * `--liveview`     — generate a Phoenix LiveView app wrapped in a Dala WebView.
                         mix dala.new my_app --liveview     — generate a Phoenix LiveView app wrapped in a Dala WebView.
                                                  Calls `mix phx.new` to scaffold a Phoenix project, then
                                                  adds the Dala native boilerplate and LiveView bridge patches
                                                  (DalaHook in app.js, dala-bridge element in root.html.heex,
                                                  DalaScreen, dala.exs with liveview_port). Requires
                                                  `phx_new` archive to be installed (`mix archive.install hex phx_new`).
    * `--ios`          — generate iOS boilerplate only (skip android/)
    * `--android`      — generate Android boilerplate only (skip ios/)
    * `--no-ios`       — alias for `--android` (skip iOS boilerplate)
    * `--no-android`   — alias for `--ios` (skip Android boilerplate)
    * `--no-install`   — skip running `mix deps.get` after generation
    * `--dest DIR`     — create project in DIR (default: current directory)
    * `--local`        — use `path:` deps pointing to local dala/dala_dev repos
                             instead of hex version constraints. **For Dala framework
                             contributors only** — not intended for app developers.
                             Paths resolved from `DALA_DIR` / `DALA_DEV_DIR` env vars,
                             falling back to `./dala` / `./dala_dev`, then `../dala` /
                             `../dala_dev`. Also pre-fills `dala.exs` with real paths
                             so `mix dala.install` skips path configuration prompts.

  ## What gets generated (native mode, default)

      APP_NAME/
        mix.exs
        lib/APP_NAME/app.ex
        lib/APP_NAME/home_screen.ex
        android/
          settings.gradle
          build.gradle
          app/
            build.gradle
            src/main/
              AndroidManifest.xml
              java/com/dala/APP_NAME/MainActivity.kt
              java/com/dala/APP_NAME/DalaBridge.kt
              java/com/dala/APP_NAME/DalaNode.kt
              java/com/dala/APP_NAME/DalaScannerActivity.kt
          gradle.properties
        ios/
          beam_main.m
          Info.plist

  ## What gets generated (--liveview mode)

  Everything `mix phx.new APP_NAME --no-install` generates, plus:

      APP_NAME/
        lib/APP_NAME/dala_screen.ex      # Dala.Screen wrapping the Phoenix WebView
        dala.exs                          # Dala config with liveview_port: 4000
        android/                         # same Android boilerplate as native mode
        ios/                             # same iOS boilerplate as native mode

  Patches applied to the Phoenix project:
    - `assets/js/app.js`                — DalaHook definition + registration
    - `lib/APP_NAME_web/.../root.html.heex` — dala-bridge hidden div
    - `lib/APP_NAME/application.ex`     — Dala.App child in supervision tree
    - `mix.exs`                          — dala / dala_dev deps added

  After generation, run:

      cd APP_NAME
      mix dala.install    # icon generation + any first-run setup

  """

  @switches [
    no_install: :boolean,
    no_ios: :boolean,
    no_android: :boolean,
    ios: :boolean,
    android: :boolean,
    dest: :string,
    local: :boolean,
    liveview: :boolean
  ]

  @impl Mix.Task
  def run(argv) do
    {opts, args, _} = OptionParser.parse(argv, strict: @switches)
    app_name = parse_app_name!(args)
    {dest_dir, liveview, gen_opts} = parse_gen_opts(opts)
    project_dir = Path.join(Path.expand(dest_dir), app_name)

    log_flags(gen_opts, liveview)
    Mix.shell().info([:green, "* creating ", :reset, project_dir])

    case generate(app_name, dest_dir, liveview, gen_opts) do
      {:error, reason} -> Mix.raise(reason)
      {:ok, project_dir} -> post_generate(project_dir, app_name, liveview, gen_opts, opts)
    end
  end

  defp parse_app_name!([name | _]), do: validate_app_name!(name)
  defp parse_app_name!([]), do: Mix.raise("Usage: mix dala.new APP_NAME")

  defp validate_app_name!(name) do
    unless valid_app_name?(name) do
      Mix.raise("App name must be lowercase letters, digits, and underscores only (e.g. my_app).")
    end

    name
  end

  defp parse_gen_opts(opts) do
    dest_dir = opts[:dest] || "."
    liveview = opts[:liveview] || false
    {no_ios, no_android} = resolve_platforms!(opts)

    gen_opts = [
      local: opts[:local] || false,
      no_ios: no_ios,
      no_android: no_android
    ]

    {dest_dir, liveview, gen_opts}
  end

  # Resolves the four platform-related flags into {no_ios?, no_android?}.
  # Positive flags (--ios, --android) and negative flags (--no-ios, --no-android)
  # are accepted; --ios is sugar for --no-android and vice versa.
  defp resolve_platforms!(opts) do
    ios? = opts[:ios] == true
    android? = opts[:android] == true
    no_ios? = opts[:no_ios] == true or android?
    no_android? = opts[:no_android] == true or ios?

    if no_ios? and no_android? do
      Mix.raise(
        "Cannot exclude both platforms. Pass at most one of --ios, --android, --no-ios, --no-android."
      )
    end

    {no_ios?, no_android?}
  end

  defp log_flags(gen_opts, liveview) do
    if gen_opts[:local] do
      Mix.shell().info([:yellow, "* local mode: using path: deps for dala and dala_dev", :reset])
    end

    if gen_opts[:no_ios] do
      Mix.shell().info([:yellow, "* iOS skipped — Android-only project", :reset])
    end

    if gen_opts[:no_android] do
      Mix.shell().info([:yellow, "* Android skipped — iOS-only project", :reset])
    end

    if liveview do
      Mix.shell().info([
        :cyan,
        "* --liveview: generating Phoenix LiveView app with Dala bridge",
        :reset
      ])
    end
  end

  defp generate(app_name, dest_dir, true = _liveview, gen_opts) do
    DalaNew.ProjectGenerator.liveview_generate(app_name, dest_dir, gen_opts)
  end

  defp generate(app_name, dest_dir, false = _liveview, gen_opts) do
    DalaNew.ProjectGenerator.generate(app_name, dest_dir, gen_opts)
  end

  defp post_generate(project_dir, app_name, liveview, gen_opts, opts) do
    unless liveview, do: print_created_files(project_dir, app_name, gen_opts)
    unless opts[:no_install], do: fetch_deps(project_dir)

    if liveview do
      print_liveview_next_steps(app_name, opts[:no_install])
    else
      print_next_steps(app_name, opts[:no_install], gen_opts)
    end
  end

  # ── private ──────────────────────────────────────────────────────────────────

  defp fetch_deps(project_dir) do
    Mix.shell().info("")
    Mix.shell().info("Fetching dependencies...")
    mix = System.find_executable("mix")
    abs_dir = Path.expand(project_dir)

    case System.cmd(mix, ["deps.get"], cd: abs_dir, into: IO.stream()) do
      {_, 0} ->
        :ok

      {_, _} ->
        Mix.shell().info([
          :yellow,
          "* deps.get failed — run it manually inside #{project_dir}",
          :reset
        ])
    end
  end

  defp print_created_files(project_dir, app_name, gen_opts) do
    no_ios = gen_opts[:no_ios] || false
    no_android = gen_opts[:no_android] || false

    common = ["mix.exs", "lib/#{app_name}/app.ex", "lib/#{app_name}/home_screen.ex"]

    android_files =
      if no_android,
        do: [],
        else: [
          "android/settings.gradle",
          "android/build.gradle",
          "android/app/build.gradle",
          "android/app/src/main/AndroidManifest.xml",
          "android/app/src/main/java/com/dala/#{app_name}/MainActivity.kt",
          "android/app/src/main/java/com/dala/#{app_name}/DalaBridge.kt",
          "android/app/src/main/java/com/dala/#{app_name}/DalaNode.kt",
          "android/app/src/main/java/com/dala/#{app_name}/DalaScannerActivity.kt",
          "android/gradle.properties"
        ]

    ios_files = if no_ios, do: [], else: ["ios/beam_main.m", "ios/Info.plist"]

    Enum.each(common ++ android_files ++ ios_files, fn f ->
      Mix.shell().info([:green, "* creating ", :reset, Path.join(project_dir, f)])
    end)
  end

  defp print_next_steps(app_name, no_install, gen_opts) do
    install_hint =
      if no_install,
        do: "\n    mix deps.get",
        else: ""

    {paths_hint, binaries_hint} = platform_specific_hints(gen_opts)
    provision_hint = ios_provision_hint(gen_opts)

    Mix.shell().info("""

    Your Dala app #{app_name} is ready!
    #{install_hint}
        cd #{app_name}
        mix dala.install                # generates app icon + first-run setup
    #{provision_hint}
    First deploy — edit dala.exs#{paths_hint}, then build native binaries
    (#{binaries_hint}), install on device, and push BEAMs:

        mix dala.deploy --native        # first time, or after native code changes

    Day-to-day development — just push changed BEAMs, no native rebuild needed:

        mix dala.deploy                 # fast push + restart
        mix dala.watch                  # auto-push on file save
    """)
  end

  # Returns a `mix dala.provision` callout when the project includes iOS, or
  # an empty string otherwise. Required as a one-time setup step before
  # `mix dala.deploy --native` can install to a physical iPhone (registers
  # the bundle ID with Apple and downloads a development provisioning
  # profile). Skipped for sim-only flows since simctl install doesn't sign.
  defp ios_provision_hint(gen_opts) do
    if gen_opts[:no_ios] do
      ""
    else
      """

          mix dala.provision              # iOS only, one-time: register bundle ID
                                         # + download provisioning profile (skip if
                                         # you're only running on the simulator)
      """
    end
  end

  defp platform_specific_hints(gen_opts) do
    no_ios = gen_opts[:no_ios] || false
    no_android = gen_opts[:no_android] || false

    case {no_android, no_ios} do
      # iOS only — no Android SDK path needed
      {true, false} -> {"", "iOS app"}
      # Android only
      {false, true} -> {" and android/local.properties with your local paths", "APK"}
      # Both
      _ -> {" and android/local.properties with your local paths", "APK + iOS app"}
    end
  end

  defp print_liveview_next_steps(app_name, no_install) do
    install_hint =
      if no_install,
        do: "\n    mix deps.get",
        else: ""

    Mix.shell().info("""


    Your Dala LiveView app #{app_name} is ready!
    #{install_hint}
    Next steps:

    1. Edit dala.exs with your local paths (dala_dir, elixir_lib).
    2. Edit android/local.properties with your Android SDK path.
    3. Run first-time setup:

        cd #{app_name}
        mix dala.install                # icon generation + first-run setup

    4. Configure your database in config/dev.exs and run:

        mix ecto.create && mix ecto.migrate

    5. Run the Phoenix server once to download JS/CSS dependencies and compile
       assets. This is required before deploying -- skipping it will result in
       missing assets on device:

        mix phx.server

       Open http://localhost:4000 in your browser to confirm it loads, then
       stop the server (Ctrl-C).

    6. iOS only — if you're targeting a physical iPhone, register the bundle
       ID with Apple and download a provisioning profile (one-time setup;
       skip for the simulator):

        mix dala.provision

    7. Deploy to device (first time — builds native APK/iOS app):

        mix dala.deploy --native

    The Dala WebView will load your Phoenix app at http://127.0.0.1:4000/.
    Verify `window.dala.send` in browser devtools routes through `pushEvent`
    (not `postMessage`) to confirm the LiveView bridge is active.

    Day-to-day development:

        mix dala.deploy                 # fast push + restart
        mix dala.watch                  # auto-push on file save
    """)
  end

  defp valid_app_name?(name) do
    case name do
      <<first, rest::binary>> when first in ?a..?z ->
        rest
        |> :binary.bin_to_list()
        |> Enum.all?(fn c -> c in ?a..?z or c in ?0..?9 or c == ?_ end)

      _ ->
        false
    end
  end
end
