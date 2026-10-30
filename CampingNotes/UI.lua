-- Camping Notes, part 3 of 3 (UI.lua).
--
-- Draws three things:
--   * a round minimap button (Tyrion the corgi) that opens settings
--   * the settings window (scale, opacity, lock, when Tyrion is shown)
--   * Tyrion again. By default he appears only during Welcoming Campfire.
--     Unlock him in settings to drag him anywhere on the UI.

local ICON = CampingNotes.ICON
local syncing = false
local indicator
local timerText
local backdropPlate
local unlockGlow
local iconDragged = false

-- A texture is a picture painted on a frame. SetTexture takes the
-- path from Core.lua, with no .tga on the end.

local function ApplyBackdrop(frame, info)
    -- BackdropTemplate is the modern way to give a frame a border.
    -- Pass that template only when its mixin exists. Older clients
    -- have SetBackdrop on every frame and no mixin at all.
    if type(frame.SetBackdrop) == "function" then
        frame:SetBackdrop(info)
        return true
    end
    return false
end

local function NewDecoratedFrame(name, parent)
    if BackdropTemplateMixin then
        return CreateFrame("Frame", name, parent, "BackdropTemplate")
    end
    return CreateFrame("Frame", name, parent)
end

-- ============================================================
-- HOW WE NOTICE THE CAMPFIRE
-- ============================================================
--
-- Welcoming Campfire is a buff you gain by sitting near a campfire.
-- Wowhead lists it as a 1-minute effect, spell ids 1289723 and 1229739.
--
-- UNIT_AURA is the message the game sends when a buff or debuff
-- changes on a unit. We only care about the player. UnitBuff walks
-- the player's buffs one index at a time until it returns nothing.
--
-- The English name is "Welcoming Campfire". Some clients also return
-- a spell id, but not always, and not always in the same slot. We
-- accept the name, or either spell id, wherever it shows up.
-- If UnitBuff is missing (possible on Forever's modern UI), we try
-- C_UnitAuras.GetBuffDataByIndex, and only if that function exists.

local CAMPFIRE_NAME = "welcoming campfire"
local CAMPFIRE_IDS = {
    [1289723] = true,
    [1229739] = true,
}

local function ReadPlayerBuff(index)
    if type(UnitBuff) == "function" then
        return UnitBuff("player", index)
    end
    if type(C_UnitAuras) == "table" and type(C_UnitAuras.GetBuffDataByIndex) == "function" then
        local aura = C_UnitAuras.GetBuffDataByIndex("player", index)
        if type(aura) ~= "table" then
            return nil
        end
        return aura.name, aura.icon, aura.applications, aura.dispelName, aura.duration, aura.expirationTime, aura.sourceUnit, aura.isStealable, aura.nameplateShowPersonal, aura.spellId
    end
    return nil
end

local function RemainingSeconds(...)
    if type(GetTime) ~= "function" then
        return true
    end
    local now = GetTime()
    local best = nil
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        -- Spell ids are large integers too, so skip the two campfire ids.
        if type(value) == "number" and not CAMPFIRE_IDS[value] and value > now and (value - now) <= 120 then
            local remain = value - now
            if not best or remain < best then
                best = remain
            end
        end
    end
    if best then
        return best
    end
    -- The buff is up, but this client did not give us an end time.
    return true
end

-- nil: buff is absent.
-- number: seconds left.
-- true: buff is present, with no usable timer.
function CampingNotes.WelcomingCampfireRemaining()
    for index = 1, 40 do
        -- Up to 12 returns. Older UnitBuff puts the spell id late, after
        -- rank and a few flags. Newer UnitBuff, and the C_UnitAuras
        -- fallback above, put it earlier. Scanning every return covers both.
        local r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12 = ReadPlayerBuff(index)
        -- Do not use the length operator here. A nil in the middle of
        -- UnitBuff's returns (a missing rank, for example) would hide
        -- every value after it, including the spell id.
        local fields = { r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12 }
        local any = false
        for i = 1, 12 do
            if fields[i] ~= nil then
                any = true
                break
            end
        end
        if not any then
            return nil
        end
        local matched = false
        if type(r1) == "string" and string.lower(r1) == CAMPFIRE_NAME then
            matched = true
        end
        if not matched then
            for i = 1, 12 do
                if CAMPFIRE_IDS[fields[i]] then
                    matched = true
                    break
                end
            end
        end
        if matched then
            return RemainingSeconds(r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12)
        end
    end
    return nil
end

local function UpdateIndicator()
    if not indicator then
        return
    end
    local remain = CampingNotes.WelcomingCampfireRemaining()
    local settings = CampingNotes.GetSettings()
    -- onlyWithBuff defaults to on. False means "show Tyrion all the time".
    local onlyWithBuff = settings.onlyWithBuff ~= false
    CampingNotes.ApplyIndicatorSettings()
    if onlyWithBuff and remain == nil then
        indicator:Hide()
        return
    end
    indicator:Show()
    if timerText then
        if type(remain) == "number" then
            local seconds = math.ceil(remain)
            if seconds < 0 then
                seconds = 0
            end
            timerText:SetText(seconds .. "s")
        else
            timerText:SetText("")
        end
    end
end

local function OnAura(unit, eventName)
    -- UNIT_AURA's first argument is the unit. Ignore everyone but us.
    -- PLAYER_ENTERING_WORLD's arguments are login flags, not a unit, so
    -- that event always scans.
    if eventName == "UNIT_AURA" and unit and unit ~= "player" then
        return
    end
    UpdateIndicator()
end

-- ============================================================
-- Tyrion, the camping indicator
-- ============================================================

local function SaveIndicatorPosition()
    if not indicator or not CampingNotes.IsReady() then
        return
    end
    local point, _, relPoint, x, y = indicator:GetPoint(1)
    if type(point) ~= "string" then
        return
    end
    local pos = CampingNotesDB.indicator
    pos.point = point
    pos.relPoint = relPoint or point
    pos.x = x or 0
    pos.y = y or 0
end

local function PlaceIndicator()
    local pos = CampingNotes.defaults.indicator
    if CampingNotes.IsReady() and type(CampingNotesDB.indicator) == "table" then
        pos = CampingNotesDB.indicator
    end
    indicator:ClearAllPoints()
    indicator:SetPoint(pos.point or "CENTER", UIParent, pos.relPoint or "CENTER", pos.x or 0, pos.y or 90)
end

function CampingNotes.ResetIndicatorPosition()
    if not indicator then
        return
    end
    local defaults = CampingNotes.defaults.indicator
    if CampingNotes.IsReady() and type(CampingNotesDB.indicator) == "table" then
        local pos = CampingNotesDB.indicator
        pos.point = defaults.point
        pos.relPoint = defaults.relPoint
        pos.x = defaults.x
        pos.y = defaults.y
    end
    PlaceIndicator()
end

function CampingNotes.ApplyIndicatorSettings()
    if not indicator then
        return
    end
    local settings = CampingNotes.GetSettings()
    local scale = settings.scale
    local opacity = settings.opacity
    if type(scale) ~= "number" then
        scale = 1
    end
    if type(opacity) ~= "number" then
        opacity = 1
    end
    indicator:SetScale(scale)
    indicator:SetAlpha(opacity)
    if backdropPlate then
        if settings.backdrop then
            backdropPlate:Show()
        else
            backdropPlate:Hide()
        end
    end
    -- A faint ring while Unlock icon is checked, so it is obvious Tyrion
    -- can be dragged. Locked, the ring stays hidden.
    if unlockGlow then
        if settings.unlocked then
            unlockGlow:Show()
        else
            unlockGlow:Hide()
        end
    end
end

local function CreateIndicator()
    indicator = CreateFrame("Frame", "CampingNotesIndicator", UIParent)
    indicator:SetSize(64, 64)
    indicator:SetFrameStrata("MEDIUM")
    indicator:SetMovable(true)
    indicator:EnableMouse(true)
    indicator:RegisterForDrag("LeftButton")
    if indicator.SetClampedToScreen then
        indicator:SetClampedToScreen(true)
    end
    indicator:Hide()

    -- A dark plate behind Tyrion. The settings checkbox shows or hides it.
    backdropPlate = indicator:CreateTexture(nil, "BACKGROUND")
    backdropPlate:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
    backdropPlate:SetSize(72, 72)
    backdropPlate:SetPoint("CENTER")
    backdropPlate:SetVertexColor(0, 0, 0, 0.55)

    local tyrion = indicator:CreateTexture(nil, "ARTWORK")
    tyrion:SetAllPoints()
    tyrion:SetTexture(ICON)

    -- Drawn under the corgi picture, larger than the icon, so the face
    -- stays clear and a pale edge shows that he is unlocked.
    unlockGlow = indicator:CreateTexture(nil, "BORDER")
    unlockGlow:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
    unlockGlow:SetSize(84, 84)
    unlockGlow:SetPoint("CENTER")
    unlockGlow:SetVertexColor(1, 0.9, 0.45, 0.4)
    unlockGlow:Hide()

    timerText = indicator:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timerText:SetPoint("TOP", indicator, "BOTTOM", 0, -2)
    timerText:SetText("")

    -- Anywhere on the UI: the position is saved in CampingNotesDB.
    -- Default is slightly above the center of the screen. Check Unlock
    -- icon in settings to drag him. Anchoring Tyrion over your
    -- character's head (a nameplate) is a possible future experiment,
    -- and it is not done here.
    PlaceIndicator()

    indicator:SetScript("OnDragStart", function(self)
        if not CampingNotes.GetSettings().unlocked then
            return
        end
        iconDragged = true
        self:StartMoving()
    end)
    indicator:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if CampingNotes.GetSettings().unlocked then
            SaveIndicatorPosition()
        end
    end)
    -- Locked: a click opens Camp Notes. Unlocked: a click is for dragging,
    -- and a finished drag must not also open the panel.
    indicator:SetScript("OnMouseUp", function(self, button)
        if iconDragged then
            iconDragged = false
            return
        end
        if CampingNotes.GetSettings().unlocked then
            return
        end
        if button == "LeftButton" or button == nil then
            CampingNotes.ToggleCampNotes()
        end
    end)
    -- OnUpdate runs while the frame is shown. It ticks the countdown
    -- and hides Tyrion when the buff falls off, even if UNIT_AURA is late.
    indicator.tick = 0
    indicator:SetScript("OnUpdate", function(self, elapsed)
        local step = 0.25
        if type(elapsed) == "number" then
            self.tick = self.tick + elapsed
        else
            self.tick = step
        end
        if self.tick < step then
            return
        end
        self.tick = 0
        UpdateIndicator()
    end)
