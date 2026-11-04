# V2 audit and V3 decisions

Audited commit: `ccc42ba1f9707c1f73ba47cead4a1f6a97a7ff09` (`Update Source`). The baseline repository contained only `Source` (102 lines) and `README.md` (84 lines). There was no test runner, build definition, CI workflow, license file, or release artifact directory. Git history and the original Syshi attribution remain intact. V2 also credited Danechka as inspiration.

GitHub reports the repository as `zryr/Heavenly-Axis`; the checked-out remote already uses that name. No replacement repository was created and no history rewrite or administrative rename was performed by this change. The connected GitHub releases collection returned an empty array during the audit; there were no published releases to inspect. A connected lookup of the prior Jump-Button-Size-Position-Changer URL returned the same repository ID (`919802588`) and canonical Heavenly-Axis name, verifying that the old URL redirects to this repository.

| V2 evidence | Practical problem | V3 decision |
| --- | --- | --- |
| `initialize()` chains three seven-second `WaitForChild` calls to `TouchGui.TouchControlFrame.JumpButton` | Missing controls prevent the editor from appearing; delayed or recreated controls are never retried | Start without priority controls; discover accessible PlayerGui descendants and subscribe to lifecycle events |
| Jump dragging begins and continues with `GetMouseLocation()` for touch | Touch coordinates and identities are lost; another finger can move or terminate a gesture | Track InputObject identity and use its position; keep pointer/GUI coordinates consistent |
| Slider and drag end on any matching input type | A second touch can terminate the first touch's operation | Complete only the owning gesture; pinch uses two tracked touches |
| `InputChanged` and `InputEnded` handlers connect globally, but Close disconnects only the jump-button handler | Destroying the window leaves handlers and captured objects alive | Each runtime owner has explicit teardown; singleton prevents duplicate handlers |
| Initialization creates fresh GUI and baselines every execution | Re-execution can duplicate editors and treat edited values as originals | Reuse a live session; absolute saved properties and per-instance original baselines |
| Export code adds offsets to the values found at execution time | Running it twice compounds position/size changes | Apply serialized UDim values idempotently |
| Only a size-offset text box and slider; the textbox has feedback through property listeners | Values can become coupled to UI refresh; no independent dimensions, groups, history, or profile boundaries | Separate pure calculations, transactions, serialized state, and UI rendering |
| AkaliNotif downloads external Lua and runs it through `loadstring` | Optional notifications depend on remote code and network availability | Build all core modules into one release; use internal status/diagnostic UI |
| Save copies generated code or logs it; no persisted profile storage | A clipboard success does not prove persistent storage or startup execution | Capability-based storage, validated data export, explicit Save result, separate loader-only startup |
| Drag toggles `Active`/`Draggable` and restores fixed values | Original interaction properties are not preserved | Transform only supported properties; report incomplete gameplay isolation |
| No undo/checkpoint, profile validator, device matrix, or controlled fixture | There is no reproducible evidence for correctness or executor compatibility | Pure/mocked tests, deterministic build checks, Luau compilation, and explicit manual protocols |

## Architecture choice

V3 uses small Lua modules with a local, generated module loader. The development modules remain compatible with Lua 5.4 so configuration, geometry, matching, and transaction behavior can be tested outside Roblox. Roblox-facing modules use ordinary services and accessible PlayerGui objects; they do not access protected CoreGui, patch Roblox movement modules, or bypass security boundaries.

The maintained `Source` path is a generated compatibility alias of `dist/HeavenlyAxis.lua`. Existing consumers retain a single file, while maintainers edit `src/`. No V2 configuration migration is attempted; the version 3 format starts fresh.

## Scope and evidence

A headless Lua runtime can verify calculations and mocks. A Luau compiler can verify syntax and bytecode compilation. Neither establishes touch-control behavior in Roblox, actual Android usability, Roblox Studio rendering, local executor capability support, or compatibility with Delta, Arceus X, Codex (Roblox), or any PC executor. Those require the manual protocol in [TESTING.md](TESTING.md).

The Nexus reference screenshot mentioned in the task was not present in the supplied repository or attachment. The interface follows the requested dark/cyan design direction without claiming fidelity to that unavailable image.
