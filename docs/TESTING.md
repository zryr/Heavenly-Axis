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

1. Open an empty place in Roblox Studio. Put `studio/TestHUD.client.lua` in `StarterPlayer > StarterPlayerScripts` as a LocalScript.
2. Put the complete generated `dist/HeavenlyAxis.lua` into a second LocalScript in the same folder. The release has its own bundled module loader; no executor or runtime HTTP loading is needed for these accessible mock GUIs.
3. Play as a client. Test at 1280×720, 800×600, 844×390, and 390×844 using Device Emulator. Record actual viewport and safe-area settings.
4. The fixture exposes a jump-style button, classic-style thumb, dynamic-style region, nested parent/child, UIScale child, overlapping buttons, three group items, hidden/offscreen controls, a layout-managed list, aspect-constrained control, and a rotated control.
5. Use **Temporary menu** to create/destroy a GUI. Use **Recreate HUD** to remove the entire HUD and recreate it after one second with equal descriptors, and **Hide / show HUD** to test visibility filtering. Recreate repeatedly and monitor connection/memory behavior.
6. Read the activation counter while editing and after leaving edit mode. The mock jump and joystick gestures must work during normal mock gameplay. Report any gameplay input leakage during editing; a GUI shield does not guarantee isolation from every game's global input listeners.
7. Stop Play to clean up. Rerunning the fixture also destroys its previous instance and disconnects its subscriptions.

The fixture does not call Humanoid.Jump, move a character, or use Roblox's internal control implementation. Passing it does not prove the effective touch region of Roblox's built-in jump button or joysticks.

## Common manual sequence

Record version/commit, device, OS, Roblox version, environment version, experience/place, screen dimensions, orientation, and capability statuses. Use a test experience you control or are permitted to modify.

| Check | Exact steps and expected observation |
| --- | --- |
| Initial startup | Execute once with no saved data. Editor/launcher starts even if TouchGui is absent; game-specific controls appear when they load. Status does not claim internal-control functional verification. |
| Duplicate startup | Execute the same release three times. One launcher/editor remains; one movement action changes geometry once. Closing/reopening retains original baseline and saved state. |
| Direct selection | Tap/click foreground and overlapping regions. Use overlap cycling and hierarchy/list selection to pick the intended parent or child. Editor UI never becomes a target. Hidden elements are filtered. |
| Movement | Drag with one pointer, add a second unrelated touch, release the unrelated touch, continue and release the first. Only the intended gesture moves the selection. Numeric X/Y and step controls agree with visible bounds. |
| Handles and sizing | Drag all corners and edges. Try tiny sizes, zero, negative, NaN-like text, huge values, aspect lock, W/H fields, size slider, +/- buttons, and cancel mid-gesture. Dimensions remain valid and the opposite-corner/center setting behaves as documented. |
| Pinch | Place two fingers on the selected area, pinch apart/together, move fingers, then lift each in either order. One completed pinch yields one undo action and continuous feedback. A third finger must not hijack it. |
| Grid/guides | Grid is visible and snapping starts off. Approach another object's edge and center; guides appear without forced movement. Enable snapping, adjust grid/tolerance, then verify the selected object snaps predictably. |
| Nested group | Select NestedParent and NestedChild together and move/scale. The child is not transformed twice. Unsupported targets are reported; failed transactional transforms restore prior values. |
| Group operations | Create/name a group; add/remove a member; rename/select it; align each axis; distribute three controls; compare proportional scaling and equal-size mode; switch center/opposite-corner anchor; reset; delete group and confirm GUI objects remain. Recreate one member and verify missing members remain in the definition. |
| Undo, Save, Cancel | Drag once, undo once, redo once. Save, drag again, Cancel and compare exact checkpoint. Undo a saved action and confirm unsaved status without disk overwrite. Redo and Save. Bound history while making more actions than its limit. |
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

For the actual jump button, classic joystick, and dynamic joystick, test visual movement separately from functional response. Press the original location, new center, resized edges, and nearby outside area before and after editing, after saving/reloading, and after respawn. Confirm actual jumping/movement and release behavior. For dynamic controls, begin touches at different locations and verify whether Roblox recreates or repositions its region. If the effective touch region cannot be adapted safely, mark functional resizing **Unsupported** or **Not Tested** as appropriate; do not promote visual success into functional success.

## PC execution matrix

| Environment | Status | Required checks |
| --- | --- | --- |
| Roblox Studio desktop mock HUD | Not Tested | Mouse drag, eight handles, numeric inputs, focused-textbox shortcut exclusion, multi/box selection, profiles, fixture recreation, cleanup |
| Compatible PC executor | Not Tested | All common checks, clipboard/storage/network capability behavior, singleton behavior across executions, real accessible control behavior |

Test shortcuts with the editor closed, open, and while typing in each text field. The configurable reopen shortcut must not consume unrelated input when unnecessary. Test Ctrl/Shift multi-selection, drag a box on empty space, Escape, undo/redo, arrow nudges, and Save as implemented in the UI.

## Recording a run

Copy the common table into a result sheet. Enter one result per check, expected/actual values, a reproduction, and evidence reference. Keep mock/pure, Studio, Android, and PC results separate. Attach screenshots or short recordings for coordinate, overlap, pinch, orientation, and internal-control functional-region checks. Never include private saved profile data or credential values in logs.
