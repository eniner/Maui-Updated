local mq                 = require('mq')
local btnUtils           = require('lib.buttonUtils')

-- Icon Rendering
local animItems          = mq.FindTextureAnimation("A_DragItem")
local animSpellIcons     = mq.FindTextureAnimation('A_SpellIcons')

---@class ezimButtonHandlers
local ezimButtonHandlers   = {}
ezimButtonHandlers.__index = ezimButtonHandlers

function ezimButtonHandlers.GetTimeMS()
    return mq.gettime() / 1000
end

---@param Button table # EZIMButtonConfig
function ezimButtonHandlers.ExportButtonToClipBoard(Button)
    local sharableButton = { Type = "Button", Button = Button, }
    ImGui.SetClipboardText(btnUtils.encodeTable(sharableButton))
    btnUtils.Output("Button: '%s' has been copied to your clipboard!", Button.Label)
    local printableButton = btnUtils.dumpTable(sharableButton):gsub("\n/", "\\n/")
    btnUtils.Output('\n' .. printableButton)
end

function ezimButtonHandlers:ExportSetToClipBoard(setKey)
    local sharableSet = { Type = "Set", Key = setKey, Set = {}, Buttons = {}, }
    for index, btnName in pairs(ezimSettings:GetSettings().Sets[setKey]) do
        sharableSet.Set[index] = btnName
    end
    for _, buttonKey in pairs(ezimSettings:GetSettings().Sets[setKey] or {}) do
        sharableSet.Buttons[buttonKey] = ezimSettings:GetSettings().Buttons[buttonKey]
    end
    ImGui.SetClipboardText(btnUtils.encodeTable(sharableSet))
end

---@param Button table # EZIMButtonConfig
---@return integer, integer, boolean #CountDown, CooldownTimer, Toggle Locked
function ezimButtonHandlers.GetButtonCooldown(Button, cacheUpdate)
    if not cacheUpdate and Button.CachedCountDown ~= nil and Button.CachedCoolDownTimer ~= nil and Button.CachedToggleLocked ~= nil then
        return Button.CachedCountDown, Button.CachedCoolDownTimer, Button.CachedToggleLocked
    end

    Button.CachedCountDown     = 0
    Button.CachedCoolDownTimer = 0
    Button.CachedToggleLocked  = false
    Button.CachedLastRan       = ezimButtonHandlers.GetTimeMS()

    if Button.TimerType == "Custom Lua" then
        local success
        local result

        if Button.Timer and Button.Timer:len() > 0 then
            success, result = btnUtils.EvaluateLua(Button.Timer)
            if not success then
                btnUtils.Output("Failed to run Timer for Button(%s): %s", Button.Label, Button.Timer)
                btnUtils.Output("RunEnv was:\n%s", Button.Timer)
                Button.CachedCountDown = 0
            else
                Button.CachedCountDown = tonumber(result) or 0
            end
        end
        if Button.Cooldown and Button.Cooldown:len() > 0 then
            success, result = btnUtils.EvaluateLua(Button.Cooldown)
            if not success then
                btnUtils.Output("Failed to run Cooldown for Button(%s): %s", Button.Label, Button.Cooldown)
                btnUtils.Output("RunEnv was:\n%s", Button.Cooldown)
                Button.CachedCoolDownTimer = 0
            else
                Button.CachedCoolDownTimer = tonumber(result) or 0
            end
        end
        if Button.ToggleCheck and Button.ToggleCheck:len() > 0 then
            success, result = btnUtils.EvaluateLua(Button.ToggleCheck)
            if not success then
                btnUtils.Output("Failed to run ToggleCheck for Button(%s): %s", Button.Label, Button.ToggleCheck)
                btnUtils.Output("RunEnv was:\n%s", Button.ToggleCheck)
                Button.CachedToggleLocked = false
            else
                Button.CachedToggleLocked = type(result) == 'boolean' and result or false
            end
        end
    elseif Button.TimerType == "Seconds Timer" then
        if Button.CooldownTimer then
            Button.CachedCountDown = Button.CooldownTimer - ezimButtonHandlers.GetTimeMS()
            if Button.CachedCountDown <= 0 or Button.CachedCountDown > Button.CooldownTimer then
                Button.CooldownTimer = nil
                return 0, 0, false
            end
            Button.CachedCoolDownTimer = Button.Cooldown
        end
    elseif Button.TimerType == "Item" then
        Button.CachedCountDown = mq.TLO.FindItem(Button.Cooldown).TimerReady() or 0
        Button.CachedCoolDownTimer = mq.TLO.FindItem(Button.Cooldown).Clicky.TimerID() or 0
    elseif Button.TimerType == "Spell Gem" then
        Button.CachedCountDown = (mq.TLO.Me.GemTimer(Button.Cooldown)() or 0) / 1000
        Button.CachedCoolDownTimer = (mq.TLO.Me.Gem(Button.Cooldown).RecastTime() or 0) / 1000
    elseif Button.TimerType == "AA" then
        Button.CachedCountDown = (mq.TLO.Me.AltAbilityTimer(Button.Cooldown)() or 0) / 1000
        Button.CachedCoolDownTimer = mq.TLO.Me.AltAbility(Button.Cooldown).MyReuseTime() or 0
    elseif Button.TimerType == "Disc" then
        Button.CachedCountDown = mq.TLO.Me.CombatAbilityTimer(Button.Cooldown).TotalSeconds() or 0
        Button.CachedCoolDownTimer = (mq.TLO.Spell(Button.Cooldown).RecastTime() or 0) / 1000
    elseif Button.TimerType == "Ability" then
        if mq.TLO.Me.AbilityTimer and mq.TLO.Me.AbilityTimerTotal then
            Button.CachedCountDown = (mq.TLO.Me.AbilityTimer(Button.Cooldown)() or 0) / 1000
            Button.CachedCoolDownTimer = (mq.TLO.Me.AbilityTimerTotal(Button.Cooldown)() or 0) / 1000
        end
    end

    return Button.CachedCountDown, Button.CachedCoolDownTimer, Button.CachedToggleLocked
