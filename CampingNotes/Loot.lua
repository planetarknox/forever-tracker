-- Camping Notes, part 2 of 3 (Loot.lua).
--
-- Records corpses you loot and adds your notes to the mob tooltip.
-- Each item remembers how many loots included it, and its quality
-- (grey, white, green, ...) when the client told us one.

local countedThisTarget = false
local paintingTooltip = false

-- Hard-coded colors if the client has no quality-color helper.
-- 0 poor, 1 common, 2 uncommon, 3 rare, 4 epic, 5 legendary.
local FALLBACK_QUALITY = {
    [0] = { 0.62, 0.62, 0.62 },
    [1] = { 1.00, 1.00, 1.00 },
    [2] = { 0.12, 1.00, 0.00 },
    [3] = { 0.00, 0.44, 0.87 },
    [4] = { 0.64, 0.21, 0.93 },
    [5] = { 1.00, 0.50, 0.00 },
}

local function LooksLikeQuality(value)
    return type(value) == "number" and value >= 0 and value <= 7 and value == math.floor(value)
end

-- GetItemInfo's third return is quality on both old and new clients.
-- GetLootSlotInfo disagrees with itself: vanilla puts quality 4th,
-- newer clients put it 5th. Prefer GetItemInfo. Fall back carefully.
local function QualityForSlot(slot, link)
    if type(GetItemInfo) == "function" and type(link) == "string" then
        local _, _, quality = GetItemInfo(link)
        if LooksLikeQuality(quality) then
            return quality
        end
    end
    if type(GetLootSlotInfo) ~= "function" then
        return nil
    end
    local _, _, _, fourth, fifth = GetLootSlotInfo(slot)
    if LooksLikeQuality(fourth) and (fifth == nil or fifth == true or fifth == false or fifth == 0 or fifth == 1) then
        return fourth
    end
    if LooksLikeQuality(fifth) then
        return fifth
    end
    if LooksLikeQuality(fourth) then
        return fourth
    end
    return nil
end

function CampingNotes.QualityColor(quality)
    if not LooksLikeQuality(quality) then
        return 1, 1, 1
    end
    quality = math.floor(quality)
    if type(GetItemQualityColor) == "function" then
        local r, g, b = GetItemQualityColor(quality)
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b
        end
    end
    if type(ITEM_QUALITY_COLORS) == "table" then
        local color = ITEM_QUALITY_COLORS[quality]
        if type(color) == "table" then
            if type(color.GetRGB) == "function" then
                local r, g, b = color:GetRGB()
                if type(r) == "number" and type(g) == "number" and type(b) == "number" then
                    return r, g, b
                end
            end
            local r = color.r or color[1]
            local g = color.g or color[2]
            local b = color.b or color[3]
            if type(r) == "number" and type(g) == "number" and type(b) == "number" then
                return r, g, b
            end
        end
    end
    local fallback = FALLBACK_QUALITY[quality] or FALLBACK_QUALITY[1]
    return fallback[1], fallback[2], fallback[3]
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
-- If that prints a string, this function can return that string instead.

local function MobKey(unit)
    if not unit or not UnitExists(unit) then
        return nil
    end
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
-- function is on the old 1.12 API list. If it is missing we do not
-- call it.
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

-- Coins have no item link, so they are skipped. The same item in two
-- slots counts once. A stack of five still counts as one appearance.
local function ItemFromSlot(slot)
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
    return name, QualityForSlot(slot, link)
end

local function ReadLootItems()
    local seen = {}
    local count = GetNumLootItems()
    if type(count) ~= "number" or count < 0 then
        count = 0
    end
    for slot = 1, count do
        local name, quality = ItemFromSlot(slot)
        if name then
            local row = seen[name]
            if not row then
                seen[name] = { quality = quality }
            elseif row.quality == nil and quality ~= nil then
                row.quality = quality
            end
        end
    end
    return seen
end

local function MobEntry(key)
    local db = CampingNotes.EnsureDB()
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

-- Older notes stored a plain number per item. Newer notes store
-- { count = n, quality = q }. Reading accepts both.
local function NormalizeItem(mob, name)
    local row = mob.items[name]
    if type(row) == "number" then
        row = { count = row }
        mob.items[name] = row
    elseif type(row) ~= "table" then
        row = { count = 0 }
        mob.items[name] = row
    end
    if type(row.count) ~= "number" then
        row.count = 0
    end
    return row
