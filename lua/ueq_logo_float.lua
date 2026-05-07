--- Floating minimize/show control — same behavior as MAUI’s logo float.
--- Default image: `maui/ultimate-eq-photo.png`. Optional per-tool override: `drawFloating { imageRelPath = 'port/ueq-port.png' }`.
local mq = require('mq')
local ImGui = require('ImGui')

local M = {}

local shared = {
    logoTex = nil,
    logoFailed = false,
    relPath = 'maui/ultimate-eq-photo.png',
    defaultSize = 88,
}

--- [relative path under mq.luaDir] = texture userdata, or `false` if load failed (don’t retry forever)
local texByRel = {}

--- Some MQ ImGui builds mis-handle ImGuiCond for SetNextWindowPos; re-applying every frame breaks drag.
--- We only set the corner position once per float id per Lua state.
local didSetFloatCorner = {}

local ImGuiCond = _G.ImGuiCond
local W = _G.ImGuiWindowFlags or ImGuiWindowFlags

local function windowFlagsFloat()
    --- Sum hex flags (same as bit32.bor); avoids dependency on bit32.
    if W then
        return (W.NoTitleBar or 1)
            + (W.NoResize or 2)
            + (W.NoScrollbar or 8)
            + (W.AlwaysAutoResize or 0x40)
            + (W.NoBackground or 0x80)
            + (W.NoFocusOnAppearing or 0x1000)
            + (W.NoSavedSettings or 0x100)
    end
    return 1 + 2 + 8 + 0x40 + 0x80 + 0x1000 + 0x100
end

local function normalizePath(p)
    return tostring(p or ''):gsub('\\', '/')
end

local function fileExists(path)
    local f = io.open(path, 'rb')
    if f then
        f:close()
        return true
    end
    return false
end

function M.ensureLogoTexture()
    if shared.logoTex or shared.logoFailed then
        return
    end
    if not mq.CreateTexture then
        shared.logoFailed = true
        return
    end
    local path = normalizePath(mq.luaDir) .. '/' .. shared.relPath
    if not fileExists(path) then
        shared.logoFailed = true
        return
    end
    local ok, tex = pcall(mq.CreateTexture, path)
    if ok and tex and type(tex.GetTextureID) == 'function' then
        shared.logoTex = tex
    else
        shared.logoFailed = true
    end
end

--- @param imageRelPath string|nil  relative to MacroQuest `lua` folder, e.g. `port/ueq-port.png`; nil = default MAUI art
local function getLogoTexture(imageRelPath)
    local rel = normalizePath(tostring(imageRelPath or '')):gsub('^/+', '')
    if rel == '' then
        M.ensureLogoTexture()
        return shared.logoTex
    end
    local cached = texByRel[rel]
    if cached ~= nil then
        return cached ~= false and cached or nil
    end
    if not mq.CreateTexture then
        texByRel[rel] = false
        return nil
    end
    local path = normalizePath(mq.luaDir) .. '/' .. rel
    if not fileExists(path) then
        texByRel[rel] = false
        return nil
    end
    local ok, tex = pcall(mq.CreateTexture, path)
    if ok and tex and type(tex.GetTextureID) == 'function' then
        texByRel[rel] = tex
        return tex
    end
    texByRel[rel] = false
    return nil
end

local function drawLogoButton(idSuffix, sizePx, tooltip, fallbackLabel, imageRelPath)
    local maxPx = sizePx or shared.defaultSize
    local fb = tostring(fallbackLabel or '…'):gsub('##', '')
    if #fb > 6 then
        fb = fb:sub(1, 6)
    end
    if fb == '' then
        fb = 'UE'
    end
    local clicked = false
    local t = getLogoTexture(imageRelPath)
    if t then
        local tw, th = maxPx, maxPx
        if t.size then
            local s = t.size
            local w0 = tonumber(s.x or s.X or (type(s) == 'table' and s[1])) or 0
            local h0 = tonumber(s.y or s.Y or (type(s) == 'table' and s[2])) or 0
            if w0 > 0 and h0 > 0 then
                local sc = math.min(maxPx / w0, maxPx / h0)
                tw, th = w0 * sc, h0 * sc
            end
        end
        ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 0, 0)
        ImGui.Image(t:GetTextureID(), ImVec2(tw, th), ImVec2(0, 0), ImVec2(1, 1))
        ImGui.PopStyleVar()
        clicked = ImGui.IsItemClicked(0)
    else
        -- No texture: avoid default ImGui “blue” button; still clearly tappable.
        ImGui.PushStyleColor(ImGuiCol.Button,         0.12, 0.12, 0.14, 0.95)
        ImGui.PushStyleColor(ImGuiCol.ButtonHovered,  0.20, 0.22, 0.28, 1.0)
        ImGui.PushStyleColor(ImGuiCol.ButtonActive,   0.28, 0.32, 0.40, 1.0)
        ImGui.PushStyleColor(ImGuiCol.Text,           0.92, 0.92, 0.95, 1.0)
        clicked = ImGui.Button(fb .. '##ueqLogoFb' .. tostring(idSuffix), maxPx, maxPx)
        ImGui.PopStyleColor(4)
    end
    if tooltip and tooltip ~= '' and ImGui.IsItemHovered() then
        ImGui.SetTooltip(tooltip)
    end
    return clicked
end

