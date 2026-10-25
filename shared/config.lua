--[[
    spraypaint - graffiti system for MTA:SA
    Spraying walls with a spray can, wiping graffiti off with a cloth.
]]--

Config = {}

-- ─── Database ────────────────────────────────────────────────────────────────

-- The resource talks to the database directly through MTA's own db functions,
-- so no database resource is needed. The table is created automatically.
--   type = "sqlite" → a file next to the resource, zero setup (default)
--   type = "mysql"  → shared with the rest of your server
Config.Database = {
    type  = "sqlite",
    table = "spraypaint",

    -- sqlite
    file  = "spraypaint.db",

    -- mysql
    host     = "127.0.0.1",
    port     = 3306,
    name     = "mta",
    user     = "root",
    password = "",
}

-- ─── Items ───────────────────────────────────────────────────────────────────

Config.SprayItem = "spraypaint"     -- item that starts spraying
Config.ClothItem = "spraycloth"     -- item that starts wiping

-- Require the player to own those items. Needs an inventory wired up in
-- server/s_integration.lua - with the standalone default everyone can spray.
Config.RequireItems = false

-- The item is taken on SAVE, not when spraying starts, so cancelling is free.
Config.ConsumeSprayOnSave = true
Config.ConsumeClothOnSave = true

-- ─── Commands ────────────────────────────────────────────────────────────────

Config.Command        = "spray"
Config.EraseCommand   = "wipespray"
Config.AdminCommand   = "sprayadmin"
Config.UseCommand     = true        -- false = only usable through an inventory item
Config.AdminRight     = "command.kick"  -- ACL right required for the admin command
Config.AdminAuthorRadius = 80       -- m: range of the author labels overlay

-- ─── Canvas ──────────────────────────────────────────────────────────────────

Config.CanvasSize = 512             -- render target resolution (px, square)

-- Texture orientation on the wall. dxDrawMaterialLine3D maps a texture onto the
-- surface rotated by 90°, these values rotate it back. Verified in-game -
-- only worth touching if you change how the surface is drawn.
-- Applies to the WALL only, never to the editor (which draws 1:1).
Config.WallRotation   = 90          -- 0, 90, 180 or 270 degrees clockwise
Config.FlipVertical   = false
Config.FlipHorizontal = false

-- ─── Surface in the world ────────────────────────────────────────────────────

Config.MaxAreaWidth  = 5.0          -- max surface width in metres
Config.MaxAreaHeight = 5.0          -- max surface height in metres
Config.MinAreaSize   = 0.3          -- min length of a side in metres
Config.WallOffset    = 0.02         -- offset from the wall (against z-fighting)

-- ─── Spraying ────────────────────────────────────────────────────────────────

Config.SprayDuration      = 6000    -- length of the spraying animation (ms)
Config.SprayMoveTolerance = 3.0     -- headroom below the server distance limit
Config.EraseDuration      = 4000    -- length of the wiping animation (ms)

-- ─── Distances ───────────────────────────────────────────────────────────────

Config.SelectionMaxDistance = 10.0  -- range when marking the corners
Config.EraserMaxDistance    = 4.0   -- max distance when wiping
Config.RenderDistance       = 60.0  -- graffiti is drawn from this distance
Config.UnloadDistance       = 90.0  -- beyond this the render target is freed
-- The server rejects a save if the player is further from the centre of the
-- surface than this. A 10 m selection plus half the canvas diagonal has to fit,
-- hence the headroom.
Config.MaxSaveDistance      = 20.0
Config.StreamRadius         = 250.0 -- radius in which the server sends graffiti to a client

-- ─── Performance ─────────────────────────────────────────────────────────────

Config.MaxActiveRenderers    = 20   -- max graffiti drawn at the same time
Config.RendererCheckInterval = 1000 -- ms between distance checks
-- Minimum spacing of recorded points in canvas coordinates (0..1).
-- Points are sampled every frame; this threshold keeps the density sane.
-- 0.006 ≈ 3 px on a 512 canvas. The thinnest brush is 5 px wide, so denser
-- sampling is invisible - it only inflates the data and fills the canvas.
Config.MinPointDistance      = 0.006

-- ─── Brushes ─────────────────────────────────────────────────────────────────

-- size = radius of the blob in canvas pixels, scatter = droplet spread
Config.BrushSizes = {
    { name = "Thin",   size = 5,  scatter = 3,  drops = 3 },
    { name = "Medium", size = 11, scatter = 7,  drops = 5 },
    { name = "Thick",  size = 22, scatter = 14, drops = 8 },
}

Config.DefaultBrush = 1

-- ─── Colors ──────────────────────────────────────────────────────────────────

Config.Colors = {
    { name = "Black",  rgb = {  0,   0,   0} },
    { name = "White",  rgb = {255, 255, 255} },
    { name = "Red",    rgb = {255,  40,  40} },
    { name = "Green",  rgb = { 40, 220,  60} },
    { name = "Blue",   rgb = { 50, 110, 255} },
    { name = "Yellow", rgb = {255, 225,  50} },
    { name = "Orange", rgb = {255, 140,  20} },
    { name = "Purple", rgb = {160,  60, 255} },
    { name = "Pink",   rgb = {255,  70, 180} },
    { name = "Cyan",   rgb = { 40, 230, 230} },
}

Config.DefaultColor = 1

-- Colored spray variants: item name -> index into Config.Colors.
-- When a player uses one of these, the color picker is locked.
Config.ColoredItems = {
    -- ["spraypaint_red"]  = 3,
    -- ["spraypaint_blue"] = 5,
}

-- ─── Limits ──────────────────────────────────────────────────────────────────

Config.MaxStrokes         = 400     -- max strokes per graffiti
Config.MaxPointsPerStroke = 3000    -- max points in a single stroke
Config.MaxTotalPoints     = 25000   -- max points overall (size cap of a drawing)
Config.MaxPerPlayer       = 0       -- max graffiti per player (0 = unlimited)

-- ─── Animations and props ────────────────────────────────────────────────────

Config.SprayAnimBlock = "SPRAYCAN"
Config.SprayAnimName  = "spraycan_full"
Config.SprayCanModel  = 365         -- object held in hand (365 = spraycan)

Config.ClothAnimBlock = "SPRAYCAN"
Config.ClothAnimName  = "spraycan_full"
Config.ClothModel     = nil         -- object ID of the cloth, nil = no prop

-- Where a held prop sits in the hand (bone 12 = right hand).
Config.PropAttach = {
    bone = 12,
    pos  = { 0.05, 0.03, 0.0 },
    rot  = { 0, 0, 0 },
}

-- ─── Keys ────────────────────────────────────────────────────────────────────

Config.Keys = {
    Action    = "mouse1",     -- mark a corner / confirm the graffiti to wipe
    Confirm   = "enter",      -- confirm the drawing in the editor
    Cancel    = "backspace",  -- cancel
    Undo      = "z",          -- undo the last stroke in the editor
    BrushUp   = "mouse_wheel_up",
    BrushDown = "mouse_wheel_down",
}

-- ─── Blacklisted zones ───────────────────────────────────────────────────────

Config.BlacklistedZones = {
    -- { x = 0.0, y = 0.0, z = 0.0, radius = 50.0 },
}

-- ─── Logging ─────────────────────────────────────────────────────────────────

Config.LogCreate = true
Config.LogDelete = true
Config.LogErase  = false            -- wiping is frequent, off by default

-- Optional Discord webhook for those logs (no extra resource needed).
-- Empty string = only the server log is written.
Config.DiscordWebhook = ""
