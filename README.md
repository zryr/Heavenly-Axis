# Heavenly Axis

**Roblox HUD & Interface Editor · V3.3.0**

Heavenly Axis edits compatible, accessible Roblox PlayerGui elements with an Android-first touch interface and PC mouse/keyboard controls. Move and resize controls, work with groups, preview profiles, and recover original layouts. The release is one self-contained script with no required runtime UI library or downloaded code.

**Original by Syshi. V2 inspired by Danechka.** Repository history is preserved. This repository did not contain a license file; this rewrite does not invent or replace a license.

> Device verification is pending. Delta, Arceus X, Codex (Roblox executor), other Android environments, PC executors, and the Studio visual fixture are **Not Tested**. Automated and mocked results do not prove effective jump/joystick touch-region resizing. Heavenly Axis does not access protected interfaces or replace Roblox movement code.

## Install and open

1. Download [`dist/HeavenlyAxis.lua`](dist/HeavenlyAxis.lua) from a reviewed commit or release in this repository.
2. Run the complete file as client-side Lua in a compatible environment. In your own Studio test place, paste it into a LocalScript in `StarterPlayerScripts`.
3. Tap a control, make your adjustment in **Quick Edit**, then choose **Save** or **Done**. If the session can save only to memory, export the checkpoint as JSON for a durable copy.

If an earlier V3 build is already running, save or export its edits and rejoin before starting the new build. Heavenly Axis reports the running version and keeps the existing session intact when you rerun the script.

The legacy [`Source`](Source) path contains the identical generated script. Do not combine modules manually. No network request is required for the core editor. The maintained project URL is **https://github.com/zryr/Heavenly-Axis**.

## Editing on Android

1. Open the editor and take or skip the practice tutorial. Tap **Jump** in Layers or tap the jump button on the canvas. Quick Edit appears alongside the selection. Drag its header or hide it to reach a covered control. Portrait moves Quick Edit to the bottom edge.
2. Choose **Move**, **Size**, **Rotate**, or **Opacity** in Quick Edit. Drag to move. Resize with the handle, pinch, slider, or size stepper. To rotate, pull the exterior handle around the selection, use the angle slider, or tap a quarter-turn button. Compatible groups rotate around their combined center.
3. Hold a spot to **Select Through**, or arm the tool in **Layers** and tap the spot. Layers also offers search, filters, hierarchy navigation, and per-layer Details. Toggle **Multi** to add or remove targets by touch.
4. Use **Tools** for groups, profiles, advanced X/Y and W/H, settings, diagnostics, and recovery. Return to the canvas to continue with the same selection.

Aspect lock preserves proportions. Advanced options show compatibility limits for the selected target. Resizing enforces a 16-unit minimum. The grid starts on and snapping starts off, with alignment guides available in either mode.

**Opacity** is relative to the original appearance. At 50%, each supported visual surface has half its original opacity. A transparent background stays transparent. **Element only** edits the selection itself. **Include contents** can fade supported descendants or an existing compatible CanvasGroup. Layers can recover a fully faded control, which may still respond to gameplay input.

Drag the grips on the toolbar, Quick Edit, and Tools panels, or drag the launcher itself. Positions are saved separately from HUD edits and adapt to the current orientation and safe area. Edge docking is optional. **Reset Editor Layout** in Settings moves the editor surfaces back to their defaults.

Short notifications confirm saves, show recovery and history results, and flag errors. The verified Save confirmation stays visible briefly when Done returns you to gameplay.

**Ignore** skips a layer during ordinary taps. **Lock** lets you inspect a layer and prevents edits that would change it through its container. Both are editor-only preferences scoped to the current experience and place. Clear them in Smart Layers settings. **Help** offers Quick Start, the resumable Guided Tour, and a searchable control reference. Practice changes stay separate from the game HUD and undo history.

The selection boundary represents screen-space bounds. Pixel changes retain existing UDim scale components; scale-based layout still adapts with its parent while offsets remain fixed. Heavenly Axis does not guess a proportional conversion for offset-based layouts. Use device/orientation profile overrides when you need distinct arrangements.

A compact Heavenly Axis launcher reopens the editor after closing. Drag it to dock along a safe edge. Save its position with the current profile. If hidden, reopen with the public `:Open()` API, rerun the release with `LoaderOnly = false`, or use the configured keyboard shortcut. Tools includes **Recover launcher**.

Editing uses an overlay to intercept intended GUI gestures. A game's global input listeners can still observe input. Check for accidental jump/movement and test normal control behavior after leaving editing mode.

## PC controls

Use mouse dragging, eight resize handles, numeric inputs, and the same groups/profiles as on Android.

| Action | Input |
| --- | --- |
| Open/close editor | F8 by default; configurable in Settings |
| Add/remove selection | Shift/Ctrl click, or multi-select mode |
| Choose overlapping element | Right-click opens Select Through. Alt click cycles hits. |
| Box selection | Drag empty canvas, or toggle box mode with B |
| Move selected controls | Arrow keys; Shift uses 10-pixel steps |
| Undo / redo | Ctrl+Z / Ctrl+Y or Ctrl+Shift+Z |
| Save | Ctrl+S |
| Cancel active gesture / deselect | Escape |