end

-- ============================================================
-- Minimap button
-- ============================================================

local minimapButton

local function MinimapRadius()
    local width = 140
    if Minimap and Minimap.GetWidth then
        local value = Minimap:GetWidth()
        if type(value) == "number" and value > 0 then
            width = value
        end
    end
    return (width / 2) + 5
end

local function PlaceMinimapButton(angle)
    if not minimapButton or not Minimap then
        return
    end
    if type(angle) ~= "number" then
        angle = CampingNotes.defaults.minimap.angle
    end
    local rad = math.rad(angle)
    local radius = MinimapRadius()
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * radius, math.sin(rad) * radius)
end

local function CursorAngle()
    if type(GetCursorPosition) ~= "function" or not Minimap or not Minimap.GetCenter then
        return nil
    end
    local cx, cy = GetCursorPosition()
    local scale = 1
    if Minimap.GetEffectiveScale then
        scale = Minimap:GetEffectiveScale()
    elseif UIParent and UIParent.GetEffectiveScale then
        scale = UIParent:GetEffectiveScale()
    end
    if type(scale) ~= "number" or scale <= 0 then
        scale = 1
    end
    cx = cx / scale
    cy = cy / scale
    local mx, my = Minimap:GetCenter()
    if type(mx) ~= "number" or type(my) ~= "number" then
        return nil
    end
    return math.deg(math.atan2(cy - my, cx - mx))
