--[[
    spraypaint - wiping with the cloth

    The player aims at a graffiti, confirms it with the left button, and after
    the wiping animation the whole graffiti disappears. The cloth is only taken
    once it finishes - interrupting costs nothing.
]]--

Eraser = {}

local active = false
local target = nil      -- the graffiti being aimed at
local wiping = nil      -- { id, startedAt } during the animation
local prop   = nil

local blockedControls  = { "fire", "aim_weapon", "next_weapon", "previous_weapon", "action" }
local movementControls = { "forwards", "backwards", "left", "right", "jump", "sprint" }

-- ─── Prop ────────────────────────────────────────────────────────────────────

local function attachProp()
    if not Config.ClothModel then return end
    prop = createObject(Config.ClothModel, 0, 0, 0)
    if not prop then return end
    setElementCollisionsEnabled(prop, false)

    local a = Config.PropAttach
    BoneAttach.attach(prop, localPlayer, a.bone,
        a.pos[1], a.pos[2], a.pos[3],
        a.rot[1], a.rot[2], a.rot[3])
end

local function removeProp()
    if isElement(prop) then
        BoneAttach.detach(prop)
        destroyElement(prop)
    end
    prop = nil
end

local function notify(text, color)
    Notify("Cloth", text, color or {255, 150, 50})
end

-- ─── Start and stop ──────────────────────────────────────────────────────────

function Eraser.stop(silent)
    if not active then return end

    active = false
    target = nil
    wiping = nil

    for _, c in ipairs(blockedControls)  do toggleControl(c, true) end
    for _, c in ipairs(movementControls) do toggleControl(c, true) end

    removeProp()
    setPedAnimation(localPlayer, false)
    setElementData(localPlayer, "spraypaint:busy", false, false)

    unbindKey(Config.Keys.Action, "down", Eraser.onAction)
    unbindKey(Config.Keys.Cancel, "down", Eraser.onCancel)

    if not silent then
        notify("Wiping stopped.", {200, 200, 200})
    end
end

function Eraser.start()
    if active or Paint.getMode() then return end
    if isPedInVehicle(localPlayer) then
        return notify("Not possible inside a vehicle.", {255, 80, 80})
    end

    active = true
    for _, c in ipairs(blockedControls) do toggleControl(c, false) end
    attachProp()
    setElementData(localPlayer, "spraypaint:busy", true, false)

    bindKey(Config.Keys.Action, "down", Eraser.onAction)
    bindKey(Config.Keys.Cancel, "down", Eraser.onCancel)

    notify("Aim at a graffiti and wipe it with the left button. Backspace cancels.",
           {120, 220, 255})
end

addEvent("spraypaint:beginErase", true)
addEventHandler("spraypaint:beginErase", root, function()
    Eraser.start()
end)

function Eraser.isActive() return active end

-- ─── Aiming ──────────────────────────────────────────────────────────────────

-- The graffiti the player is aiming at (nearest ray/surface intersection).
local function findAimedGraffiti()
    local ox, oy, oz, dx, dy, dz = Aim.getRay()
    local dim, int = getElementDimension(localPlayer), getElementInterior(localPlayer)

    local best, bestT = nil, math.huge

    for _, g in pairs(Graffiti) do
        if g.dimension == dim and g.interior == int then
            local u, _, t = Util.rayToCanvasUV(g, ox, oy, oz, dx, dy, dz)
            if u and t <= Config.EraserMaxDistance and t < bestT then
                best, bestT = g, t
            end
        end
    end

    return best
end

-- ─── Actions ─────────────────────────────────────────────────────────────────

function Eraser.onAction()
    if not active or wiping then return end

    if not target then
        return notify("Aim at a graffiti in range.")
    end

    -- During the animation only the ID is kept, not a reference to the record:
    -- that can disappear in the meantime (re-stream from the server, another
    -- player deleting it).
    wiping = { id = target.id, startedAt = getTickCount() }
    for _, c in ipairs(movementControls) do toggleControl(c, false) end
    setPedAnimation(localPlayer, Config.ClothAnimBlock, Config.ClothAnimName, -1, true, false, false)
end

function Eraser.onCancel()
    if not active then return end
    Eraser.stop()
end

-- ─── Wiping progress ─────────────────────────────────────────────────────────

local function updateWiping()
    local g = Graffiti[wiping.id]
    if not g then
        notify("That graffiti is gone.")
        return Eraser.stop(true)
    end

    local px, py, pz = getElementPosition(localPlayer)
    if Util.dist3D(px, py, pz, g.x, g.y, g.z) > Config.EraserMaxDistance + 2.0 then
        notify("You moved away, wiping aborted.")
        return Eraser.stop(true)
    end

    if getTickCount() - wiping.startedAt >= Config.EraseDuration then
        triggerServerEvent("spraypaint:erase", localPlayer, wiping.id)
        Eraser.stop(true)
    end
end

-- ─── Render loop ─────────────────────────────────────────────────────────────

addEventHandler("onClientRender", root, function()
    if not active then return end

    if wiping then
        local id, startedAt = wiping.id, wiping.startedAt
        updateWiping()
        if not active then return end       -- updateWiping may have ended the mode

        HUD_drawEraser(Graffiti[id], (getTickCount() - startedAt) / Config.EraseDuration)
        return
    end

    -- The target is only searched for outside the animation, so it cannot
    -- switch while wiping
    target = findAimedGraffiti()
    HUD_drawEraser(target, nil)
end)
