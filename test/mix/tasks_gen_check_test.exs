defmodule Mix.Tasks.Oma.GenCheckTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  setup do
    dir = Path.join(System.tmp_dir!(), "oma-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  describe "mix oma.gen" do
    test "writes one file per built-in and an index", %{dir: dir} do
      out = capture_io(fn -> Mix.Tasks.Oma.Gen.run(["--out", dir, "--tier", "builtin"]) end)
      assert out =~ "generated 22 themes"

      files = dir |> File.ls!() |> Enum.sort()
      assert "index.css" in files
      assert "tokyo-night.css" in files
      assert length(files) == 23

      index = File.read!(Path.join(dir, "index.css"))
      assert index =~ ~s(@import "./tokyo-night.css";)
      refute index =~ "semantic"

      assert File.read!(Path.join(dir, "tokyo-night.css")) ==
               File.read!("test/fixtures/tokyo-night.css")
    end

    test "shared layers, daisyui and filters", %{dir: dir} do
      capture_io(fn ->
        Mix.Tasks.Oma.Gen.run([
          "--out",
          dir,
          "--tier",
          "builtin,community",
          "--complete-only",
          "--semantic",
          "--tailwind",
          "--daisyui",
          "--daisyui-plugin",
          "daisyui/theme"
        ])
      end)

      index = File.read!(Path.join(dir, "index.css"))

      assert String.starts_with?(
               index,
               ~s(@import "./semantic.css";\n@import "./tailwind.css";\n)
             )

      assert File.exists?(Path.join(dir, "semantic.css"))
      assert File.exists?(Path.join(dir, "tailwind.css"))
      assert File.read!(Path.join(dir, "nord.css")) =~ ~s(@plugin "daisyui/theme" {)

      complete = Oma.Themes.select(tiers: [:builtin, :community], complete_only: true)
      refute File.exists?(Path.join(dir, "aetheria.css"))
      assert dir |> Path.join("*.css") |> Path.wildcard() |> length() == length(complete) + 3
    end

    test "stale files are removed and --theme narrows", %{dir: dir} do
      File.write!(Path.join(dir, "stale.css"), "x")

      capture_io(fn ->
        Mix.Tasks.Oma.Gen.run(["--out", dir, "--theme", "nord", "--theme", "gruvbox"])
      end)

      assert dir |> File.ls!() |> Enum.sort() == ["gruvbox.css", "index.css", "nord.css"]
    end

    test "requires --out and a known tier" do
      assert_raise Mix.Error, ~r/--out/, fn -> Mix.Tasks.Oma.Gen.run([]) end

      assert_raise Mix.Error, ~r/unknown tier/, fn ->
        Mix.Tasks.Oma.Gen.run(["--out", "x", "--tier", "nope"])
      end
    end
  end

  describe "mix oma.check" do
    test "passes when every failure is a known exception", %{dir: dir} do
      p = Oma.Themes.get!("vantablack")
      exceptions = Path.join(dir, "exceptions.txt")
      known = Enum.map_join(Oma.Contrast.failures(p), "\n", &Oma.Contrast.key(p.name, &1))
      File.write!(exceptions, "# generated in test\n" <> known <> "\n")

      out =
        capture_io(fn ->
          Mix.Tasks.Oma.Check.run(["--theme", "vantablack", "--exceptions", exceptions])
        end)

      assert out =~ "0 unexpected"
    end

    test "the committed exceptions file covers every vendored theme" do
      out = capture_io(fn -> Mix.Tasks.Oma.Check.run([]) end)
      assert out =~ "0 unexpected"
    end

    test "exits 1 on an unexpected failure and writes markdown", %{dir: dir} do
      failing =
        Oma.Themes.builtin() |> Enum.find(&(Oma.Contrast.failures(&1) != [])) ||
          flunk("expected at least one built-in with a contrast failure")

      empty = Path.join(dir, "empty.txt")
      File.write!(empty, "")
      md = Path.join(dir, "report.md")

      out =
        capture_io(fn ->
          assert catch_exit(
                   Mix.Tasks.Oma.Check.run([
                     "--theme",
                     failing.name,
                     "--exceptions",
                     empty,
                     "--markdown",
                     md
                   ])
                 ) == {:shutdown, 1}
        end)

      # the failure banner goes to stderr; the summary line on stdout carries the count
      assert out =~ ~r/[1-9]\d* unexpected/
      report = File.read!(md)
      assert report =~ "# Contrast report"
      assert report =~ "| #{failing.name} |"
      assert report =~ "**"
    end
  end
end
