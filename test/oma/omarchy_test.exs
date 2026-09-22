defmodule Oma.OmarchyTest do
  use ExUnit.Case, async: true
  alias Oma.Omarchy

  @colors File.read!("priv/themes/builtin/nord.toml")
  @no_mode String.replace(@colors, ~r/^mode = .*\n/m, "")

  describe "theme_files/1" do
    test "picks themes/<name>/colors.toml and notices a light.mode marker" do
      paths = ~w(
        README.md
        themes/nord/colors.toml
        themes/nord/backgrounds/1.png
        themes/paper/colors.toml
        themes/paper/light.mode
        themes/broken/neovim.lua
        themes/deep/nested/colors.toml
        default/colors.toml
      )

      assert Omarchy.theme_files(paths) == %{
               "nord" => %{colors: "themes/nord/colors.toml", light?: false},
               "paper" => %{colors: "themes/paper/colors.toml", light?: true}
             }
    end
  end

  describe "content/2" do
    test "is verbatim without a marker" do
      assert Omarchy.content(@no_mode, false) == @no_mode
    end

    test "prepends mode = light for a marker only when the file has no mode key" do
      assert Omarchy.content(@no_mode, true) == ~s(mode = "light"\n\n) <> @no_mode
      assert Omarchy.content(@colors, true) == @colors
    end
  end

  describe "from_dir/1" do
    setup do
      root = Path.join(System.tmp_dir!(), "oma-omarchy-#{System.unique_integer([:positive])}")
      File.mkdir_p!(Path.join(root, "themes/nord"))
      File.mkdir_p!(Path.join(root, "themes/paper"))
      File.write!(Path.join(root, "themes/nord/colors.toml"), @colors)
      File.write!(Path.join(root, "themes/paper/colors.toml"), @no_mode)
      File.write!(Path.join(root, "themes/paper/light.mode"), "")
      git!(root, ["init", "-q"])
      git!(root, ["-c", "user.email=t@e.st", "-c", "user.name=t", "add", "."])
      git!(root, ["-c", "user.email=t@e.st", "-c", "user.name=t", "commit", "-q", "-m", "init"])
      on_exit(fn -> File.rm_rf!(root) end)
      %{root: root}
    end

    defp git!(dir, args),
      do: {_, 0} = System.cmd("git", ["-C", dir | args], stderr_to_stdout: true)

    test "reads every theme and the HEAD commit", %{root: root} do
      assert {:ok, %Omarchy{commit: commit, themes: themes}} = Omarchy.from_dir(root)
      assert String.match?(commit, ~r/^[0-9a-f]{40}$/)
      assert Map.keys(themes) |> Enum.sort() == ["nord", "paper"]
      assert themes["nord"] == @colors
      assert themes["paper"] == ~s(mode = "light"\n\n) <> @no_mode
    end

    test "reports a missing checkout" do
      assert {:error, {:no_themes_dir, _}} = Omarchy.from_dir("/nonexistent/omarchy")
    end
  end
end
