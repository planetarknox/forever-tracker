# Camping Notes

A beginner addon for the WoW Forever client (classic-style, game version 1.60.x).

Camping Notes is a personal loot-drop notebook. The notes are yours for now. Sharing them with other players is the later goal, and sharing is not built yet.

## What it does right now

When you log in, Camping Notes prints one line in chat:

> Camping Notes loaded! hello, adventurer.

It keeps a personal history of corpses you loot. Each mob name remembers how many times you opened its loot window, and which items were in that window. Hover a mob and the tooltip gains up to five lines, the items that appeared most often, each with a percentage:

> Chunk of Boar Meat: 75%

The percentage is times that item was in the window, divided by times you looted that mob name. Under those lines is a total, such as `4 loots recorded`. If you have never looted that mob, the tooltip shows one dim line: `no loot data yet`. Players get no extra line.

Item lines can be colored by rarity (grey through orange). That checkbox starts on. Coins are skipped. A stack counts once. A window that contains only coins still counts as one loot.

The history and the settings below are saved across logout in `CampingNotesDB`. Every character on the account shares that saved table. That is account storage, not sending notes to other players.

Tyrion the corgi is the addon icon. A round button with his picture sits on the edge of the minimap. Drag it around the edge. Left-click opens or closes the settings window.

Tyrion also sits on your UI, slightly above the center of the screen until you move him. He starts locked. Check **Unlock icon** and a faint highlight appears; drag him anywhere, then uncheck it so he stays put. **Reset position** puts him back. His spot is saved in `CampingNotesDB`. By default he is visible only while the Welcoming Campfire buff is on you (about a minute, from sitting near a campfire). Uncheck **Show icon only during Welcoming Campfire** to leave him up all the time. Scale, opacity, and the backdrop follow the other settings. A small countdown shows when the client tells us when the buff ends.

Click locked Tyrion to open **Camp Notes**. That panel is where other players' shared loot notes will go. Sharing is not built yet, so it says `No notes from other campers yet` and, underneath, lists a few of your own most-looted mobs.

`/camp` opens settings. `/camp bestiary` opens the bestiary. `/camp reset` erases loot notes and keeps settings, including where Tyrion sits.

The bestiary lists every mob in your notes, A to Z. The search box filters that list as you type. Click a mob to see how many times you looted it and every drop you have recorded, with the same rarity colors as the tooltip. A button in the settings window opens it too. Shared notes from other campers are not merged in yet. When they are, they will come through the same list.

## The Interface number

`CampingNotes/CampingNotes.toc` has `## Interface: 00000`. That `00000` is a placeholder, so replace it before you test. Type this in-game and put the number it prints in place of `00000`:

```
/dump select(4, GetBuildInfo())
```

That number comes from your own Forever client. The addon list uses it to decide whether the addon matches the client.

## Install and test

1. Copy the `CampingNotes` folder into the Forever client's `Interface/AddOns` folder, so the `.toc` sits directly at `Interface/AddOns/CampingNotes/CampingNotes.toc`.
2. On the character-select screen, open AddOns and enable Camping Notes.
3. Turn on Lua errors so mistakes show up in chat: `/console scriptErrors 1`
4. Log in and look for this chat line: `Camping Notes loaded! hello, adventurer.`
5. Kill and loot several creatures with the same name. Let each corpse become your target (opening loot usually does that) and leave it selected until the window closes. Do not reopen the window.
6. Hover another creature with that name. The tooltip should list up to five drops, a percentage for each, and how many loots were recorded. With rarity colors on, the item lines use grey, white, green, blue, purple, or orange.
7. Click the round Tyrion button on the minimap. The settings window opens. Drag the sliders, and toggle the backdrop and rarity checkboxes. Check **Unlock icon**, drag Tyrion somewhere else on the screen, then uncheck it. Click **Reset position** if you want the original spot back.
8. Type `/reload`. Open settings again. The sliders, checkboxes, and Tyrion's position should still match what you set. Drag the minimap button, `/reload`, and it should stay where you left it.
9. With **Show icon only during Welcoming Campfire** checked, sit at a campfire until that buff is on you. Tyrion should show for about 60 seconds, then hide. If a timer is available, a small countdown sits under him. Uncheck that setting and Tyrion stays visible without the buff.
10. While Tyrion is locked, click him. Camp Notes opens and includes the line `No notes from other campers yet`.
11. Type `/camp` to open settings. Type `/camp reset`. Loot notes clear. Open settings again and confirm the sliders and Tyrion's position did not reset.
12. Loot a few different creatures, then type `/camp bestiary` (or click **Bestiary** in settings). They are listed A to Z. Type part of a name in the search box and the list narrows. Click a mob and confirm every drop is listed, not only five, with percentages.
13. After you edit the addon, type `/reload` to load the new files without restarting the game.

## Limitations

- Mobs are stored by name. Every creature with that name shares one history. `/dump UnitGUID("target")` is the in-game check for a unique id. The addon does not call `UnitGUID` yet. `MobKey` in `Loot.lua` is the function to change if that dump prints an id.
- Opening the loot window again while the same corpse stays targeted does not add another count. Skinning that corpse while it stays targeted is ignored for the same reason. If you select something else and then come back, the next window can be counted, including a skin.
- Chests, herbs, ore, and fishing are ignored when your target is not a dead creature. A dead creature that stays targeted while you open a chest can receive that chest's items.
- The tooltip hook tries `OnTooltipSetUnit`, then `OnShow`, then a `SetUnit` wrapper. `HookUnitTooltip` in `Loot.lua` is that choice. If the extra lines never show up, that function is the piece to replace.
- Welcoming Campfire is detected by the buff name or spell ids 1289723 and 1229739. If this client returns neither, Tyrion stays hidden while **Show icon only during Welcoming Campfire** is checked. Uncheck it to keep him visible. `WelcomingCampfireRemaining` in `UI.lua` is that function.
- Tyrion's on-screen picture is a saved screen position you set with **Unlock icon**. Anchoring him over your character's head is not built.
- Camp Notes does not receive other players' notes yet. The panel is the place that will go. The bestiary reads mobs through `BestiaryEntries` in `Loot.lua`. That function is where shared notes will be merged.
- Sharing notes with other players is not built yet.
- This was checked with a Lua parser and a texture-header check, not inside the game.

## Credits

The icon, Tyrion the corgi, was drawn by [General Pedro](https://ko-fi.com/generalpedro).
