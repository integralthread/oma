defmodule Oma.MixProject do
  use Mix.Project

  def project do
    [
      app: :oma,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "Oma",
      source_url: "https://github.com/integralthread/oma",
      docs: docs()
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "docs/SCHEMA.md",
        "docs/SOURCES.md",
        "docs/CONTRAST.md"
      ],
      groups_for_extras: [Reference: ~r"docs/"],
      groups_for_modules: [
        Palettes: [Oma.Palette, Oma.Palette.Parser, Oma.Palette.Alacritty, Oma.Color, Oma.Slug],
        Rendering: [Oma.CSS, Oma.Contrast],
        Sources: [Oma.Themes, Oma.Catalog, Oma.Omarchy, Oma.HTTP]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :inets, :ssl, :public_key, :crypto]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end
end
