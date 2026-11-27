# Heavenly Axis V3 architecture

## Source and packaging

Edit `src/*.lua`. `tools/build.py` sorts module filenames, embeds each module in a local factory, caches module return values, rejects missing static dependencies, and calls `Bootstrap`. No `loadstring`, remote module fetch, or file execution is needed by the core release. Both `dist/HeavenlyAxis.lua` and `Source` are generated from the same bytes. The header includes a deterministic source SHA-256 rather than a timestamp.

The sources use the Lua/Luau common subset. Lua 5.4 test execution is practical for pure logic and mocks; Luau compilation independently checks the target language. Roblox API behavior still requires Studio/device validation.

## Responsibility boundaries

| Module | Responsibility |
| --- | --- |
| `Util` | Copy/equality and finite-number helpers for portable state |
| `Geometry` | Screen rectangles, minimum dimensions, relative sizing, nested roots, alignment/distribution, snapping/guides |
| `Coordinates` | Core UI coordinate space, mouse conversion, overlay-local placement and safe-area rectangles |
| `Identity` | Escaped hierarchy descriptors and conservative exact matching; recognized built-in identities |
| `History` | Bounded completed transactions, undo/redo, saved checkpoint, dirty comparison, Cancel |
| `Config` | Version 3 schema, field/count/range limits, scope keys, applicability and merge order |
| `Capabilities` | Independent file, clipboard, input, and optional network capability discovery without brand assumptions |
| `Storage` | Bounded JSON, validated reads, staged/backup saves with readback, export/import, separate draft data |
| `Profiles` | Named scoped configurations, management, preview candidates, confirmed import overwrites/deletion |
| `Discovery` | Accessible PlayerGui index, smart hit ranking, clipping and compatibility, per-instance baselines, event cleanup |
| `Transform` | Idempotent property application, root-pruned screen geometry, UDim and UIScale conversion, stabilization and rollback |
| `UILayout` | Pure responsive placement for the toolbar, Quick Edit and management workspace |
| `UI` | Native toolbar, contextual inspector and workspace, launcher, selection overlays and dialogs |
| `Input` | Interaction ownership, touch and mouse lifecycle, pinch, box/multi selection, sliders and floating surfaces |
| `App` | Live authoritative layout, groups/preferences, checkpoints, previews, recovery, lifecycle and UI coordination |
| `Bootstrap` | Service/client startup, bounded waits, public session reservation and duplicate prevention |

## Portable state and identities

History and saved configuration contain plain tables, never Instance references. An element descriptor records the names/classes/ordinals of ancestors below PlayerGui, its class, ambiguity information, and an optional recognized built-in control kind. Keys are derived from that descriptor. A same-name hierarchy is deliberately ambiguous even if an ordinal exists; ordinals are not proof that a recreated object is the same control.

Matching requires a unique exact compatible hierarchy. Changes in name, parent, class, or ambiguity leave the entry unresolved. Unresolved entries remain in the profile; users can explicitly remap them and update group membership. Shape/color/screen proximity do not establish identity. Recognized built-in control hints require the actual `TouchGui/TouchControlFrame` lineage and expected classes; fixture mocks are game-specific objects.

Discovery records accessible objects, while the UI/hit list filters visibility. A baseline is captured once per actual object before editor transforms. New instances get new baselines. Saved layouts specify absolute Position/Size UDim components so reapplication does not add offsets repeatedly. Baselines and live objects stay in runtime adapters; portable states survive destruction.

## Coordinates and layout

Editing calculations use the Core UI safe-area coordinate system. Roblox documents GUI `AbsolutePosition`, pointer `InputObject.Position`, and `GetGuiObjectsAtPosition()` in that shared space. `GetMouseLocation()` provides an uninset point, so its adapter applies the top-left inset. UI placement subtracts the overlay parent's actual absolute origin before constructing an offset. `GuiService:GetInsetArea()` provides rectangles in the canonical space. The camera viewport describes device-safe dimensions and can differ from the full drawable area. [GuiBase2d API source](https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/GuiBase2d.yaml), [BasePlayerGui API source](https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/BasePlayerGui.yaml), [GuiService insets](https://create.roblox.com/docs/reference/engine/classes/GuiService#GetInsetArea), [Camera viewport source](https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/Camera.yaml)

