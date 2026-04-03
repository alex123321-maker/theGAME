# Stage 1 Generator Architecture

## Source Of Truth

`MapData` is the only source of truth for local-map generation.
The renderer reads `MapData` and never derives gameplay logic back from scene nodes, meshes, or temporary overlay geometry.

## Generation Phases

The stage-1 pipeline runs in this order:

1. `generate_layout_composition`
2. `generate_regions`
3. `generate_clearing`
4. `generate_major_blockers`
5. `generate_water_body`
6. `generate_entries`
7. `generate_roads`
8. `resolve_surface_transitions`
9. `build_buildable_mask`
10. `validate_map`

Each phase writes logical state into `MapData`, not directly into the scene.

## Core Layers

`MapData` now persists these layers and masks:

- `terrain_layer`
- `height_layer`
- `region_layer`
- `road_mask`
- `water_mask`
- `blocker_mask`
- `buildable_mask`
- `village_center_mask`
- `transition_layer`

Per-tile state is stored in `TileData`, including:

- `base_terrain_type`
- `height_class`
- `region_id`
- `is_walkable`
- `is_buildable`
- `is_road`
- `is_water`
- `is_blocked`
- `road_width_class`
- `transition_type`
- `transition_flags`
- `debug_tags`

## Class Responsibilities

- `MapGenerator`: orchestrates the generation pipeline.
- `LayoutComposer`: chooses the high-level composition template and anchors.
- `RegionGenerator`: initializes open ground, corridor regions, and the clearing.
- `BlockerGenerator`: stamps large blocker masses only.
- `WaterGenerator`: builds a single coherent water body when selected.
- `RoadGenerator`: creates road graphs and rasterizes curved road paths onto the grid.
- `TransitionResolver`: computes transition priorities and adjacency flags.
- `MapValidator`: validates center connectivity, entries, buildable area, and road presence.
- `MapRenderer3D`: builds the greybox scene from `MapData`.
- `MapDebugOverlay`: visualizes logical layers such as terrain, regions, roads, blockers, and validation.

## Transition Priorities

Transition resolution uses explicit surface priorities.
Higher-priority surfaces dominate visual conflict handling:

1. `RAVINE_EDGE`
2. `WATER`
3. `BLOCKER`
4. `ROAD`
5. `CLEARING`
6. `GROUND`

Adjacent transition flags are stored by category and side so future surface types can add more detailed edge modules without changing the source-of-truth model.

## Debug Workflow

Runtime regeneration still happens through the existing debug panel.
Useful overlay modes for stage 1:

- `base_terrain`
- `regions`
- `roads`
- `water`
- `blockers`
- `height`
- `buildable`
- `validation`

The validation panel summary reports:

- seed
- composition template
- center area
- entry count
- reachable entries
- road tiles
- water tiles
- blocker tiles
- buildable tiles
- stage-by-stage validation status

## Adding A New Surface Later

To add a new surface type safely:

1. Extend `MapTypes` with the terrain and transition semantics.
2. Add tile-level flags or metadata only in `TileData`.
3. Write generation logic into a dedicated generator module.
4. Update `TransitionResolver` priorities and adjacency flags.
5. Extend `MapRenderer3D` and `MapDebugOverlay`.
6. Update `MapValidator` if the new surface changes gameplay constraints.
