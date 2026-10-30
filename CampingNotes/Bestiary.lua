-- Camping Notes, part 4 of 4 (Bestiary.lua).
--
-- A window that lists every mob in your loot notes. A search box
-- filters that list as you type. Click a name to see every drop,
-- not just the five lines on the tooltip.
--
-- The list itself comes from CampingNotes.BestiaryEntries in Loot.lua.
-- That is the one function to change when shared notes from other
-- campers start arriving.

local VIEW_ROWS = 12
local ROW_HEIGHT = 18
local selectedName = nil
local searchBox = nil
local listButtons = {}
local dropLines = {}
local listScroll = nil
local listChild = nil
local listBar = nil
local dropScroll = nil
local dropChild = nil
local dropBar = nil
local detailTitle = nil
local detailTotal = nil
local bestiaryFrame = nil
local useListScroll = false
local useDropScroll = false

-- CreateFrame throws if a frame type or XML template is missing.
-- pcall turns that into a false result so we can try something simpler.
local function TryFrame(kind, name, parent, template)
    local ok, frame = pcall(CreateFrame, kind, name, parent, template)
    if ok and frame then
        return frame
    end
    if template then
        ok, frame = pcall(CreateFrame, kind, name, parent)
        if ok and frame then
            return frame
        end
    end
    return nil
end

local function Backdrop(frame)
    if frame and type(frame.SetBackdrop) == "function" then
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 32,
            edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
    end
end

local function NewPanel(name)
    local template = nil
    if BackdropTemplateMixin then
        template = "BackdropTemplate"
    end
    local frame = TryFrame("Frame", name, UIParent, template)
    if not frame then
        return nil
    end
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    if frame.SetClampedToScreen then
        frame:SetClampedToScreen(true)
    end
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)
    Backdrop(frame)
    return frame
end

-- A scroll frame is a window that can slide a taller child frame
-- up and down. FauxScrollFrameTemplate is an old XML helper that
-- builds one for you. We use it only when that template and
-- FauxScrollFrame_Update both exist. Otherwise we build a plain
-- ScrollFrame, and if that frame type is missing we page with a slider.
local function AttachScroll(parent, width, height, x, y)
    local scroll = nil
    local child = nil
    local mode = "page"
    -- Plain ScrollFrame first. It has existed since early clients and
    -- needs no XML template. FauxScrollFrameTemplate is the fallback
    -- for a client that has the helper but no bare scroll methods.
    scroll = TryFrame("ScrollFrame", nil, parent)
    if scroll and scroll.SetScrollChild and scroll.SetVerticalScroll then
        mode = "scroll"
    else
        scroll = nil
        if type(FauxScrollFrame_Update) == "function" then
            scroll = TryFrame("ScrollFrame", nil, parent, "FauxScrollFrameTemplate")
            if scroll and scroll.SetScrollChild then
                mode = "scroll"
            else
                scroll = nil
            end
        end
    end

    if mode == "scroll" then
        child = CreateFrame("Frame", nil, scroll)
        child:SetSize(width, height)
        scroll:SetScrollChild(child)
        scroll:SetSize(width, height)
        scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    else
        child = CreateFrame("Frame", nil, parent)
        child:SetSize(width, height)
        child:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    end

    local bar = TryFrame("Slider", nil, parent)
    if bar then
        bar:SetOrientation("VERTICAL")
        bar:SetSize(16, height)
        bar:SetPoint("TOPLEFT", child, "TOPRIGHT", 4, 0)
        bar:SetMinMaxValues(0, 0)
        if bar.SetValue then
            bar:SetValue(0)
        end
        if bar.SetValueStep then
            bar:SetValueStep(1)
        end
        local thumb = bar:CreateTexture(nil, "OVERLAY")
        thumb:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
        thumb:SetSize(16, 24)
        if bar.SetThumbTexture then
            bar:SetThumbTexture(thumb)
        end
    end
    return scroll, child, bar, mode == "scroll"
end

local function WireScrollBar(scroll, child, bar, viewHeight)
    if not bar then
        return
    end
    bar:SetScript("OnValueChanged", function(self, value)
        if type(value) ~= "number" then
            value = self:GetValue()
        end
        if scroll and scroll.SetVerticalScroll then
            scroll:SetVerticalScroll(value)
        else
            -- No scroll frame: the list redraws a window of rows.
            if bar.redraw then
                bar.redraw()
            end
        end
    end)
    if scroll and scroll.EnableMouseWheel then
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(_, delta)
            local step = ROW_HEIGHT
            if type(delta) ~= "number" then
                delta = 0
            end
            local current = bar:GetValue() or 0
            bar:SetValue(current - (delta * step))
        end)
    end
    bar.viewHeight = viewHeight
end

