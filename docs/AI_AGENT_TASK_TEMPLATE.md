# AI Agent Task Template (Isometric Runtime)

Use this structure for each implementation task.

## Goal

Describe the expected user-visible or system-visible result.

## Constraints

- Keep `MapData` as source of truth.
- Do not move generation logic into renderer.
- Preserve deterministic generation for identical seed + generator version.
- Keep runtime regeneration without scene reload.

## Files To Change

List explicit files or directories.

## Expected Artifact

Describe created/updated runtime behavior, scene nodes, scripts, assets, or docs.

## Completion Criteria

Define measurable checks:

- runtime action works
- no parse errors in headless run
- diagnostics updated
- regression seed navigation works

## Invariants That Must Not Break

- serialization format for map data
- generation pass data contract
- overlay availability in isometric mode
