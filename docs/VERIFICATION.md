# V3 implementation and verification report

Report date: **2026-11-04 (America/Chicago)**. Device/Studio execution was not available in this implementation environment. The statuses below distinguish implementation and automated evidence from actual Roblox runtime verification.

## Available checks

The following commands were executed against the assembled implementation:

| Command | Actual result |
| --- | --- |
| `python3 -m pip install -r requirements-dev.txt` | Passed — Lupa 2.6 development runtime installed |
| `python3 tools/build.py` | Passed — generated 202,498-byte `dist/HeavenlyAxis.lua` and byte-identical `Source` |
| `python3 tools/build.py --check` | Passed — committed-output comparison against deterministic generation |
| `python3 tools/test.py` | Passed — 7 suites, 450 reported checks, 17 Lua syntax checks, 0 failures |
| `python3 tools/luau_check.py` | Passed — Luau 0.728 compiled 24 files |

Final suite counts: app 53, core 54, input 21, persistence 90, release 4, runtime 176, UI 52. `git diff --check` also Passed. Tests are pure/mocked. They do not constitute a Roblox client, Studio rendering run, executor test, or physical-device test.

Automated coverage includes schema/import limits and malformed values, scope precedence, screen geometry, group scaling/alignment/distribution, nested root selection, identity ambiguity, bounded history/checkpoints, preview/cancel data integrity, local storage success/failure/backup/corruption behavior, draft separation, touch/mouse gesture ownership, idempotent transforms, unsupported targets, rollback, and runtime cleanup using mocks.

## Acceptance mapping

“Implemented” describes code present in this PR. The status column describes available verification of the full user-facing criterion. Use the detailed protocol in [TESTING.md](TESTING.md) to promote runtime rows only after collecting evidence.

| # | Acceptance criterion | Implementation and evidence | Full runtime status |
| --- | --- | --- | --- |
| 1 | Direct/list compatible GUI selection | PlayerGui discovery, searchable hierarchy, hit selection, editor exclusion; matching/discovery mocks | Not Tested |
| 2 | Intended touch/mouse movement | InputObject ownership, screen-space property adapter; pure/mocked movement cases | Not Tested |
| 3 | Synchronized handles/pinch/slider/steps/numerics | Shared rectangle transforms and inspector refresh; gesture session tests | Not Tested |
| 4 | Grid/guides with snapping off by default | Grid/guides overlays; pure snap calculations/default preference | Not Tested |
| 5 | Temporary/named groups and alignment/distribution | Group membership and UI; geometry/group tests | Not Tested |
| 6 | Avoid nested double transforms | Ancestor-root pruning; nested-selection and transform mocks | Not Tested in Roblox; automated cases Passed |
| 7 | Honest jump/joystick editing | Priority built-in identities, visual adapter, explicit functional-region caveats | Not Tested; universal functional adaptation Unsupported |
| 8 | Completed-action undo/redo across saves | Bounded before/after transactions and persistent checkpoint comparison; history/gesture tests | Not Tested in Roblox; automated cases Passed |
| 9 | Save/Cancel/preview/profile consistency | Separate candidate previews and checkpoint state; profile/storage/history tests | Not Tested in Roblox; automated cases Passed |
| 10 | Saved restoration after GUI recreation | Event discovery plus exact identity and absolute UDim application; mocked recreation/idempotence | Not Tested in Roblox; automated cases Passed |
| 11 | Repeated execution does not duplicate/compound | Singleton reservation/reuse, lifecycle teardown, absolute restore; source/mocked checks | Not Tested in Roblox |
| 12 | Missing/unsupported targets do not crash editor | Per-target compatibility/skips; runtime invalid/missing object tests | Not Tested in Roblox; automated cases Passed |
| 13 | Honest storage/export/import results | Capability states, write/readback, validation and export fallback; storage failure tests | Not Tested on physical executor; automated cases Passed |
| 14 | Small Android usability | Responsive bottom sheet, scrolling/collapse, touch-sized controls | Not Tested |
| 15 | PC keyboard/mouse support | Shortcuts, focus guards, box/multi selection and mouse handles; input mocks | Not Tested |
| 16 | Orientation/device/adaptive behavior | Scoped overrides, viewport events and preserved native UDim scale/offset semantics | Not Tested; no automatic proportional offset conversion |
| 17 | Recoverable Safe Mode preserves saves | Suspension, original-baseline restore, public recovery API and separate delete | Not Tested in Roblox |
| 18 | Opt-in reversible experimental adjustments | Explicit per-element approval, bounded stabilization/suspension, Safe Mode block | Not Tested in Roblox; mocks cover bounded/error paths |
| 19 | Honest diagnostics/capabilities | Bounded log, unsupported reasons, failed/unverified state messages | Not Tested visually; storage/capability mocks Passed |
| 20 | Reproducible build and automated checks | Deterministic bundler, checked-in releases, CI and Lua/Luau checks | Passed for executed commands above |