end

---@param Button table # EZIMButtonConfig
---@param cursorScreenPos table # cursor position on screen
---@param size number # button size
function ezimButtonHandlers.RenderButtonCooldown(Button, cursorScreenPos, size)
    local currentTimer = ezimButtonHandlers.GetTimeMS()
    local updateRate = Button.UpdateRate or 0

    local updateCache = (Button.CachedLastRan == nil or ((currentTimer - Button.CachedLastRan) > updateRate) or ((currentTimer - Button.CachedLastRan) < 0))
    local countDown, coolDowntimer, toggleLocked = ezimButtonHandlers.GetButtonCooldown(Button, updateCache)

    if coolDowntimer == 0 and not toggleLocked then return end

    local ratio = 1 - (countDown / (coolDowntimer))

    if toggleLocked then
        ratio = 100
    end

    local start_angle = (1.5 * math.pi)
    local end_angle = math.pi * ((2 * ratio) - 0.5)
    local center = ImVec2(cursorScreenPos.x + (size / 2), cursorScreenPos.y + (size / 2))

    local draw_list = ImGui.GetWindowDrawList()
    draw_list:PushClipRect(cursorScreenPos, ImVec2(cursorScreenPos.x + size, cursorScreenPos.y + size), true)
    draw_list:PathLineTo(center)
    draw_list:PathArcTo(center, size, start_angle, end_angle, 0)
    draw_list:PathFillConvex(ImGui.GetColorU32(0.8, 0.02, 0.02, 0.75))
    draw_list:PopClipRect()
end

---@param Button table # EZIMButtonConfig
---@param cursorScreenPos ImVec2 # cursor position on screen
---@param size number # button size
function ezimButtonHandlers.RenderButtonIcon(Button, cursorScreenPos, size)
    if not Button.Icon and (not Button.IconLua or Button.IconLua:len() == 0) then
        return ezimButtonHandlers.RenderButtonRect(Button, cursorScreenPos, size, 255)
    end

    local draw_list = ImGui.GetWindowDrawList()

    local iconId = Button.Icon
    local iconType = Button.IconType

    if Button.IconLua and Button.IconLua:len() > 0 then
        local success
        success, iconId, iconType = btnUtils.EvaluateLua(Button.IconLua)
        if not success then
            btnUtils.Debug("Failed to evaluate IconLua: %s\nError:\n%s", Button.IconLua, iconId)
            iconId = Button.Icon
            iconType = Button.IconType
        end
    end

    local renderIconAnim = animItems
    if iconType == nil or iconType == "Spell" then
        animSpellIcons:SetTextureCell(tonumber(iconId) or 0)
        renderIconAnim = animSpellIcons
    else
        animItems:SetTextureCell(tonumber(iconId) or 0)
    end

    draw_list:AddTextureAnimation(renderIconAnim, cursorScreenPos, ImVec2(size, size))