end

local function CreateMinimapButton()
    if not Minimap then
        return
    end
    local dragged = false
    minimapButton = CreateFrame("Button", "CampingNotesMinimapButton", Minimap)
    minimapButton:SetSize(31, 31)
    minimapButton:SetFrameStrata("MEDIUM")
    if minimapButton.SetFrameLevel and Minimap.GetFrameLevel then
        minimapButton:SetFrameLevel(Minimap:GetFrameLevel() + 5)
    end
    minimapButton:EnableMouse(true)
    minimapButton:RegisterForClicks("LeftButtonUp")
    minimapButton:RegisterForDrag("LeftButton")

    local icon = minimapButton:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture(ICON)
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)

    local border = minimapButton:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT")

    if minimapButton.SetHighlightTexture then
        minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    end

    PlaceMinimapButton(CampingNotes.defaults.minimap.angle)

    minimapButton:SetScript("OnDragStart", function(self)
        dragged = true
        self:SetScript("OnUpdate", function()
            local angle = CursorAngle()
            if not angle then
                return
            end
            if CampingNotes.IsReady() then
                CampingNotesDB.minimap.angle = angle
            end
            PlaceMinimapButton(angle)
        end)
    end)
    minimapButton:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    minimapButton:SetScript("OnClick", function(_, button)
        if dragged then
            dragged = false
            return
        end
        if button == "LeftButton" or button == nil then
            CampingNotes.ToggleSettings()
        end
    end)
    minimapButton:SetScript("OnEnter", function(self)
        if not GameTooltip or not GameTooltip.SetOwner then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Camping Notes")
        GameTooltip:AddLine("Click to open settings", 0.9, 0.9, 0.9)
        GameTooltip:Show()
    end)
    minimapButton:SetScript("OnLeave", function()
        if GameTooltip and GameTooltip.Hide then
            GameTooltip:Hide()
        end
    end)
