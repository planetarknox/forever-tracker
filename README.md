# Camping Notes

A beginner addon for the WoW Forever client (classic-style, game version 1.60.x).

Camping Notes is a personal loot-drop notebook. The notes are yours for now. Sharing them with other players is the later goal, and sharing is not built yet.

## What it does right now

When you log in, Camping Notes prints one line in chat:

> Camping Notes loaded! hello, adventurer.

It also keeps a personal history of corpses you loot. Each mob name remembers how many times you opened its loot window, and which items were in that window. Hover a mob and the tooltip gains up to five lines, the items that appeared most often, each with a percentage:

> Chunk of Boar Meat: 75%

The percentage is times that item was in the window, divided by times you looted that mob name. Under those lines is a total, such as `4 loots recorded`. If you have never looted that mob, the tooltip shows one dim line: `no loot data yet`. Players get no extra line.

Coins are skipped. A stack counts once: five meat in one slot is one appearance of that item. A window that contains only coins still counts as one loot. The history is saved across logout in the `CampingNotesDB` table (see SavedVariables in the `.toc`), and every character on the account shares that saved table. That is account storage, not sending notes to other players.

There is still no quest tracking, no on-screen window, and no way to share notes. `/camp` prints a short help line. `/camp reset` erases the history and confirms in chat.

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
6. Hover another creature with that name, alive or dead. The tooltip should list up to five drops, a percentage for each, and how many loots were recorded.
7. Type `/reload`, then hover that kind of creature again. The same numbers should still be there.
8. Type `/camp` for help, then `/camp reset`. The next hover of that creature should show `no loot data yet`.
9. After you edit the addon, type `/reload` to load the new files without restarting the game.

## Limitations

- Mobs are stored by name. Every creature with that name shares one history. Two different boars are not told apart. `/dump UnitGUID("target")` is the in-game check for a unique id. The addon does not call `UnitGUID` yet. `MobKey` in `CampingNotes.lua` is the function to change if that dump prints an id.
- Opening the loot window again while the same corpse stays targeted does not add another count. Skinning that corpse while it stays targeted is ignored for the same reason. If you select something else and then come back, the next window can be counted, including a skin. A corpse whose first window is only the skin (the drops were already taken) stores that skin as a drop.
- Chests, herbs, ore, and fishing are ignored when your target is not a dead creature. A dead creature that stays targeted while you open a chest can receive that chest's items. There is no old loot-source id to separate those.
- The tooltip hook tries `OnTooltipSetUnit`, then `OnShow`, then a `SetUnit` wrapper. `HookUnitTooltip` is that whole choice. Forever's UI comes from the modern client, which removed `OnTooltipSetUnit`. If the extra lines never show up, that function is the piece to replace. This was checked with a Lua parser only, not inside the game.
- Sharing notes with other players is not built yet.
