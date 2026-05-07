local mq                            = require('mq')
local Set                           = require('mq.Set')
local btnUtils                      = require('lib.buttonUtils')
local ezimButtonHandlers              = require('ezimButtonHandlers')
local themes                        = require('extras.themes')

local WINDOW_SETTINGS_ICON_SIZE     = 22

local editTabPopup                  = "edit_tab_popup"

---@class ezimHotbarClass
local ezimHotbarClass                 = {}
ezimHotbarClass.__index               = ezimHotbarClass
ezimHotbarClass.id                    = 1
ezimHotbarClass.openGUI               = true
ezimHotbarClass.shouldDrawGUI         = true
ezimHotbarClass.setupComplete         = false
ezimHotbarClass.lastWindowX           = 0
ezimHotbarClass.lastWindowY           = 0
ezimHotbarClass.lastButtonPageHeight  = 0
ezimHotbarClass.lastButtonPageWidth   = 0
ezimHotbarClass.lastWindowHeight      = 0
ezimHotbarClass.lastWindowWidth       = 0
ezimHotbarClass.buttonSizeDirty       = false
ezimHotbarClass.visibleButtonCount    = 0
ezimHotbarClass.cachedCols            = 0
ezimHotbarClass.cachedRows            = 0
ezimHotbarClass.highestRenderTime     = 0

ezimHotbarClass.importObjectPopupOpen = false

ezimHotbarClass.validDecode           = false
ezimHotbarClass.importText            = ""
ezimHotbarClass.decodedObject         = {}

ezimHotbarClass.newSetName            = ""
ezimHotbarClass.currentSelectedSet    = 0

ezimHotbarClass.lastFrameTime         = 0

ezimHotbarClass.importTextChanged     = false

ezimHotbarClass.updateWindowPosSize   = false
ezimHotbarClass.newWidth              = 0
ezimHotbarClass.newHeight             = 0
ezimHotbarClass.newX                  = 0
ezimHotbarClass.newY                  = 0

ezimHotbarClass.searchText            = ""

ezimHotbarClass.currentDnDData        = nil

ezimHotbarClass.alphaMenu             = {
    { name = "A-D",   filter = function(i) return i >= "A" and i <= "D" end, items = {}, },
    { name = "E-H",   filter = function(i) return i >= "E" and i <= "H" end, items = {}, },
    { name = "I-L",   filter = function(i) return i >= "I" and i <= "L" end, items = {}, },
    { name = "M-P",   filter = function(i) return i >= "M" and i <= "P" end, items = {}, },
    { name = "Q-T",   filter = function(i) return i >= "Q" and i <= "T" end, items = {}, },
    { name = "U-X",   filter = function(i) return i >= "U" and i <= "X" end, items = {}, },
    { name = "Y-Z",   filter = function(i) return i >= "Y" and i <= "Z" end, items = {}, },
    { name = "0-9",   filter = function(i) return i >= "0" and i <= "9" end, items = {}, },
    { name = "Other", filter = function(i) return true end,                  items = {}, }, }


function ezimHotbarClass.new(id, createFresh)
    local newHotbar = setmetatable({ id = id, }, ezimHotbarClass)

    if createFresh then
        ezimSettings:GetCharConfig().Windows[id] = {
            Visible = true,
            Sets = {},
            Locked = false,
            HideTitleBar = false,
            CompactMode = false,
            AdvTooltips = true,
            ShowSearch = false,
            PerCharacterPositioning = false,
        }

        -- if this character doesn't have the sections in the config, create them
        newHotbar.updateWindowPosSize = true
        newHotbar.newWidth = 1000
        newHotbar.newHeight = 150
        newHotbar.newX = 500
        newHotbar.newY = 500

        ezimSettings:SaveSettings(true)
    end

    ezimSettings:GetCharConfig().Windows[id].Sets = ezimSettings:GetCharConfig().Windows[id].Sets or {}

    return newHotbar
end

function ezimHotbarClass:SetVisible(bVisible)
    ezimSettings:GetCharacterWindow(self.id).Visible = bVisible
    self.openGUI = bVisible
    ezimSettings:SaveSettings(true)
end

function ezimHotbarClass:ToggleVisible()
    ezimSettings:GetCharacterWindow(self.id).Visible = not ezimSettings:GetCharacterWindow(self.id).Visible
    self.openGUI = ezimSettings:GetCharacterWindow(self.id).Visible
    ezimSettings:SaveSettings(true)
end

function ezimHotbarClass:IsVisible()
    return ezimSettings:GetCharacterWindow(self.id).Visible
end

function ezimHotbarClass:PerCharacterPositioning()
    return ezimSettings:GetCharacterWindow(self.id).PerCharacterPositioning
end

