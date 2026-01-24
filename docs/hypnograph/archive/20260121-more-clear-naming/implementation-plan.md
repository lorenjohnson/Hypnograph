# More Clear Naming (Implementation Plan)

Goal: align types and terminology with the “ideal-state nouns” from [the overview](overview.md).

Constraint: keep changes mechanical and rename-safe; avoid adding long-lived aliases. Defer on-disk key changes until the final step.

## Cross-cutting rule: rename identifiers, not just types

For each rename, also update:

- Local variables and parameters (avoid `let recipe = HypnographSession`, prefer `session`).
- Property names and computed properties where they encode the old noun.
- Function names (`loadRecipe` → `loadSession`, etc.) when the noun is part of the API.
- File names when they are user-facing or central (optional, but preferred for core models).

Suggested identifier mapping (use consistently across the codebase):

| Type rename | Preferred variable/parameter name |
|---|---|
| `HypnogramRecipe` → `HypnographSession` | `recipe` → `session` |
| `HypnogramClip` → `Hypnogram` | `clip` → `hypnogram` |
| `HypnogramSource` → `HypnogramLayer` | `source` → `layer` |
| `VideoClip` → `MediaClip` | `clip`/`videoClip` → `mediaClip` |

## Phase 0: Inventory and diagram refresh

- Update `docs/ontology/HypnographDomainDiagram.md` labels to match the chosen final nouns.
- List all call sites / file formats that store:
  - `HypnogramRecipe`
  - `HypnogramClip`
  - `HypnogramSource`
  - `VideoClip`

## Phase 1: Media slice naming

- Rename `VideoClip` → `MediaClip`.
  - Update all references (`HypnogramSource.clip`, libraries, tests, UI).
  - Keep JSON keys unchanged for now (still encode/decode as `clip` if that is the existing key).

## Phase 2: Layer naming

- Rename `HypnogramSource` → `HypnogramLayer`.
  - Update references such as `clip.sources` → `clip.layers` only if/when we also change keys and API shape; otherwise keep property names stable until Phase 4.

## Phase 3: Playable item naming

- Rename `HypnogramClip` → `Hypnogram`.
  - Update container properties (`recipe.clips` → `session.hypnograms`) only in Phase 4 (to avoid partial schema mismatches).

## Phase 4: Session naming + schema/key finalization (breaking point)

This is the “final step” you described: once everything works, then flip persisted names/keys together.

- Rename `HypnogramRecipe` → `HypnographSession`.
- Sweep identifier names: `recipe` → `session` across app/UI/storage layers.
- Update persisted keys everywhere (files, settings, history), likely:
  - `clips` → `hypnograms`
  - `sources` → `layers`
  - `clip` → `mediaClip`
- Decide migration strategy:
  - **Option A (migration)**: support decoding old keys once, re-save in new schema, then remove legacy support later.
  - **Option B (break)**: no migration; existing `.hypno` and history are considered invalid and must be recreated.

## Phase 5: Cleanup

- Remove any temporary bridging code if used during migration.
- Ensure docs match the final nouns (`docs/ontology/*` and project docs).
