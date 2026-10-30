-- ForeverTracker
--
-- This is the whole addon for now. When you log in, it prints one friendly
-- line in the chat window. It does not track gold, loot, or quests yet.

-- WoW runs this file once, from top to bottom, when the addon is loaded.
-- That happens before you finish entering the world, so it is too early to
-- print a greeting. We set up a listener here, and the print happens later.

-- A frame is a small object the game gives us. Frames usually draw buttons
-- and windows, but a frame can also stay invisible and listen for news.
-- CreateFrame("Frame") makes one of those objects. We keep it in a local
-- variable named "frame" so the rest of this file can use it. "local" means
-- the name stays inside this file instead of leaking out as a global.
local frame = CreateFrame("Frame")

-- An event is a message the game sends when something happens, such as
-- logging in, looting a monster, or entering combat. RegisterEvent signs
-- our frame up for one message: "when this happens, tell me."
--
-- PLAYER_LOGIN fires once, after your character has entered the world.
-- The chat window exists by then, so a printed line will actually show up.
frame:RegisterEvent("PLAYER_LOGIN")

-- SetScript attaches a function to the frame. The "OnEvent" script runs
-- whenever any event we registered actually fires.
--
-- Original 1.x clients announce which event fired by filling in global
-- variables (event, arg1, and so on). Later clients pass that same info
-- as arguments to the function. We only signed up for PLAYER_LOGIN, so if
-- this function runs at all, that is the event we were waiting for. We do
-- not read the event name, and the same function works either way.
local function OnPlayerLogin()
    -- DEFAULT_CHAT_FRAME is the main chat window. AddMessage writes one
    -- line of text there, in the same place system messages appear.
    DEFAULT_CHAT_FRAME:AddMessage("ForeverTracker loaded! hello, adventurer.")
end

frame:SetScript("OnEvent", OnPlayerLogin)
