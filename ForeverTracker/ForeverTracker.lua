-- ForeverTracker
--
-- On login, prints one hello line in chat.
-- After that, remembers corpses you loot. Hover a mob to see the five
-- items that showed up most often in your own loot windows, with the
-- percent of loots that contained each one.

-- A frame is a small object the game gives us. Frames usually draw
-- buttons and windows. This one stays invisible and listens for news.
-- "local" keeps the name inside this file.
local frame = CreateFrame("Frame")

-- SavedVariables is how the game remembers a global table between
-- sessions. The .toc line "## SavedVariables: ForeverTrackerDB" means:
-- when you log out, save the global table named ForeverTrackerDB, and
-- put it back before firing ADDON_LOADED for this addon.
--
-- On a brand new install that global is nil. Indexing nil is an error,
-- so we build an empty table once the game has restored saved data
-- (or left it nil, the first time).
-- savedReady stays false until that moment, so a loot event cannot
-- touch the table early and block the saved copy from loading.
local savedReady = false

-- True after we have counted the corpse that is currently targeted.
-- Cleared when the target changes. See OnLootOpened for why.
local countedThisTarget = false

-- True while we are adding our own tooltip lines, so Show() cannot
-- call us again and add a second copy.
local paintingTooltip = false

local function Say(text)
    DEFAULT_CHAT_FRAME:AddMessage(text)
end

local function EnsureDB()
    if type(ForeverTrackerDB) ~= "table" then
        ForeverTrackerDB = {}
    end
    if type(ForeverTrackerDB.mobs) ~= "table" then
        ForeverTrackerDB.mobs = {}
    end
    return ForeverTrackerDB
end

-- ============================================================
-- HOW WE IDENTIFY A MOB
-- ============================================================
--
-- Recording and the tooltip both call MobKey, so there is one place
-- to change if the name is not a good enough id.
--
-- Today the key is the unit's name from UnitName. Every "Young Boar"
-- shares one history. UnitGUID would tell two boars apart, but this
-- client might not have it. In game, try:
--   /dump UnitGUID("target")
-- If that prints a string of letters and numbers, this function can
-- return that string instead of the name.

local function MobKey(unit)
    if not unit or not UnitExists(unit) then
        return nil
    end
    -- Players are not mobs. Hovering another player adds nothing.
    if UnitIsPlayer(unit) then
        return nil
    end
    local name = UnitName(unit)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    return name
end

-- A loot window we are willing to record: a dead creature is targeted,
-- and it is not a player or a friendly NPC. Chests, herbs, and ore do
-- not become your target, so they fail this check.
-- Fishing loot is skipped when the client has IsFishingLoot. That
-- function is on the old 1.12 API list; if this client has no such
-- function we simply do not call it.
local function IsRecordableCorpse()
    if type(IsFishingLoot) == "function" and IsFishingLoot() then
        return false
    end
    if not UnitExists("target") then
        return false
    end
    if UnitIsPlayer("target") then
        return false
    end
    if not UnitIsDead("target") then
        return false
    end
    if UnitIsFriend("player", "target") then
        return false
    end
    return true
end

-- ============================================================
-- Loot window
-- ============================================================

-- One slot in the loot window. Coins have no item link, so they are
-- skipped. The same item in two slots counts once for this corpse.
-- A stack of five still counts as one appearance: the percent later
-- is "how many loots included this item", not "how many pieces".
local function ItemNameFromSlot(slot)
    local link = GetLootSlotLink(slot)
    if type(link) ~= "string" or link == "" then
        return nil
    end
    local _, name = GetLootSlotInfo(slot)
    if type(name) ~= "string" or name == "" then
        local _, _, fromLink = string.find(link, "|h%[(.-)%]|h")
        name = fromLink
    end
    if type(name) ~= "string" or name == "" then
        return nil
    end
    return name
end

local function ReadLootItems()
    local seen = {}
    local count = GetNumLootItems()
    if type(count) ~= "number" or count < 0 then
        count = 0
    end
    for slot = 1, count do
        local name = ItemNameFromSlot(slot)
        if name then
            seen[name] = true
        end
    end
    return seen
end

local function MobEntry(key)
    local db = EnsureDB()
    local mob = db.mobs[key]
    if type(mob) ~= "table" then
        mob = { loots = 0, items = {} }
        db.mobs[key] = mob
    end
    if type(mob.items) ~= "table" then
        mob.items = {}
    end
    if type(mob.loots) ~= "number" or mob.loots < 0 then
        mob.loots = 0
    end
    return mob
end