No physical Android/PC acceptance criterion is marked Passed solely because code compiled. No real built-in jump/classic/dynamic joystick touch region has been verified.

## Compatibility matrix

| Target | Visual editing | Functional jump/joystick region | Persistent profiles | Automatic startup |
| --- | --- | --- | --- | --- |
| Delta, Android | Not Tested | Not Tested | Not Tested | Not Tested |
| Arceus X, Android | Not Tested | Not Tested | Not Tested | Not Tested |
| Codex (Roblox), Android | Not Tested | Not Tested | Not Tested | Not Tested |
| Other Android environment | Not Tested | Not Tested | Not Tested | Not Tested |
| PC executor | Not Tested | Not Tested | Not Tested | Not Tested |
| Studio mock HUD | Not Tested visually | Unsupported — mocks do not implement Roblox movement | Unsupported for executor file APIs; in-memory/export path provided | Not Tested as LocalScript startup |
| Protected/inaccessible GUI | Unsupported | Unsupported | Configuration may remain unmatched | Unsupported |

## Known limitations and manual work

- Actual Android touch precision, multi-touch ownership, inset/safe-area behavior, small-screen usability, launcher docking, and orientation transitions require device testing.
- Built-in jump and both joystick variants require independent visual and effective-region tests. Dynamic Roblox controls may reposition or be recreated by Roblox. The editor does not patch their internal movement implementation.
- Game scripts using global input listeners may still observe editing touches. The UI warns that complete gameplay isolation is unverified.
- Matching is intentionally strict. Renamed/reparented/ambiguous targets remain unmatched until explicit remapping. Invisible elements are not exposed as direct editable hits.
- Layout-managed, constrained, automatic-size, rotated-ancestor, or unusual scaled structures may be experimental or unsupported. Approved changes can still be rejected; repeated unstable targets are suspended rather than continuously enforced.
- Pixel offsets remain pixels on different screens; native UDim scale components adapt. Use scoped profiles for different orientation/device layouts. No inferred fixed-resolution proportional remapping is claimed.
- File storage and autoexecution are environment capabilities. Missing file APIs use memory/export; autoexecute setup is manual and must be verified after restart.
- Portable executor file APIs do not guarantee atomic replacement. Staging, backups, readback, preserved corrupt files, and export mitigate failures without claiming crash-proof disk writes.
- There was no Nexus screenshot in the supplied assets, so visual fidelity to that reference was not assessed.
- The original repository had no license. Attribution/history were retained; no licensing grant was fabricated.

## Remaining device checks

Run every common protocol row in [TESTING.md](TESTING.md), then complete each environment's matrix independently. Prioritize one-finger drag, two/three-finger identity, pinch and slider history, actual jump/joystick response after resizing, profile preview Cancel fidelity, respawn/GUI recreation, duplicate execution, corrupt storage handling, Safe Mode, and portrait/landscape transitions. Record environment/version, device/OS, game/place, viewport, capability results, expected/actual behavior, and visual evidence.

## Rebranding and delivery

The connected GitHub repository already reports **`zryr/Heavenly-Axis`** with the original commit history. Looking up the old repository URL returned the same repository ID (`919802588`) and canonical name, verifying the redirect. No repository replacement, deletion, or history rewrite was made. The maintained source/UI/docs/releases use Heavenly Axis and preserve the Syshi/Danechka attribution. One comprehensive implementation branch/PR contains the rewrite; no merge is authorized by this task.