local function QueryText()
    if searchBox and searchBox.GetText then
        local text = searchBox:GetText()
        if type(text) == "string" then
            return string.lower(text)
        end
    end
    return ""
end

local function FilteredEntries()
    local all = CampingNotes.BestiaryEntries()
    local query = QueryText()
    if query == "" then
        return all
    end
    local kept = {}
    for i = 1, #all do
        local name = string.lower(all[i].name)
        -- The 4th argument true means "plain text", so a mob named
        -- with a parenthesis does not get read as a pattern.
        if string.find(name, query, 1, true) then
            kept[#kept + 1] = all[i]
        end
    end
    return kept
end

local function FindEntry(name)
    if type(name) ~= "string" then
        return nil
    end
    local all = CampingNotes.BestiaryEntries()
    for i = 1, #all do
        if all[i].name == name then
            return all[i]
        end
    end
    return nil
end

local function EnsureListButton(index)
    local button = listButtons[index]
    if button then
        return button
    end
    button = CreateFrame("Button", nil, listChild)
    button:SetSize(168, ROW_HEIGHT)
    button:SetPoint("TOPLEFT", 2, -((index - 1) * ROW_HEIGHT))
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", 4, 0)
    label:SetText("")
    button.label = label
    button:SetScript("OnClick", function(self)
        selectedName = self.mobName
        CampingNotes.RefreshBestiary()
    end)
    listButtons[index] = button
    return button
end

local function EnsureDropLine(index)
    local line = dropLines[index]
    if line then
        return line
    end
    line = dropChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    line:SetPoint("TOPLEFT", 4, -((index - 1) * ROW_HEIGHT))
    line:SetWidth(230)
    if line.SetJustifyH then
        line:SetJustifyH("LEFT")
    end
    line:SetText("")
    dropLines[index] = line
    return line
end

local function ShowDetails()
    local entry = FindEntry(selectedName)
    if not entry then
        if detailTitle then
            detailTitle:SetText("Select a mob")
        end
        if detailTotal then
            detailTotal:SetText("")
        end
        for i = 1, #dropLines do
            dropLines[i]:Hide()
        end
        return
    end
    if detailTitle then
        detailTitle:SetText(entry.name)
    end
    if detailTotal then
        if entry.loots == 1 then
            detailTotal:SetText("1 loot recorded")
        else
            detailTotal:SetText(entry.loots .. " loots recorded")
        end
    end
    local colorDrops = CampingNotes.ColorByRarity()
    for i = 1, #entry.drops do
        local drop = entry.drops[i]
        local line = EnsureDropLine(i)
        line:SetText(drop.name .. ": " .. drop.percent .. "%")
        local r, g, b = 1, 1, 1
        if colorDrops then
            r, g, b = CampingNotes.QualityColor(drop.quality)
        end
        if line.SetTextColor then
            line:SetTextColor(r, g, b)
        end
        line:Show()
    end
    for i = #entry.drops + 1, #dropLines do
        dropLines[i]:Hide()
    end
    local height = #entry.drops * ROW_HEIGHT
    if height < ROW_HEIGHT then
        height = ROW_HEIGHT
    end
    if dropChild then
        dropChild:SetHeight(height)
    end
    if useDropScroll and dropBar and dropScroll and dropScroll.SetVerticalScroll then
        local maxScroll = height - 220
        if maxScroll < 0 then
            maxScroll = 0
        end
        dropBar:SetMinMaxValues(0, maxScroll)
    end
end

local refreshing = false

function CampingNotes.RefreshBestiary()
    if refreshing or not bestiaryFrame then
        return
    end
    refreshing = true
    local entries = FilteredEntries()
    local stillThere = false
    for i = 1, #entries do
        if entries[i].name == selectedName then
            stillThere = true
            break
        end
    end
    if not stillThere then
        selectedName = entries[1] and entries[1].name or nil
    end

    if useListScroll then
        for i = 1, #entries do
            local button = EnsureListButton(i)
            button.mobName = entries[i].name
            button.label:SetText(entries[i].name)
            if entries[i].name == selectedName and button.label.SetTextColor then
                button.label:SetTextColor(1, 0.82, 0)
            elseif button.label.SetTextColor then
                button.label:SetTextColor(1, 1, 1)
            end
            button:Show()
        end
        for i = #entries + 1, #listButtons do
            listButtons[i]:Hide()
        end
        local height = #entries * ROW_HEIGHT
        if height < ROW_HEIGHT then
            height = ROW_HEIGHT
        end
        listChild:SetHeight(height)
        if listBar then
            local maxScroll = height - (VIEW_ROWS * ROW_HEIGHT)
            if maxScroll < 0 then
                maxScroll = 0
            end
            listBar:SetMinMaxValues(0, maxScroll)
        end
    else
        local offset = 0
        if listBar and listBar.GetValue then
            offset = listBar:GetValue() or 0
            offset = math.floor(offset)
            if offset < 0 then
                offset = 0
            end
        end
        local maxOffset = #entries - VIEW_ROWS
        if maxOffset < 0 then
            maxOffset = 0
        end
        if listBar then
            listBar:SetMinMaxValues(0, maxOffset)
            if offset > maxOffset then
                offset = maxOffset
            end
        end
        for i = 1, VIEW_ROWS do
            local entry = entries[offset + i]
            local button = EnsureListButton(i)
            if entry then
                button.mobName = entry.name
                button.label:SetText(entry.name)
                if entry.name == selectedName and button.label.SetTextColor then
                    button.label:SetTextColor(1, 0.82, 0)
                elseif button.label.SetTextColor then
                    button.label:SetTextColor(1, 1, 1)
                end
                button:Show()
            else
                button.mobName = nil
                button:Hide()
            end
        end
    end
    ShowDetails()
    refreshing = false
end

local function CreateBestiary()
    bestiaryFrame = NewPanel("CampingNotesBestiary")
    if not bestiaryFrame then
        return
    end
    bestiaryFrame:SetSize(520, 360)
    bestiaryFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    bestiaryFrame:Hide()

    local title = bestiaryFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -14)
    title:SetText("Bestiary")

    local close = CreateFrame("Button", nil, bestiaryFrame)
    close:SetSize(28, 28)
    close:SetPoint("TOPRIGHT", -8, -8)
    local closeText = close:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    closeText:SetPoint("CENTER")
    closeText:SetText("X")
    close:SetScript("OnClick", function()
        bestiaryFrame:Hide()
    end)

    -- An EditBox is a one-line text field. OnTextChanged runs on every
    -- keystroke, which is how the list narrows as you type.
    searchBox = TryFrame("EditBox", nil, bestiaryFrame)
    if searchBox then
        searchBox:SetSize(180, 20)
        searchBox:SetPoint("TOPLEFT", 24, -40)
        if searchBox.SetAutoFocus then
            searchBox:SetAutoFocus(false)
        end
        if searchBox.SetFontObject then
            pcall(searchBox.SetFontObject, searchBox, "GameFontHighlight")
        end
        if searchBox.SetTextInsets then
            searchBox:SetTextInsets(4, 4, 2, 2)
        end
        local plate = searchBox:CreateTexture(nil, "BACKGROUND")
        plate:SetAllPoints()
        plate:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
        plate:SetVertexColor(0, 0, 0, 0.6)
        searchBox:SetScript("OnTextChanged", function()
            CampingNotes.RefreshBestiary()
        end)
        searchBox:SetScript("OnEscapePressed", function(self)
            if self.ClearFocus then
                self:ClearFocus()
            end
        end)
    else
        local missing = bestiaryFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        missing:SetPoint("TOPLEFT", 24, -40)
        missing:SetText("Search is not available on this client.")
    end

    local searchLabel = bestiaryFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchLabel:SetPoint("BOTTOMLEFT", searchBox or bestiaryFrame, searchBox and "TOPLEFT" or "TOPLEFT", 0, 2)
    if not searchBox then
        searchLabel:SetPoint("TOPLEFT", 24, -28)
    end
    searchLabel:SetText("Search mobs")

    local listTop = -68
    listScroll, listChild, listBar, useListScroll = AttachScroll(bestiaryFrame, 180, VIEW_ROWS * ROW_HEIGHT, 20, listTop)
    WireScrollBar(listScroll, listChild, listBar, VIEW_ROWS * ROW_HEIGHT)
    if listBar and not useListScroll then
        listBar.redraw = function()
            CampingNotes.RefreshBestiary()
        end
    end

    detailTitle = bestiaryFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    detailTitle:SetPoint("TOPLEFT", 240, -40)
    detailTitle:SetText("Select a mob")
    detailTotal = bestiaryFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detailTotal:SetPoint("TOPLEFT", 240, -58)
    detailTotal:SetText("")

    dropScroll, dropChild, dropBar, useDropScroll = AttachScroll(bestiaryFrame, 240, 220, 236, -80)
    WireScrollBar(dropScroll, dropChild, dropBar, 220)

    if type(UISpecialFrames) == "table" then
        local found = false
        for i = 1, #UISpecialFrames do
            if UISpecialFrames[i] == "CampingNotesBestiary" then
                found = true
                break
            end
        end
        if not found then
            table.insert(UISpecialFrames, "CampingNotesBestiary")
        end
    end

    bestiaryFrame:SetScript("OnShow", function()
        CampingNotes.RefreshBestiary()
    end)
    bestiaryFrame:Hide()
end

function CampingNotes.ShowBestiary()
    if not bestiaryFrame then
        return
    end
    bestiaryFrame:Show()
    if bestiaryFrame.Raise then
        bestiaryFrame:Raise()
    end
end

CreateBestiary()