local function RecordMobLoot(key, seen)
    local mob = MobEntry(key)
    mob.loots = mob.loots + 1
    for name in pairs(seen) do
        local previous = mob.items[name]
        if type(previous) ~= "number" then
            previous = 0
        end
        mob.items[name] = previous + 1
    end
end

-- LOOT_OPENED fires when a loot window opens (corpse, chest, skin,
-- herb, or a window you opened again).
--
-- Without a unique mob id we cannot tell "this exact corpse" from
-- "another creature with the same name". Best effort:
--   * The first window while a corpse stays targeted is recorded.
--   * Further windows are ignored until the target changes.
-- That covers reopening the same window, and skinning that corpse
-- while it stays targeted.
-- It does not cover skinning after you select something else and
-- come back, and it does not cover a chest you open while a dead
-- enemy is still targeted. Both can be stored as a new loot.
-- The first window on a corpse is always stored, so a corpse that
-- only had a skinning window (someone else took the drops) stores
-- the skin as if it were a drop.
local function OnLootOpened()
    if not savedReady then
        return
    end
    if countedThisTarget then
        return
    end
    if not IsRecordableCorpse() then
        return
    end
    local key = MobKey("target")
    if not key then
        return
    end
    RecordMobLoot(key, ReadLootItems())
    countedThisTarget = true
end

local function OnTargetChanged()
    countedThisTarget = false
end

-- ============================================================
-- Tooltip
-- ============================================================

local function Percent(count, loots)
    if loots <= 0 then
        return 0
    end
    local pct = math.floor((count / loots) * 100 + 0.5)
    if pct > 100 then
        pct = 100
    end
    if pct < 0 then
        pct = 0
    end
    return pct
end

-- Most common first. Ties break by name so the order does not jump
-- around between hovers.
local function TopDrops(mob)
    local list = {}
    if type(mob.items) == "table" then
        for name, count in pairs(mob.items) do
            if type(name) == "string" and type(count) == "number" and count > 0 then
                table.insert(list, { name = name, count = count })
            end
        end
    end
    table.sort(list, function(a, b)
        if a.count ~= b.count then
            return a.count > b.count
        end
        return a.name < b.name
    end)
    return list
end

local function ResolveTooltip(tooltip)
    if tooltip and tooltip.AddLine then
        return tooltip
    end
    -- 1.x script handlers often leave the frame in the global "this"
    -- and pass no arguments.
    if this and this.AddLine then
        return this
    end
    return GameTooltip
end

local function UnitForTooltip(unitFromHook)
    if UnitExists("mouseover") then
        return "mouseover"
    end
    if unitFromHook and UnitExists(unitFromHook) then
        return unitFromHook
    end
    return nil
end

local function AddDropLines(tooltip, unitFromHook)
    tooltip = ResolveTooltip(tooltip)
    if not tooltip or not tooltip.AddLine then
        return false
    end
    local key = MobKey(UnitForTooltip(unitFromHook))
    if not key then
        return false
    end

    local mob = nil
    if savedReady and type(ForeverTrackerDB) == "table" and type(ForeverTrackerDB.mobs) == "table" then
        mob = ForeverTrackerDB.mobs[key]
    end
    if type(mob) ~= "table" or type(mob.loots) ~= "number" or mob.loots <= 0 then
        tooltip:AddLine("no loot data yet", 0.5, 0.5, 0.5)
        return true
    end

    local list = TopDrops(mob)
    local limit = #list
    if limit > 5 then
        limit = 5
    end
    for i = 1, limit do
        local row = list[i]
        local pct = Percent(row.count, mob.loots)
        tooltip:AddLine(row.name .. ": " .. pct .. "%", 1, 1, 1)
    end

    local total = mob.loots .. " loots recorded"
    if mob.loots == 1 then
        total = "1 loot recorded"
    end
    tooltip:AddLine(total, 0.7, 0.7, 0.7)
    return true
end

local function PaintTooltip(tooltip, unitFromHook)
    if paintingTooltip then
        return
    end
    paintingTooltip = true
    local resolved = ResolveTooltip(tooltip)
    local added = AddDropLines(resolved, unitFromHook)
    -- Show() again so the box grows to fit the new lines. The flag above
    -- stops that Show() from running this function a second time.
    if added and resolved and resolved.Show then
        resolved:Show()
    end
    paintingTooltip = false
end

