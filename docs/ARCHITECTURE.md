# Heavenly Axis V3 architecture

## Source and packaging

Edit `src/*.lua`. `tools/build.py` sorts module filenames, embeds each module in a local factory, caches module return values, rejects missing static dependencies, and calls `Bootstrap`. No `loadstring`, remote module fetch, or file execution is needed by the core release. Both `dist/HeavenlyAxis.lua` and `Source` are generated from the same bytes. The header includes a deterministic source SHA-256 rather than a timestamp.

The sources use the Lua/Luau common subset. Lua 5.4 test execution is practical for pure logic and mocks; Luau compilation independently checks the target language. Roblox API behavior still requires Studio/device validation.

## Responsibility boundaries

| Module | Responsibility |
| --- | --- |
| `Util` | Copy/equality and finite-number helpers for portable state |
| `Geometry` | Screen rectangles, minimum dimensions, resize/scale, nested roots, alignment/distribution, snapping/guides |
| `Identity` | Escaped hierarchy descriptors and conservative exact matching; recognized built-in identities |
| `History` | Bounded completed transactions, undo/redo, saved checkpoint, dirty comparison, Cancel |
| `Config` | Version 3 schema, field/count/range limits, scope keys, applicability and merge order |
| `Capabilities` | Independent file, clipboard, input, and optional network capability discovery without brand assumptions |
| `Storage` | Bounded JSON, validated reads, staged/backup saves with readback, export/import, separate draft data |
| `Profiles` | Named scoped configurations, management, preview candidates, confirmed import overwrites/deletion |
| `Discovery` | Accessible PlayerGui indexing, visibility/compatibility, per-instance baselines, event subscription cleanup |
| `Transform` | Idempotent property application, root-pruned world-space editing, supported UDim/UIScale conversion, rollback and bounded experimental stabilization |
| `UI` | Responsive dark/cyan panel, four tabs, lists, inspector, launcher, grid, highlights, handles and dialogs |
| `Input` | Touch identity, mouse gestures, pinch ownership, box/multi selection, slider sessions and shortcuts |
| `App` | Live authoritative layout, groups/preferences, checkpoints, previews, recovery, lifecycle and UI coordination |
| `Bootstrap` | Service/client startup, bounded waits, public session reservation and duplicate prevention |

## Portable state and identities

History and saved configuration contain plain tables, never Instance references. An element descriptor records the names/classes/ordinals of ancestors below PlayerGui, its class, ambiguity information, and an optional recognized built-in control kind. Keys are derived from that descriptor. A same-name hierarchy is deliberately ambiguous even if an ordinal exists; ordinals are not proof that a recreated object is the same control.

Matching requires a unique exact compatible hierarchy. Changes in name, parent, class, or ambiguity leave the entry unresolved. Unresolved entries remain in the profile; users can explicitly remap them and update group membership. Shape/color/screen proximity do not establish identity. Recognized built-in control hints require the actual `TouchGui/TouchControlFrame` lineage and expected classes; fixture mocks are game-specific objects.

Discovery records accessible objects, while the UI/hit list filters visibility. A baseline is captured once per actual object before editor transforms. New instances get new baselines. Saved layouts specify absolute Position/Size UDim components so reapplication does not add offsets repeatedly. Baselines and live objects stay in runtime adapters; portable states survive destruction.

## Transforms and groups

Screen rectangles are `{x, y, w, h}` in the same coordinate space as InputObject positions and overlay absolute bounds. Target properties remain UDim scale-plus-offset values. Pixel edits adjust offsets using the object's anchor and accumulated supported UIScale factors; they do not discard scale components. Group transforms prune descendants when a selected ancestor already moves them.

The transform adapter validates intended roots before writing an interactive operation. If a write fails, the selection rolls back. Applying a saved layout may skip individual incompatible/missing elements and report counts. It applies ancestors before descendants so explicit saved nested properties remain meaningful.

The minimum interactive screen dimension is 16 pixels. Invalid/non-finite values are rejected. Position is not clamped silently; offscreen placement remains deliberate and recovery is separate. Default proportional group scaling uses the opposite corner. Equal-size and center-based modes are explicit preferences.

Properties controlled by layouts/constraints are experimental where reversible property edits are possible. They need explicit approval. Some structures remain unsupported. A bounded stabilization observation checks whether changes held; repeated failure suspends overrides. No continuous property-enforcement loop disables Roblox movement or fights the game indefinitely.

## History, checkpoints, and previews

`beginGesture` captures the pre-action portable state. Pointer updates modify the live layout without appending history frames. `endGesture` commits one before/after entry. Keyboard/numeric/group actions use the same completed-transaction principle. History holds at most 80 actions.