end

---@param Button table # EZIMButtonConfig
---@param cursorScreenPos ImVec2 # cursor position on screen
---@param size number # button size
---@param alpha number # button alpha color
function ezimButtonHandlers.RenderButtonRect(Button, cursorScreenPos, size, alpha)
    local draw_list = ImGui.GetWindowDrawList()
    local buttonStyle = ImGui.GetStyleColorVec4(ImGuiCol.Button)
    local Colors = btnUtils.split(Button.ButtonColorRGB, ",")
    local buttonBGCol = IM_COL32(tonumber(Colors[1]) or math.floor(buttonStyle.x * 255),
        tonumber(Colors[2]) or math.floor(buttonStyle.y * 255),
        tonumber(Colors[3]) or math.floor(buttonStyle.z * 255),
        #Colors == 0 and math.floor(buttonStyle.w * 255) or alpha)

    draw_list:AddRectFilled(cursorScreenPos, ImVec2(cursorScreenPos.x + size, cursorScreenPos.y + size), buttonBGCol)
end

---@param Button table # EZIMButtonConfig
---@param label string
---@param subText string?
function ezimButtonHandlers.RenderButtonTooltip(Button, label, subText)
    -- hover tooltip
    if Button.Unassigned == nil and ImGui.IsItemHovered() then
        local tooltipText = label

        -- check label instead of tooltipText because if there is no text we dont care about the timer.
        if label:len() > 0 then
            local countDown, _ = ezimButtonHandlers.GetButtonCooldown(Button)
            if countDown ~= 0 then
                tooltipText = tooltipText .. "\n\n" .. btnUtils.FormatTime(math.ceil(countDown))
            end

            ImGui.BeginTooltip()
            ImGui.Text(tooltipText)
            if subText then
                ImGui.Separator()
                ImGui.Text(subText)
            end
            ImGui.EndTooltip()
        end
    end
end

---@param Button table # EZIMButtonConfig
---@param cursorScreenPos ImVec2 # cursor position on screen
---@param size number # button size
---@param label string
function ezimButtonHandlers.RenderButtonLabel(Button, cursorScreenPos, size, label)
    local Colors = btnUtils.split(Button.TextColorRGB, ",")
    local buttonLabelCol = IM_COL32(tonumber(Colors[1]) or 255, tonumber(Colors[2]) or 255, tonumber(Colors[3]) or 255, 255)
    local draw_list = ImGui.GetWindowDrawList()

    ezimButtonHandlers.CalcButtonTextPos(Button, size)

    draw_list:PushClipRect(cursorScreenPos, ImVec2(cursorScreenPos.x + size, cursorScreenPos.y + size), true)
    draw_list:AddText(ImVec2(cursorScreenPos.x + (Button.labelMidX or 0), cursorScreenPos.y + (Button.labelMidY or 0)), buttonLabelCol, label)
    draw_list:PopClipRect()
end

---@param cursorScreenPos ImVec2 # cursor position on screen
---@param text string
function ezimButtonHandlers.RenderButtonDebugText(cursorScreenPos, text)
    local buttonLabelCol = IM_COL32(255, 0, 0, 255)
    local draw_list = ImGui.GetWindowDrawList()

    draw_list:AddText(ImVec2(cursorScreenPos.x, cursorScreenPos.y), buttonLabelCol, text)
end

---@param Button table # EZIMButtonConfig
---@param leaveSpaces boolean? # leave spaces or replace with new line.
function ezimButtonHandlers.ResolveButtonLabel(Button, leaveSpaces, cacheUpdate)
    if not cacheUpdate and Button.CachedLabel ~= nil then
        return leaveSpaces and Button.CachedLabel or Button.CachedLabel:gsub(" ", "\n")
    end
    local success = true
    local evaluatedLabel = Button.Label

    if Button.EvaluateLabel then
        success, evaluatedLabel = btnUtils.EvaluateLua(Button.Label)
        if not success then
            btnUtils.Debug("Failed to evaluate Button Label:\n%s\nError:\n%s", Button.Label, evaluatedLabel)
        end
    end
    evaluatedLabel = tostring(evaluatedLabel)

    Button.CachedLabel = evaluatedLabel

    return leaveSpaces and Button.CachedLabel or Button.CachedLabel:gsub(" ", "\n")
end

function ezimButtonHandlers.CalcButtonTextPos(Button, size)
    local label_x, label_y = ImGui.CalcTextSize(ezimButtonHandlers.ResolveButtonLabel(Button, false))
    local midX, midY = math.max(math.floor((size - label_x) / 2), 0), math.floor((size - label_y) / 2)
    if midX ~= Button.labelMidX or midY ~= Button.labelMidY then
        Button.labelMidX, Button.labelMidY = midX, midY
    end
end

---@param Button table # EZIMButtonConfig
---@param size number # size to render the button as
---@param renderLabel boolean # render the label on top or not
---@param fontScale number # Font scale for text
---@param advTooltips boolean # enable advanced tooltips6
---@return boolean # clicked
function ezimButtonHandlers.Render(Button, size, renderLabel, fontScale, advTooltips)
    local evaluatedLabel = ezimButtonHandlers.ResolveButtonLabel(Button) or ""
    local clicked = false
    local startTimeMS = os.clock() * 1000
    local cursorScreenPos = ImGui.GetCursorScreenPosVec()

    ezimButtonHandlers.RenderButtonIcon(Button, cursorScreenPos, size)
    clicked = ImGui.Selectable('', false, ImGuiSelectableFlags.DontClosePopups, size, size)
    if ImGui.IsItemHovered() then
        ezimButtonHandlers.RenderButtonRect(Button, cursorScreenPos, size, 200)
    end

    ezimButtonHandlers.RenderButtonCooldown(Button, cursorScreenPos, size)

    -- label and tooltip
    ImGui.SetWindowFontScale(fontScale)
    if renderLabel then
        ezimButtonHandlers.RenderButtonLabel(Button, cursorScreenPos, size, evaluatedLabel)
    end
    ezimButtonHandlers.RenderButtonTooltip(Button, evaluatedLabel, advTooltips and (Button.Cmd or nil) or nil)
    ImGui.SetWindowFontScale(1)


    local endTimeMS = os.clock() * 1000

    local renderTimeMS = math.ceil(endTimeMS - startTimeMS)

    if btnUtils.enableDebug then
        if Button.highestRenderTime == nil or renderTimeMS > Button.highestRenderTime then Button.highestRenderTime = renderTimeMS end
        ImGui.SetWindowFontScale(0.8)
        ezimButtonHandlers.RenderButtonDebugText(cursorScreenPos, tostring(Button.highestRenderTime))
        ezimButtonHandlers.RenderButtonDebugText(ImVec2(cursorScreenPos.x, cursorScreenPos.y + 10), string.format("%d,%d", Button.labelMidX, Button.labelMidY))
        ImGui.SetWindowFontScale(1)
    end

    return clicked
end

function ezimButtonHandlers.FireTimer(Button)
    if Button.TimerType == "Seconds Timer" then
        Button.CooldownTimer = ezimButtonHandlers.GetTimeMS() + Button.Cooldown
    end
end

function ezimButtonHandlers.EvaluateAndCache(Button)
    ezimButtonHandlers.ResolveButtonLabel(Button, false, true)
end

---@param Button table # EZIMButtonConfig
function ezimButtonHandlers.Exec(Button)
    if Button.Cmd then
        if Button.Cmd:find("^--[ ]?lua") == nil then
            local cmds = btnUtils.split(Button.Cmd, "\n")
            for i, c in ipairs(cmds) do
                if c:len() > 0 and c:find('^#') == nil and c:find('^[-]+') == nil and c:find('^|') == nil then
                    if c:find('^/') then
                        -- don't use cmdf here because users might have %'s in their commands.
                        mq.cmd(c)
                    else
                        btnUtils.Output('\arInvalid command on Line %d : \ax%s', i, c)
                    end
                else
                    btnUtils.Debug("Ignored: %s", c)
                end
            end
        else
            btnUtils.EvaluateLua(Button.Cmd)
        end
        ezimButtonHandlers.FireTimer(Button)
    end
end

return ezimButtonHandlers