end

local function RecordMobLoot(key, seen)
    local mob = MobEntry(key)
    mob.loots = mob.loots + 1
    for name, info in pairs(seen) do
        local row = NormalizeItem(mob, name)
        row.count = row.count + 1
        if type(info) == "table" and LooksLikeQuality(info.quality) then
            row.quality = info.quality
        end
    end
end

-- LOOT_OPENED fires when a loot window opens.
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
-- only had a skinning window stores the skin as if it were a drop.
local function OnLootOpened()
    if not CampingNotes.IsReady() then
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

function CampingNotes.ResetLoot()
    if not CampingNotes.IsReady() then
        CampingNotes.Say("Camping Notes is not ready yet.")
        return
    end
    local db = CampingNotes.EnsureDB()
    db.mobs = {}
    countedThisTarget = false
    CampingNotes.Say("Camping Notes: loot notes cleared. Your settings were kept.")
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

local function ItemCountAndQuality(row)
    if type(row) == "number" then
        return row, nil
    end
    if type(row) == "table" and type(row.count) == "number" then
        return row.count, row.quality
    end
    return nil, nil
end

-- Most common first. Ties break by name so the order stays put.
local function TopDrops(mob)
    local list = {}
    if type(mob.items) == "table" then
        for name, row in pairs(mob.items) do
            local count, quality = ItemCountAndQuality(row)
            if type(name) == "string" and type(count) == "number" and count > 0 then
                table.insert(list, { name = name, count = count, quality = quality })
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

-- The only read the bestiary uses. Each entry is
--   { name = "Young Boar", loots = 4, drops = { { name, count, quality, percent }, ... } }
-- Drops are every recorded item, most common first (not just five).
-- Shared notes from other campers are not loaded yet. When they are,
-- merge them into this list here so the window does not need to change.
function CampingNotes.BestiaryEntries()
    local result = {}
    if not CampingNotes.IsReady() or type(CampingNotesDB) ~= "table" or type(CampingNotesDB.mobs) ~= "table" then
        return result
    end
    for name, mob in pairs(CampingNotesDB.mobs) do
        if type(name) == "string" and type(mob) == "table" then
            local loots = mob.loots
            if type(loots) ~= "number" or loots < 0 then
                loots = 0
            end
            local ranked = TopDrops(mob)
            local drops = {}
            for i = 1, #ranked do
                local row = ranked[i]
                drops[i] = {
                    name = row.name,
                    count = row.count,
                    quality = row.quality,
                    percent = Percent(row.count, loots),
                }
            end
            if loots > 0 or #drops > 0 then
                result[#result + 1] = { name = name, loots = loots, drops = drops }
            end
        end
    end
    table.sort(result, function(a, b)
        return string.lower(a.name) < string.lower(b.name)
    end)
    return result
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
    if CampingNotes.IsReady() and type(CampingNotesDB) == "table" and type(CampingNotesDB.mobs) == "table" then
        mob = CampingNotesDB.mobs[key]
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
    local useColor = CampingNotes.ColorByRarity()
    for i = 1, limit do
        local row = list[i]
        local pct = Percent(row.count, mob.loots)
        local r, g, b = 1, 1, 1
        if useColor and LooksLikeQuality(row.quality) then
            r, g, b = CampingNotes.QualityColor(row.quality)
        end
        tooltip:AddLine(row.name .. ": " .. pct .. "%", r, g, b)
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
    -- Show() again so the box grows to fit the new lines. The flag
    -- above stops that Show() from running this function a second time.
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
--     not have this script. The mainline UI removed it again in patch
--     10.0. Forever shares that mainline UI, so this script may be
--     missing there.
--   * If HookScript exists but that script does not, we hook OnShow and
--     only add lines when a mob is under the cursor.
--   * If HookScript itself is missing, we wrap SetUnit. That is the
--     original 1.x way.
local function HookUnitTooltip(callback)
    if type(GameTooltip) ~= "table" and type(GameTooltip) ~= "userdata" then
        return
    end
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

CampingNotes.Listen("LOOT_OPENED", OnLootOpened)
CampingNotes.Listen("PLAYER_TARGET_CHANGED", OnTargetChanged)
HookUnitTooltip(PaintTooltip)
