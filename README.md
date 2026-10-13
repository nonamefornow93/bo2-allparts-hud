# All Parts HUD + Origins-style multi-part carrying

A script mod for **Call of Duty: Black Ops II Zombies on [Plutonium](https://plutonium.pw) (T6)** that lets you carry many buildable parts at once, build a whole buildable in a single hold, and see a parts panel and pickup readout.

**Maps:** Tranzit (`zm_transit`), Die Rise (`zm_highrise`), Buried (`zm_buried`).

---

## Features

### 1. Parts panel (all 3 maps)
A panel under your score shows, for every buildable:

- its name,
- how many of its parts you are carrying (for example `2/3`),
- an icon for every part: **bright = you carry it, dark = you don't**,
- the row turns **green** when that buildable is finished, and keeps showing the full set (for example `3/3`) with every part icon filled — even after the parts have been used, so a finished buildable always reads complete.

The header shows your total carried parts and how many buildables are finished, for example:

```
PARTS (4)    2/9 BUILT
```

The panel is hidden by default. **Hold `TAB`** to show it, release to hide it.

### 2. Carry many parts at once (Tranzit + Die Rise)
Every part type gets its own inventory slot, so you can sweep the map and carry one of everything — Origins/BO3 style.

A build table only lights up once you are carrying the **whole remaining set** of parts for that buildable; while you are still missing some, it only tells you that more parts are needed. With the full set, **one hold on `USE`** builds every part at once and finishes the buildable — no more feeding a table one part at a time, and no half-built tables that refuse the last part.

> **NOTE:** Buried keeps the normal one-part-at-a-time behaviour (plus its own booze/candy/keys item) because that map's sloth AI depends on it. The panel and the pickup feedback still work on Buried.

Parts still spawn at **one random spot each game**, exactly like the normal game — all parts are on the map from round 1, you just have to find them.

### 3. Pickup notification (all 3 maps)
The original game's little corner "carried part" icon is hidden. Instead, when you pick a part up, a readout appears in the **top-left corner** showing the buildable's icon (one fixed icon for the whole buildable) and how many of its parts you are carrying, for example:

```
[icon]  1/3 parts
```

It fades away a few seconds after you pick the part up. The count turns **green** once you are carrying the whole set (e.g. `3/3 parts`), so you can see at a glance that the table is ready to build. (The part is still carried normally and still builds at the workbenches — only the old single-part corner icon is gone.)

The readout uses the game's own small HUD font, so it is already tiny. If you want to resize it, set this console dvar (1 = default; it applies on your next pickup):

```
allparts_pickup_scale 1
```

### 4. Pickup & complete feedback (all 3 maps)
- Picking a part up gives a short white screen flash. The game's own pickup sound (`zmb_buildable_pickup`) still plays.
- When a buildable is finished, a green **`<NAME> COMPLETE`** banner pops up just under the crosshair. The game's own completion sound still plays.

---

## Install

### Automatic
1. Run **`install.bat`** (it copies `zm_allparts_hud.gsc` into your Plutonium scripts folder and sets the keys).
2. **Completely close** Plutonium and Black Ops II.
3. Start the game and play Zombies on Tranzit, Die Rise or Buried.

### Manual
1. Copy `zm_allparts_hud.gsc` to:
   ```
   %LOCALAPPDATA%\Plutonium\storage\t6\scripts\zm\
   ```
   (create the folders if they don't exist — full path is `C:\Users\<you>\AppData\Local\Plutonium\storage\t6\scripts\zm\`).
2. Open the console (the `~` key) and type:
   ```
   bind TAB "+switchseat"
   bind B   "+scores"
   ```
3. **Completely close** Plutonium and Black Ops II, then start again.

> Scripts are only loaded when the game starts — you must fully restart Plutonium/BO2 after installing.

---

## Keys

| Key | Action |
|-----|--------|
| `TAB` (hold) | Show the parts panel |
| `B` | Scoreboard |

`TAB` is bound to `+switchseat` (an input that has no effect in Zombies). The script reads its held state, which is how the panel knows `TAB` is down. `B` is bound to `+scores`, moving the scoreboard off `TAB`.

If holding `TAB` does nothing, re-apply the two binds above in the console — some mods/menus reset your key binds when loaded.

---

## Map support

| Map | Multi-part carry + full-set build | Parts panel | Pickup feedback |
|-----|:---:|:---:|:---:|
| Tranzit | ✅ | ✅ | ✅ |
| Die Rise | ✅ | ✅ | ✅ |
| Buried | ❌ (vanilla one-at-a-time) | ✅ | ✅ |

The mod only activates on those three maps and does nothing elsewhere.

---

## Troubleshooting

- **Nothing happens in game:** make sure the file is exactly in `storage\t6\scripts\zm`, and fully restart the Plutonium launcher and the game.
- **Holding `TAB` does nothing:** re-apply the two console binds above.
- **Down (last stand):** your carried parts drop next to you, exactly like the normal game.
- **The panel lists small single-item rows** like Booze or Chalk on Buried — that is normal.

---

## License

[MIT](LICENSE) — do whatever you like, just keep the copyright notice.
