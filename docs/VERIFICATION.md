# V3.5.0 verification

The recording described in the request was unavailable in the workspace. The reported HotBar, Number, and Backpack selections informed the representative fixture. Those observations provide no exact live hierarchy. Roblox Studio, native touch, and Heroes Battlegrounds remained unavailable on the Linux test host.

## Executed V3.5 checks

| Command | Result |
| --- | --- |
| `python3 tools/build.py --check` and `cmp Source dist/HeavenlyAxis.lua` | Passed. Both release paths reproduce the same 645,405 bytes. |
| `python3 tools/test.py` | Passed. Thirteen suites, 1,450 checks, 30 Lua syntax checks, zero failures. |
| `python3 tools/luau_check.py` | Passed. Luau 0.728 compiled 44 files, including the Studio fixture. |
| `python3 tools/lucide_subset.py <pinned checkout> --check` | Passed. The 75 locally bundled Lucide glyphs reproduce exactly. |

The 98 bundled checks exercise the verified edit, save, reopen, and cold restore sequence on source-equivalent release paths. The 173 UI checks cover touch targets, panel scrolling and placement, contextual selection, and preview cleanup. The 129 Input checks include pinch handoff, scroll arbitration, focus loss, recreation, and modal cancellation.

## Complete-ability walkthrough

| Step | Evidence |
| --- | --- |
| Tap an ability | Discovery tests cover actionable and repeated composite controls, overlapping buttons, transparent decoration, named parts, and whole-control selection with layout-owned position. |
| Understand restrictions | The inspector shows layout ownership next to the selected ability. Input checks exercise whole-control drag, a managed drag that leaves geometry unchanged, and deliberate layer or container dragging. |
| Switch scopes | App and UI checks exercise Whole control, Individual layer, Entire container, picker preview, and returning to the same control. Scope navigation stays outside layout history and saves. |
| Recover and reopen | The release workflow exercises the checkpoint, recreation, direct tools, and Reset All. The configuration schema remains V3. |

Earlier taps could prefer individually editable children over a passive ability wrapper. The transform guard separately refused changes to a slot's layout-owned position. Selection now uses hierarchy, visible bounds, actionable controls, and repeated composite structure. Transform eligibility is checked after selection. Simple lists can still permit a supported size edit. Grid and flex layouts can control both position and size. A user can select an editable container explicitly to move its contents together.

The refreshed native interface uses a pinned Lucide subset without runtime downloads. Icons mount passive geometry, preserve action labels, and use the existing touch owner. Layers enforces a bounded display batch. [Research and architecture choices](REFERENCE-DESIGN.md) · [Icon implementation and license](ICON-SYSTEM.md)

## Layout and allocation review

The source-derived previews ran the shipped bundle and fixture in a shared Roblox API mock. Viewports included 640 × 360, 932 × 360, 393 × 852, 1024 × 768, and 1440 × 900. The review shortened the scoped pinch hint and practice copy, corrected the order and placement of candidates in Select Through, and checked direct access to the managed bar action. Toasts avoid active editing surfaces and are passive. The neutral Reset toast can briefly overlap an inactive HUD control. Native text wrapping, image payloads, CanvasGroup composition, dispatch, and frame timing remain **Not Tested**. [Mock layout contact sheet](visual-qa-v3.5.png) · [Responsive layouts](visual-qa-responsive-v3.5.png)

On a 32-control mock at 640 × 360, the idle editor used 1,138 owned descendants, up from 668 in V3.4.0. The Layers page used 1,886, up from 932. Native icon strokes account for much of the additional GUI geometry. Connections increased from 284 to 285 on the idle editor. Eight reopen cycles left the counted objects and connections stable, and destroy left zero connections. Icon colors update only when they change. The composite tour fixture mounts on demand and clears on close. These comparisons measure structural costs in mocks.

## V3.4.0 baseline

