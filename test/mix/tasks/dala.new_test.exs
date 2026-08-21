# SPDX-FileCopyrightText: 2024 Dala contributors <https://github.com/manhvu/dala/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.Dala.NewTest do
  # async: false — Mix.shell() is process-global, and the task mutates the
  # filesystem in the cwd. All tests run inside a temp cwd via setup.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  @task "dala.new"

  setup do
    tmp = Path.join(System.tmp_dir!(), "dala_new_task_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    prev_cwd = File.cwd!()
    File.cd!(tmp)

    on_exit(fn ->
      File.cd!(prev_cwd)
      File.rm_rf!(tmp)
    end)

    :ok
  end

  defp run_task(args) do
    capture_io(:stdio, fn ->
      Mix.Task.rerun(@task, args)
    end)
  end

  defp task_error_message(args) do
    e = assert_raise(Mix.Error, fn -> Mix.Task.rerun(@task, args) end)
    Exception.message(e)
  end

  # ── happy path ────────────────────────────────────────────────────────────────

  test "generates a native project in the current directory" do
    run_task(["my_task_app", "--no-install"])

    assert File.dir?("my_task_app")
    assert File.exists?(Path.join("my_task_app", "mix.exs"))
    assert File.exists?(Path.join("my_task_app", "lib/my_task_app/app.ex"))
    assert File.exists?(Path.join("my_task_app", "lib/my_task_app/home_screen.ex"))
  end

  test "--dest generates into the given directory" do
    File.mkdir_p!("nested/dest")
    run_task(["dest_app", "--no-install", "--dest", "nested/dest"])

    assert File.dir?("nested/dest/dest_app")
    assert File.exists?(Path.join("nested/dest/dest_app", "mix.exs"))
  end

  test "--no-ios skips ios/ but keeps android/" do
    run_task(["ios_skip_app", "--no-install", "--no-ios"])

    assert File.dir?(Path.join("ios_skip_app", "android"))
    refute File.dir?(Path.join("ios_skip_app", "ios"))
  end

  test "--no-android skips android/ but keeps ios/" do
    run_task(["android_skip_app", "--no-install", "--no-android"])

    assert File.dir?(Path.join("android_skip_app", "ios"))
    refute File.dir?(Path.join("android_skip_app", "android"))
  end

  test "--ios is sugar for --no-android" do
    run_task(["sugar_app", "--no-install", "--ios"])

    assert File.dir?(Path.join("sugar_app", "ios"))
    refute File.dir?(Path.join("sugar_app", "android"))
  end

  test "--android is sugar for --no-ios" do
    run_task(["sugar2_app", "--no-install", "--android"])

    assert File.dir?(Path.join("sugar2_app", "android"))
    refute File.dir?(Path.join("sugar2_app", "ios"))
  end

  test "prints next steps after generation" do
    output = run_task(["steps_app", "--no-install"])

    assert output =~ "Your Dala app steps_app is ready!"
    assert output =~ "mix dala.install"
    assert output =~ "mix dala.deploy --native"
    assert output =~ "mix dala.watch"
  end

  test "prints deps.get hint when --no-install is passed" do
    output = run_task(["hint_app", "--no-install"])
    assert output =~ "mix deps.get"
  end

  test "prints iOS provision hint when iOS is included" do
    output = run_task(["prov_app", "--no-install"])
    assert output =~ "mix dala.provision"
  end

  test "omits iOS provision hint for Android-only projects" do
    output = run_task(["prov_skip_app", "--no-install", "--no-ios"])
    refute output =~ "mix dala.provision"
  end

  test "prints platform-specific hints" do
    both = run_task(["hint_both_app", "--no-install"])
    assert both =~ "APK + iOS app"

    ios_only = run_task(["hint_ios_app", "--no-install", "--no-android"])
    assert ios_only =~ "iOS app"
    refute ios_only =~ "local.properties with your local paths"

    android_only = run_task(["hint_android_app", "--no-install", "--no-ios"])
    assert android_only =~ "APK"
    assert android_only =~ "local.properties with your local paths"
  end

  test "prints created files list for native projects" do
    output = run_task(["created_app", "--no-install"])

    assert output =~ "mix.exs"
    assert output =~ "lib/created_app/app.ex"
    assert output =~ "android/app/src/main/AndroidManifest.xml"
    assert output =~ "ios/beam_main.m"
  end

  test "created files list respects platform exclusions" do
    output = run_task(["created_ios_app", "--no-install", "--no-android"])
    refute output =~ "AndroidManifest.xml"
    assert output =~ "ios/beam_main.m"
  end

  # ── validation errors ─────────────────────────────────────────────────────────

  test "raises when no app name is given" do
    assert task_error_message([]) =~ "Usage: mix dala.new APP_NAME"
  end

  test "raises on invalid app name characters" do
    assert task_error_message(["My-App"]) =~ "lowercase letters, digits, and underscores"
  end

  test "raises on app name starting with a digit" do
    assert task_error_message(["1app"]) =~ "lowercase letters, digits, and underscores"
  end

  test "raises on reserved word app name" do
    assert task_error_message(["end"]) =~ "reserved word"
  end

  test "raises on consecutive underscores" do
    assert task_error_message(["my__app"]) =~ "consecutive or trailing underscores"
  end

  test "raises on trailing underscore" do
    assert task_error_message(["my_app_"]) =~ "consecutive or trailing underscores"
  end

  test "raises when both platforms are excluded" do
    assert task_error_message(["both_excluded_app", "--no-ios", "--no-android"]) =~
             "Cannot exclude both platforms"
  end

  test "raises when the target directory already exists" do
    File.mkdir_p!("existing_app")
    assert task_error_message(["existing_app", "--no-install"]) =~ "already exists"
  end

  # ── liveview flag ─────────────────────────────────────────────────────────

  test "prints liveview banner with --liveview (generation itself is integration-tested)" do
    # Running the full --liveview path spawns `mix phx.new` (~30s). The banner
    # and flag plumbing are what this unit test covers; the pipeline itself is
    # covered by the integration suite in ProjectGeneratorTest.
    output =
      capture_io(:stdio, fn ->
        try do
          Mix.Task.rerun(@task, ["lv_banner_app", "--liveview", "--no-install"])
        catch
          :exit, _ -> :ok
        end
      end)

    assert output =~ "--liveview: generating Phoenix LiveView app with Dala bridge"
  end

  # ── fetch_deps ────────────────────────────────────────────────────────────

  test "runs deps.get after generation and reports success" do
    # Fake `mix` that succeeds for deps.get.
    fake_bin = Path.join(System.tmp_dir!(), "dala_new_fake_bin_#{System.unique_integer()}")
    File.mkdir_p!(fake_bin)
    File.write!(Path.join(fake_bin, "mix"), "#!/bin/sh\necho fake deps resolved\nexit 0\n")
    File.chmod!(Path.join(fake_bin, "mix"), 0o755)

    prev_path = System.get_env("PATH")
    System.put_env("PATH", "#{fake_bin}:#{prev_path}")

    try do
      output = run_task(["deps_ok_app"])
      assert output =~ "Fetching dependencies..."
      assert output =~ "fake deps resolved"
      refute output =~ "deps.get failed"
    after
      System.put_env("PATH", prev_path)
      File.rm_rf!(fake_bin)
    end
  end

  test "warns (but does not raise) when deps.get fails" do
    # Fake `mix` that fails for deps.get.
    fake_bin = Path.join(System.tmp_dir!(), "dala_new_fake_bin_#{System.unique_integer()}")
    File.mkdir_p!(fake_bin)
    File.write!(Path.join(fake_bin, "mix"), "#!/bin/sh\necho boom >&2\nexit 1\n")
    File.chmod!(Path.join(fake_bin, "mix"), 0o755)

    prev_path = System.get_env("PATH")
    System.put_env("PATH", "#{fake_bin}:#{prev_path}")

    try do
      output = run_task(["deps_fail_app"])
      assert output =~ "Fetching dependencies..."
      assert output =~ "deps.get failed"
      # The generated project is still left in place for a manual retry.
      assert File.dir?("deps_fail_app")
    after
      System.put_env("PATH", prev_path)
      File.rm_rf!(fake_bin)
    end
  end

  test "prints local-mode banner with --local" do
    # --local requires a dala sibling; create one so generation succeeds.
    File.mkdir_p!("dala")
    File.mkdir_p!("dala_dev")

    output = run_task(["local_banner_app", "--no-install", "--local"])
    assert output =~ "local mode: using path: deps"
  end
end