---@return integer, integer
function ezimHotbarClass:StartTheme()
    local theme = ezimSettings:GetSettings().Themes and ezimSettings:GetSettings().Themes[self.id] or nil

    if not theme then
        theme = ezimSettings.Globals.CustomThemes and
            ezimSettings.Globals.CustomThemes[ezimSettings:GetCharacterWindow(self.id).Theme] or nil
    end

    if not theme then
        theme = themes[ezimSettings:GetCharacterWindow(self.id).Theme or ""] or nil
    end

    local themeColorPop = 0
    local themeStylePop = 0

    if theme ~= nil then
        for n, t in pairs(theme) do
            if t.color then
                ImGui.PushStyleColor(ImGuiCol[t.element], t.color.r, t.color.g, t.color.b, t.color.a)
                themeColorPop = themeColorPop + 1
            elseif t.stylevar then
                ImGui.PushStyleVar(ImGuiStyleVar[t.stylevar], t.value)
                themeStylePop = themeStylePop + 1
            else
                if type(t) == 'table' then
                    if t['Dynamic_Color'] then
                        local ret, colors = btnUtils.EvaluateLua(t['Dynamic_Color'])
                        if ret then
                            ---@diagnostic disable-next-line: param-type-mismatch
                            ImGui.PushStyleColor(ImGuiCol[n], colors)
                            themeColorPop = themeColorPop + 1
                        end
                    elseif t['Dynamic_Var'] then
                        local ret, var = btnUtils.EvaluateLua(t['Dynamic_Var'])
                        if ret then
                            if type(var) == 'table' then
                                ---@diagnostic disable-next-line: param-type-mismatch, deprecated
                                ImGui.PushStyleVar(ImGuiStyleVar[n], unpack(var))
                            else
                                ---@diagnostic disable-next-line: param-type-mismatch
                                ImGui.PushStyleVar(ImGuiStyleVar[n], var)
                            end
                            themeStylePop = themeStylePop + 1
                        end
                    elseif #t == 4 then
                        local colors = btnUtils.shallowcopy(t)
                        for i = 1, 4 do
                            if type(colors[i]) == 'string' then
                                local ret, color = btnUtils.EvaluateLua(colors[i])
                                if ret then
                                    colors[i] = color
                                end
                            end
                        end
                        ---@diagnostic disable-next-line: param-type-mismatch, deprecated
                        ImGui.PushStyleColor(ImGuiCol[n], unpack(colors))
                        themeColorPop = themeColorPop + 1
                    else
                        ---@diagnostic disable-next-line: param-type-mismatch, deprecated
                        ImGui.PushStyleVar(ImGuiStyleVar[n], unpack(t))
                        themeStylePop = themeStylePop + 1
                    end
                end
            end
        end
    end

    return themeColorPop, themeStylePop
end

---@param themeColorPop integer
---@param themeStylePop integer
function ezimHotbarClass:EndTheme(themeColorPop, themeStylePop)
    if themeColorPop > 0 then
        ImGui.PopStyleColor(themeColorPop)
    end
    if themeStylePop > 0 then
        ImGui.PopStyleVar(themeStylePop)
    end
end

function ezimHotbarClass:RenderHotbar(flags)
    if not self:IsVisible() then return end

    if self.updateWindowPosSize then
        btnUtils.Debug("Setting new(%d: %s) pos: %d, %d and size: %d, %d", self.id, tostring(self), self.newX, self.newY,
            self.newWidth, self.newHeight)
        self.updateWindowPosSize = false
        ImGui.SetNextWindowSize(self.newWidth, self.newHeight)

        ImGui.SetNextWindowPos(self.newX, self.newY)
        self.lastButtonPageHeight = self.newHeight
        self.lastButtonPageWidth  = self.newWidth
        self.lastWindowX          = self.newX
        self.lastWindowY          = self.newY
    end

    local colorPop, stylePop = self:StartTheme()
    local renderName = string.format('EZ Instance Master - %d', self.id)

    if self:PerCharacterPositioning() then
        renderName = renderName .. "##" .. mq.TLO.EverQuest.Server() .. "_" .. mq.TLO.Me.Name()
    end

    ImGui.PushID("##MainWindow_" .. tostring(self.id))
    self.openGUI, self.shouldDrawGUI = ImGui.Begin(renderName, self.openGUI,
        bit32.bor(flags))

    if not ImGui.IsMouseDown(ImGuiMouseButton.Left) then
        self.lastWindowX, self.lastWindowY = ImGui.GetWindowPos()
        self.lastWindowHeight = ImGui.GetWindowHeight()
        self.lastWindowWidth = ImGui.GetWindowWidth()
    end

    if self.openGUI and self.shouldDrawGUI then
        local startTimeMS = os.clock() * 1000
        local cursorScreenPos = ImGui.GetCursorScreenPosVec()

        self:RenderTabs()

        self:RenderImportButtonPopup()

        local endTimeMS = os.clock() * 1000

        local renderTimeMS = math.ceil(endTimeMS - startTimeMS)

        if btnUtils.enableDebug then
            if renderTimeMS > self.highestRenderTime then self.highestRenderTime = renderTimeMS end
            ImGui.SetWindowFontScale(0.8)
            self:RenderDebugText(cursorScreenPos, tostring(self.highestRenderTime))
            ImGui.SetWindowFontScale(1)
        end
    end

    ImGui.End()
    ImGui.PopID()

    self:EndTheme(colorPop, stylePop)

    if self.openGUI ~= self:IsVisible() then
        self:SetVisible(self.openGUI)
        self.openGUI = true
        if not self:IsVisible() then
            btnUtils.Output("Hotbar %d hidden! Use `/ezim %d` to bring it back.", self.id, self.id)
        end
    end

    self.setupComplete = true
end