Shortcuts pause while a textbox has focus. Close editing before normal gameplay. Some games also listen to these keys; editor shortcuts do not promise complete game-input isolation.

## Groups

Select multiple compatible layers, then choose **Quick Group** in Groups to work with them together. Name it to reuse it later. You can work on one member, return to the group, or ungroup while keeping the current geometry. **Select Siblings** previews related controls in the same container.

Enable multi-select and tap/click members. Moving a selection transforms only selected roots so a selected child is not moved twice through its selected parent. Use group controls to align edges/centers and distribute three or more elements evenly.

Proportional scaling resizes the selection as a unit. **Equal size change** applies an equivalent size adjustment to each editable root and keeps the controls at their respective positions. Opposite-corner scaling is the default for handles, with optional center scaling. Named groups support creation, renaming, adding and removing members, and selection. Missing members remain in the saved group for restoration or remapping.

## Save, history, and Cancel

**Reset All Changes** in Tools and Recovery restores supported HUD edits to their original values in one undoable action. Locked edits are kept. Save makes the reset effective for this device and orientation, including adjustments inherited from broader profiles. Saved profiles remain available. **Discard Unsaved Changes** returns to the current checkpoint, and **Reset Editor Layout** only moves the editor's own panels.

One verified drag, pinch, slider adjustment, or group operation is one history action. History holds up to 80 completed actions. **Save** waits for pending geometry verification and establishes a checkpoint, while keeping undo history for the active layout. Undo after Save changes the live layout and marks it unsaved. Choose Save again to persist it.

**Done** returns to gameplay. With unsaved changes, it offers Save, Discard, and Continue editing. A failed save keeps the session open. With memory-only storage, export the checkpoint before leaving if you need it after restart. **Cancel changes** restores the latest checkpoint and clears that layout's undo history. Profile and import previews have their own Apply and Cancel actions.

## Profiles and portable JSON

Use **Profiles** to create, rename, duplicate, preview, switch, and confirm deletion of named profiles. Only one profile per applicable scope is active. More specific settings override less specific settings:

1. Global defaults: recognized built-in controls and editor preferences only.
2. Experience-level layouts.
3. Place-specific layouts.
4. Place-bound device overrides (`touch` or `desktop`).
5. Place-bound orientation overrides (`portrait` or `landscape`, optionally device-specific).

Global data is limited to recognized built-in controls and editor preferences. Version 3 JSON from earlier V3 releases still loads. New saves may store individual property overrides or explicit removals. Renamed, reparented, or ambiguous elements remain unresolved until explicitly remapped.

Deleting the active profile resolves the remaining scope defaults immediately. GUI elements remain intact, and the deleted layout is not copied into a less-specific profile. Save persists the deletion; Cancel can restore the latest saved profile data and layout.

**Export** includes the latest accepted checkpoint. Press **Save** first to include current edits. Export also works with a memory-only checkpoint. **Import** validates JSON, previews it before activation, and asks for confirmation before replacing conflicting profiles. Save pending work before applying a different profile. Apply activates the selected profile in its own scope. More-specific active overrides retain precedence. If one masks an edit, choose that profile as the save target. Save writes the changes made in the current scope and keeps inherited properties at their source.

When file APIs are supported, saved profiles, staging/backup data, and unsaved recovery drafts are separate local JSON files. A corrupt existing save is preserved and blocks destructive replacement. Save reports actual write/readback success or a memory-only/manual-export fallback. An available API alone is shown as unverified.

Unsaved drafts are written separately and offered on the next matching session. Recovery opens a preview for confirmation. If the original saved profile changed, Recovery preserves the draft file and reports the mismatch. Rotating with pending changes keeps those changes assigned to the original orientation until Save or Discard, then loads the current orientation's layout.

## Startup and loader-only operation

Saving data does not install automatic execution. If your environment offers a supported autoexecute folder, configure it yourself using that environment's instructions. Place a local copy of the reviewed release there and prepend:

```lua
getgenv().HeavenlyAxisOptions = { LoaderOnly = true }
-- Paste the complete HeavenlyAxis.lua release below this line.
```

`getgenv()` is environment-specific. A Studio LocalScript can set `_G.HeavenlyAxisOptions` instead. Loader-only mode restores saved layouts and lifecycle subscriptions without constructing the full editor. To open it later in the same environment:

```lua
getgenv().__HEAVENLY_AXIS_V3:Open()
```

The `LoaderOnly` option remains set in the shared environment. A bare rerun keeps loader-only behavior while it is true. Use `:Open()` as above, or set `getgenv().HeavenlyAxisOptions = { LoaderOnly = false }` before rerunning the release. In Studio, use `_G.__HEAVENLY_AXIS_V3:Open()`. All public API examples use a **colon**. The same session exposes `:Close()`, `:SafeMode()`, `:Destroy()`, and `:VerifyStartup()`.

Restart the Roblox client, then inspect `:VerifyStartup()`. Its version/start timestamp, active profile, loader/editor mode, storage status, and application counts establish that the session actually started. Recheck after another restart to verify your own autoexecute setup. A Save notification or a successful script run is not proof of future automatic execution. Startup support is **Not Tested** on named executors.