The layout planner uses the available safe area. A landscape toolbar leaves room for a floating, contextual inspector that can move away from the selection. Portrait places the inspector low and accounts for the software keyboard. The secondary workspace has its own scrollable body. [UI architecture decision](MOBILE_RESCUE.md#ui-architecture-decision)

## Transforms and groups

Screen rectangles are `{x, y, w, h}`. Target properties remain UDim scale-plus-offset values. Pixel edits use a stable transaction reference to adjust offsets with the object's anchor and supported UIScale factors, preserving scale components. Group transforms prune descendants when a selected ancestor already moves them.

The transform adapter validates intended roots before writing. A completed edit waits for bounded geometry verification. Failure restores the transaction's original properties and leaves history at its prior state. Saved restoration can skip individual unavailable elements, reports counts, and applies ancestors before descendants.

The minimum interactive dimension is 16 Roblox UI units. Invalid values are rejected. Explicit position entry permits offscreen placement, and Recovery can bring a selection back. Group tools can scale the whole selection proportionally or adjust the dimensions of each supported member by the same amount. The anchor preference controls center-based adjustments.

Properties controlled by layouts/constraints are experimental where reversible property edits are possible. They need explicit approval. Some structures remain unsupported. A bounded stabilization observation checks whether changes held; repeated failure suspends overrides. No continuous property-enforcement loop disables Roblox movement or fights the game indefinitely.

## History, checkpoints, and previews

`beginGesture` captures the pre-action portable state after the pointer crosses its motion threshold. Pointer updates modify the live layout. Gesture completion verifies final geometry before committing one before/after entry. Keyboard, numeric and group actions use the same completed-transaction principle. History holds at most 80 actions.

Save waits for bounded stabilization. A successful write and readback establishes the durable checkpoint. Where file APIs are absent, Save establishes an explicitly memory-only checkpoint. A failed write preserves the previous checkpoint and dirty state. JSON export represents the latest accepted checkpoint. Save retains undo entries in the current edit context. Undo, redo and discard verify restoration before changing history. Dirty status compares the resulting layout with the checkpoint.

Profile and import previews carry separate candidate data. Preview chooses the edited scope and retains normal resolution, including more-specific active layers. Cancel restores the prior state and suspension. Apply selects the edit destination in memory. Save persists activation and changes, and detects when a more-specific profile prevents a broader-layer edit from matching the live result. Draft recovery uses preview and requires explicit Apply.

## Configuration precedence

The root schema has `version = 3`, a profile array, an `active` map, and validated editor preferences. Each profile has an ID/name, scope qualifiers, a layout map, named groups, and preferences. An active-map key is derived from `(scope, scopeId, device, orientation)`, permitting one active profile per scope key.

Resolution merges global → experience → place → device → orientation. Device and orientation scopes are place-bound. General orientation entries merge before device-specific orientation entries. Applicable active profiles contribute. Global layout and group entries may reference recognized built-in controls only.

Existing V3 full entries load and resolve with their original precedence. A save can add sparse overrides for inherited properties, explicit removal markers or group removals to preserve layer boundaries. New values use the same staged write and backup process. Earlier V3 readers may reject configurations containing those extensions. Retain the prior validated backup if you need to reopen the configuration with an earlier build.

UDim scale values adapt when parent bounds change, and offsets remain fixed in Roblox units. Rotation during an unsaved editing session retains the original orientation as its save and draft context. Save or discard concludes that session and loads the current orientation's matching overrides.

## Storage and recovery

File capability discovery requires separate readable/writable/existence functions. It makes no detection-time writes. The fixed files are:

- `HeavenlyAxis-v3.json`: saved configuration.
- `HeavenlyAxis-v3.backup.json`: previous validated save.
- `HeavenlyAxis-v3.pending.json`: staged checkpoint.
- `HeavenlyAxis-v3.draft.<experience>.<place>.<device>.<orientation>.json`: recoverable unsaved state, isolated by context and separate from profiles.

Before overwriting the primary, Storage validates it, stages the new JSON, preserves a backup, writes, and checks exact readback. A damaged primary is retained and blocks overwrite; a valid backup may be loaded in memory. These APIs do not offer a portable atomic filesystem rename, so a crash during final write remains possible; the backup/staged files and manual export are recovery paths. Nothing silently deletes saved profiles.

Imports are JSON only, size-limited to 2 MiB, schema/range/count checked, then merged into a preview. Conflicting existing profile content requires explicit confirmation. No input is evaluated as Lua. Clipboard success means the API accepted the data; the user still verifies pasting.

Draft writes are debounced. Recovery checks the editing context and, for new drafts, its saved profile and baseline reference. A changed reference preserves the stored draft and prevents automatic application. Safe Mode restores available baselines, suspends profile and experimental application, and preserves saved data.

## Startup and cleanup

Bootstrap waits at most 15 seconds each for LocalPlayer and PlayerGui, then reports failure rather than hanging forever. The environment session key is `__HEAVENLY_AXIS_V3`. Re-execution reuses the live session; initialization reserves the singleton before module setup can yield.

`HeavenlyAxisOptions.LoaderOnly` creates the restoration/runtime path without constructing the complete editor. The shared `LoaderOnly` option remains true until explicitly changed; rerunning alone does not open the editor while it is true. Call `:Open()` or set `LoaderOnly = false` before rerunning. `:Open()` lazily adds UI/input; `:Close()` releases editing interactions and keeps restoration available. `:SafeMode()` restores originals and opens recovery controls. `:Destroy()` disconnects subscriptions and restores available originals by default.

Discovery uses debounced structural refreshes and caches tree ordering and classifications. Elements pages render bounded row batches from their current search and discovery revision. Gesture alignment candidates are computed once at drag start. Input and overlay updates during a gesture avoid management list rebuilds. Experimental observations and startup waits are bounded. Owners disconnect subscriptions, destroy their GUI, and invalidate deferred callbacks through lifecycle guards.

## Change discipline

When adding a preference, update Config's allowlist/range validator and tests. When changing the schema, define a new version deliberately; do not reinterpret old input silently. When changing identity, add ambiguous/recreated cases before loosening matching. Keep real internal-control functional verification separate from screen-space property tests. Update the acceptance report and rebuild both tracked release artifacts before opening a PR.
