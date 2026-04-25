local mq = require('mq')

local M = {}

local themes = {
    ['template'] = {
        windowBg = {0.04, 0.02, 0.08, 0.95},
        titleBg = {0.14, 0.02, 0.22, 1.00},
        titleBgActive = {0.24, 0.04, 0.32, 1.00},
        button = {0.18, 0.06, 0.26, 1.00},
        buttonHovered = {0.36, 0.09, 0.44, 1.00},
        buttonActive = {0.50, 0.12, 0.58, 1.00},
        frameBg = {0.10, 0.04, 0.16, 1.00},
        frameBgHovered = {0.18, 0.07, 0.26, 1.00},
        frameBgActive = {0.22, 0.09, 0.30, 1.00},
        header = {0.22, 0.07, 0.30, 1.00},
        text = {0.92, 0.96, 1.00, 1.00},
        border = {0.90, 0.16, 0.68, 0.70},
        separator = {0.22, 0.90, 0.84, 0.60},
        menuBarBg = {0.08, 0.03, 0.14, 1.00},
        tableRowBg = {0.00, 0.00, 0.00, 0.00},
        tableRowBgAlt = {0.08, 0.03, 0.14, 0.60},
        tableBorderLight = {0.30, 0.10, 0.40, 0.60},
        tableBorderStrong = {0.60, 0.18, 0.80, 0.80},
        scrollbarBg = {0.02, 0.01, 0.06, 0.80},
        scrollbarGrab = {0.30, 0.08, 0.40, 0.80},
        scrollbarGrabHovered = {0.50, 0.14, 0.60, 0.90},
        popupBg = {0.02, 0.03, 0.08, 0.98},
        checkMark = {0.96, 0.86, 0.30, 1.00},
    },
    ['neon_purple'] = {
        windowBg = {0.05, 0.05, 0.05, 0.95},
        titleBg = {0.1, 0.05, 0.15, 1.0},
        titleBgActive = {0.3, 0.1, 0.4, 1.0},
        button = {0.5, 0.1, 0.7, 1.0},
        buttonHovered = {0.7, 0.2, 0.9, 1.0},
        buttonActive = {0.4, 0.05, 0.6, 1.0},
        frameBg = {0.15, 0.1, 0.2, 1.0},
        frameBgHovered = {0.25, 0.15, 0.3, 1.0},
        frameBgActive = {0.30, 0.18, 0.36, 1.0},
        header = {0.4, 0.15, 0.55, 1.0},
        text = {0.95, 0.85, 1.0, 1.0},
        border = {0.6, 0.2, 0.8, 0.5},
        separator = {0.5, 0.2, 0.7, 0.8},
        popupBg = {0.08, 0.04, 0.12, 0.98},
        checkMark = {0.95, 0.85, 1.0, 1.0},
    },
    ['cyber_blue'] = {
        windowBg = {0.02, 0.02, 0.08, 0.95},
        titleBg = {0.05, 0.1, 0.2, 1.0},
        titleBgActive = {0.1, 0.3, 0.5, 1.0},
        button = {0.1, 0.4, 0.8, 1.0},
        buttonHovered = {0.2, 0.5, 0.95, 1.0},
        buttonActive = {0.05, 0.3, 0.6, 1.0},
        frameBg = {0.1, 0.15, 0.25, 1.0},
        frameBgHovered = {0.15, 0.25, 0.35, 1.0},
        frameBgActive = {0.12, 0.21, 0.32, 1.0},
        header = {0.15, 0.4, 0.65, 1.0},
        text = {0.85, 0.95, 1.0, 1.0},
        border = {0.2, 0.6, 0.9, 0.5},
        separator = {0.2, 0.5, 0.8, 0.8},
        popupBg = {0.04, 0.08, 0.14, 0.98},
        checkMark = {0.85, 0.95, 1.0, 1.0},
    },
    ['toxic_green'] = {
        windowBg = {0.02, 0.05, 0.02, 0.95},
        titleBg = {0.05, 0.15, 0.05, 1.0},
        titleBgActive = {0.1, 0.4, 0.1, 1.0},
        button = {0.2, 0.7, 0.2, 1.0},
        buttonHovered = {0.3, 0.9, 0.3, 1.0},
        buttonActive = {0.15, 0.5, 0.15, 1.0},
        frameBg = {0.1, 0.2, 0.1, 1.0},
        frameBgHovered = {0.15, 0.3, 0.15, 1.0},
        frameBgActive = {0.13, 0.24, 0.13, 1.0},
        header = {0.2, 0.6, 0.2, 1.0},
        text = {0.85, 1.0, 0.85, 1.0},
        border = {0.3, 0.8, 0.3, 0.5},
        separator = {0.25, 0.7, 0.25, 0.8},
        popupBg = {0.04, 0.10, 0.04, 0.98},
        checkMark = {0.85, 1.0, 0.85, 1.0},
    },
    ['hot_pink'] = {
        windowBg = {0.08, 0.02, 0.05, 0.95},
        titleBg = {0.2, 0.05, 0.1, 1.0},
        titleBgActive = {0.5, 0.1, 0.3, 1.0},
        button = {0.9, 0.2, 0.5, 1.0},
        buttonHovered = {1.0, 0.4, 0.7, 1.0},
        buttonActive = {0.7, 0.1, 0.4, 1.0},
        frameBg = {0.2, 0.1, 0.15, 1.0},
        frameBgHovered = {0.3, 0.15, 0.25, 1.0},
        frameBgActive = {0.25, 0.13, 0.20, 1.0},
        header = {0.7, 0.15, 0.4, 1.0},
        text = {1.0, 0.85, 0.95, 1.0},
        border = {0.9, 0.3, 0.6, 0.5},
        separator = {0.8, 0.25, 0.5, 0.8},
        popupBg = {0.15, 0.06, 0.10, 0.98},
        checkMark = {1.0, 0.85, 0.95, 1.0},
    },
    ['orange_blaze'] = {
        windowBg = {0.05, 0.03, 0.0, 0.95},
        titleBg = {0.15, 0.08, 0.0, 1.0},
        titleBgActive = {0.4, 0.2, 0.0, 1.0},
        button = {0.9, 0.5, 0.1, 1.0},
        buttonHovered = {1.0, 0.6, 0.2, 1.0},
        buttonActive = {0.7, 0.4, 0.05, 1.0},
        frameBg = {0.2, 0.12, 0.05, 1.0},
        frameBgHovered = {0.3, 0.18, 0.08, 1.0},
        frameBgActive = {0.26, 0.16, 0.07, 1.0},
        header = {0.7, 0.4, 0.1, 1.0},
        text = {1.0, 0.95, 0.85, 1.0},
        border = {0.9, 0.5, 0.2, 0.5},
        separator = {0.8, 0.45, 0.15, 0.8},
        popupBg = {0.16, 0.10, 0.04, 0.98},
        checkMark = {1.0, 0.95, 0.85, 1.0},
    },
    ['ice_blue'] = {
        windowBg = {0.02, 0.05, 0.08, 0.95},
        titleBg = {0.05, 0.12, 0.18, 1.0},
        titleBgActive = {0.1, 0.25, 0.4, 1.0},
        button = {0.2, 0.6, 0.8, 1.0},
        buttonHovered = {0.3, 0.75, 0.95, 1.0},
        buttonActive = {0.15, 0.5, 0.65, 1.0},
        frameBg = {0.1, 0.18, 0.25, 1.0},
        frameBgHovered = {0.15, 0.25, 0.35, 1.0},
        frameBgActive = {0.13, 0.22, 0.30, 1.0},
        header = {0.2, 0.5, 0.7, 1.0},
        text = {0.9, 0.98, 1.0, 1.0},
        border = {0.3, 0.7, 0.9, 0.5},
        separator = {0.25, 0.65, 0.85, 0.8},
        popupBg = {0.06, 0.12, 0.18, 0.98},
        checkMark = {0.9, 0.98, 1.0, 1.0},
    },
    ['matrix_hack'] = {
        windowBg = {0.0, 0.0, 0.0, 0.98},
        titleBg = {0.0, 0.08, 0.0, 1.0},
        titleBgActive = {0.0, 0.25, 0.0, 1.0},
        button = {0.0, 0.5, 0.0, 1.0},
        buttonHovered = {0.0, 0.7, 0.0, 1.0},
        buttonActive = {0.0, 0.35, 0.0, 1.0},
        frameBg = {0.0, 0.12, 0.0, 1.0},
        frameBgHovered = {0.0, 0.2, 0.0, 1.0},
        frameBgActive = {0.0, 0.17, 0.0, 1.0},
        header = {0.0, 0.4, 0.0, 1.0},
        text = {0.0, 1.0, 0.0, 1.0},
        border = {0.0, 0.6, 0.0, 0.7},
        separator = {0.0, 0.5, 0.0, 0.9},
        popupBg = {0.0, 0.06, 0.0, 0.98},
        checkMark = {0.0, 1.0, 0.0, 1.0},
    },
    ['term_hack'] = {
        windowBg = {0.0, 0.02, 0.0, 0.98},
        titleBg = {0.0, 0.1, 0.05, 1.0},
        titleBgActive = {0.0, 0.3, 0.15, 1.0},
        button = {0.0, 0.6, 0.3, 1.0},
        buttonHovered = {0.0, 0.8, 0.4, 1.0},
        buttonActive = {0.0, 0.45, 0.22, 1.0},
        frameBg = {0.0, 0.15, 0.08, 1.0},
        frameBgHovered = {0.0, 0.25, 0.12, 1.0},
        frameBgActive = {0.0, 0.20, 0.10, 1.0},
        header = {0.0, 0.5, 0.25, 1.0},
        text = {0.2, 1.0, 0.6, 1.0},
        border = {0.0, 0.7, 0.35, 0.7},
        separator = {0.0, 0.6, 0.3, 0.9},
        popupBg = {0.0, 0.08, 0.04, 0.98},
        checkMark = {0.2, 1.0, 0.6, 1.0},
    },
}

