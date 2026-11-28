# Verification and device protocol

Use these result labels exactly: **Passed**, **Failed**, **Unsupported**, **Not Tested**. A capability may additionally be shown in the product as **Available but unverified**, **Supported and verified**, **Unsupported**, or **Failed**. A detected API is not an executor test.

## Automated checks

Run from the repository root with Python 3.12:

```sh
python3 -m pip install -r requirements-dev.txt
python3 tools/build.py
python3 tools/build.py --check
python3 tools/test.py
python3 tools/luau_check.py
```

`tools/test.py` discovers `tests/*.lua`, creates a fresh Lua 5.4 runtime per suite, and syntax-checks modules, Studio fixture, and releases. Tests use assertions; a suite returning a number reports its check count. Dependencies are development-only. `tools/luau_check.py` uses Luau 0.728 on Linux x86_64, verifies the downloaded archive's pinned SHA-256, and compiles the maintained Lua files. On another platform, set `LUAU_COMPILE` to an installed `luau-compile` executable. Downloading the compiler requires network access; it is never downloaded by the Roblox release.

Build output must be byte-identical between clean runs and match both tracked artifacts. CI checks the committed artifacts rather than silently updating them.

## Controlled Studio fixture

Use **Fade** to open a transparent ability row with an image, mixed text transparency and strokes, plus nested existing CanvasGroups. Test **Element only** and **Include contents** separately at 50%, 0%, and 100%. Fade a CanvasGroup to 50%, then change one nested element to 100%. Compare the edited element and its unchanged siblings against the initial render, then Undo twice. Confirm the background stays transparent, a fully faded control stays available through Layers and Select Through, and Recreate applies changes only to the original matched scope.

Use **Rotate** on the labeled sample. Drag the exterior handle across the angle boundary, move the rotated sample, and Undo. Then try rotating a compatible group and confirm center-to-center spacing stays consistent. Drag the toolbar, Quick Edit, and Tools grips near safe-area edges, rotate the device, and reset panel placement in Settings. Confirm **Reset All Changes** with several controls selected, including a named group. Check that the selection, guides, and handles clear. Undo and verify that the previous edits return while the canvas stays clear. Redo, save, and reopen in the same orientation to check inherited modifications and named groups.

For V3.2.0, start or skip the practice tutorial before editing the game HUD. On a touch viewport, long-press an overlapping control and select a candidate from Select Through. Repeat with its explicit action in Layers. Set Ignore and Lock separately and verify that the canvas selection, editing controls, and parent protection change while the fixture GUI itself stays unchanged.

Use **Bars** in the fixture controls to show the representative numbered ability bars. The simple list should permit resizing the first button without changing its raw Position. The flex and grid cases should offer a container route when the layout owns the adjustment. Move the container and use Undo, confirming that tapping a fixture ability after Done still reports its activation. These fixtures exercise supported Roblox layouts. A live Heroes Battlegrounds session is a separate validation step.

1. Open an empty place in Roblox Studio. Put `studio/TestHUD.client.lua` in `StarterPlayer > StarterPlayerScripts` as a LocalScript.
2. Put the complete generated `dist/HeavenlyAxis.lua` into a second LocalScript in the same folder. The release has its own bundled module loader; no executor or runtime HTTP loading is needed for these accessible mock GUIs.
3. Play as a client. Start with 1536×695, 960×440, 640×360, and 932×430 landscape. Then try 393×852 and 360×640 portrait, 1024×768 tablet, and 1920×1080 desktop. Use Studio's [Device Simulator](https://create.roblox.com/docs/studio/testing-modes#device-simulation) and include a notched profile in both orientations. Record rendered viewport and simulator scale rather than assuming the preset matches Roblox UI units.
4. Tap `JumpStyle` inside `TouchControlFrameMock`. Check that the mock button wins the direct hit and that the parent is still selectable explicitly. Try the 22-unit `TinyControl`, the visible and clipped portions of `PartlyClippedChild`, `OverlapFront` and `OverlapBack`, the long decorative label, and simultaneous parent/child selection. Compare displayed and actual geometry for `ScaledChild`, `RelativeXXControl`, and `RelativeYYControl`. Inspect compatibility on layout-managed, aspect-constrained, and rotated objects.
5. Tap **Insets** with the editor closed. With the editor open, tap each purple probe and compare its position and outline to Studio Output. The client logs the input point, Roblox viewport units, inset areas, absolute GUI geometry, and raw and inset-subtracted engine hit results. Repeat with a notched profile and after rotation. Temporarily collapse/move any editor surface that obscures a probe. The `TopbarSafeInsets` probe can be constrained by the available top-bar slot.
6. Tap **240 items** to add a bounded visible collection. Open Elements, scroll, search for `StressTile197`, and choose a result. Monitor Diagnostics or Studio's Script Performance panel during drag and repeated reopen. Verify that edits preserve list position and repeated activity does not increase connections or GUI instances without bound. Disable the collection to exercise removal.
7. Use **Menu** to create and destroy a temporary GUI. Use **Recreate** to remove the mock HUD and rebuild it after one second with matching descriptors. Use **Show / hide** to test visibility filtering. Repeat while watching selection and restoration.
8. Compare the mock activation counter before editing, during canvas gestures, and after Done. Report any input leakage. Stop Play to clean up, or rerun the fixture to destroy all previous fixture screens and disconnect their subscriptions.