end

-- ============================================================
-- Settings window
-- ============================================================
--
-- A slider is a bar you drag to pick a number between two ends.
-- A checkbox is a box that is on or off. Both write into
-- CampingNotesDB.settings, which Core.lua fills with defaults.

local settingsFrame
local scaleSlider
local opacitySlider
local backdropBox
local rarityBox
local unlockBox
local onlyBuffBox

local function Checked(box)
    local value = box:GetChecked()
    return value == true or value == 1
end

local function MakeSlider(parent, caption, minValue, maxValue, step, key, y)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", 28, y)
    label:SetText(caption)

    local slider = CreateFrame("Slider", nil, parent)
    slider:SetPoint("TOPLEFT", 28, y - 18)
    slider:SetSize(200, 18)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(minValue, maxValue)
    if slider.SetValueStep then
        slider:SetValueStep(step)
    end
    if slider.SetObeyStepOnDrag then
        slider:SetObeyStepOnDrag(true)
    end
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    thumb:SetSize(24, 24)
    if slider.SetThumbTexture then
        slider:SetThumbTexture(thumb)
    end
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetTexture("Interface\\Buttons\\UI-SliderBar-Background")
    track:SetPoint("LEFT", slider, "LEFT", 0, 0)
    track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
    track:SetHeight(8)

    local function ShowValue(value)
        if type(value) ~= "number" then
            value = minValue
        end
        label:SetText(caption .. ": " .. string.format("%.2f", value))
    end

    slider:SetScript("OnValueChanged", function(self, value)
        if type(value) ~= "number" then
            value = self:GetValue()
        end
        ShowValue(value)
        if syncing or not CampingNotes.IsReady() then
            return
        end
        CampingNotesDB.settings[key] = value
        CampingNotes.ApplyIndicatorSettings()
    end)
    slider.ShowValue = ShowValue
    return slider
end

local function MakeCheck(parent, caption, key, y)
    local box = CreateFrame("CheckButton", nil, parent)
    box:SetSize(24, 24)
    box:SetPoint("TOPLEFT", 24, y)
    box:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    box:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    box:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
    box:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    local label = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", box, "RIGHT", 4, 0)
    label:SetText(caption)
    box:SetScript("OnClick", function(self)
        if syncing or not CampingNotes.IsReady() then
            return
        end
        CampingNotesDB.settings[key] = Checked(self)
        UpdateIndicator()
    end)
    return box
end

local function SyncSettingsWidgets()
    if not settingsFrame then
        return
    end
    local settings = CampingNotes.GetSettings()
    syncing = true
    scaleSlider:SetValue(settings.scale or 1)
    opacitySlider:SetValue(settings.opacity or 1)
    backdropBox:SetChecked(settings.backdrop and true or false)
    rarityBox:SetChecked(settings.colorByRarity ~= false)
    unlockBox:SetChecked(settings.unlocked and true or false)
    onlyBuffBox:SetChecked(settings.onlyWithBuff ~= false)
    syncing = false
    CampingNotes.ApplyIndicatorSettings()
end

function CampingNotes.ShowSettings()
    if not settingsFrame then
        return
    end
    SyncSettingsWidgets()
    settingsFrame:Show()
    if settingsFrame.Raise then
        settingsFrame:Raise()
    end
end