function ezimHotbarClass:RenderTabs()
    local lockedIcon = ezimSettings:GetCharacterWindow(self.id).Locked and Icons.FA_LOCK .. '##lockTabButton' or
        Icons.FA_UNLOCK .. '##lockTablButton'

    if ezimSettings:GetCharacterWindow(self.id).CompactMode then
        local start_x, start_y = ImGui.GetCursorPos()

        local iconPadding = 2
        local settingsIconSize = math.ceil(((ezimSettings:GetCharacterWindow(self.id).ButtonSize or 6) * 10) / 2) -
            iconPadding
        ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, 0, iconPadding)
        ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 0, 0)

        if ImGui.Button(lockedIcon, settingsIconSize, settingsIconSize) then
            --ImGuiWindowFlags.NoMove
            ezimSettings:GetCharacterWindow(self.id).Locked = not ezimSettings:GetCharacterWindow(self.id).Locked
            ezimSettings:SaveSettings(true)
        end

        ImGui.SetCursorPosY(ImGui.GetCursorPosY() + (iconPadding))
        ImGui.Button(Icons.MD_SETTINGS, settingsIconSize, settingsIconSize)
        ImGui.PopStyleVar(2)

        ImGui.SameLine()

        self:RenderTabContextMenu()
        self:RenderCreateTab()
        self.currentSelectedSet = 1

        local style = ImGui.GetStyle()
        ImGui.SetCursorPos(ImVec2(start_x + settingsIconSize + (style.ItemSpacing.x), start_y))

        ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, 0, 0)
        ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 0, 0)
        ImGui.BeginChild("##buttons_child", nil, nil, bit32.bor(ImGuiChildFlags.AlwaysAutoResize, ImGuiChildFlags.AutoResizeY))

        if ezimSettings:GetCharacterWindowSets(self.id)[1] ~= nil then
            self:RenderButtons(ezimSettings:GetCharacterWindowSets(self.id)[1], "")
        end

        ImGui.EndChild()
        ImGui.PopStyleVar(2)
    else
        if ImGui.Button(lockedIcon, WINDOW_SETTINGS_ICON_SIZE, WINDOW_SETTINGS_ICON_SIZE) then
            --ImGuiWindowFlags.NoMove
            ezimSettings:GetCharacterWindow(self.id).Locked = not ezimSettings:GetCharacterWindow(self.id).Locked
            ezimSettings:SaveSettings(true)
        end

        ImGui.SameLine()
        ImGui.Button(Icons.MD_SETTINGS, WINDOW_SETTINGS_ICON_SIZE, WINDOW_SETTINGS_ICON_SIZE)
        ImGui.SameLine()
        self:RenderTabContextMenu()
        self:RenderCreateTab()

        if ImGui.BeginTabBar("Tabs", ImGuiTabBarFlags.Reorderable) then
            if (#ezimSettings:GetCharacterWindowSets(self.id) or 0) > 0 then
                for i, set in ipairs(ezimSettings:GetCharacterWindowSets(self.id)) do
                    if ImGui.BeginTabItem(set) then
                        SetLabel = set
                        self.currentSelectedSet = i

                        -- tab edit popup
                        if ImGui.BeginPopupContextItem(set) then
                            ImGui.Text("Edit Name:")
                            local tmp, changed = ImGui.InputText("##edit", set, 0)
                            if changed or self.newSetName:len() == 0 then self.newSetName = tmp end
                            if ImGui.Button("Save") then
                                EZIMEditPopup:CloseEditPopup()
                                local newSetLabel = self.newSetName
                                if self.newSetName ~= nil then
                                    ezimSettings:GetCharacterWindowSets(self.id)[i] = self.newSetName

                                    -- move the old button set to the new name
                                    ezimSettings:GetSettings().Sets[newSetLabel], ezimSettings:GetSettings().Sets[SetLabel] =
                                        ezimSettings:GetSettings().Sets[SetLabel], nil

                                    -- update the character button set name
                                    for curCharKey, curCharData in pairs(ezimSettings:GetSettings().Characters) do
                                        for windowIdx, windowData in ipairs(curCharData.Windows or {}) do
                                            for setIdx, oldSetName in ipairs(windowData.Sets or {}) do
                                                if oldSetName == set then
                                                    btnUtils.Output(string.format(
                                                        "\awUpdating section '\ag%s\aw' renaming \am%s\aw => \at%s",
                                                        curCharKey,
                                                        oldSetName, self.newSetName))
                                                    ezimSettings:GetSettings().Characters[curCharKey].Windows[windowIdx].Sets[setIdx] =
                                                        self.newSetName
                                                end
                                            end
                                        end
                                    end

                                    -- update set to the new name so the button render doesn't fail
                                    SetLabel = newSetLabel
                                    ezimSettings:SaveSettings(true)
                                end
                                ImGui.CloseCurrentPopup()
                            end
                            ImGui.EndPopup()
                        end
                        if ezimSettings:GetCharacterWindow(self.id).ShowSearch then
                            ImGui.Text("Search")
                            ImGui.SameLine()
                            self.searchText = ImGui.InputText("##SearchText", self.searchText, ImGuiInputTextFlags.None)
                        else
                            self.searchText = ""
                        end
                        self:RenderButtons(SetLabel, self.searchText)
                        ImGui.EndTabItem()
                    end
                end
            end
        else
            ImGui.Text(string.format("No Sets Added! Add one by right-clicking on %s", Icons.MD_SETTINGS))
        end
        ImGui.EndTabBar()
    end
end

---@param cursorScreenPos ImVec2 # cursor position on screen
---@param text string
function ezimHotbarClass:RenderDebugText(cursorScreenPos, text)
    local buttonLabelCol = IM_COL32(255, 0, 0, 255)
    local draw_list = ImGui.GetWindowDrawList()

    draw_list:AddText(ImVec2(cursorScreenPos.x, cursorScreenPos.y), buttonLabelCol, text)
end

function ezimHotbarClass:RenderTabContextMenu()
    local openPopup = false

    local unassigned = {}
    local charLoadedSets = {}
    for _, v in ipairs(ezimSettings:GetCharacterWindowSets(self.id) or {}) do
        charLoadedSets[v] = true
    end
    for k, _ in pairs(ezimSettings:GetSettings().Sets) do
        if charLoadedSets[k] == nil then
            unassigned[k] = true
        end
    end

    if ImGui.BeginPopupContextItem() then
        if btnUtils.getTableSize(unassigned) > 0 then
            if ImGui.BeginMenu("Add Set") then
                for k, _ in pairs(unassigned) do
                    if ImGui.MenuItem(k) then
                        table.insert(ezimSettings:GetCharacterWindowSets(self.id), k)
                        ezimSettings:SaveSettings(true)
                        break
                    end
                end
                ImGui.EndMenu()
            end
        end

        if ImGui.BeginMenu("Remove Set") then
            for i, v in ipairs(ezimSettings:GetCharacterWindowSets(self.id)) do
                if ImGui.MenuItem(v) then
                    table.remove(ezimSettings:GetCharConfig().Windows[self.id].Sets, i)
                    ezimSettings:SaveSettings(true)
                    break
                end
            end
            ImGui.EndMenu()
        end

        if ImGui.BeginMenu("Delete Set") then
            for k, _ in pairs(ezimSettings:GetSettings().Sets) do
                if ImGui.MenuItem(k) then
                    -- clean up any references to this set.
                    for charConfigKey, charConfigValue in pairs(ezimSettings:GetSettings().Characters or {}) do
                        for windowKey, windowData in ipairs(charConfigValue.Windows or {}) do
                            for setKey, setName in pairs(windowData.Sets or {}) do
                                if setName == k then
                                    ezimSettings:GetSettings().Characters[charConfigKey].Windows[windowKey].Sets[setKey] = nil
                                end
                            end
                        end
                    end
                    ezimSettings:GetSettings().Sets[k] = nil
                    ezimSettings:SaveSettings(true)
                    break
                end
            end
            ImGui.EndMenu()
        end

        if ImGui.BeginMenu("Delete Hotkey") then
            local sortedKeys = {}
            for k, v in pairs(ezimSettings:GetSettings().Buttons) do
                table.insert(sortedKeys,
                    { Label = ezimButtonHandlers.ResolveButtonLabel(v, true), id = k, })
            end
            table.sort(sortedKeys, function(a, b) return a.Label < b.Label end)

            local sortedAlphaMenu = {}

            for idx, buttonData in ipairs(sortedKeys) do
                for _, menuGroup in ipairs(self.alphaMenu) do
                    sortedAlphaMenu[menuGroup.name] = sortedAlphaMenu[menuGroup.name] or {}
                    if menuGroup.filter(buttonData.Label:sub(1, 1):upper()) then
                        table.insert(sortedAlphaMenu[menuGroup.name], { idx = idx, buttonData = buttonData, })
                        break
                    end
                end
            end

            for _, menuGroup in pairs(self.alphaMenu) do
                local items = sortedAlphaMenu[menuGroup.name] or {}
                if #items > 0 then
                    if ImGui.BeginMenu(menuGroup.name) then
                        for _, item in ipairs(items) do
                            if ImGui.MenuItem(item.buttonData.Label .. "##delete_menu_" .. tostring(item.idx)) then
                                -- clean up any references to this Button.
                                for setNameKey, setButtons in pairs(ezimSettings:GetSettings().Sets) do
                                    for buttonKey, buttonName in pairs(setButtons) do
                                        if buttonName == item.buttonData.id then
                                            ezimSettings:GetSettings().Sets[setNameKey][buttonKey] = nil
                                        end
                                    end
                                end
                                ezimSettings:GetSettings().Buttons[item.buttonData.id] = nil
                                ezimSettings:SaveSettings(true)
                                break
                            end
                        end
                        ImGui.EndMenu()
                    end
                end
            end
            ImGui.EndMenu()
        end

        if ImGui.MenuItem("Create New Set") then
            openPopup = true
        end

        ImGui.Separator()

        if ImGui.BeginMenu("Button Size") then
            for i = 3, 10 do
                local checked = ezimSettings:GetCharacterWindow(self.id).ButtonSize == i
                if ImGui.MenuItem(tostring(i), nil, checked) then
                    ezimSettings:GetCharacterWindow(self.id).ButtonSize = i
                    self.buttonSizeDirty = true
                    ezimSettings:SaveSettings(true)
                    break
                end
            end
            ImGui.EndMenu()
        end

        local font_scale = {
            {
                label = "Tiny",
                size = 8,
            },
            {
                label = "Small",
                size = 9,
            },
            {
                label = "Normal",
                size = 10,
            },
            {
                label = "Large",
                size  = 11,
            },
        }

        if ImGui.BeginMenu("Font Scale") then
            for i, v in ipairs(font_scale) do
                local checked = ezimSettings:GetCharacterWindow(self.id).Font == v.size
                if ImGui.MenuItem(v.label, nil, checked) then
                    ezimSettings:GetCharacterWindow(self.id).Font = v.size
                    ezimSettings:SaveSettings(true)
                    break
                end
            end
            ImGui.EndMenu()
        end

        if ImGui.BeginMenu("Set Theme") then
            local checked = ezimSettings:GetCharacterWindow(self.id).Theme == nil
            if ImGui.MenuItem("Default", nil, checked) then
                ezimSettings:GetCharacterWindow(self.id).Theme = nil
                ezimSettings:SaveSettings(true)
            end
            for n, _ in pairs(themes) do
                checked = (ezimSettings:GetCharacterWindow(self.id).Theme or "") == n
                if ImGui.MenuItem(n, nil, checked) then
                    ezimSettings:GetCharacterWindow(self.id).Theme = n
                    ezimSettings:SaveSettings(true)
                    break
                end
            end
            for n, _ in pairs(ezimSettings.Globals.CustomThemes or {}) do
                checked = (ezimSettings:GetCharacterWindow(self.id).Theme or "") == n
                if ImGui.MenuItem(n, nil, checked) then
                    ezimSettings:GetCharacterWindow(self.id).Theme = n
                    ezimSettings:SaveSettings(true)
                    break
                end
            end
            ImGui.EndMenu()
        end

        ImGui.Separator()

        if ImGui.BeginMenu("Share Set") then
            for k, _ in pairs(ezimSettings:GetSettings().Sets) do
                if ImGui.MenuItem(k) then
                    ezimButtonHandlers:ExportSetToClipBoard(k)
                    btnUtils.Output("Set: '%s' has been copied to your clipboard!", k)
                end
            end
            ImGui.EndMenu()
        end

        if ImGui.MenuItem("Import Button or Set") then
            self.importObjectPopupOpen = true
            self.importText = ImGui.GetClipboardText() or ""
            self.importTextChanged = true
        end

        if ImGui.BeginMenu("Copy Local Set") then
            local charList = {}
            for k, _ in pairs(ezimSettings:GetSettings().Characters) do
                local menuItem = k:sub(1, 1):upper() .. k:sub(2)
                menuItem = menuItem:gsub("_", ": ")
                table.insert(charList, { displayName = menuItem, key = k, })
            end
            table.sort(charList, function(a, b) return a.key < b.key end)
            for _, value in ipairs(charList) do
                if ImGui.MenuItem(value.displayName) then
                    CopyLocalSet(value.key)
                end
            end
            ImGui.EndMenu()
        end

        ImGui.Separator()

        if ImGui.BeginMenu("Display Settings") then
            if ImGui.MenuItem((ezimSettings:GetCharacterWindow(self.id).HideTitleBar and "Show" or "Hide") .. " Title Bar") then
                ezimSettings:GetCharacterWindow(self.id).HideTitleBar = not ezimSettings:GetCharacterWindow(self.id)
                    .HideTitleBar
                ezimSettings:SaveSettings(true)
            end
            if ImGui.MenuItem((ezimSettings:GetCharacterWindow(self.id).CompactMode and "Normal" or "Compact") .. " Mode") then
                ezimSettings:GetCharacterWindow(self.id).CompactMode = not ezimSettings:GetCharacterWindow(self.id)
                    .CompactMode
                ezimSettings:SaveSettings(true)
            end
            if ImGui.MenuItem((ezimSettings:GetCharacterWindow(self.id).PerCharacterPositioning and "Global Window Positioning" or "Per Char Window Positioning")) then
                ezimSettings:GetCharacterWindow(self.id).PerCharacterPositioning = not ezimSettings:GetCharacterWindow(self.id)
                    .PerCharacterPositioning
                ezimSettings:SaveSettings(true)
            end
            if ImGui.MenuItem((ezimSettings:GetCharacterWindow(self.id).AdvTooltips and "Disable" or "Enable") .. " Advanced Tooltips") then
                ezimSettings:GetCharacterWindow(self.id).AdvTooltips = not ezimSettings:GetCharacterWindow(self.id)
                    .AdvTooltips
                ezimSettings:SaveSettings(true)
            end
            if ImGui.MenuItem((ezimSettings:GetCharacterWindow(self.id).HideScrollbar and "Show" or "Hide") .. " Scrollbar") then
                ezimSettings:GetCharacterWindow(self.id).HideScrollbar = not ezimSettings:GetCharacterWindow(self.id)
                    .HideScrollbar
                ezimSettings:SaveSettings(true)
            end
            if ImGui.MenuItem((ezimSettings:GetCharacterWindow(self.id).ShowSearch and "Disable" or "Enable") .. " Search") then
                ezimSettings:GetCharacterWindow(self.id).ShowSearch = not ezimSettings:GetCharacterWindow(self.id)
                    .ShowSearch
                ezimSettings:SaveSettings(true)
            end
            local fps_scale = {
                {
                    label = "Instant",
                    fps = 0,
                },
                {
                    label = "10 FPS",
                    fps = 1,
                },
                {
                    label = "4 FPS",
                    fps = 2.5,
                },
                {
                    label = "1 FPS",
                    fps   = 10,
                },
            }

            if ImGui.BeginMenu("Update FPS") then
                for _, v in ipairs(fps_scale) do
                    local checked = ezimSettings:GetCharacterWindow(self.id).FPS == v.fps
                    if ImGui.MenuItem(v.label, nil, checked) then
                        ezimSettings:GetCharacterWindow(self.id).FPS = v.fps
                        ezimSettings:SaveSettings(true)
                        break
                    end
                end
                ImGui.EndMenu()
            end
            -- TODO: Make this a reference to a character since it can dynamically change.
            --if ImGui.MenuItem("Save Layout as Default") then
            --    ezimSettings:GetSettings().Defaults = {
            --        width = self.lastButtonPageWidth,
            --        height = self.lastButtonPageHeight,
            --        x = self.lastWindowX,
            --        y = self.lastWindowY,
            --        CharSettings = ezimSettings:GetCharConfig(),
            --    }
            --    ezimSettings:SaveSettings(true)
            --end
            ImGui.EndMenu()
        end

        if ImGui.MenuItem("Create New Hotbar") then
            table.insert(EZIMHotbars, ezimHotbarClass.new(ezimSettings:GetNextWindowId(), true))
        end

        if ImGui.BeginMenu("Show/Hide Hotbar") then
            for hbIdx, hotbarClass in ipairs(EZIMHotbars) do
                if ImGui.MenuItem(string.format("EZ Instance Master - %d", hbIdx), nil, hotbarClass:IsVisible()) then
                    hotbarClass:ToggleVisible()
                end
            end
            ImGui.EndMenu()
        end

        --[[if ImGui.MenuItem("Replicate Size/Pos") then
            local x, y = ImGui.GetWindowPos()
            ButtonActors.send({
                from = mq.TLO.Me.DisplayName(),
                script = "EZInstanceMaster",
                event = "CopyLoc",
                width = self.lastButtonPageWidth,
                height = self.lastButtonPageHeight,
                x = self.lastWindowX,
                y = self.lastWindowY,
                windowId = self.id,
                hideTitleBar = ezimSettings:GetCharacterWindow(self.id).HideTitleBar,
                compactMode = ezimSettings:GetCharacterWindow(self.id).CompactMode,
            })
        end]]

        ImGui.Separator()

        if ImGui.BeginMenu("Dev") then
            if ImGui.MenuItem((btnUtils.enableDebug and "Disable" or "Enable") .. " Debug") then
                btnUtils.enableDebug = not btnUtils.enableDebug
            end
            if ImGui.MenuItem("Remove All Duped Buttons") then
                local duplicatekeys = Set.new({})
                for buttonKey, buttonData in pairs(ezimSettings:GetSettings().Buttons or {}) do
                    btnUtils.Output("\awTesting Button: \am%s", buttonKey)
                    for curBtnKey, curBtn in pairs(ezimSettings:GetSettings().Buttons or {}) do
                        if buttonKey ~= curBtnKey and curBtn.Cmd == buttonData.Cmd then
                            btnUtils.Output("\awButton: \am%s \awis a duplicate!", buttonKey)
                            duplicatekeys:add(curBtnKey)
                            duplicatekeys:add(buttonKey)
                            break
                        end
                    end
                end

                for _, key in ipairs(duplicatekeys:toList()) do
                    btnUtils.Output("\awDuplicate: \am%s \aw(\at%s\aw)", key, ezimSettings:GetSettings().Buttons[key].Label)
                    local isUsed = false
                    for _, setButtons in pairs(ezimSettings:GetSettings().Sets) do
                        for _, buttonName in pairs(setButtons) do
                            if buttonName == key then
                                isUsed = true
                            end
                        end
                    end

                    if isUsed then
                        btnUtils.Output("   \ag-> Used")
                    else
                        if ezimSettings:GetSettings().Buttons[key] then
                            btnUtils.Output("   \ay-> Unused - Removing!")
                            ezimSettings:GetSettings().Buttons[key] = nil
                        else
                            btnUtils.Output("   \ay-> Unused - Previosuly Removed!")
                        end
                    end
                end
                ezimSettings:SaveSettings(true)
            end
            ImGui.EndMenu()
        end

        ImGui.EndPopup()
    end

    if openPopup and ImGui.IsPopupOpen(editTabPopup) == false then
        ImGui.OpenPopup(editTabPopup)
        openPopup = false
    end
end

function ezimHotbarClass:RenderContextMenu(Set, Index, buttonID)
    local button = ezimSettings:GetButtonBySetIndex(Set, Index)

    if ImGui.BeginPopupContextItem(buttonID) then
        local unassigned = {}
        local keys = {}
        for _, v in pairs(ezimSettings:GetSettings().Sets[Set] or {}) do keys[v] = true end
        for k, v in pairs(ezimSettings:GetSettings().Buttons) do
            if keys[k] == nil then
                unassigned[k] = v
            end
        end
        --editPopupName = "edit_button_popup|" .. Index
        -- only list hotkeys that aren't already assigned to the button set
        if btnUtils.getTableSize(unassigned) > 0 then
            if ImGui.BeginMenu("Assign Hotkey") then
                -- hytiek: BEGIN ADD
                -- Create an array to store the sorted keys
                local sortedKeys = {}

                -- Populate the array with non-nil keys from the original table
                for key, value in pairs(unassigned) do
                    if value ~= nil then
                        table.insert(sortedKeys, key)
                    end
                end

                -- Sort the keys based on the Label field
                table.sort(sortedKeys, function(a, b)
                    local labelA = unassigned[a] and ezimButtonHandlers.ResolveButtonLabel(unassigned[a], true)
                    local labelB = unassigned[b] and ezimButtonHandlers.ResolveButtonLabel(unassigned[b], true)
                    return labelA < labelB
                end)

                local sortedAlphaMenu = {}

                for idx, key in ipairs(sortedKeys) do
                    local value = unassigned[key]
                    if value ~= nil then
                        for _, menuGroup in ipairs(self.alphaMenu) do
                            sortedAlphaMenu[menuGroup.name] = sortedAlphaMenu[menuGroup.name] or {}
                            local label = ezimButtonHandlers.ResolveButtonLabel(value, true)
                            if menuGroup.filter(label:sub(1, 1):upper()) then
                                table.insert(sortedAlphaMenu[menuGroup.name], { idx = idx, key = key, value = value, label = label, })
                                break
                            end
                        end
                    end
                end


                for _, menuGroup in pairs(self.alphaMenu) do
                    local items = sortedAlphaMenu[menuGroup.name] or {}
                    if #items > 0 then
                        if ImGui.BeginMenu(menuGroup.name) then
                            for _, item in ipairs(items) do
                                if ImGui.MenuItem(item.label .. "##assign_menu_" .. tostring(item.idx)) then
                                    ezimSettings:GetSettings().Sets[Set][Index] = item.key
                                    ezimSettings:SaveSettings(true)
                                    break
                                end
                            end
                            ImGui.EndMenu()
                        end
                    end
                end

                ImGui.EndMenu()
            end
        end

        -- only show create new for unassigned buttons
        if button.Unassigned == true then
            if ImGui.MenuItem("Create New") then
                EZIMEditPopup:OpenEditPopup(Set, Index)
            end
        else
            if ImGui.MenuItem("Edit") then
                EZIMEditPopup:OpenEditPopup(Set, Index)
            end
            if ImGui.MenuItem("Unassign") then
                ezimSettings:GetSettings().Sets[Set][Index] = nil
                ezimSettings:SaveSettings(true)
            end
            if ImGui.MenuItem("Delete") then
                local buttonID = ezimSettings:GetSettings().Sets[Set][Index]
                for setNameKey, setButtons in pairs(ezimSettings:GetSettings().Sets) do
                    for buttonKey, buttonName in pairs(setButtons) do
                        if buttonName == buttonID then
                            ezimSettings:GetSettings().Sets[setNameKey][buttonKey] = nil
                        end
                    end
                end
                ezimSettings:GetSettings().Buttons[buttonID] = nil
                ezimSettings:SaveSettings(true)
            end

            if ImGui.MenuItem(Icons.MD_SHARE) then
                ezimButtonHandlers.ExportButtonToClipBoard(button)
            end
            btnUtils.Tooltip("Copy contents of this button to share with friends.")
        end

        ImGui.EndPopup()
    end
end

---@param Set string
---@param searchText string
function ezimHotbarClass:RenderButtons(Set, searchText)
    ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, ImVec2(4, 4))
    if ImGui.GetWindowWidth() ~= self.lastButtonPageWidth or ImGui.GetWindowHeight() ~= self.lastButtonPageHeight or self.buttonSizeDirty then
        self:RecalculateVisibleButtons(Set)
    end

    local btnSize = (ezimSettings:GetCharacterWindow(self.id).ButtonSize or 6) * 10

    local renderButtonCount = self.visibleButtonCount
    local isEZSet = type(Set) == 'string' and Set:find("^EZIM %-") ~= nil
    if isEZSet then
        renderButtonCount = 0
        for i = 1, 100 do
            if ezimSettings:GetSettings().Sets[Set] and ezimSettings:GetSettings().Sets[Set][i] ~= nil then
                renderButtonCount = i
            end
        end
    end
    local gridCount = 0

    for ButtonIndex = 1, renderButtonCount do
        local button = ezimSettings:GetButtonBySetIndex(Set, ButtonIndex)
        if button and button.SectionHeader then
            if gridCount % self.cachedCols ~= 0 and gridCount > 0 then
                ImGui.NewLine()
            end
            gridCount = 0
            ImGui.Spacing()
            ImGui.TextColored(0.95, 0.88, 0.30, 1.0, tostring(button.Label or ''))
            ImGui.Separator()
        else
            local searchMatch = true

            if searchText:len() > 0 then
                searchMatch =
                    (button.CachedLabel or ""):lower():find(searchText:lower()) ~= nil
                    or
                    (button.Cmd or ""):lower():find(searchText:lower()) ~= nil
            end

            if searchMatch then
                local clicked = false

                local buttonID = string.format("##Button_%s_%d", Set, ButtonIndex)
                local showLabel = true
                local btnKey = ezimSettings:GetButtonSectionKeyBySetIndex(Set, ButtonIndex)
                if ezimSettings.settings.Buttons[btnKey] ~= nil and ezimSettings.settings.Buttons[btnKey].ShowLabel ~= nil then
                    showLabel = ezimSettings.settings.Buttons[btnKey].ShowLabel
                end
                ImGui.PushID(buttonID)
                clicked = ezimButtonHandlers.Render(button, btnSize, showLabel, (ezimSettings:GetCharacterWindow(self.id).Font or 10) / 10,
                    ezimSettings:GetCharacterWindow(self.id).AdvTooltips)
                ImGui.PopID()
                -- TODO Move this to button config class and out of the UI thread.
                if clicked then
                    if button.Unassigned then
                        EZIMEditPopup:CreateButtonFromCursor(Set, ButtonIndex)
                    else
                        ezimButtonHandlers.Exec(button)
                    end
                else
                    -- setup drag and drop
                    if ImGui.BeginDragDropSource() then
                        self.currentDnDData = { Set = Set, Index = ButtonIndex, }
                        ImGui.SetDragDropPayload("BTN", self.id)
                        ImGui.Button(button.Label, btnSize, btnSize)
                        ImGui.EndDragDropSource()
                    end
                    if ImGui.BeginDragDropTarget() then
                        local payload = ImGui.AcceptDragDropPayload("BTN")

                        if payload ~= nil then
                            ---@diagnostic disable-next-line: undefined-field
                            local dndData = EZIMHotbars[payload.Data].currentDnDData
                            local success = dndData ~= nil
                            if success then
                                local to_set = dndData.Set
                                local to_num = dndData.Index
                                btnUtils.Output("Dropping button from set '" ..
                                    tostring(to_set) .. "' index " .. tostring(to_num) .. " to set '" .. tostring(Set) .. "' index " .. tostring(ButtonIndex))

                                -- swap the keys in the button set
                                ezimSettings:GetSettings().Sets[to_set][to_num], ezimSettings:GetSettings().Sets[Set][ButtonIndex] =
                                    ezimSettings:GetSettings().Sets[Set][ButtonIndex], ezimSettings:GetSettings().Sets[to_set][to_num]
                                ezimSettings:SaveSettings(true)
                            else
                                btnUtils.Output("\arError: Failed to decode dropped button payload :: %s!\ax", payload.Data or "nil")
                            end
                        end
                        ImGui.EndDragDropTarget()
                    end

                    self:RenderContextMenu(Set, ButtonIndex, buttonID)
                end

                -- button grid
                gridCount = gridCount + 1
                if gridCount % self.cachedCols ~= 0 then ImGui.SameLine() end
            end
        end
    end
    ImGui.PopStyleVar(1)