--- Thin strip above the logo: drag here to move (borderless windows don’t drag from the image reliably).
local function drawFloatingDragStrip(id, stripW, stripH)
    stripH = tonumber(stripH) or 10
    if stripH <= 0 then
        return
    end
    local w = tonumber(stripW) or 88
    ImGui.InvisibleButton('##ueqdrag_' .. tostring(id), w, stripH)
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('Drag here to move')
    end
    if ImGui.IsItemActive() and ImGui.IsMouseDragging(0) then
        pcall(function()
            local dd = ImGui.GetMouseDragDelta(0)
            local dx, dy = 0, 0
            if type(dd) == 'table' then
                dx = tonumber(dd.x or dd[1]) or 0
                dy = tonumber(dd.y or dd[2]) or 0
            else
                dx = tonumber(dd) or 0
                dy = tonumber(select(2, ImGui.GetMouseDragDelta(0))) or 0
            end
            if dx == 0 and dy == 0 and ImGui.GetMouseDragDelta then
                local a, b = ImGui.GetMouseDragDelta()
                if type(a) == 'table' then
                    dx = tonumber(a.x or a[1]) or 0
                    dy = tonumber(a.y or a[2]) or 0
                else
                    dx, dy = tonumber(a) or 0, tonumber(b) or 0
                end
            end
            local wx, wy = ImGui.GetWindowPos()
            if type(wx) == 'table' then
                wx = tonumber(wx.x or wx[1]) or 0
                wy = tonumber(wx.y or wx[2]) or 0
            else
                wx = tonumber(wx) or 0
                wy = tonumber(wy) or 0
            end
            local condA = (ImGuiCond and ImGuiCond.Always) or 1
            ImGui.SetWindowPos(wx + dx, wy + dy, condA)
            ImGui.ResetMouseDragDelta(0)
        end)
    end
end

local function setNextWindowCorner(opts)
    local corner = tostring(opts.placement or 'top_right'):lower():gsub('-', '_')
    local pad = tonumber(opts.edgePad) or 12
    local offX = tonumber(opts.offsetX) or 0
    local offY = tonumber(opts.offsetY) or 0

    local io = ImGui.GetIO and ImGui.GetIO() or nil
    local dw, dh = 1920, 1080
    if io and io.DisplaySize then
        local ds = io.DisplaySize
        dw = tonumber(ds.x or ds[1] or dw) or dw
        dh = tonumber(ds.y or ds[2] or dh) or dh
    end
    if dw < 160 then
        dw = 1920
    end
    if dh < 120 then
        dh = 1080
    end

    local cond = (ImGuiCond and ImGuiCond.FirstUseEver) or 4

    local x, y, px, py
    if corner == 'top_left' then
        x, y, px, py = pad + offX, pad + offY, 0, 0
    elseif corner == 'bottom_left' then
        x, y, px, py = pad + offX, dh - pad + offY, 0, 1
    elseif corner == 'bottom_right' then
        x, y, px, py = dw - pad + offX, dh - pad + offY, 1, 1
    else
        x, y, px, py = dw - pad + offX, pad + offY, 1, 0
    end

    pcall(function()
        if ImGui.SetNextWindowPos then
            if ImVec2 then
                ImGui.SetNextWindowPos(ImVec2(x, y), cond, ImVec2(px, py))
            else
                ImGui.SetNextWindowPos(x, y, cond, px, py)
            end
        end
    end)
end

--- opts.imageRelPath — optional; PNG under `mq.luaDir`, e.g. `port/ueq-port.png` for Jeeves Porter.
--- Same order as MAUI: draw this **before** the tool’s main ImGui.Begin so the float is always submitted.
function M.drawFloating(opts)
    if opts.showToggle == false then
        return
    end
    if type(opts.isAnyOpen) ~= 'function' or type(opts.onClick) ~= 'function' then
        return
    end

    local id = tostring(opts.id or 'UEQ')
    local res = tostring(opts.resourceName or id):gsub('##', '')
    local winTitle = opts.windowTitle or opts.resourceName or ('Float ' .. id)
    winTitle = tostring(winTitle):gsub('##', '')
    local fb = opts.fallbackLabel or res:sub(1, 4)
    if fb == '' then
        fb = 'UE'
    end

    local anyOpen = opts.isAnyOpen()
    local tipHide = opts.tooltipHide or 'Hide window'
    local tipShow = opts.tooltipShow or 'Show window'
    if res ~= '' then
        tipHide = res .. '\n' .. tipHide
        tipShow = res .. '\n' .. tipShow
    end
    local tip = anyOpen and tipHide or tipShow

    local sz = opts.sizePx or shared.defaultSize
    if not didSetFloatCorner[id] then
        setNextWindowCorner(opts)
        didSetFloatCorner[id] = true
    end

    local floatWinFlags = windowFlagsFloat()

    ImGui.PushStyleVar(ImGuiStyleVar.WindowBorderSize, 0)
    ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, 0, 0)
    ImGui.PushStyleColor(ImGuiCol.Border, 0, 0, 0, 0)
    ImGui.PushStyleColor(ImGuiCol.WindowBg, 0, 0, 0, 0)
    ImGui.Begin(winTitle .. '###UEQFloat_' .. id, nil, floatWinFlags)
    if opts.showDragStrip ~= false then
        drawFloatingDragStrip(id, sz, opts.dragStripHeight)
    end
    if drawLogoButton(id, sz, tip, fb, opts.imageRelPath) then
        opts.onClick()
    end
    ImGui.End()
    ImGui.PopStyleColor(2)
    ImGui.PopStyleVar(2)
end

return M