function CampingNotes.ToggleSettings()
    if not settingsFrame then
        return
    end
    if settingsFrame:IsShown() then
        settingsFrame:Hide()
    else
        CampingNotes.ShowSettings()
    end
end

-- ============================================================
-- Camp Notes panel
-- ============================================================
--
-- Clicking locked Tyrion opens this. Later it will list loot notes
-- shared by other players at the campfire. Sharing is not built yet,
-- so the first line says so. Under that, a short list of your own
-- most-looted mobs is shown from the notebook you already keep.

local notesFrame
local notesLines = {}

-- Camp notes reuse the bestiary reader, then pick the busiest mobs.
-- That reader is the one place shared notes will be merged later.
local function OwnTopMobs(limit)
    local entries = CampingNotes.BestiaryEntries()
    table.sort(entries, function(a, b)
        if a.loots ~= b.loots then
            return a.loots > b.loots
        end
        return string.lower(a.name) < string.lower(b.name)
    end)
    local found = {}
    for i = 1, #entries do
        if i > limit then
            break
        end
        local entry = entries[i]
        local item = entry.drops[1] and entry.drops[1].name or nil
        found[#found + 1] = { name = entry.name, loots = entry.loots, item = item }
    end
    return found
end

local function RefreshCampNotes()
    if not notesLines[1] then
        return
    end
    notesLines[1]:SetText("No notes from other campers yet")
    local rows = OwnTopMobs(5)
    if #rows == 0 then
        notesLines[2]:SetText("")
        for i = 1, 5 do
            notesLines[i + 2]:SetText("")
        end
        return
    end
    notesLines[2]:SetText("Your notes:")
    for i = 1, 5 do
        local row = rows[i]
        if row then
            local text = row.name .. " (" .. row.loots .. " loots)"
            if row.item then
                text = text .. " - " .. row.item
            end
            notesLines[i + 2]:SetText(text)
        else
            notesLines[i + 2]:SetText("")
        end
    end
end

local function AddEscapeClose(frameName)
    if type(UISpecialFrames) ~= "table" then
        return
    end
    for i = 1, #UISpecialFrames do
        if UISpecialFrames[i] == frameName then
            return
        end
    end
    table.insert(UISpecialFrames, frameName)
end

function CampingNotes.ToggleCampNotes()
    if not notesFrame then
        return
    end
    if notesFrame:IsShown() then
        notesFrame:Hide()
    else
        RefreshCampNotes()
        notesFrame:Show()
        if notesFrame.Raise then
            notesFrame:Raise()
        end
    end
end

local function CreateCampNotes()
    notesFrame = NewDecoratedFrame("CampingNotesCampPanel", UIParent)
    notesFrame:SetSize(340, 240)
    notesFrame:SetPoint("CENTER", UIParent, "CENTER", 240, 0)
    notesFrame:SetFrameStrata("DIALOG")
    notesFrame:SetMovable(true)
    notesFrame:EnableMouse(true)
    notesFrame:RegisterForDrag("LeftButton")
    if notesFrame.SetClampedToScreen then
        notesFrame:SetClampedToScreen(true)
    end
    notesFrame:Hide()
    ApplyBackdrop(notesFrame, {
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })

    local title = notesFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("Camp Notes")

    local close = CreateFrame("Button", nil, notesFrame)
    close:SetSize(28, 28)
    close:SetPoint("TOPRIGHT", -10, -10)
    local closeText = close:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    closeText:SetPoint("CENTER")
    closeText:SetText("X")
    close:SetScript("OnClick", function()
        notesFrame:Hide()
    end)

    for i = 1, 7 do
        local line = notesFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        line:SetPoint("TOPLEFT", 20, -46 - ((i - 1) * 22))
        line:SetWidth(300)
        if line.SetJustifyH then
            line:SetJustifyH("LEFT")
        end
        line:SetText("")
        notesLines[i] = line
    end
    if notesLines[1].SetTextColor then
        notesLines[1]:SetTextColor(0.7, 0.7, 0.7)
    end

    notesFrame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    notesFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)
    notesFrame:SetScript("OnShow", function()
        RefreshCampNotes()
    end)
    AddEscapeClose("CampingNotesCampPanel")
end