end

function ezimHotbarClass:RecalculateVisibleButtons(Set)
    self.buttonSizeDirty = false

    btnUtils.Debug("\arHave old lW=%d lH=%d", self.lastButtonPageWidth, self.lastButtonPageHeight)

    self.lastButtonPageWidth = ImGui.GetWindowWidth()
    self.lastButtonPageHeight = ImGui.GetWindowHeight()

    btnUtils.Debug("\arSetting new lW=%d lH=%d", self.lastButtonPageWidth, self.lastButtonPageHeight)

    local cursorX, cursorY = ImGui.GetCursorPos() -- this will get us the x pos we start at which tells us of the offset from the main window border
    local style = ImGui.GetStyle()                -- this will get us ItemSpacing.x which is the amount of space between buttons

    -- global button configs
    local btnSize = (ezimSettings:GetCharacterWindow(self.id).ButtonSize or 6) * 10
    self.cachedCols = math.floor((self.lastButtonPageWidth - cursorX) / (btnSize + style.ItemSpacing.x))
    self.cachedRows = math.floor((self.lastButtonPageHeight - cursorY) / (btnSize + style.ItemSpacing.y))

    local count = 100
    if self.cachedRows * self.cachedCols < 100 then count = self.cachedRows * self.cachedCols end

    -- get the last assigned button and make sure it is visible.
    local lastAssignedButton = 1
    for i = 1, 100 do if not ezimSettings:GetButtonBySetIndex(Set, i).Unassigned then lastAssignedButton = i end end

    -- if the last forced visible buttons isn't the last in a row then render to the end of that row.
    -- stay with me here. The last button needs to look at the number of buttons per row (cols) and
    -- the position of this button in that row (button%cols) and add enough to get to the end of the row.
    if lastAssignedButton % self.cachedCols ~= 0 then
        lastAssignedButton = lastAssignedButton + (self.cachedCols - (lastAssignedButton % self.cachedCols))
    end

    self.visibleButtonCount = math.min(math.max(count, lastAssignedButton), 100)