The fixture does not call Humanoid.Jump, move a character, or use Roblox's internal control implementation. Passing it does not prove the effective touch region of Roblox's built-in jump button or joysticks.

## Visual run

Capture landscape first. Record the launcher with the editor closed, then the toolbar before selection and Quick Edit with the jump control selected. Hide or move Quick Edit and capture access to a previously covered control. Inspect selection alignment, label readability, button spacing and the complete size controls at 640×360 and on a notched profile.

Open Elements, Advanced, Groups, Profiles and Settings. Capture scrolling, a long name, empty and unavailable states, and the Done confirmation dialog. Rotate to portrait, focus the size input to show the keyboard and check that the field stays visible. Save rendered screenshots with the viewport, platform and revision recorded for each run.

## Common manual sequence

Record version/commit, device, OS, Roblox version, environment version, experience/place, screen dimensions, orientation, and capability statuses. Use a test experience you control or are permitted to modify.

| Check | Exact steps and expected observation |
| --- | --- |
| Initial startup | Execute once with no saved data. Editor/launcher starts even if TouchGui is absent; game-specific controls appear when they load. Status does not claim internal-control functional verification. |
| Duplicate startup | Execute the same release three times. One launcher/editor remains; one movement action changes geometry once. Closing/reopening retains original baseline and saved state. |
| Direct selection | Tap/click foreground and overlapping regions. Use overlap cycling and hierarchy/list selection to pick the intended parent or child. Editor UI never becomes a target. Hidden elements are filtered. |
| Movement | Drag with one pointer, add a second unrelated touch, release the unrelated touch, continue and release the first. Only the intended gesture moves the selection. Numeric X/Y and step controls agree with visible bounds. |
| Handles and sizing | Try touch handles on `TinyControl` and mouse handles on desktop. Compare the slider, its thumb, the percentage field, actual dimensions, and fine steps. Try zero, negative, invalid and oversized entries, aspect lock, independent W/H input, and cancellation mid-gesture. |
| Pinch | Start one finger on the selection and the other close outside it, then reverse their order. Spread and contract in separate runs, lifting a different finger first in each. Repeat from a moving drag and for a proportional group. Check that there is no jump when the second finger joins, unrelated touches stay free, each completed pinch yields one undo action, and a distant second finger leaves the first gesture in control. |
| Grid/guides | Grid is visible and snapping starts off. Approach another object's edge and center; guides appear without forced movement. Enable snapping, adjust grid/tolerance, then verify the selected object snaps predictably. |
| Nested group | Select NestedParent and NestedChild together and move/scale. The child is not transformed twice. Unsupported targets are reported; failed transactional transforms restore prior values. |
| Group operations | Create/name a group, add/remove a member, rename/select it, align each axis, and distribute three controls. Compare scaling the group bounds with applying the same adjustment to each member. Use differently sized members and compare their final sizes and positions. Change the resize anchor, reset, and delete the group. Recreate one member and verify missing members remain in the definition. |
| Undo, Save, Done | Tap without moving and verify no undo entry. Drag, undo, and redo. Save, drag again, tap Done, continue editing, then tap Done and discard. Reopen and compare the checkpoint. Undo after saving and compare the stored data. Make more actions than the history limit. |
| Profiles | Create two named place profiles, edit/save each, preview the other, Cancel and compare layout; preview again and Apply. Test rename, duplicate, confirmed deletion, original restore, suspend, and resume. Unsaved edits must receive appropriate handling. |
| Scope isolation | Save recognized built-in defaults globally and game-specific GUI at experience/place scope. Join another experience: game-specific data must not apply. Test experience→place→device→orientation precedence and one active profile per scope. |
| Import/export | Export JSON; import a copy as preview; Cancel; import and Apply. Try duplicate IDs/names requiring overwrite confirmation, truncated JSON, wrong version, non-finite/oversized properties, inconsistent keys, unknown members, and code text. Invalid data must be rejected without execution or silent replacement. |
| Persistence | Save with working storage, with absent storage, and with read/write APIs that fail. Status must distinguish disk success, memory-only checkpoint, and manual export. Preserve a malformed saved file and verify it is not overwritten silently. |
| Drafts | Make unsaved changes, terminate the session, reopen. Offer recovery without applying the draft. Restore/decline explicitly; saved profile remains separate. Try incompatible experience/device/orientation context. |
| Recreation | Save a target, destroy/recreate its GUI with identical identity, respawn, then delay initial GUI creation. Saved properties reapply once. Rename/reparent it or introduce duplicate siblings; leave it unresolved for manual remapping rather than guessing. |
| Recovery | Move a target offscreen, use recovery controls. Hide/move launcher and use keyboard/API recovery. In loader-only mode, use `:Open()` or set `LoaderOnly = false` before rerunning; a bare rerun retains the shared true option. Safe Mode suspends profiles and experimental edits, restores available originals, and opens the editor without deleting profiles. |
| Experimental override | With Safe Mode off, approve one supported experimental target explicitly. Save/reload and inspect approval. Introduce a script that rewrites it; bounded stabilization must suspend repeated failure. Disable approval and restore. Never edit protected interfaces. |
| Orientation | Rotate landscape→portrait→landscape during idle and during a gesture. Inspector remains usable, launcher recovers within safe display bounds, pending gesture ends safely, and profile-specific/adaptive rules are predictable. |
| Updates | Trigger optional metadata check with working/blocked networking. Startup stays usable. Show current/available version or failure; never execute replacement code. |
| Teardown | Exit edit mode and test game input. Destroy session and confirm no GUI, bound shortcuts, input handlers, or retries remain. Saved profiles remain intact. |

