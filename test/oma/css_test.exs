defmodule Oma.CSSTest do
  use ExUnit.Case, async: true
  doctest Oma.CSS
  alias Oma.CSS
  alias Oma.Themes

  describe "variables/2" do
    test "tokyo-night matches the golden file" do
      css = CSS.variables(Themes.get!("tokyo-night"))
      assert css == File.read!("test/fixtures/tokyo-night.css")

      assert String.starts_with?(
               css,
               ~s(:root[data-theme="tokyo-night"] {\n  color-scheme: dark;\n)
             )

      assert css =~ "--accent: #7aa2f7;"
      assert css =~ "--darker-background: #0e0e14;"
      assert css =~ "--bright-foreground: #c0caf5;"
      assert css =~ "--brown: #75493d;"
      assert css =~ "--bright-magenta: #bb9af7;"
      assert css =~ "--text-on-accent: #0e0e14;"
      refute css =~ "_"
    end

    test "a light theme sets color-scheme light" do
      assert CSS.variables(Themes.get!("flexoki-light")) =~ "color-scheme: light;"
    end

    test "desktop-only keys are not emitted" do
      css = CSS.variables(Themes.get!("hackerman"))
      refute css =~ "hyprland"
      refute css =~ "active-border"
    end

    test "slugs with underscores or dots make a valid quoted selector" do
      {:ok, p} = Oma.Palette.from_file("priv/themes/community/black_arch.toml", tier: :community)
      assert CSS.variables(p) =~ ~s(:root[data-theme="black_arch"] {)
      {:ok, p} = Oma.Palette.from_file("test/fixtures/aetheria.toml", name: "a.b+c")
      assert CSS.variables(p) =~ ~s(:root[data-theme="a.b+c"] {)
    end

    test "selector can be overridden" do
      assert CSS.variables(Themes.get!("nord"), selector: ":root") =~ ~r/^:root \{/
    end
  end

  test "semantic layer and tailwind theme reference every role" do
    semantic = CSS.semantic_layer()
    tailwind = CSS.tailwind_theme()

    for role <-
          ~w(surface surface-sunken surface-deepest surface-raised text text-secondary text-strong
                   text-strongest border divider placeholder brand link focus-ring error warning success info) do
      assert semantic =~ "--#{role}: var(--", role
    end

    for role <-
          ~w(surface text border brand error info red yellow orange green cyan blue magenta brown) do
      assert tailwind =~ "--color-#{role}: var(--", role
    end

    assert String.starts_with?(tailwind, "@theme {")
  end

  describe "daisyui/2" do
    test "base-200 is the raised surface in dark and dark_background in light" do
      dark = Themes.get!("tokyo-night")
      light = Themes.get!("flexoki-light")
      assert CSS.daisyui(dark) =~ "--color-base-200: #{dark.lighter_background};"
      assert CSS.daisyui(light) =~ "--color-base-200: #{light.dark_background};"
    end

    test "content colours are the better-contrasting ramp end" do
      p = Themes.get!("tokyo-night")
      css = CSS.daisyui(p)
      # accent #7aa2f7 is bright, so text on it is the darkest stop
      assert CSS.content_color(p, p.accent) == p.darker_background
      assert css =~ "--color-primary-content: #{p.darker_background};"
      # neutral is the darkest stop, so text on it is the brightest
      assert css =~ "--color-neutral-content: #{p.bright_foreground};"

      for base <- [
            p.accent,
            p.magenta,
            p.cyan,
            p.red,
            p.green,
            p.yellow,
            p.blue,
            p.darker_background
          ] do
        pick = CSS.content_color(p, base)
        other = if pick == p.darker_background, do: p.bright_foreground, else: p.darker_background
        assert Oma.Color.contrast_ratio(pick, base) >= Oma.Color.contrast_ratio(other, base)
      end
    end

    test "plugin path and flags are configurable" do
      css =
        CSS.daisyui(Themes.get!("nord"),
          plugin: "daisyui/theme",
          default: true,
          prefersdark: true
        )

      assert css =~ ~s(@plugin "daisyui/theme" {)
      assert css =~ "default: true;"
      assert css =~ "prefersdark: true;"
      assert css =~ ~s(color-scheme: "dark";)
      assert css =~ ~s(name: "nord";)
    end
  end

  test "theme_file appends the daisyui block only when asked" do
    p = Themes.get!("nord")
    assert CSS.theme_file(p) == CSS.variables(p)
    assert CSS.theme_file(p, daisyui: true) == CSS.variables(p) <> "\n" <> CSS.daisyui(p)
  end
end