local cache = {
    key = 'template',
    nextReadAt = 0,
}

local function normalize_theme_key(raw)
    local k = tostring(raw or ''):lower()
    if k == '' or k == 'default' then return 'template' end
    if k == 'red' then return 'cyber_blue' end
    if themes[k] then return k end
    return nil
end

local function get_theme_key()
    local now = mq.gettime and mq.gettime() or 0
    if now < cache.nextReadAt then
        return cache.key
    end
    cache.nextReadAt = now + 2000

    local path = string.format('%s/%s_%s.ini', mq.configDir, mq.TLO.EverQuest.Server(), mq.TLO.Me.CleanName())
    local f = io.open(path, 'r')
    if f then
        local inMaui = false
        for line in f:lines() do
            local header = line:match('^%s*%[([^%]]+)%]%s*$')
            if header then
                inMaui = (header:lower() == 'maui')
            elseif inMaui then
                local key, value = line:match('^%s*([^=]+)%s*=%s*(.-)%s*$')
                local normalized = normalize_theme_key(value)
                if key and normalized and key:lower() == 'theme' then
                    cache.key = normalized
                    break
                end
            end
        end
        f:close()
    end
    return cache.key
end

function M.push()
    local key = get_theme_key()
    local t = themes[key] or themes.template
    local token = {colors = 0, vars = 0}
    local function pick(colorKey, fallback)
        return t[colorKey] or fallback
    end
    local function pushc(col, rgba)
        ImGui.PushStyleColor(col, rgba[1], rgba[2], rgba[3], rgba[4])
        token.colors = token.colors + 1
    end
    local windowBg = pick('windowBg', themes.template.windowBg)
    local frameBg = pick('frameBg', themes.template.frameBg)
    local frameBgHovered = pick('frameBgHovered', themes.template.frameBgHovered)
    local button = pick('button', themes.template.button)
    local buttonHovered = pick('buttonHovered', themes.template.buttonHovered)
    local buttonActive = pick('buttonActive', themes.template.buttonActive)
    local border = pick('border', themes.template.border)
    local separator = pick('separator', themes.template.separator)
    local menuBarBg = pick('menuBarBg', frameBg)
    local tableRowBg = pick('tableRowBg', {0.00, 0.00, 0.00, 0.00})
    local tableRowBgAlt = pick('tableRowBgAlt', frameBgHovered)
    local tableBorderLight = pick('tableBorderLight', border)
    local tableBorderStrong = pick('tableBorderStrong', border)
    local scrollbarBg = pick('scrollbarBg', windowBg)
    local scrollbarGrab = pick('scrollbarGrab', frameBg)
    local scrollbarGrabHovered = pick('scrollbarGrabHovered', frameBgHovered)

    local function pushv(var, ...)
        ImGui.PushStyleVar(var, ...)
        token.vars = token.vars + 1
    end

    pushv(ImGuiStyleVar.WindowRounding, 4)
    pushv(ImGuiStyleVar.FrameRounding, 5)
    pushv(ImGuiStyleVar.ChildRounding, 0)
    pushv(ImGuiStyleVar.PopupRounding, 8)
    pushv(ImGuiStyleVar.GrabRounding, 6)
    pushv(ImGuiStyleVar.TabRounding, 0)
    pushv(ImGuiStyleVar.WindowBorderSize, 1)
    pushv(ImGuiStyleVar.FrameBorderSize, 1)
    pushv(ImGuiStyleVar.ChildBorderSize, 1)
    pushv(ImGuiStyleVar.WindowPadding, 8, 6)
    pushv(ImGuiStyleVar.FramePadding, 4, 2)
    pushv(ImGuiStyleVar.ItemSpacing, 6, 4)
    pushv(ImGuiStyleVar.CellPadding, 4, 3)

    pushc(ImGuiCol.WindowBg, windowBg)
    pushc(ImGuiCol.ChildBg, pick('childBg', {0.02, 0.03, 0.08, 1.00}))
    pushc(ImGuiCol.MenuBarBg, menuBarBg)
    pushc(ImGuiCol.TitleBg, pick('titleBg', themes.template.titleBg))
    pushc(ImGuiCol.TitleBgActive, pick('titleBgActive', themes.template.titleBgActive))
    pushc(ImGuiCol.Button, button)
    pushc(ImGuiCol.ButtonHovered, buttonHovered)
    pushc(ImGuiCol.ButtonActive, buttonActive)
    pushc(ImGuiCol.FrameBg, frameBg)
    pushc(ImGuiCol.FrameBgHovered, frameBgHovered)
    pushc(ImGuiCol.FrameBgActive, pick('frameBgActive', frameBgHovered))
    pushc(ImGuiCol.Header, pick('header', button))
    pushc(ImGuiCol.HeaderHovered, buttonHovered)
    pushc(ImGuiCol.HeaderActive, buttonActive)
    pushc(ImGuiCol.TableRowBg, tableRowBg)
    pushc(ImGuiCol.TableRowBgAlt, tableRowBgAlt)
    pushc(ImGuiCol.TableBorderLight, tableBorderLight)
    pushc(ImGuiCol.TableBorderStrong, tableBorderStrong)
    pushc(ImGuiCol.Text, pick('text', themes.template.text))
    pushc(ImGuiCol.Border, border)
    pushc(ImGuiCol.Separator, separator)
    pushc(ImGuiCol.ScrollbarBg, scrollbarBg)
    pushc(ImGuiCol.ScrollbarGrab, scrollbarGrab)
    pushc(ImGuiCol.ScrollbarGrabHovered, scrollbarGrabHovered)
    pushc(ImGuiCol.TextDisabled, pick('textDisabled', {0.72, 0.72, 0.72, 1.00}))
    pushc(ImGuiCol.CheckMark, pick('checkMark', themes.template.checkMark))
    pushc(ImGuiCol.PopupBg, pick('popupBg', themes.template.popupBg))
    pushc(ImGuiCol.Tab, pick('tab', frameBg))
    pushc(ImGuiCol.TabHovered, pick('tabHovered', frameBgHovered))
    pushc(ImGuiCol.TabActive, pick('tabActive', pick('header', button)))
    return token
end

function M.pop(token)
    if token and token.vars and token.vars > 0 then
        ImGui.PopStyleVar(token.vars)
    end
    if token and token.colors and token.colors > 0 then
        ImGui.PopStyleColor(token.colors)
    end
end

return M
