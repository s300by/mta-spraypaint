# spraypaint

Graffiti system for **MTA:SA**. A player marks an area on a wall, sprays a
drawing onto it, and the result is stored in a database — everyone nearby sees
it. A cloth wipes graffiti back off.

Standalone resource: no inventory, database, notification or bone-attach
resource is required. SQLite is used by default, so there is nothing to set up.
If you do run a framework, there is one file to plug it into — see
[Integration](#integration).

## Features

- Free-hand drawing in an in-game editor: 10 colors, 3 brushes, undo, clear
- The graffiti grows on the wall during a ~6 s spraying animation
- Stored as **strokes, not an image** — a few kB per graffiti, not hundreds
- Server-side validation of geometry, distance and stroke data
- Wiping with a cloth, with its own animation
- Streaming with a hard cap on how many graffiti are rendered at once
- Admin tools: list, delete, teleport, bulk clear, author labels
- Optional Discord logging through a webhook

## Installation

1. Copy the `spraypaint` folder into your server's `resources/` directory.
2. `start spraypaint`
3. In-game: `/spray` to spray, `/wipespray` to wipe.

The table is created automatically on first start. With the default SQLite
setup it lands in `spraypaint.db` next to the resource (and is excluded by
`.gitignore`).

To share your server's MySQL database instead, edit `Config.Database`:

```lua
Config.Database = {
    type = "mysql",
    table = "spraypaint",
    host = "127.0.0.1", port = 3306,
    name = "mta", user = "root", password = "secret",
}
```

## Controls

**Spraying** — `/spray`, or an inventory item (see below). Three steps:

**1. Pick the surface.** Aim at a wall and click the first corner with the left
button, then the second. A rectangle is formed. Both corners have to be on the
same wall.

**2. Draw.** The editor opens with a canvas. Draw the design with the mouse:

| Input | Action |
|---|---|
| Left button (drag) | draw |
| Click a color / 1–9, 0 | pick a color |
| Click a brush / mouse wheel | brush size |
| Z or the Undo button | undo the last stroke |
| Clear all | wipe the canvas |
| Spray it / Enter | confirm |
| Cancel / Backspace | discard |

**3. Spraying.** The editor closes, the player turns to the wall and the
animation starts. The graffiti grows on the wall over ~6 s
(`Config.SprayDuration`). Only once it finishes is it saved on the server and
the item taken — interrupting with Backspace keeps the item.

**Wiping** — `/wipespray`, or the cloth item. Aim at a graffiti (it gets an
orange outline) and confirm with the left button. After the wiping animation
(~4 s, `Config.EraseDuration`) the graffiti disappears entirely and the cloth
is taken. Backspace interrupts at any time, and then the item stays.

## Admin

`/sprayadmin` requires the ACL right from `Config.AdminRight`
(`command.kick` by default):

| Command | Description |
|---|---|
| `list [radius]` | list graffiti nearby with their ID and author |
| `authors` | toggle in-game author labels |
| `delete <id>` | delete one graffiti |
| `tp <id>` | teleport to a graffiti |
| `clear <radius>` | delete everything nearby |
| `player <id\|name>` | delete every graffiti of that player |

Creating and deleting is written to the server log, and posted to Discord when
`Config.DiscordWebhook` is set. Wiping is logged only if `Config.LogErase` is
turned on — it tends to be frequent.

## Configuration

Everything is in `shared/config.lua`. The settings that get tuned most often:

- `Config.Database` — sqlite (default) or mysql.
- `Config.WallRotation` (0/90/180/270) and `Config.FlipVertical` /
  `FlipHorizontal` — orientation of the image on the wall.
  `dxDrawMaterialLine3D` maps a texture onto the surface rotated by 90°, hence
  the default rotation of 90. These values are verified in-game; they are only
  worth touching if you change how the surface is drawn. **Applies to the wall
  only, never to the editor** — the editor canvas is drawn 1:1 so the player
  sees exactly what they draw.
- `Config.SprayDuration` / `EraseDuration` — animation lengths (6000 / 4000 ms).
- `Config.MaxTotalPoints` — size cap of a drawing (25000 points). The player
  sees the usage as a percentage in the editor, and a drawing that is too
  complex is rejected **before** the animation, not after it.
- `Config.MinPointDistance` — stroke sampling density (0.006 ≈ 3 px). Lower =
  smoother curves, but the canvas fills up faster.
- `Config.CanvasSize` — canvas resolution (512). Higher = sharper, but costlier.
- `Config.MaxActiveRenderers` — how many graffiti may be drawn at once (20).
- `Config.Colors` / `Config.BrushSizes` — palette and brushes.
- `Config.BlacklistedZones` — where spraying is not allowed.
- `Config.ColoredItems` — spray variants with a locked color, e.g.:

  ```lua
  Config.ColoredItems = {
      ["spraypaint_red"] = 3,   -- index into Config.Colors
  }
  ```

## Integration

Out of the box `Config.RequireItems = false`, so anyone can use `/spray`.
To hook it up to your own systems, edit `server/s_integration.lua`:

| Function | Default behaviour |
|---|---|
| `Integration.countItem(plr, item)` | returns 1 — everyone "owns" a can |
| `Integration.takeItem(plr, item, count)` | no-op |
| `Integration.getOwnerId(plr)` | the player's account name |
| `Integration.isAdmin(plr)` | ACL right from `Config.AdminRight` |
| `Integration.notify(plr, title, text, color)` | the built-in popup from `c_notify.lua` |
| `Integration.onGraffitiErased(plr, g)` | empty hook (payouts, job progress, …) |

Example:

```lua
function Integration.countItem(plr, item)
    return tonumber(exports["my-inventory"]:countPlayerItem(plr, item)) or 0
end

function Integration.takeItem(plr, item, count)
    return exports["my-inventory"]:takePlayerItem(plr, item, count)
end
```

Then set `Config.RequireItems = true` and add two items named after
`Config.SprayItem` / `Config.ClothItem` to your inventory. Trigger these client
events when an item is used:

```lua
triggerClientEvent(plr, "spraypaint:itemUse",  plr)   -- spray can
triggerClientEvent(plr, "spraypaint:clothUse", plr)   -- cloth
```

Set `Config.UseCommand = false` if you want the items to be the only way in.

The resource also exports two server functions:

```lua
exports.spraypaint:Spray_getAll()     -- every graffiti currently loaded
exports.spraypaint:Spray_delete(id)   -- delete one
```

## How it works

A graffiti is **not stored as an image** but as a list of strokes — color,
brush and points in canvas coordinates 0–1. In the database that is JSON, so one
graffiti costs single-digit kilobytes instead of hundreds.

On the client the strokes are drawn into a `dxCreateRenderTarget`, which is then
projected onto the wall with `dxDrawMaterialLine3D` as a flat rectangle. The
render target is filled incrementally (only the new points each frame) and a
full redraw has a budget of ~900 blobs per frame, so walking up to a large
graffiti does not tank the FPS.

The editor uses **the same render target and the same stroke format**, just
displayed in 2D on screen. That is why the preview matches the wall exactly and
there are no two drawing paths that could drift apart.

The gradual reveal during the animation uses that same incrementality: points
are only **appended** to the preview canvas as time passes, so nothing is ever
redrawn from scratch.

Only the **wall normal** is stored in the database — the horizontal and vertical
canvas vectors are derived from it (`Util.basisFromNormal`), so there is nothing
to get out of sync.

The server is the only authority: it verifies the item, the player's distance
from the canvas, and the structure and limits of the strokes
(`Util.validateStrokes`). Client data is never trusted — without validation
someone could send a canvas with a million points and tank everyone's FPS.

## Files

```
spraypaint/
├─ meta.xml
├─ shared/
│  ├─ config.lua          -- all settings
│  └─ utils.lua           -- vector math, canvas basis, stroke validation
├─ server/
│  ├─ s_db.lua            -- sqlite/mysql through MTA's own db functions
│  ├─ s_integration.lua   -- inventory / admin / notification hooks
│  ├─ s_main.lua          -- authority: items, validation, saving, streaming
│  └─ s_admin.lua         -- /sprayadmin, logging, author overlay
└─ client/
   ├─ c_notify.lua        -- built-in notification popup
   ├─ c_boneattach.lua    -- minimal bone attachment (replaces bone_attach)
   ├─ c_aim.lua           -- camera ray, wall and canvas hits
   ├─ c_canvas.lua        -- render target, incremental stroke drawing
   ├─ c_render.lua        -- streaming and drawing of saved graffiti
   ├─ c_hud.lua           -- crosshair, hints, progress bars
   ├─ c_editor.lua        -- the drawing editor
   ├─ c_paint.lua         -- the spraying flow
   ├─ c_eraser.lua        -- wiping with the cloth
   ├─ c_main.lua          -- entry points, sync, cleanup
   └─ c_admin_overlay.lua -- author labels for admins
```

## Credits

Written from scratch. Functionally inspired by the FiveM script
`f4-spraypaint`, but no code is shared with it — that script's logic is
escrow-encrypted and cannot be ported.