end

function ezimHotbarClass:RenderImportButtonPopup()
    if not self.importObjectPopupOpen then return end

    local shouldDrawImportPopup = false

    self.importObjectPopupOpen, shouldDrawImportPopup = ImGui.Begin("Import Button or Set", self.importObjectPopupOpen,
        ImGuiWindowFlags.None)
    if ImGui.GetWindowWidth() < 500 or ImGui.GetWindowHeight() < 100 then
        ImGui.SetWindowSize(math.max(500, ImGui.GetWindowWidth()), math.max(100, ImGui.GetWindowHeight()))
    end
    if self.importObjectPopupOpen and shouldDrawImportPopup then
        if ImGui.SmallButton(Icons.MD_CONTENT_PASTE) then
            self.importText = ImGui.GetClipboardText()
            self.importTextChanged = true
        end
        btnUtils.Tooltip("Paste from Clipboard")
        ImGui.SameLine()

        if self.importTextChanged then
            self.validDecode, self.decodedObject = btnUtils.decodeTable(self.importText)
            self.validDecode = type(self.decodedObject) == 'table' and self.validDecode or false
        end

        if self.validDecode then
            ImGui.PushStyleColor(ImGuiCol.Text, 0.02, 0.8, 0.02, 1.0)
        else
            ImGui.PushStyleColor(ImGuiCol.Text, 0.8, 0.02, 0.02, 1.0)
        end
        self.importText, self.importTextChanged = ImGui.InputText(
            (self.validDecode and Icons.MD_CHECK or Icons.MD_NOT_INTERESTED) .. " Import Code", self.importText,
            ImGuiInputTextFlags.None)
        ImGui.PopStyleColor()

        -- save button
        if self.validDecode and self.decodedObject then
            if ImGui.Button("Import " .. (self.decodedObject.Type or "Failed")) then
                if self.decodedObject.Type == "Button" then
                    ezimSettings:ImportButtonAndSave(self.decodedObject.Button, true)
                elseif self.decodedObject.Type == "Set" then
                    ezimSettings:ImportSetAndSave(self.decodedObject, self.id)
                else
                    btnUtils.Output("\arError: imported object was not a button or a set!")
                end
                -- reset everything
                self.decodedObject = {}
                self.importText = ""
                self.importObjectPopupOpen = false
            end
        end
    end
    ImGui.End()
