# Where Omarchy themes come from

Researched 2026-09-22 against omarchy `quattro` @ 947e2fc0 and the live
registry catalog (generated 2026-09-22T05:09Z, schema_version 1).

## Three tiers

| Tier | Where | Count | Palette quality |
|------|-------|-------|-----------------|
| Built-in | `themes/<name>/colors.toml` in `omacom/omarchy`, installed at `/usr/share/omarchy/themes/` | 22 | Complete: all 24 keys, `mode` declared |
| Listed community | `omacom/omarchy-theme-registry`, published as `catalog.json` | 154 listed of 191 registered | Raw keys as the author wrote them; 61 partial, 61 without `mode` |
| Any git URL | `omarchy theme install <url>` clones into `~/.config/omarchy/themes/<slug>/` | unbounded | Anything from a full `colors.toml` to a legacy `alacritty.toml` |

Omarchy resolves all three the same way at install time: read
`colors.toml` (or derive one from `alacritty.toml`), then run the fallback
cascade in `bin/omarchy-theme-color`. The 24-key contract in `SCHEMA.md`
describes the built-ins, not the ecosystem. The registry only requires 9
keys: `accent`, `background`, `foreground`, `red`, `yellow`, `green`,
`cyan`, `blue`, `magenta`. Everything else is derived.

## The registry

- Repo: https://github.com/omacom/omarchy-theme-registry (branch `master`).
  One `themes/<slug>.json` per theme with `slug`, `repo`, `name`,
  `submitted_by`, `added_at`, optional `tags`. Nothing else is stored; the
  build clones every repo, validates, and publishes.
- Rules: `packages/validator/src/validate.ts`; constants mirrored from
  omarchy in `packages/schema/src/constants.ts` (built-in reserved names,
  denied files, required palette keys).
- Rebuilds on push, every 6 hours, or by dispatch. A theme that starts
  failing keeps its last-good entry; missing three refreshes drops it.
- Published under `/v1/`: `catalog.json`, `catalog.min.json`,
  `catalog.json.sha256`, `themes/<slug>.json`,
  `previews/<slug>/<sha>/{1200,480}.webp`, `report.json`.
- Live CDN today: `https://pub-98465b4520f24f9a8f162c4f722a293f.r2.dev/v1/`.
  This is an R2 public bucket chosen by the registry's `CDN_BASE_URL`
  variable and could move. `cdn.themes.omarchy.org` and
  `themes.omarchy.org` did not resolve from this machine; the public
  gallery is served at https://omarchy.org/themes/.
- Fallback snapshot: `data/catalog.json` on `master` of
  https://github.com/omacom/omarchy-theme-marketplace (the Rails site),
  committed for when the CDN is down. Was 4 days stale at research time.

## Catalog entry shape

```json
{
  "slug": "01", "name": "01",
  "repo": "https://github.com/OldJobobo/omarchy-01-theme",
  "author": {"login": "...", "url": "..."},
  "description": "...", "license": null, "stars": 16,
  "mode": "dark", "hue": "blue",
  "colors": { "accent": "#ab92fc", "...": "raw keys from colors.toml" },
  "generation": "hybrid",
  "ignored_on_install": ["alacritty.toml", "neovim.lua"],
  "installed_files": ["colors.toml", "backgrounds/...", "preview.png"],
  "backgrounds": {"count": 23, "has_video": true, "total_bytes": 48028127},
  "preview": {"src": "...1200.webp", "thumb": "...480.webp", "width": 1200, "height": 675, "placeholder": "#282838"},
  "commit": "b79621f8...", "pushed_at": "2026-08-13T01:24:42Z",
  "added_at": "2026-09-11", "tags": ["anime"], "featured": false,
  "warnings": ["IGNORED_ON_INSTALL", "PALETTE_PARTIAL", "MODE_UNDECLARED"],
  "install": "omarchy theme install https://github.com/OldJobobo/omarchy-01-theme"
}
```

Facts that matter for Oma:

- `colors` holds only the keys the author defined, with legacy aliases
  (`bg`, `color4`, ...) already mapped to canonical names. It is not the
  resolved palette. Distribution today: 93 themes with 25 keys, 4 with 20,
  4 with 19, 53 with 17. The 17-key shape (no `selection`, `muted`,
  ramp neutrals or `light_foreground`) is the alacritty-derived set.
- `mode` is already resolved, by luminance when the author left it out.
- `generation`: `native` 51 (colors.toml only), `hybrid` 95 (colors.toml
  plus legacy files), `legacy` 8 (alacritty.toml only).
- `commit` pins the validated revision, so
  `https://raw.githubusercontent.com/<owner>/<repo>/<commit>/colors.toml`
  fetches the exact file without a clone.
- `report.json` lists the 35 excluded and 2 missing themes with reasons.
  34 of 35 exclusions are a missing `preview.png`; the palettes may be
  fine, but they are not what Omarchy users can see in the gallery.
- No community slug collides with a built-in name; the validator forbids it.
- The registry's constants describe a sparse-checkout
  `omarchy theme install <name>` (by slug, not URL) that the `quattro`
  checkout does not have yet. Registry and OS are not always in step.

## Recommendation for Oma

1. Do not require the `omarchy` checkout. It is over 300 MB for 22 small
   files; fetch `themes/<name>/colors.toml` by path at a pinned commit
   (`Oma.Omarchy`). A clone is still worth having to read the derivation
   script, templates and tests, so keep `--omarchy DIR` for that.
2. Do not bootstrap 190 theme repos. Pull `catalog.json` in `mix oma.sync`,
   verify `catalog.json.sha256`, and treat each entry's `colors` as raw
   palette input through the same `Oma.Palette.from_raw/2` path a file takes.
   One code path for files and catalog entries.
3. Vendor the result: `priv/themes/builtin/<name>.toml` copied from the
   checkout, `priv/themes/community/<slug>.toml` written from the catalog
   in the same flat format, plus `priv/themes/CATALOG` recording
   `generated_at` and the omarchy commit. Keep per-theme metadata (`repo`,
   `commit`, `mode`, `hue`, `warnings`, `preview.thumb`) in a small JSON
   index for pickers.
4. Validation contract (`Oma.Palette`): 9 hard-required keys as
   the registry defines, derivation for the rest, and a `complete?` flag so
   an app can offer only fully specified palettes if it wants.
5. Make the CDN base URL a task option with the r2.dev URL as today's
   default, and fall back to the marketplace snapshot when it fails.
6. For a theme that is not listed, support `mix oma.add <git-url>`, which
   does what `omarchy theme install` does: clone, read `colors.toml` or
   derive from `alacritty.toml`, and slug the repo name the same way.