## Android execution matrix

Every row below is **Not Tested** until a real device result is recorded. “Codex” here means the Roblox executor, not OpenAI Codex.

| Environment | Status | Required checks |
| --- | --- | --- |
| Delta / Android | Not Tested | Full common sequence, one/two/three-finger identity, landscape/portrait, safe areas, storage/export capabilities, built-in control functional regions |
| Arceus X / Android | Not Tested | Same sequence independently; do not infer capability behavior from Delta |
| Codex (Roblox) / Android | Not Tested | Same sequence independently; identify application/version precisely |
| Other Android environment | Not Tested | Record name/version and actual capabilities; run same sequence |

For the actual jump button, classic joystick, and dynamic joystick, record visual movement and functional response separately. Press the original location, new center, resized edges, and nearby outside area before editing, after editing and reloading, and after respawn. Confirm jumping, movement, and release behavior. Begin dynamic joystick touches at different locations and record any control recreation or repositioning by Roblox. Mark unavailable functional resizing **Unsupported** and unobserved behavior **Not Tested**.

## PC execution matrix

| Environment | Status | Required checks |
| --- | --- | --- |
| Roblox Studio desktop mock HUD | Not Tested | Mouse drag, eight handles, numeric inputs, focused-textbox shortcut exclusion, multi/box selection, profiles, fixture recreation, cleanup |
| Compatible PC executor | Not Tested | All common checks, clipboard/storage/network capability behavior, singleton behavior across executions, real accessible control behavior |

Test shortcuts with the editor closed, open, and while typing in each text field. The configurable reopen shortcut must not consume unrelated input when unnecessary. Test Ctrl/Shift multi-selection, drag a box on empty space, Escape, undo/redo, arrow nudges, and Save as implemented in the UI.

## Recording a run

Copy the common table into a result sheet. Enter one result per check, expected/actual values, a reproduction, and evidence reference. Keep mock/pure, Studio, Android, and PC results separate. Attach screenshots or short recordings for coordinate, overlap, pinch, orientation, and internal-control functional-region checks. Never include private saved profile data or credential values in logs.