local function CreateSettings()
    settingsFrame = NewDecoratedFrame("CampingNotesSettings", UIParent)
    settingsFrame:SetSize(380, 430)
    settingsFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    settingsFrame:SetFrameStrata("DIALOG")
    settingsFrame:SetMovable(true)
    settingsFrame:EnableMouse(true)
    settingsFrame:RegisterForDrag("LeftButton")
    if settingsFrame.SetClampedToScreen then
        settingsFrame:SetClampedToScreen(true)
    end
    settingsFrame:Hide()

    ApplyBackdrop(settingsFrame, {
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })

    local title = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("Camping Notes")

    local subtitle = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOP", 0, -40)
    subtitle:SetWidth(300)
    subtitle:SetText("Unlock Tyrion to drag him anywhere on your UI. Lock him, then click him to open Camp Notes.")

    -- A plain X, so we do not depend on the UIPanelCloseButton template.
    local close = CreateFrame("Button", nil, settingsFrame)
    close:SetSize(28, 28)
    close:SetPoint("TOPRIGHT", -10, -10)
    local closeText = close:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    closeText:SetPoint("CENTER")
    closeText:SetText("X")
    close:SetScript("OnClick", function()
        settingsFrame:Hide()
    end)

    scaleSlider = MakeSlider(settingsFrame, "Scale", 0.5, 2, 0.05, "scale", -72)
    opacitySlider = MakeSlider(settingsFrame, "Opacity", 0.25, 1, 0.05, "opacity", -122)
    backdropBox = MakeCheck(settingsFrame, "Show backdrop behind Tyrion", "backdrop", -180)
    rarityBox = MakeCheck(settingsFrame, "Color item names by rarity", "colorByRarity", -210)
    unlockBox = MakeCheck(settingsFrame, "Unlock icon", "unlocked", -240)
    onlyBuffBox = MakeCheck(settingsFrame, "Show icon only during Welcoming Campfire", "onlyWithBuff", -270)

    local reset = CreateFrame("Button", nil, settingsFrame)
    reset:SetSize(160, 22)
    reset:SetPoint("TOPLEFT", 28, -308)
    local resetPlate = reset:CreateTexture(nil, "BACKGROUND")
    resetPlate:SetAllPoints()
    resetPlate:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
    resetPlate:SetVertexColor(0.15, 0.15, 0.15, 0.9)
    local resetText = reset:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    resetText:SetPoint("CENTER")
    resetText:SetText("Reset position")
    reset:SetScript("OnClick", function()
        CampingNotes.ResetIndicatorPosition()
    end)

    local bestiaryButton = CreateFrame("Button", nil, settingsFrame)
    bestiaryButton:SetSize(160, 22)
    bestiaryButton:SetPoint("LEFT", reset, "RIGHT", 12, 0)
    local bestiaryPlate = bestiaryButton:CreateTexture(nil, "BACKGROUND")
    bestiaryPlate:SetAllPoints()
    bestiaryPlate:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
    bestiaryPlate:SetVertexColor(0.15, 0.15, 0.15, 0.9)
    local bestiaryText = bestiaryButton:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    bestiaryText:SetPoint("CENTER")
    bestiaryText:SetText("Bestiary")
    bestiaryButton:SetScript("OnClick", function()
        if CampingNotes.ShowBestiary then
            CampingNotes.ShowBestiary()
        end
    end)

    local hint = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOM", 0, 16)
    hint:SetWidth(320)
    hint:SetText("Drag the round button around the minimap. Unlock icon lets you drag Tyrion.")

    settingsFrame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    settingsFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)
    settingsFrame:SetScript("OnShow", function()
        SyncSettingsWidgets()
    end)

    -- Escape closes a frame whose name is listed in UISpecialFrames.
    -- That global is missing on some very old clients, so check first.
    AddEscapeClose("CampingNotesSettings")

    SyncSettingsWidgets()
end

local function ApplySavedLayout()
    if CampingNotes.IsReady() and type(CampingNotesDB.minimap) == "table" then
        PlaceMinimapButton(CampingNotesDB.minimap.angle)
    end
    PlaceIndicator()
    SyncSettingsWidgets()
    UpdateIndicator()
end

CreateIndicator()
CreateMinimapButton()
CreateCampNotes()
CreateSettings()

CampingNotes.Listen("ADDON_LOADED", ApplySavedLayout)
CampingNotes.Listen("UNIT_AURA", OnAura)
CampingNotes.Listen("PLAYER_ENTERING_WORLD", OnAura)
