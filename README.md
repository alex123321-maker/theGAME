# Village Map Foundation (Isometric Runtime Build)

Godot `4.6.1` project for deterministic procedural village map generation.

## Current Scope

- `MapData` is the single source of truth for map logic.
- Isometric presentation is handled in `scripts/presentation`.
- Runtime regeneration is available from an in-game debug panel:
  - `Regenerate Current`
  - `Randomize Seed`
  - `Apply Seed`
  - `Prev Seed` / `Next Seed`
  - `Export JSON`
  - `Screenshot`
  - `Log`
- Debug overlays and tile hover selection work in isometric view.
- Reference seed regression set contains at least 10 seeds.

## Main Paths

- `autoload/` runtime state and debug event bus
- `scripts/core/` map data and generation passes
- `scripts/presentation/` projection, resolver, renderer, overlays, prop placement
- `scenes/map_view/` runtime scene root
- `scenes/ui/` runtime debug panel
- `assets/tiles/world_isometric/` base isometric tiles
- `assets/props/world_isometric/` prop sprites
- `resources/tilesets/world_isometric_tileset.tres` tileset placeholder contract
- `tests/seeds/reference_seeds.json` regression seed list

## Controls

- `R` regenerate current seed
- `T` randomize seed
- `Tab` cycle overlay mode
- `G` toggle grid
- `W/A/S/D` or arrows move camera
- `Q/E` zoom

## Notes

- Renderer changes do not mutate `MapData`.
- Generation remains seed-deterministic for fixed engine + generator version.
- Runtime regeneration should not require scene reload.