Save waits for the bounded transform stabilization observation and refuses to persist if the layout changes or rolls back; review the result before retrying. Successful persistence establishes the checkpoint. With unsupported file APIs, a valid Save establishes an explicitly memory-only checkpoint. A failed file write preserves the previous checkpoint and dirty state; the valid candidate remains available for manual export. Save leaves undo entries intact. Undoing a saved action changes the live state and dirty comparison; it does not save automatically. Cancel restores the checkpoint and clears transient undo/redo branches.

Profile/import preview stores a separate pre-preview state and candidate configuration. Previewing a lower-scope profile disables applicable higher-scope active slots in the candidate only, ensuring the chosen layer is visible and the Save destination is unambiguous. The definitions remain intact. Cancel restores that state, activation metadata, and prior suspension. Apply activates the candidate in memory and starts the new profile session's history; Save is explicit. Unsaved draft recovery also uses preview so it cannot silently alter gameplay at startup.

## Configuration precedence

The root schema has `version = 3`, a profile array, an `active` map, and validated editor preferences. Each profile has an ID/name, scope qualifiers, a layout map, named groups, and preferences. An active-map key is derived from `(scope, scopeId, device, orientation)`, permitting one active profile per scope key.

Resolution merges global → experience → place → device → orientation. Device/orientation scopes are place-bound. General orientation entries merge before device-specific orientation entries. Only applicable active profiles contribute. Global entries/groups may reference recognized built-in controls only; this prevents a game's custom HUD from leaking into another game through defaults.

Native UDim scale values continue to adapt when parents/viewports change; offsets remain fixed. Orientation changes can resolve matching overrides when there is no active unsaved draft/preview. If unsaved work exists, it is retained and the user is told to apply a profile deliberately. No heuristic rewrites offsets based on screen ratios.

## Storage and recovery

File capability discovery requires separate readable/writable/existence functions. It makes no detection-time writes. The fixed files are:

- `HeavenlyAxis-v3.json`: saved configuration.
- `HeavenlyAxis-v3.backup.json`: previous validated save.
- `HeavenlyAxis-v3.pending.json`: staged checkpoint.
- `HeavenlyAxis-v3.draft.<experience>.<place>.<device>.<orientation>.json`: recoverable unsaved state, isolated by context and separate from profiles.

Before overwriting the primary, Storage validates it, stages the new JSON, preserves a backup, writes, and checks exact readback. A damaged primary is retained and blocks overwrite; a valid backup may be loaded in memory. These APIs do not offer a portable atomic filesystem rename, so a crash during final write remains possible; the backup/staged files and manual export are recovery paths. Nothing silently deletes saved profiles.

Imports are JSON only, size-limited to 2 MiB, schema/range/count checked, then merged into a preview. Conflicting existing profile content requires explicit confirmation. No input is evaluated as Lua. Clipboard success means the API accepted the data; the user still verifies pasting.

Draft writes are debounced. Recovery is offered only for the matching context and requires a user action. Invalid draft content is preserved until explicitly discarded. Safe Mode restores available baselines, suspends profile/experimental application, and leaves saved data untouched.

## Startup and cleanup

Bootstrap waits at most 15 seconds each for LocalPlayer and PlayerGui, then reports failure rather than hanging forever. The environment session key is `__HEAVENLY_AXIS_V3`. Re-execution reuses the live session; initialization reserves the singleton before module setup can yield.

`HeavenlyAxisOptions.LoaderOnly` creates the restoration/runtime path without constructing the complete editor. The shared `LoaderOnly` option remains true until explicitly changed; rerunning alone does not open the editor while it is true. Call `:Open()` or set `LoaderOnly = false` before rerunning. `:Open()` lazily adds UI/input; `:Close()` releases editing interactions and keeps restoration available. `:SafeMode()` restores originals and opens recovery controls. `:Destroy()` disconnects subscriptions and restores available originals by default.

Discovery is event-driven with debounced structural refreshes. It does not scan the entire PlayerGui tree every render frame. Gesture alignment candidates are cached at gesture start. Experimental observations and startup waits are bounded. Owners disconnect subscriptions, destroy their GUI, and invalidate deferred callbacks through lifecycle guards.

## Change discipline

When adding a preference, update Config's allowlist/range validator and tests. When changing the schema, define a new version deliberately; do not reinterpret old input silently. When changing identity, add ambiguous/recreated cases before loosening matching. Keep real internal-control functional verification separate from screen-space property tests. Update the acceptance report and rebuild both tracked release artifacts before opening a PR.
