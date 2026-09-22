# Plan: generate web themes from Omarchy palettes

Oma turns Omarchy palettes into themes a Phoenix app can use, following
`PHX.md` (the CSS contract), `SCHEMA.md` (the built-in palette contract)
and `SOURCES.md` (where themes come from). This file is the build plan.

Numbers as of 2026-09-22: 22 built-in themes in omarchy `quattro` @
`947e2fc0`, 154 community themes listed in the registry catalog (191
registered, 35 excluded for a missing preview, 2 unreachable), 176 total.

## Shape of the project

Oma is a plain Mix library plus Mix tasks, not a Phoenix app. Phoenix apps
in `ex/*` add it as a dependency and either run its generator into their
`assets/css/themes/` or import the CSS it ships in `priv/`. Keeping the
generator out of any one app means every app gets the same contract and
the same fixes.

### Sources

Three tiers, matching how the OS itself finds themes (see `SOURCES.md`):

| Tier | Read from | Fetched by |
|------|-----------|------------|
| Built-in | `./omarchy/themes/*/colors.toml`, the bootstrap checkout | `mise bootstrap repos apply` |
| Listed community | `catalog.json` published by `omacom/omarchy-theme-registry` | `mix oma.sync` over HTTPS |
| Unlisted | any git repo laid out like an Omarchy theme | `mix oma.add <git-url>` |

None of these is committed. What is committed is the vendored result:

```
priv/themes/
  builtin/<name>.toml        copied verbatim from the checkout
  community/<slug>.toml      written from catalog `colors`, same flat format
  extra/<slug>.toml          added by hand with mix oma.add
  index.json                 per-theme metadata for pickers (below)
  SOURCES                    omarchy commit, catalog generated_at, CDN URL
```

The library and its tests read only from `priv/`, so a consumer never
needs the checkout or network. A sync is a reviewed commit, and its diff
shows exactly what changed upstream.

`index.json` carries what a picker or gallery page wants and the palette
does not hold: `tier`, `name`, `repo`, `commit`, `author`, `mode`, `hue`,
`stars`, `tags`, `featured`, `warnings`, `preview.thumb` URL, and
`complete` (whether the author defined the full 24-key palette).

### Palette contract

The 24-key schema in `SCHEMA.md` is what the built-ins ship, not what the
ecosystem guarantees. Of 154 listed community themes, 61 are partial and
53 define only 17 keys. The registry requires nine: `accent`,
`background`, `foreground`, `red`, `yellow`, `green`, `cyan`, `blue`,
`magenta`. Oma adopts the same line:

- **Hard errors**: any of the nine missing, a colour value that is not
  6-digit hex, a `mode` that is neither `dark` nor `light`, a name that
  fails the upstream slug rule `^[a-z0-9_][a-z0-9._+-]*$`.
- **Derived**: every other key, using the cascade in
  `bin/omarchy-theme-color` verbatim. Legacy aliases (`bg`, `color0..15`,
  `purple`, `theme_type`) resolve first, then neutrals from `background`
  mixed with black, `bright_*` from the base hue mixed 20% with white,
  `orange` from `yellow`, `brown` from `orange`, `mode` from background
  channel sum when undeclared.
- **Flag**: `complete?` is true only when all 24 keys were present before
  derivation. Apps that want polished-only palettes filter on it.

One code path: a `colors.toml` file, a catalog entry's `colors` map and
an `alacritty.toml` all become the same raw key map before validation and
derivation. The catalog and a file must produce identical palettes for the
same theme.

## Modules

