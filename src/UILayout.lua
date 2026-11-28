local Layout = {}

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(value, maximum))
end

function Layout.place(rect, area, x, y)
    local w, h = math.min(rect.w, area.w), math.min(rect.h, area.h)
    return {
        x = clamp(x, area.x, area.x + area.w - w),
        y = clamp(y, area.y, area.y + area.h - h),
        w = w,
        h = h,
    }
end

function Layout.intersects(first, second)
    return first and second and first.x < second.x + second.w and second.x < first.x + first.w
        and first.y < second.y + second.h and second.y < first.y + first.h
end

function Layout.fromPlacement(rect, area, placement)
    if not placement then return rect end
    local dx, dy = math.max(0, area.w - rect.w), math.max(0, area.h - rect.h)
    local x, y = area.x + (placement.x or 0) * dx, area.y + (placement.y or 0) * dy
    if placement.dock == "left" then x = area.x
    elseif placement.dock == "right" then x = area.x + dx
    elseif placement.dock == "top" then y = area.y
    elseif placement.dock == "bottom" then y = area.y + dy end
    return Layout.place(rect, area, x, y)
end

function Layout.toPlacement(rect, area, docking)
    local dx, dy = math.max(0, area.w - rect.w), math.max(0, area.h - rect.h)
    local x, y = clamp((rect.x - area.x) / math.max(1, dx), 0, 1), clamp((rect.y - area.y) / math.max(1, dy), 0, 1)
    local edge, distance
    if docking then
        for _, entry in ipairs({{"left", rect.x - area.x}, {"right", area.x + area.w - rect.x - rect.w},
            {"top", rect.y - area.y}, {"bottom", area.y + area.h - rect.y - rect.h}}) do
            if entry[2] <= 20 and (not distance or entry[2] < distance) then edge, distance = entry[1], entry[2] end
        end
    end
    return {x = x, y = y, dock = edge}
end

function Layout.avoid(rect, area, obstacle)
    if not Layout.intersects(rect, obstacle) then return rect end
    local best, distance
    for _, origin in ipairs({{rect.x, obstacle.y + obstacle.h + 7}, {rect.x, obstacle.y - rect.h - 7},
        {obstacle.x + obstacle.w + 7, rect.y}, {obstacle.x - rect.w - 7, rect.y}}) do
        local candidate = Layout.place(rect, area, origin[1], origin[2])
        local cost = (candidate.x - rect.x) ^ 2 + (candidate.y - rect.y) ^ 2
        if not Layout.intersects(candidate, obstacle) and (not distance or cost < distance) then best, distance = candidate, cost end
    end
    return best or rect
end

function Layout.plan(safe, touch, keyboardHeight)
    local margin, gap = 8, 8
    local w = math.max(1, safe.w - margin * 2)
    local h = math.max(1, safe.h - margin * 2 - math.max(0, keyboardHeight or 0))
    local area = {x = safe.x + margin, y = safe.y + margin, w = w, h = h}
    local portrait = safe.w < safe.h
    local keyboard = (keyboardHeight or 0) > 0
    local compactLandscape = touch and not portrait and safe.w < 700
    local toolbarW = math.min(w, w < 400 and 372 or 414)
    local toolbar = {x = area.x, y = area.y, w = toolbarW, h = math.min(48, h)}
    local occupied = keyboard and 0 or toolbar.h + gap
    local content = {x = area.x, y = area.y + occupied, w = w, h = math.max(1, h - occupied)}
    local panelW = math.min(portrait and 350 or (touch and (compactLandscape and 246 or 262) or 286), content.w)
    local panelH = math.min(244, content.h)
    local panel = {x = content.x, y = content.y, w = panelW, h = panelH}
    if portrait and not keyboard then
        panel.x = content.x + math.floor((content.w - panel.w) / 2)
        panel.y = content.y + content.h - panel.h
    elseif not touch and not keyboard then
        panel.x = content.x + content.w - panel.w
    end
    local workspaceW = math.min(content.w, portrait and 430 or 408)
    local workspaceH = math.min(content.h, portrait and 560 or 536)
    local workspace = {x = panel.x, y = content.y, w = workspaceW, h = workspaceH}
    if portrait then
        workspace.x = content.x + math.floor((content.w - workspace.w) / 2)
        workspace.y = content.y + content.h - workspace.h
    elseif not touch then
        workspace.x = content.x + content.w - workspace.w
    end
    return {area = area, content = content, toolbar = toolbar, panel = panel, workspace = workspace,
        portrait = portrait, toolbarVisible = not keyboard, brandVisible = toolbar.w >= 390}
end

function Layout.panelForSelection(plan, bounds, manual)
    local panel, area = plan.panel, plan.content
    if manual then return Layout.place(panel, area, manual.x, manual.y) end
    if not Layout.intersects(panel, bounds) then return panel end
    local oppositeX = panel.x > area.x + 1 and area.x or area.x + area.w - panel.w
    local oppositeY = panel.y > area.y + 1 and area.y or area.y + area.h - panel.h
    local alternatives = plan.portrait and {{panel.x, oppositeY}, {oppositeX, panel.y}}
        or {{oppositeX, panel.y}, {panel.x, oppositeY}}
    for _, origin in ipairs(alternatives) do
        local candidate = Layout.place(panel, area, origin[1], origin[2])
        if not Layout.intersects(candidate, bounds) then return candidate end
    end
    return panel
end

return Layout