end

function ezimHotbarClass:RenderCreateTab()
    if ImGui.BeginPopup(editTabPopup) then
        ImGui.Text("New Button Set:")
        local tmp, selected = ImGui.InputText("##edit", '', 0)
        if selected then self.newSetName = tmp end
        if ImGui.Button("Save") then
            if self.newSetName ~= nil and self.newSetName:len() > 0 then
                if ezimSettings:GetSettings().Sets[self.newSetName] == nil then
                    table.insert(ezimSettings:GetCharConfig().Windows[self.id].Sets, self.newSetName)
                    ezimSettings:GetSettings().Sets[self.newSetName] = {}
                    ezimSettings:SaveSettings(true)
                else
                    btnUtils.Output("\arError Saving Set: A set with this name already exists!\ax")
                end
            else
                btnUtils.Output("\arError Saving Set: Name cannot be empty.\ax")
            end
            ImGui.CloseCurrentPopup()
        end
        ImGui.EndPopup()
    end
end

function ezimHotbarClass:ReloadConfig()
    local config = ezimSettings:GetCharacterWindow(self.id)
    btnUtils.Debug("\ayWindow(%d: %s) config: \n%s", self.id, tostring(self), btnUtils.dumpTable(config))
    self.updateWindowPosSize           = true
    self.newWidth                      = config.Width or 100
    self.newHeight                     = config.Height or 40
    self.newX                          = config.Pos and (config.Pos.x or 10)
    self.newY                          = config.Pos and (config.Pos.y or 10)
    self.buttonSizeDirty               = true

    self.lastWindowX, self.lastWindowY = self.newX, self.newY
    self.lastWindowWidth               = self.newWidth
    self.lastWindowHeight              = self.newHeight
    btnUtils.Debug("\agWindow(%d: %s) config set!", self.id, tostring(self))