| Module | Responsibility |
|--------|----------------|
| `Oma.Color` | Hex parsing, `mix/3` (upstream `mix_color`, round-half-up), channel-sum luminance for `mode` inference (`> 382` is light), WCAG relative luminance and contrast ratio. |
| `Oma.Palette` | Struct with one field per schema key plus `name`, `tier`, `complete?`. `from_raw/2` takes a raw string map, `validate/1` applies the contract above, `derive/1` runs the upstream cascade. Legacy names accepted on input, never emitted. |
| `Oma.Palette.Parser` | Hand-rolled flat TOML reader mirroring the upstream line-by-line loader. No Hex dependency. |
| `Oma.Palette.Alacritty` | Raw key map from a legacy `alacritty.toml`, the same 17 keys `omarchy-theme-colors-from-alacritty` emits. Only needed by `mix oma.add`. |
| `Oma.Catalog` | Fetch `catalog.json` and `catalog.json.sha256` from a base URL, verify, decode. `entries/1` yields `{slug, raw_colors, meta}`. Handles `report.json` for a summary of exclusions. |
| `Oma.Themes` | Compile-time index of `priv/themes`. `all/0`, `builtin/0`, `community/0`, `complete/0`, `get!/1`, `valid?/1`, `light/0`, `dark/0`, `meta/1`. Recompiles via `@external_resource` on the TOML files and `index.json`. |
| `Oma.CSS` | Pure renderers returning iodata. `variables/1` emits the `:root[data-theme="name"]` block with `color-scheme` and one `--key` per schema colour, underscores to hyphens, `hyprland_*` and `active_*` dropped. `semantic_layer/0`, `tailwind_theme/0`, `daisyui/1` (table in `PHX.md` section 3, `-content` picked by luminance), `index/1`. |
| `Oma.Contrast` | Runs the pair table from `PHX.md` section 7 and returns `{pair, ratio, minimum}` failures. |
| `Mix.Tasks.Oma.Sync` | `mix oma.sync [--omarchy DIR] [--catalog URL] [--no-community]` refreshes `builtin/` from the checkout and `community/` from the catalog, rewrites `index.json` and `SOURCES`, prints added, removed and changed themes. Falls back to the marketplace repo's committed `data/catalog.json` when the CDN fails. |
| `Mix.Tasks.Oma.Add` | `mix oma.add <git-url>` does what `omarchy theme install` does: derive the slug from the repo name, shallow-clone to a temp dir, read `colors.toml` or derive from `alacritty.toml`, write `extra/<slug>.toml` and an index entry. |
| `Mix.Tasks.Oma.Gen` | `mix oma.gen --out DIR [--tier builtin,community,extra] [--complete-only] [--daisyui] [--semantic] [--tailwind]` writes `<name>.css` per theme plus `index.css`. |
| `Mix.Tasks.Oma.Check` | `mix oma.check [--tier ...]` prints the contrast report and exits non-zero on failures outside the known-exceptions list. |

## Milestones

Each milestone ends with `mix test` green and is a natural commit.

1. **Colour math and parser.** `Oma.Color` and `Oma.Palette.Parser` with
   unit tests. Verify `mix/3` against upstream: `brown` for a theme that
   omits it must equal what `omarchy-theme-color --file ... brown` prints.
   Verify mode inference on `flexoki-light` (`#FFFCF0` sums to 747) and
   `tokyo-night` (`#1a1b26` sums to 91).

2. **Palette contract and derivation.** `Oma.Palette` with negative tests
   for each hard error and derivation tests at three levels: a built-in
   without `orange`/`brown` (`last-horizon`, `solitude`, `white`), a
   17-key community shape (fixture copied from the `aetheria` catalog
   entry, which lacks `selection`, `muted`, all ramp neutrals and
   `light_foreground`), and a legacy-alias map (`bg`, `color4`). Assert
   `complete?` is false for the last two. Assert derivation is idempotent.

3. **Built-in sync.** `mix oma.sync --no-community` and the first
   `priv/themes/builtin/` commit. `Oma.Themes` on top with a test that
   `light/0` returns exactly the five light built-ins.

4. **Catalog sync.** `Oma.Catalog` against a fixture `catalog.json` cut to
   a handful of entries (one `native`, one `hybrid`, one `legacy`, one
   partial). Then `mix oma.sync` end to end and the first `community/`
   commit with `index.json` and `SOURCES`. Test that a community theme
   written from the catalog and one read back from its file derive to the
   same palette. Test that the sha256 check rejects a tampered body.

5. **CSS renderers.** Golden-file test for `tokyo-night` matching the
   block in `PHX.md` section 2. Then `semantic_layer/0`,
   `tailwind_theme/0` and `index/1`. `daisyui/1` last, with tests for the
   `base-200` rule and luminance-chosen `-content` colours. Confirm a slug
   with `_` or `.` (for example `black_arch`) renders a valid quoted
   `data-theme` selector and file name.