Repeated execution reuses the live session; it does not intentionally create extra editors or add saved offsets repeatedly. Delayed/recreated accessible controls are matched through lifecycle discovery. Unknown/missing controls do not block startup.

## Recovery and experimental controls

**Safe Mode** suspends the active profile, stops experimental application, restores available original properties, and opens the editor. It preserves saved profiles. To request recovery before running the release:

```lua
getgenv().HeavenlyAxisOptions = { SafeMode = true }
-- Paste the complete release below.
```

For an existing session, call `getgenv().__HEAVENLY_AXIS_V3:SafeMode()`. Use profile Resume to leave suspension deliberately. **Restore originals** also preserves saved profiles; confirmed deletion is a separate operation. Offscreen recovery controls move selected targets back into the usable display region. `:Destroy()` disconnects the session and restores available originals; `:Destroy(false)` tears down while retaining the current layout.

Each layer reports separate support for movement, resizing, and appearance. A simple list can allow size changes while keeping positions under its control. Flex, grid, table, automatic sizing, and constraints can limit those adjustments. Use **Select container** when offered to move the whole bar. Layout-owned operations remain unavailable through the editor. Details can copy the layer path, its controller, and the latest failed adjustment when clipboard access is available. The live Heroes Battlegrounds layout remains unverified. [Layout and size behavior](https://create.roblox.com/docs/ui/list-flex-layouts)

## Compatibility and diagnostics

| Environment / behavior | Status | Evidence or limit |
| --- | --- | --- |
| Pure/mocked model tests | See [verification report](docs/VERIFICATION.md) | Tests run outside Roblox |
| Self-contained build and Luau compile | See [verification report](docs/VERIFICATION.md) | No runtime device evidence |
| Studio controlled visual HUD | Not Tested | Fixture and exact protocol provided |
| Delta / Android | Not Tested | Requires real device and environment checks |
| Arceus X / Android | Not Tested | Requires independent verification |
| Codex (Roblox) / Android | Not Tested | This is not OpenAI Codex |
| Other Android environments | Not Tested | Capability-based, no brand assumptions |
| PC executor and real Roblox controls | Not Tested | Mouse/keyboard implementation requires actual execution checks |
| Protected or inaccessible interfaces | Unsupported | No access bypass or movement-module replacement |
| Universal functional joystick resizing | Unsupported | Visual changes do not establish effective input-region changes |

Supported scope is accessible, compatible PlayerGui descendants. Some layout constraints, automatic sizing, scrolling transforms, rotations, dynamic game scripts, protected controls, or ambiguous identities cannot be edited safely. Jump and joystick names are priority hints, not a guarantee. Built-in visual resizing remains **unverified functionally** until real touch-region checks pass.

Settings contains capability results and an expandable bounded diagnostic log for startup, element matching, saves, recovery, and skipped operations. Keep logs free of private profile contents. Optional update checks retrieve trusted GitHub release metadata in the background; they never download/execute replacement code. If no release/network is available, use the repository's Releases page and replace your local script manually.

## Build and tests

```sh
python3 -m pip install -r requirements-dev.txt
python3 tools/build.py
python3 tools/build.py --check
python3 tools/test.py
python3 tools/luau_check.py
```

The build sorts modules deterministically and emits `dist/HeavenlyAxis.lua` plus the identical `Source` alias. Edit `src/*.lua`, then rebuild. Lupa and the Luau compiler are development tools only. CI checks reproducibility, pure/mocked behavior, Lua syntax, and Luau compilation.

Use [`studio/TestHUD.client.lua`](studio/TestHUD.client.lua) for controlled rendering/interaction tests in a place you own. Follow the full [Android/PC/Studio protocol](docs/TESTING.md), including real jump and joystick effective-region checks. See [verification and acceptance status](docs/VERIFICATION.md) for actual results and limitations.

## Maintainer overview

- `src/Util.lua`, `Geometry.lua`, `Identity.lua`, `History.lua`, `Config.lua`: pure validation, calculations, matching, and transactions.
- `src/Discovery.lua`, `Transform.lua`: accessible GUI discovery, compatibility, original baselines, and reversible properties.
- `src/Capabilities.lua`, `Storage.lua`, `Profiles.lua`: actual capability checks, validated storage, hierarchy, and preview management.
- `src/UI.lua`, `UILayout.lua`, `Input.lua`, `Coordinates.lua`: responsive editing surfaces, selection overlay, owned touch/mouse gestures, and screen-coordinate boundaries.
- `src/App.lua`, `Bootstrap.lua`: session lifecycle, recovery, profile restoration, public API, and duplicate prevention.
- `tools/`, `tests/`, `studio/`, `docs/`: deterministic packaging, automated checks, controlled HUD, and verification instructions.

See the [mobile rescue audit](docs/MOBILE_RESCUE.md), [architecture](docs/ARCHITECTURE.md), and [V2 audit](docs/AUDIT.md).
See [release changes](docs/CHANGELOG.md) for V3.3.0.
