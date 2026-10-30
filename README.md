# forever-tracker

A beginner addon for the WoW Forever client (classic-style, game version 1.60.x).

## What it does right now

ForeverTracker prints one line to the chat window when you log in:

> ForeverTracker loaded! hello, adventurer.

That is all. There is no tracking, no saved data, no slash commands, and no on-screen window yet. Later steps will add tracking (gold, loot, quests, and so on) one piece at a time.

## The Interface number

`ForeverTracker/ForeverTracker.toc` has `## Interface: 00000`. That `00000` is a placeholder, not a real client number, so do not leave it as-is. Before you test, replace it with the number from this command, typed in-game:

```
/dump select(4, GetBuildInfo())
```

That number comes from your own Forever client. The addon list uses it to decide whether the addon matches the client.

## Install and test

1. Copy the `ForeverTracker` folder into the Forever client's `Interface/AddOns` folder, so the `.toc` sits directly at `Interface/AddOns/ForeverTracker/ForeverTracker.toc`.
2. On the character-select screen, open AddOns and enable ForeverTracker.
3. Turn on Lua errors so mistakes show up in chat: `/console scriptErrors 1`
4. Log in and look for this chat line: `ForeverTracker loaded! hello, adventurer.`
5. After you edit the addon, type `/reload` to load the new files without restarting the game.
