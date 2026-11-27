# V3 mobile rescue verification

Studio rendering and physical Android testing were unavailable in the Debian Linux workspace. All runtime gates that depend on those environments remain open. This report distinguishes source inspection, pure/mock execution, a Studio renderer, and physical touch measurements. [Roblox Studio system requirements](https://create.roblox.com/docs/studio/setup)

## Executed checks

| Command | Result |
| --- | --- |
| `python3 tools/build.py` and `python3 tools/build.py --check` | Passed. Both tracked release paths reproduce the same 301,812 bytes. |
| `work/test-venv/bin/python tools/test.py` | Passed. Eight suites, 693 checks, 19 Lua syntax checks, zero failures. |
| `python3 tools/luau_check.py` | Passed. Pinned Luau 0.728 compiled 27 files. |
| `git diff --check` and `cmp dist/HeavenlyAxis.lua Source` | Passed. |

The test suites cover App orchestration (79), core geometry and history (57), discovery (33), input (46), persistence (116), bundle startup (4), transform and runtime adapters (253), and UI layout and interactions (105). The UI suite instantiates the production UI and input controller in a Lua fixture and exercises the touch editing loop. The viewport cases include 1536 × 695, 960 × 440, 640 × 360, 932 × 430, 393 × 852, 360 × 640, 1024 × 768 and 1920 × 1080, plus safe-area and keyboard variations.

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

## Headless layout comparison

The baseline ran through the original mobile UI's layout mock. The rescue runs the pure responsive planner. Both use representative Roblox UI dimensions and a 24-unit top inset. The area figures compare the original panel with the rescue toolbar and selected Quick Edit inspector. The toolbar alone takes less space before selection.

| Landscape viewport | Baseline panel and scroll body | Baseline area | Rescue Quick Edit | Rescue area |
| --- | --- | ---: | --- | ---: |
| 1536 × 695 | 1520 × 364.7, body 132.7 high | 51.9% | 262 × 202 | 6.9% |
| 960 × 440 | 944 × 302, body 70 high | 67.5% | 262 × 202 | 17.5% |
| 640 × 360 | 624 × 234, body 70 high | 63.4% | 262 × 202 | 32.1% |
| 932 × 430 | 916 × 302, body 70 high | 69.0% | 262 × 202 | 18.5% |

The fixture loaded, toggled all four inset configurations, added and removed its 240-object collection, recreated its mock HUD, and released its owned screens and connections in Lua mocks. The Roblox geometry probe is available for Studio execution. [Controlled fixture protocol](TESTING.md#controlled-studio-fixture)

## Headless indexing comparison

The same headless Roblox mock indexed 240 sibling controls inside a shared parent. The measurements count hierarchy work and installed property watchers. Client frame time and device memory remain unmeasured.

| Startup measurement | Baseline | Rescue |
| --- | ---: | ---: |
| Descendant scans | 1 | 1 |
| `GetChildren()` calls | 1,685 | 243 |
| Entries returned by all `GetChildren()` calls | 173,763 | 242 |
| Mock `IsA()` checks | 348,974 | 6,023 |
| Owned property watchers | 964 | 726 |

A second mock applied 120 updates to one selected control during one gesture. Classification calls dropped from 2,160 to 1 and `GetChildren()` enumerations from 6,840 to 1. Both versions made zero full-tree scans and queued zero stabilization timers during those updates. The rescue keeps the gesture reference for successive writes and verifies geometry on completion.

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