6. **Gen task.** `mix oma.gen` into a temp dir under test, with `--tier`
   and `--complete-only` filtering. Commit a generated
   `priv/static/themes/` for built-ins only; 176 files is too much to ship
   by default, and consumers wanting community themes generate them.

7. **Contrast report.** `Oma.Contrast` and `mix oma.check`. Run once across
   all 176 and record failures in `notes/CONTRAST.md` before deciding
   which pairs are hard failures and which become a per-theme
   `--text-on-accent` override. Expect derived neutrals in partial
   palettes to fail `dark_foreground` on `background` often; that is a
   reason for `--complete-only`, not a bug in the generator.

8. **Add task.** `mix oma.add` against a public theme repo, with the slug
   derivation tested on `omarchy-<name>-theme`, `<name>`, and scp-style
   URLs the way `omarchy-theme-install` strips them.

9. **Consumer walkthrough.** In one existing Phoenix 1.8 app under `ex/`,
   add Oma as a path dependency, run `mix oma.gen --out assets/css/themes
   --semantic --tailwind --daisyui --complete-only`, wire
   `@import "./themes/index.css"` into `app.css`, and follow `PHX.md`
   section 5 for the picker and `data-theme` persistence, using
   `index.json` metadata for thumbnails and grouping by `hue`. Write down
   every friction point and feed it back into task flags or docs.

## Decisions taken

- **Vendor the palettes, not just the CSS.** Compile-time palette access
  for emails and PDFs needs raw values; committing `priv/themes/` gives
  that and makes generation reproducible without checkout or network.
- **Catalog, not clones, for community themes.** One GET replaces 190
  clones, and the catalog is exactly what Omarchy users see. The `commit`
  field pins the validated revision if a raw `colors.toml` is ever needed.
- **Nine required keys, derive the rest.** Matching the registry means
  every listed theme loads. `complete?` lets apps be stricter.
- **No runtime dependencies.** `req` as a dev-only dependency for
  `mix oma.sync` and `mix oma.add`; the library itself stays dependency
  free. Hand-rolled flat TOML parser mirroring the upstream loader.
- **CDN base URL is an option with a default.** Today's default is the
  R2 public bucket URL in `SOURCES.md`; it is configuration, not
  contract. Verify `catalog.json.sha256` on every sync.
- **Drop `hyprland_*`, `active_border_color`, `active_tab_background`
  from CSS output.** Desktop concerns. Keep them on the struct.
- **Emit hex, not RGB channels.** Tailwind v4 mixes hex with
  `color-mix()`. A `--format tailwind3` flag is a later addition.
- **Theme names follow the upstream slug rule.** `[a-z0-9_][a-z0-9._+-]*`,
  lowercased; built-in names are reserved and a community or extra theme
  may not shadow one, exactly as the registry enforces.
- **Contrast failures are grandfathered, not fixed.** The first run of
  `mix oma.check` found 117 failing pairs in 82 of 176 themes, 13 of them
  built-ins (`dark_foreground` on `background` accounts for 65). All of
  them are listed in `priv/themes/contrast_exceptions.txt` with their
  ratios, so the check passes today and fails only on a new failure. The
  full table is `notes/CONTRAST.md`. Every theme file also emits
  `--text-on-accent`, the ramp end that contrasts best with `accent`, so
  the 13 `background`-on-`accent` failures have a legible alternative.
- **Excluded registry themes stay out.** Missing previews are the
  registry's gate, not ours, but shipping what the gallery does not show
  would confuse anyone comparing. `report.json` is summarised in the sync
  output so exclusions are visible.

## Status

Milestones 1 to 8 are implemented and tested (`mix test`, 70+ tests).
Milestone 9, the consumer walkthrough, needs a Phoenix app under `ex/`
and has not been run.

## Open questions

- Should `Oma.Themes.default/0` be a library default (`tokyo-night`) or
  always supplied by the consumer? Leaning consumer-supplied via app
  config, with `tokyo-night` as the documented fallback.
- Should sync be automated (a scheduled job opening a PR every six hours
  like the registry) or stay manual? Manual until the diff noise is known.
- Should `index.json` mirror preview thumbnails into `priv/static` or link
  to the immutable CDN URLs? Linking for now; the URLs are content
  addressed by commit.
- Omarchy ships a `neovim.lua` per built-in theme. Deriving syntax token
  colours from it (`PHX.md` section 6) is out of scope for now.
