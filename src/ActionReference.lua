-- Shared plain-language action descriptions for Help and the guided tour.
local Reference = {}

local draft = "Changes the current edit. Save to keep it."
local editor = "Changes only Heavenly Axis."
local selection = "Changes editor selection only."
local files = "Uses the current saved checkpoint."
local session = "Changes the session. Save to keep the change."
local icons = {
    launcher = "move", toolbar = "grip", quickEdit = "sliders-horizontal", tools = "wrench", canvas = "panel-top-close",
    dragPanel = "grip", collapse = "chevron-left", help = "circle-help", select = "mouse-pointer-2", layers = "layers",
    selectThrough = "eye", selectionScope = "layers", wholeControl = "mouse-pointer-2", individualLayer = "layers",
    entireContainer = "group", ignore = "eye-off", move = "move", size = "scaling", rotate = "rotate-cw", opacity = "droplet",
    groups = "group", quickGroup = "group", save = "save", done = "check", undo = "undo", redo = "redo",
    resetElement = "rotate-ccw", resetAll = "rotate-ccw", compatibility = "info", diagnostics = "info",
}
local function action(id, label, how, effect, note)
    return {id = id, label = label, how = how, effect = effect, note = note, icon = icons[id]}
end

Reference.sections = {
    {title = "Editor and panels", icon = "grip", items = {
        action("launcher", "Axis launcher", "Tap the docked Axis mark to reopen the editor. Drag it along an edge to move it.", editor, "Settings includes Recover launcher if you hid it."),
        action("toolbar", "Main toolbar", "Open Layers or Tools, toggle Multi, work through history, or finish editing.", editor, "On compact screens, History holds Undo and Redo. On the narrowest screens, use Tools → Actions → Save layout."),
        action("quickEdit", "Quick Edit", "Select a visible control to open the compact adjustment panel.", editor, "The panel can move away from the selected control."),
        action("tools", "Tools", "Open the last workspace you used. Switch between Edit tools, Groups, Profiles, Settings, and Help in its navigation.", editor),
        action("canvas", "Canvas", "Return to your selected control and editing tools.", editor),
        action("dragPanel", "Move an editor panel", "Grab the panel by its header or grip and drag it away from a control.", editor, "The editor clamps panels inside the safe screen area."),
        action("collapse", "Hide or show Quick Edit", "Tap Hide to make more room for the canvas. Tap Show Quick Edit when you need the tools again.", editor, "The selection stays active."),
        action("dock", "Dock a panel", "Bring its dedicated grip near a screen edge to place the panel there.", editor),
        action("resetEditor", "Reset Editor Layout", "Restore the default toolbar, Quick Edit, and Tools positions in Settings.", editor, "Preserves game controls and saved HUD profiles."),
        action("help", "Help", "Open Help and choose Quick Start, Guided Tour, or the action reference.", editor),
    }},
    {title = "Selection and Layers", icon = "layers", items = {
        action("select", "Select a control", "Tap a control on the canvas. The outline shows what will move or resize.", selection),
        action("selectionScope", "Change selection scope", "Use the scope button in Quick Edit to choose Whole control, Individual layer, or Entire container.", selection,
            "If something overlaps, open Select Through and choose from Controls, Containers, or Individual layers."),
        action("wholeControl", "Whole control", "Choose Whole control to select an ability as one button. Its outline includes the badge, icon, and label.", selection,
            "Move the whole button to keep its visual layers together, when its layout permits movement."),
        action("individualLayer", "Individual layer", "Choose Individual layer, then tap the badge, icon, or label you want. You can also pick it from Layers or Select Through.", selection,
            "The smaller outline marks the only visual layer your edit will target."),
        action("entireContainer", "Entire container", "Choose Entire container to target an ability bar or parent. For a layout-managed button, use Select entire bar or Select container when offered.", selection,
            "Moving a supported container keeps its controls in their assigned positions inside it."),
        action("clearSelection", "Clear selection", "Tap empty canvas or choose Clear selection in Layer actions. On PC you can press Escape.", selection),
        action("layers", "Layers", "Use search to find a control or open a parent's children. Return to Canvas when ready.", selection, "Layers can locate editable controls that are difficult to tap, including fully faded controls."),
        action("smartSelection", "Smart Selection", "Keep Smart Selection on to prefer visible, useful controls when several overlap.", editor),
        action("selectThrough", "Select Through", "Hold still on the canvas, right-click on PC, or arm Select Through and tap a point. Pick the control from the list.", selection, "Moving your finger starts the intended drag instead of opening the picker."),
        action("parent", "Parent and children", "Open Layer actions and choose Select parent or Choose children.", selection, "Moving a container can affect its children."),
        action("ignore", "Ignore in editor", "Choose Ignore on a Layer to exclude it from ordinary editor selection. Use the ignored filter to restore it.", editor, "Game visibility and taps stay unchanged."),
        action("lock", "Lock editing", "Lock a Layer to keep it inspectable while preventing changes. Unlock it to edit again.", editor, "Game visibility and taps stay unchanged."),
        action("boxSelect", "Box Select", "Choose Box Select, then drag around several controls on the canvas.", selection),
    }},
    {title = "Direct edit", icon = "move", items = {
        action("move", "Move", "Drag a selected control, or use arrow steps and the position fields under Edit tools.", draft, "Optional snapping and guides can help align it."),
        action("size", "Size", "Start with two fingers on or near the selection. Spread to grow, bring them together to shrink, and lift either finger to finish. You can also drag a handle, move the Size slider, or enter a value.", draft, "The percentage is relative to the original or selected starting size shown beside it."),
        action("aspect", "Aspect lock", "Keep it on to preserve proportions; turn it off for independent width and height.", editor),
        action("fine", "Fine adjustments", "Use the nearby minus and plus controls for small changes. On PC use the arrow keys for movement.", draft),
        action("rotate", "Rotate", "Drag the rotation handle, move the angle slider, or use the angle steps beside it.", draft, "Rotation turns around the control's center. Some groups and parent layouts cannot rotate together."),
        action("resetRotation", "Reset rotation", "Use Reset angle in Rotate to restore the selected control's original angle.", draft),
        action("opacity", "Opacity", "Move the Opacity slider from 0% to 100% to fade supported visuals relative to their original appearance.", draft, "100% restores original opacity. At 0%, find the control in Layers or Select Through. It may still respond to gameplay input."),
        action("opacityElement", "Element opacity", "Choose Element only to fade supported visual properties on the selection itself.", draft),
        action("opacityContents", "Contents opacity", "Choose Include contents to fade supported visuals within the selected container.", draft, "Original differences between the image, text, and backgrounds stay intact. Unsupported visuals are explained inline."),
        action("grid", "Grid and alignment guides", "Use the grid and guides as position references while editing.", editor, "Guides do not move controls unless snapping is enabled."),
        action("snap", "Snapping", "Enable snapping in Settings to align to the grid or nearby guides during movement.", editor),
        action("compatibility", "Why a tool is unavailable", "Read the explanation beside the disabled action. Open its containing bar or advanced details for supported alternatives.", editor, "Managed layouts and other constraints can control position or size even when a visual change remains available."),
    }},
    {title = "Groups", icon = "group", items = {
        action("groups", "Groups", "Open Groups to return to a named set of controls or manage its members.", selection),
        action("multi", "Multi-select", "Turn on Multi and tap controls to add or remove them from the selection.", selection),
        action("siblings", "Select siblings", "Select a control and use Select Siblings to select other compatible children of the same container.", selection),
        action("quickGroup", "Quick Group", "Turn on Multi, select two or more controls, then choose Quick Group in Groups.", draft,
            "A group can include unrelated controls, such as Jump and an ability. It moves them together without changing the game's hierarchy."),
        action("groupName", "Name or update a group", "Use Groups to name the selection, rename a saved group, or add and remove members.", draft),
        action("groupScale", "Scale a group", "Select the group and resize its combined outline to scale the whole arrangement.", draft),
        action("equalSize", "Apply the same size change", "Choose Adjust each member's size to apply the same size change to each editable member while keeping the arrangement in place.", draft),
        action("editMember", "Edit within a group", "Choose an individual member from Groups or Layers to edit it separately.", selection),
        action("align", "Align and distribute", "Use Alignment and spacing in Groups to organize two or more selected controls.", draft, "Distribution requires at least three supported targets."),
        action("ungroup", "Ungroup", "Remove the grouping from Groups when you no longer want to edit its members together.", draft, "The original controls remain in the game."),
    }},
    {title = "Save, profiles and recovery", icon = "save", items = {
        action("save", "Save", "Check the edited layout, then tap Save to establish a checkpoint.", "Writes locally only where storage is available.", "Memory-only sessions can export the checkpoint to JSON. Saving does not enable automatic startup."),
        action("done", "Done", "Tap Done to return to gameplay. If edits are waiting, choose Save, Discard, or Continue editing.", "Stores changes only if you choose Save."),
        action("undo", "Undo", "Tap Undo, or choose Undo last change in History, to step back one completed edit.", draft),
        action("redo", "Redo", "Tap Redo, or choose Redo last change in History, to reapply the edit you just undid.", draft),
        action("cancel", "Discard changes", "Tap Done, then choose Discard to return to the last checkpoint and leave editing.", "Restores the session checkpoint."),
        action("resetElement", "Reset Element", "Select a control and choose Reset in Quick Edit's Move or Size tool to restore its original supported properties.", draft),
        action("resetAll", "Reset All Changes", "Choose Tools → Actions → Reset All Changes. Review its scope and confirm.", draft, "Clears the selection and keeps saved profiles. Undo brings back the preceding edits with the canvas still clear."),
        action("profiles", "Profiles", "Create, preview, apply, rename, duplicate, or delete named layouts in Profiles.", session, "More-specific profiles can override broader ones. Deletion is a separate confirmed action."),
        action("profilePreview", "Preview a profile", "Preview a profile, then choose Apply to use it or Cancel to return.", session),
        action("transfer", "Import or export JSON", "Save before exporting current edits. Import validated JSON as a preview, then Apply if it is the intended layout.", files),
        action("recover", "Recover a control", "Select an offscreen, missed, or fully faded target in Layers, then use Recover or Reset Element as appropriate.", draft),
        action("safeMode", "Safe Mode", "Use Safe Mode in Settings to restore available original properties and suspend saved overrides.", "Preserves saved profiles."),
        action("draft", "Recover an unsaved draft", "Open a matching recovery draft as a preview. Apply it to work on it or Cancel without changing the checkpoint.", session),
        action("remap", "Remap a missing control", "Choose an unmatched saved entry, then select a compatible replacement and confirm Remap.", draft),
        action("settings", "Settings", "Adjust grid, snapping, launcher, shortcuts, and other editor options.", editor),
        action("diagnostics", "Diagnostics", "Open Diagnostics to see storage results, compatibility and observed problems.", editor),
        action("startup", "Automatic startup", "Follow the separate startup instructions for your supported environment and verify after reopening Roblox.", "Keeps existing saved profiles."),
    }},
}

local byId = {}
for _, section in ipairs(Reference.sections) do
    for _, item in ipairs(section.items) do byId[item.id] = item end
end

function Reference.get(id)
    return byId[id]
end

function Reference.search(query)
    local text = (type(query) == "string" and query or ""):lower():match("^%s*(.-)%s*$")
    if text == "" then return Reference.sections end
    local results = {}
    for _, section in ipairs(Reference.sections) do
        local items = {}
        for _, item in ipairs(section.items) do
            local searchable = string.lower(table.concat({item.id, item.label, item.how, item.effect, item.note or "", section.title}, " "))
            if searchable:find(text, 1, true) then items[#items + 1] = item end
        end
        if #items > 0 then results[#results + 1] = {title = section.title, icon = section.icon, items = items} end
    end
    return results
end

return Reference