end

function ezimHotbarClass:GiveTime()
    local now = os.clock()

    -- update every visible button to save on our FPS.
    if not ezimSettings:GetCharacterWindow(self.id).FPS then
        ezimSettings:GetCharacterWindow(self.id).FPS = 0
        ezimSettings:SaveSettings(true)
    end

    local fps = ezimSettings:GetCharacterWindow(self.id).FPS / 10

    if now - self.lastFrameTime < fps then return end
    self.lastFrameTime = now

    for i, set in ipairs(ezimSettings:GetCharacterWindowSets(self.id)) do
        if self.currentSelectedSet == i then
            --btnUtils.Debug("Caching Visibile Buttons for Set: %s / %d", set, i)
            local renderButtonCount = self.visibleButtonCount

            for ButtonIndex = 1, renderButtonCount do
                local button = ezimSettings:GetButtonBySetIndex(set, ButtonIndex)

                ezimButtonHandlers.EvaluateAndCache(button)
            end
        end
    end

    local config = ezimSettings:GetCharacterWindow(self.id)

    if config then
        if self.setupComplete and not EZIMUpdateSettings then -- wont have valid positions until the render loop has run once.
            if not config.Pos or (config.Pos.x ~= self.lastWindowX or config.Pos.y ~= self.lastWindowY) or config.Height ~= self.lastWindowHeight or config.Width ~= self.lastWindowWidth then
                config.Pos    = config.Pos or {}
                config.Pos.x  = self.lastWindowX
                config.Pos.y  = self.lastWindowY
                config.Height = self.lastWindowHeight
                config.Width  = self.lastWindowWidth
                ezimSettings:SaveSettings(true)
            end
        end
    else
        btnUtils.Output("\ayError: No config found for bar: %d", self.id)
    end
end

return ezimHotbarClass
