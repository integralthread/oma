defmodule Mix.Tasks.Oma.AddTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  @colors File.read!("test/fixtures/aetheria.toml")

  setup do
    root = Path.join(System.tmp_dir!(), "oma-add-test-#{System.unique_integer([:positive])}")
    priv = Path.join(root, "priv")
    File.mkdir_p!(Path.join(priv, "builtin"))
    File.write!(Path.join(priv, "builtin/nord.toml"), File.read!("priv/themes/builtin/nord.toml"))
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, priv: priv}
  end

  defp git!(dir, args), do: {_, 0} = System.cmd("git", ["-C", dir | args], stderr_to_stdout: true)

  defp repo(root, name, files) do
    dir = Path.join(root, name)
    File.mkdir_p!(dir)
    for {file, body} <- files, do: File.write!(Path.join(dir, file), body)
    git!(dir, ["init", "-q"])
    git!(dir, ["-c", "user.email=t@e.st", "-c", "user.name=t", "add", "."])
    git!(dir, ["-c", "user.email=t@e.st", "-c", "user.name=t", "commit", "-q", "-m", "init"])
    dir
  end

  test "clones a repo, derives the slug and vendors colors.toml", %{root: root, priv: priv} do
    dir = repo(root, "omarchy-glacier-theme", %{"colors.toml" => @colors})
    out = capture_io(fn -> Mix.Tasks.Oma.Add.run([dir, "--priv", priv]) end)
    assert out =~ "added glacier (dark, partial, from colors.toml)"

    assert File.exists?(Path.join(priv, "extra/glacier.toml"))
    index = JSON.decode!(File.read!(Path.join(priv, "index.json")))
    assert index["glacier"]["tier"] == "extra"
    assert index["glacier"]["repo"] == dir
    assert String.match?(index["glacier"]["commit"], ~r/^[0-9a-f]{40}$/)
    assert index["glacier"]["complete"] == false
    assert index["glacier"]["mode"] == "dark"
  end

  test "derives from alacritty.toml and honours light.mode", %{root: root, priv: priv} do
    alacritty = """
    [colors.primary]
    background = "#fffcf0"
    foreground = "#100f0f"
    [colors.normal]
    black = "#100f0f"
    red = "#af3029"
    green = "#66800b"
    yellow = "#ad8301"
    blue = "#205ea6"
    magenta = "#a02f6f"
    cyan = "#24837b"
    white = "#cecdc3"
    """

    dir = repo(root, "paper", %{"alacritty.toml" => alacritty, "light.mode" => ""})

    out =
      capture_io(fn -> Mix.Tasks.Oma.Add.run([dir, "--priv", priv, "--name", "paper-light"]) end)

    assert out =~ "added paper-light (light, partial, from alacritty.toml)"
    assert File.read!(Path.join(priv, "extra/paper-light.toml")) =~ ~s(mode = "light")
  end

  test "--local reads a directory without cloning and keeps other index entries", %{
    root: root,
    priv: priv
  } do
    File.write!(Path.join(priv, "index.json"), ~s({"nord": {"tier": "builtin"}}\n))
    dir = Path.join(root, "omarchy-dune-theme")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "colors.toml"), @colors)

    capture_io(fn -> Mix.Tasks.Oma.Add.run(["--local", dir, "--priv", priv]) end)
    index = JSON.decode!(File.read!(Path.join(priv, "index.json")))
    assert Map.keys(index) |> Enum.sort() == ["dune", "nord"]
    refute Map.has_key?(index["dune"], "commit")
  end

  test "refuses built-in names, bad slugs and option-like URLs", %{root: root, priv: priv} do
    dir = repo(root, "omarchy-nord-theme", %{"colors.toml" => @colors})

    assert_raise Mix.Error, ~r/built-in/, fn ->
      capture_io(fn -> Mix.Tasks.Oma.Add.run([dir, "--priv", priv]) end)
    end

    assert_raise Mix.Error, ~r/usable theme name/, fn ->
      Mix.Tasks.Oma.Add.run(["--local", dir, "--name", "Bad", "--priv", priv])
    end

    assert_raise Mix.Error, ~r/git option/, fn ->
      Mix.Tasks.Oma.Add.run(["--upload-pack=x", "--priv", priv])
    end

    assert_raise Mix.Error, ~r/no colors.toml/, fn ->
      Mix.Tasks.Oma.Add.run(["--local", root, "--name", "empty", "--priv", priv])
    end
  end
end