-- HOW WE HOOK THE TOOLTIP
--
-- A tooltip hook means "after you build the hover box, run my function
-- too." The game's own lines stay. We only add ours at the bottom.
--
-- Clients disagree about which hook exists:
--   * OnTooltipSetUnit runs after a unit tooltip is filled. HookScript
--     attaches us without removing the game's handler. Stock 1.12 did
--     not have this script (it arrived later). The mainline UI removed
--     it again in patch 10.0. Forever shares that mainline UI, so this
--     script may be missing there.
--   * If HookScript exists but that script does not, we hook OnShow and
--     only add lines when a mob is under the cursor (UnitExists
--     "mouseover"). A client that rebuilds the tooltip from data after
--     OnShow can wipe those lines. This function is the place to swap
--     if hover text never appears.
--   * If HookScript itself is missing, we wrap SetUnit. That is the
--     original 1.x way: the game calls SetUnit to fill a unit tooltip,
--     we call the original, then we add our lines.
local function HookUnitTooltip(callback)
    if type(GameTooltip.HookScript) == "function" and type(GameTooltip.HasScript) == "function" then
        local ok, supported = pcall(GameTooltip.HasScript, GameTooltip, "OnTooltipSetUnit")
        if ok and supported then
            GameTooltip:HookScript("OnTooltipSetUnit", function(tooltip)
                callback(tooltip)
            end)
            return
        end
    end

    if type(GameTooltip.HookScript) == "function" then
        GameTooltip:HookScript("OnShow", function(tooltip)
            callback(tooltip)
        end)
        return
    end

    if type(GameTooltip.SetUnit) ~= "function" then
        return
    end
    local originalSetUnit = GameTooltip.SetUnit
    GameTooltip.SetUnit = function(tooltip, unit)
        originalSetUnit(tooltip, unit)
        callback(tooltip, unit)
    end
end

-- ============================================================
-- Slash commands
-- ============================================================
--
-- A slash command is a chat line that starts with /, like /wave or
-- /reload. The game looks at the first word. If an addon registered
-- that word, the game runs the addon's function instead of sending
-- the text to other people. Whatever you type after the command is
-- the message. We care about an empty message, or the word "reset".
--
-- SLASH_FOREVERTRACKER1 and SlashCmdList["FOREVERTRACKER"] must use
-- the same id. The id is not shown in chat. The player types /ftrack.

local function Trim(text)
    text = string.gsub(text or "", "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return text
end

local function OnSlash(message)
    local text = string.lower(Trim(message))
    if text == "reset" then
        if not savedReady then
            Say("ForeverTracker is not ready yet.")
            return
        end
        EnsureDB()
        ForeverTrackerDB.mobs = {}
        countedThisTarget = false
        Say("ForeverTracker: all loot data cleared.")
        return
    end
    Say("ForeverTracker: /ftrack shows this help. /ftrack reset erases every recorded loot.")
end

SLASH_FOREVERTRACKER1 = "/ftrack"
SlashCmdList["FOREVERTRACKER"] = OnSlash

-- ============================================================
-- Events
-- ============================================================
--
-- An event is a message the game sends when something happens.
-- RegisterEvent signs this frame up. The OnEvent function runs when
-- one of those messages arrives.
--
-- ADDON_LOADED fires once per addon, after that addon's saved
-- variables are restored. The first argument is the addon folder
-- name. We ignore every name except ForeverTracker.
-- PLAYER_LOGIN fires once after you enter the world. Chat exists, so
-- the hello line can be seen.
-- LOOT_OPENED fires when a loot window opens.
-- PLAYER_TARGET_CHANGED fires when you select something else, or
-- clear your target. That ends the "same corpse" guard above.
--
-- Original 1.x clients do not pass those details into the function.
-- They fill globals named event and arg1, and call the function with
-- no arguments. Newer clients call it as (frame, event, arg1).
-- A few builds call it as (event, arg1). ReadEvent accepts all three.

local function ReadEvent(p1, p2, p3)
    if type(p1) == "string" then
        return p1, p2
    end
    if type(p2) == "string" then
        return p2, p3
    end
    return event, arg1
end

local function OnAddonLoaded(addonName)
    if addonName ~= "ForeverTracker" then
        return
    end
    EnsureDB()
    savedReady = true
end

local function OnPlayerLogin()
    Say("ForeverTracker loaded! hello, adventurer.")
end

local function OnEvent(p1, p2, p3)
    local eventName, firstArg = ReadEvent(p1, p2, p3)
    if eventName == "ADDON_LOADED" then
        OnAddonLoaded(firstArg)
    elseif eventName == "PLAYER_LOGIN" then
        OnPlayerLogin()
    elseif eventName == "LOOT_OPENED" then
        OnLootOpened()
    elseif eventName == "PLAYER_TARGET_CHANGED" then
        OnTargetChanged()
    end
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("LOOT_OPENED")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:SetScript("OnEvent", OnEvent)

HookUnitTooltip(PaintTooltip)