Roblox Studio and physical Android hardware were unavailable in the Linux workspace. The supplied attachments contained written briefs. The referenced screen recording was unavailable. The evidence below covers the bundled editor executed against API mocks and source-derived layout previews. Native rendering, simultaneous touch dispatch, and device performance require the Studio and Android runs. [Roblox Studio system requirements](https://create.roblox.com/docs/studio/setup)

### Executed V3.4 checks

| Command | Result |
| --- | --- |
| `python3 tools/build.py` and `python3 tools/build.py --check` | Passed. Both tracked release paths reproduce the same 582,091 bytes. |
| `python3 tools/test.py` | Passed. Twelve suites, 1,283 checks, 27 Lua syntax checks, zero failures. |
| `python3 tools/luau_check.py` | Passed. Pinned Luau 0.728 compiled 40 files, including the shared Roblox test fixture. |
| `git diff --check` and `cmp dist/HeavenlyAxis.lua Source` | Passed. |

The suites cover App orchestration (119), core geometry and history (59), direct transform integration (49), discovery (60), input (121), notifications (37), onboarding (51), opacity planning (32), persistence (189), bundled integration (75), transform and runtime adapters (333), and UI layout and interactions (158). Viewport scenarios include 1536 × 695, 960 × 440, 640 × 360, 932 × 430, 393 × 852, 360 × 640, 1024 × 768 and 1920 × 1080, plus safe-area and software keyboard variations.

## Experience overhaul

| Workflow | Verified against the bundled editor or maintained modules |
| --- | --- |
| Toolbar and Quick Edit | Portrait groups history and keeps Save at one tap at 360 units wide. A narrower viewport keeps Save in Layout Actions. Active Size explains pinch. Quick Edit can hide without dropping the selection. Tools opens its last destination and management rows expose focused menus. |
| Pinch | Tests cover expansion, contraction, a second touch near the selection, a distant touch, both release orders, close starting touches, an unrelated third finger, drag handoff, focus loss, menu cancellation, orientation change, and recreated controls. Bundled tests confirm one history action and proportional group spacing. |
| Opacity | Tests compare expected property values for images, text, strokes, backgrounds, and existing CanvasGroups, including nested overrides, a 0% fade, authored recovery at 100%, legacy background overrides, undo/redo, profile switching, and exact recreation. Exact replay visits the saved branches. Faded artwork stays available through explicit selection while ordinary taps can reach layers beneath it. |
| Reset All | Bundle restores original geometry, rotation, and image opacity and clears the selection, inspector, outlines, handles, guides, box, and Select Through. Tests cover named groups, protected and missing controls, inherited data, rollback failure, and Save/Discard. Undo restores previous edits with the canvas still deselected. |
| Save and recovery | Tests simulate an interrupted final write, a missing primary file, backup recovery without overwriting files, repeat saves preserving the previous backup, and concurrent edits requiring a fresh checkpoint. |

Reviewed the V3.4.0 bundle's mock instance geometry at 640 × 360 and 932 × 360 landscape, 393 × 852 portrait, 1024 × 768 tablet, and 1440 × 900 desktop. States included the empty and selected canvas, each Quick Edit tool, selection groups, Select Through, management pages, onboarding, Reset All and toasts. The review prompted a visible pinch hint, labeled numeric fields, and direct Save at 360 units with 44-unit buttons. Preview typography, wrapping, and stacking are approximations. Native touch and visual gates remain **Not Tested**. [Mock layout contact sheet](visual-qa-v3.4.png)

Opacity uses accessible scalar properties. Video content without such a property and inaccessible, ambiguous, or blocked layers have limited support. Direct-surface plans are bounded. When nested overrides require splitting an existing CanvasGroup fade, native blending of overlapping translucent pixels still requires visual comparison in Roblox Studio. [Controlled fixture protocol](TESTING.md#controlled-studio-fixture)

## Direct tools and recovery

| Workflow | Headless evidence |
| --- | --- |
| Movable editor | Bundled toolbar grip movement and Reset Editor Layout. Independent device and orientation buckets, safe travel, optional docking, and cancellation are covered by mocks. |
| Rotate | Bundled exterior-handle gesture commits one action. Subsequent movement preserves the angle. Compatible group roots orbit their shared center and cancel as one transaction. |
| Opacity | Bundle fades a visible image on a transparent background. Appearance planning covers text, stroke, group compositing, exact descendants, and scope. An exact recreated child regains its fade while a newly added sibling retains its own original appearance. |
| Reset All | The bundle restores position, size, rotation, and a faded image together. Undo restores the edits. App and persistence tests cover Save, Discard, protected controls, scoped inheritance, and cold restore. |
| Quick Start and Help | Isolated practice, chapter navigation, resume across instances, skip, and completion. Tutorial gestures include panel dragging, selection, resizing, rotation, opacity, grouping, and resetting. |

## Master workflow coverage

| Workflow | Tested evidence |
| --- | --- |
| First open, edit, save, exit and reopen | Bundled startup, skip, Jump, drag, slider, pinch, Save readback, Done, reopen and cold restore. The onboarding suite also runs the complete isolated practice flow. |
| Transparent and overlapping layers | Bundled Select Through inspects the overlay, chooses it explicitly, applies Ignore and then selects Jump. Discovery fixtures cover hidden, clipped and decorative candidates. |
| Logical groups | Bundled Quick Group, movement of both members, naming, individual-member focus, ungrouping and checkpoint restoration. |
| Layout-managed controls | Bundled representative list member offers size and a movable container. Dragging the position is refused, changing size leaves raw Position untouched, and the container can move. Runtime tests exercise reflow, flex, grid, constraints, and rollback. |
| Touch, keyboard and orientation | Mocked ownership and cancellation, slider versus scroll, long-press versus drag, pinch handoff, keyboard fit and profile orientation pinning. |
| Persistence and recovery | Independent editor preferences and layout saves, interrupted writes, locked parent and sibling guards, lost targets, draft recovery, cold restore and Safe Mode. |
| PC | Mocked right-click selection, mouse input and keyboard behavior. Native dispatch in a Roblox client remains unverified. |

The Studio fixture provides representative list, flex and grid bars for a supported runtime check. The reported Heroes Battlegrounds behavior is consistent with layout ownership. Its live hierarchy and behavior remain unverified. [Fixture protocol](TESTING.md#controlled-studio-fixture)

## Existing touchscreen coverage

- The toolbar emphasizes Save while there are unsaved edits, or marks Tools when Save is inside Layout Actions. Quick Edit groups its touch stepper, indicates numeric focus, and shows which corner the resize handle controls. The invisible handle margin passes taps through to neighboring controls while remaining available for drag resizing.
- Typed notifications distinguish successful saves, memory-only saves, retries, and failed adjustments. Notifications stay within the safe area, avoid the selection and inspector when possible, and leave touch interaction available. Bundled tests verify that a confirmed Save remains visible immediately after Done and then expires.
- Fresh bundle execution covers opening the editor through the LocalScript and shared-environment paths, selecting Jump, dragging, slider resizing, pinching, Save readback, Undo, Done, reopening, and cold restore through `Source`. It also verifies the version notice, original-layout recovery, and teardown.
- Horizontal slider ownership pauses the inspector scroller and restores it on release or cancellation. Vertical swipes remain available for scrolling. Releasing an unchanged field makes no history entry. Fine steps move a tiny selection by a visible increment. Blank taps ignore passive, transparent structural zones, which remain in the explicit element list.
- Ordinary settled transforms can verify at the early 40 ms check. Delayed layout gets a bounded retry. An element recreated under the same identity during a drag stays out of that gesture. The selection overlay coalesces redundant redraw requests.
- Inspected source-derived mock geometry for the welcome surface and Quick Edit at landscape and portrait sizes. The previews show bounds and placement. They omit native fonts, clipping, device rendering and touch dispatch.

## Acceptance gates

| Gate | Status | Evidence and remaining validation |
| --- | --- | --- |
| A · Immediate usability | Not Tested | Headless layout calculations and baseline comparison below. Verify the complete jump workflow and visible gameplay in landscape. |
| B · Touch interaction | Not Tested | Mock gesture ownership, tap threshold, pinch, slider and cancellation. Verify real simultaneous touches, scroll inertia and editor dismissal. |
| C · Geometry and selection | Not Tested | Mock inset boundaries, ranking and guarded transforms. Compare actual touch point, outline and HUD geometry across all inset probes and orientations. |
| D · Responsive layout | Not Tested | Simulated viewport, safe-area and keyboard geometry. Render short landscape, portrait and tablet, and test moving and hiding the inspector. |
| E · Visual quality | Not Tested | Studio rendering and screenshots were unavailable. Inspect actual spacing, legibility, modal sizing, control glyphs and clipped states. |
| F · Persistence and recovery | Not Tested | Mock checkpoint, storage failure, profile layers, saved restoration and draft recovery. Verify Android persistence, startup restoration and Safe Mode independently. |
| G · Performance | Not Tested | Source audit and mocked scan, list rebuild and cleanup checks. Measure client responsiveness on the 240-element fixture and a physical Android device. |
| H · Evidence | Passed | All gates have an explicit status. The reproducible protocol below records Studio and device evidence independently. |

## Historical headless layout comparison

The baseline ran through the original mobile UI's layout mock. The rescue runs the pure responsive planner. Both use representative Roblox UI dimensions and a 24-unit top inset. The area figures compare the original panel with the rescue toolbar and selected Quick Edit inspector. The toolbar alone takes less space before selection.

| Landscape viewport | Baseline panel and scroll body | Baseline area | Rescue Quick Edit | Rescue area |
| --- | --- | ---: | --- | ---: |
| 1536 × 695 | 1520 × 364.7, body 132.7 high | 51.9% | 262 × 244 | 8.0% |
| 960 × 440 | 944 × 302, body 70 high | 67.5% | 262 × 244 | 20.1% |
| 640 × 360 | 624 × 234, body 70 high | 63.4% | 246 × 244 | 34.9% |
| 932 × 430 | 916 × 302, body 70 high | 69.0% | 262 × 244 | 21.2% |

The fixture loaded, toggled all four inset configurations, added and removed its 240-object collection, recreated its mock HUD, and released its owned screens and connections in Lua mocks. The Roblox geometry probe is available for Studio execution. [Controlled fixture protocol](TESTING.md#controlled-studio-fixture)

## Headless indexing comparison

The same headless Roblox mock indexed 240 sibling controls inside a shared parent. The measurements count hierarchy work and installed property watchers. Client frame time and device memory remain unmeasured.

| Startup measurement | Baseline | Rescue |
| --- | ---: | ---: |
| Descendant scans | 1 | 1 |
| `GetChildren()` calls | 1,685 | 243 |
| Entries returned by all `GetChildren()` calls | 173,763 | 242 |
| Mock `IsA()` checks | 348,974 | 5,781 |
| Owned property watchers | 964 | 726 |

A second mock applied 120 updates to one selected control during one gesture. Classification calls dropped from 2,160 to 1 and `GetChildren()` enumerations from 6,840 to 1. A four-control group produced 10,080 versus 4 classifications and 31,680 versus 4 child enumerations for the same update count. Both versions made zero full-tree scans and queued zero stabilization timers during the updates. The rescue keeps the gesture reference for successive writes and verifies geometry on completion.

## Compatibility

| Target | Visual editing | Built-in effective touch behavior | Local files and startup |
| --- | --- | --- | --- |
| Delta on Android | Not Tested | Not Tested | Not Tested |
| Arceus X on Android | Not Tested | Not Tested | Not Tested |
| Codex Roblox executor on Android | Not Tested | Not Tested | Not Tested |
| Authorized PC Roblox environment | Not Tested | Not Tested | Not Tested |
| Roblox Studio mock HUD | Not Tested | Unsupported by fixture design | Executor file APIs unsupported in an ordinary LocalScript. Manual JSON export is available. |
| Protected or inaccessible GUI | Unsupported | Unsupported | Profiles can retain the unresolved identity. |

The editor changes accessible GUI properties. Roblox movement implementations and game scripts with global input listeners can behave independently of those properties. File reads and writes, optional clipboard use, and startup depend on the actual environment. The runtime reports detected capabilities and observed failures.

## Android checks to run first

1. In landscape on a compact or notched phone, open from the docked launcher. Tap JumpButton, then drag it, resize with the slider, pinch and handle, enter a size, and tap Save and Done. Reopen and verify the saved geometry and its actual jump response at the old and new positions.
2. Scroll Elements, choose an overlapping control or explicit parent, then multi-select and move a group. Move or hide Quick Edit to reach controls below it. Test a third finger during pinch, interruption mid-drag, and rotation during a pending edit. Compare the selection outline and undo count after each operation.
3. Test save failure and unsupported file access, a saved restore after respawn or restart, draft recovery, and Safe Mode. Verify the jump and both joystick visual and effective regions independently. [Full device protocol](TESTING.md)
