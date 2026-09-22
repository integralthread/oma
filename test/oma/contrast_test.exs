defmodule Oma.ContrastTest do
  use ExUnit.Case, async: true
  doctest Oma.Contrast
  alias Oma.Contrast
  alias Oma.Themes

  test "reports every pair with a rounded ratio" do
    report = Contrast.report(Themes.get!("tokyo-night"))
    assert length(report) == length(Contrast.pairs())
    assert Enum.all?(report, &(&1.ratio == Float.round(&1.ratio, 2)))
    body = Enum.find(report, &(&1.fg == :foreground and &1.bg == :background))
    assert body.pass?
    assert body.ratio > 4.5
  end

  test "failures are the non-passing subset and check wraps them" do
    p = Themes.get!("tokyo-night")
    assert Contrast.failures(p) == Enum.reject(Contrast.report(p), & &1.pass?)

    case Contrast.check(p) do
      :ok -> assert Contrast.failures(p) == []
      {:error, failures} -> assert failures == Contrast.failures(p)
    end
  end

  test "a deliberately bad palette fails" do
    raw = %{
      "accent" => "#111111",
      "background" => "#101010",
      "foreground" => "#181818",
      "red" => "#111111",
      "yellow" => "#111111",
      "green" => "#111111",
      "cyan" => "#111111",
      "blue" => "#111111",
      "magenta" => "#111111"
    }

    {:ok, p} = Oma.Palette.from_raw(raw, name: "mud")
    assert {:error, failures} = Contrast.check(p)
    assert length(failures) == length(Contrast.pairs())
  end
end
