# Implementation Notes: Isometric Runtime Regeneration

## Architecture Contract

1. `MapData` remains the authoritative data model.
2. Generation passes operate only on logical map data.
3. Isometric conversion lives in `world_projection.gd`.
4. Renderer is presentation-only and must not mutate logical gameplay fields.

## Projection Contract

- `logical_to_screen(logical: Vector2i) -> Vector2`
- `screen_to_logical_approx(screen_position: Vector2) -> Vector2i`
- `get_tile_anchor_offset() -> Vector2`

Keep projection formulas isolated in `scripts/presentation/world_projection.gd`.

## Runtime Regeneration Contract

- Three independent actions:
  - regenerate current seed
  - randomize and regenerate
  - apply typed seed and regenerate
- Regeneration must preserve:
  - camera state (except first initialization)
  - overlay mode
  - grid visibility
  - props visibility

## Validation Surface

Validator report must expose:

- `ok`
- `errors`
- metrics including:
  - `entry_count`
  - `reachable_entries`
  - `buildable_in_center_pct`

Panel and logs must display both human-readable and machine-readable diagnostics.

## Regression Loop

- Reference seeds are stored in `tests/seeds/reference_seeds.json`.
- `Prev Seed` / `Next Seed` browse this list in runtime.
- Batch screenshot helper: `scripts/map_test_runner.gd`.
