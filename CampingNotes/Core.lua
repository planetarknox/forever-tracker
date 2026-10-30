-- Camping Notes, part 1 of 3 (Core.lua).
--
-- This file loads first. It keeps the saved notebook, the login line,
-- and the /camp command. Loot.lua records drops. UI.lua draws Tyrion
-- the corgi, the minimap button, and the settings window.
--
-- CampingNotes is a table of functions. CampingNotesDB is the table the
-- game saves. They are different on purpose: functions must not be
-- written into the saved notebook.

CampingNotes = CampingNotes or {}

-- A texture path has no file extension. The client finds
-- CampingNotes/Media/icon.tga from this string. Backslashes are what
-- the game expects, even on a computer that uses forward slashes.
CampingNotes.ICON = "Interface\\AddOns\\CampingNotes\\Media\\icon"

-- Numbers used when a saved key is missing. Old notebooks gain these
-- keys on login. Keys the player already set are left alone.
CampingNotes.defaults = {
    settings = {
        scale = 1,
        opacity = 1,
        backdrop = true,
        colorByRarity = true,
        -- Locked until the player checks Unlock icon. onlyWithBuff hides
        -- Tyrion unless Welcoming Campfire is on them.
        unlocked = false,
        onlyWithBuff = true,
    },
    minimap = {
        angle = 220,
    },
    indicator = {
        point = "CENTER",
        relPoint = "CENTER",
        x = 0,
        y = 90,
    },
}

CampingNotes.ready = false
CampingNotes.handlers = {}

-- A frame is an invisible object that can listen for game events.
local frame = CreateFrame("Frame")

function CampingNotes.Say(text)
    DEFAULT_CHAT_FRAME:AddMessage(text)
end

function CampingNotes.IsReady()
    return CampingNotes.ready and true or false
end

-- Copy missing keys from defaults into the saved table. A value the
-- player already stored (including false) is kept.
local function FillDefaults(saved, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(saved[key]) ~= "table" then
                saved[key] = {}
            end
            FillDefaults(saved[key], value)
        elseif saved[key] == nil then
            saved[key] = value
        end
    end
end

-- SavedVariables is how the game remembers a global table between
-- sessions. The .toc line "## SavedVariables: CampingNotesDB" means:
-- save the global named CampingNotesDB on logout, and put it back
-- before ADDON_LOADED for this addon.
--
-- On a new install that global is nil. We build it here, after the
-- game has had its chance to restore the old copy. Building it earlier
-- can block that restore.
function CampingNotes.EnsureDB()
    if type(CampingNotesDB) ~= "table" then
        CampingNotesDB = {}
    end
    if type(CampingNotesDB.mobs) ~= "table" then
        CampingNotesDB.mobs = {}
    end
    FillDefaults(CampingNotesDB, CampingNotes.defaults)
    return CampingNotesDB
end

-- Before the notebook is restored, callers get the defaults and must
-- not write them. After that, this is the live saved settings table.
function CampingNotes.GetSettings()
    if CampingNotes.IsReady() and type(CampingNotesDB) == "table" and type(CampingNotesDB.settings) == "table" then
        return CampingNotesDB.settings
    end
    return CampingNotes.defaults.settings
end

function CampingNotes.ColorByRarity()
    local settings = CampingNotes.GetSettings()
    if settings.colorByRarity == nil then
        return true
    end
    return settings.colorByRarity and true or false
end

-- Other files call Listen to run a function when an event fires.
-- RegisterEvent is safe to call more than once for the same name.
function CampingNotes.Listen(eventName, fn)
    local list = CampingNotes.handlers[eventName]
    if not list then
        list = {}
        CampingNotes.handlers[eventName] = list
        frame:RegisterEvent(eventName)
    end
    list[#list + 1] = fn
end

-- A slash command is a chat line that starts with /, like /wave.
-- The game reads the first word. If an addon registered it, the game
-- runs the addon's function instead of sending the text to other
-- people. The rest of the line is the message.
--
-- SLASH_CAMPINGNOTES1 and SlashCmdList["CAMPINGNOTES"] share an id
-- that is not shown in chat. The player types /camp.
local function Trim(text)
    text = string.gsub(text or "", "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return text
end

local function OnSlash(message)
    local text = string.lower(Trim(message))
    if text == "reset" then
        -- ResetLoot lives in Loot.lua. It clears mob notes only.
        if CampingNotes.ResetLoot then
            CampingNotes.ResetLoot()
        end
        return
    end
    if text == "bestiary" then
        if CampingNotes.ShowBestiary then
            CampingNotes.ShowBestiary()
        end
        return
    end
    if text == "" then
        if CampingNotes.ShowSettings then
            CampingNotes.ShowSettings()
        end
        return
    end
    CampingNotes.Say("Camping Notes: /camp opens settings. /camp bestiary opens the bestiary. /camp reset erases loot notes and keeps your settings.")
end

SLASH_CAMPINGNOTES1 = "/camp"
SlashCmdList["CAMPINGNOTES"] = OnSlash

-- Original 1.x clients do not pass event details into the function.
-- They fill globals named event and arg1. Newer clients call the
-- function as (frame, event, arg1). A few builds use (event, arg1).
local function ReadEvent(p1, p2, p3)
    if type(p1) == "string" then
        return p1, p2
    end
    if type(p2) == "string" then
        return p2, p3
    end
    return event, arg1
end

local function OnEvent(p1, p2, p3)
    local eventName, firstArg = ReadEvent(p1, p2, p3)
    if eventName == "ADDON_LOADED" then
        -- The folder name is CampingNotes, with no space. The title
        -- players see is "Camping Notes". Many addons load, so ignore
        -- every name except ours. Saved data is restored just before
        -- this event for that addon.
        if firstArg ~= "CampingNotes" then
            return
        end
        CampingNotes.EnsureDB()
        CampingNotes.ready = true
    elseif eventName == "PLAYER_LOGIN" then
        -- Chat exists once you have entered the world.
        CampingNotes.Say("Camping Notes loaded! hello, adventurer.")
    end
    local list = CampingNotes.handlers[eventName]
    if list then
        for i = 1, #list do
            list[i](firstArg, eventName)
        end
    end
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", OnEvent)
