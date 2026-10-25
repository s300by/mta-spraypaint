--[[
    spraypaint - database layer.

    Uses MTA's own db functions (dbConnect/dbQuery/dbExec), so the resource does
    not depend on any database resource. SQLite is the default and needs no
    setup at all - the file is created next to the resource on first start.
    Switch Config.Database.type to "mysql" to share your server's database.

    The table is created automatically, so there is no install.sql to forget.
]]--

Db = {}

local connection = nil
local cfg   = Config.Database
local TABLE = cfg.table or "spraypaint"

function Db.table()
    return TABLE
end

function Db.isReady()
    return connection ~= nil
end

-- ─── Connect ─────────────────────────────────────────────────────────────────

local function connect()
    if cfg.type == "mysql" then
        connection = dbConnect("mysql",
            ("dbname=%s;host=%s;port=%d;charset=utf8mb4"):format(
                tostring(cfg.name), tostring(cfg.host), tonumber(cfg.port) or 3306),
            tostring(cfg.user), tostring(cfg.password), "share=1")
    else
        connection = dbConnect("sqlite", cfg.file or "spraypaint.db")
    end

    if not connection then
        outputDebugString("[spraypaint] ERROR: could not connect to the database.", 1)
        outputServerLog("[spraypaint] ERROR: could not connect to the database")
        return false
    end
    return true
end

-- Separate schemas: MySQL wants AUTO_INCREMENT and an engine, SQLite wants
-- INTEGER PRIMARY KEY AUTOINCREMENT and accepts neither.
local function createTable()
    if cfg.type == "mysql" then
        return dbExec(connection, ([[CREATE TABLE IF NOT EXISTS `%s` (
            `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
            `owner_id`    VARCHAR(64) DEFAULT NULL,
            `owner_name`  VARCHAR(64) DEFAULT NULL,
            `x` FLOAT NOT NULL, `y` FLOAT NOT NULL, `z` FLOAT NOT NULL,
            `nx` FLOAT NOT NULL, `ny` FLOAT NOT NULL, `nz` FLOAT NOT NULL,
            `width` FLOAT NOT NULL, `height` FLOAT NOT NULL,
            `dimension` INT NOT NULL DEFAULT 0,
            `interior`  INT NOT NULL DEFAULT 0,
            `strokes` MEDIUMTEXT NOT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `idx_owner` (`owner_id`),
            KEY `idx_pos` (`x`, `y`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]):format(TABLE))
    end

    return dbExec(connection, ([[CREATE TABLE IF NOT EXISTS `%s` (
        `id`         INTEGER PRIMARY KEY AUTOINCREMENT,
        `owner_id`   TEXT,
        `owner_name` TEXT,
        `x` REAL NOT NULL, `y` REAL NOT NULL, `z` REAL NOT NULL,
        `nx` REAL NOT NULL, `ny` REAL NOT NULL, `nz` REAL NOT NULL,
        `width` REAL NOT NULL, `height` REAL NOT NULL,
        `dimension` INTEGER NOT NULL DEFAULT 0,
        `interior`  INTEGER NOT NULL DEFAULT 0,
        `strokes` TEXT NOT NULL,
        `created_at` TEXT DEFAULT CURRENT_TIMESTAMP
    )]]):format(TABLE))
end

function Db.init()
    if not connect() then return false end
    createTable()
    return true
end

-- ─── Queries ─────────────────────────────────────────────────────────────────

function Db.loadAll()
    if not connection then return nil end
    local qh = dbQuery(connection, ("SELECT * FROM `%s`"):format(TABLE))
    if not qh then return nil end
    return dbPoll(qh, -1)
end

-- Inserts a graffiti and returns its new id (nil on failure).
function Db.insert(data, ownerId, ownerName, json)
    if not connection then return nil end

    local qh = dbQuery(connection, ([[INSERT INTO `%s`
        (owner_id, owner_name, x, y, z, nx, ny, nz, width, height, dimension, interior, strokes)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)]]):format(TABLE),
        ownerId, ownerName,
        data.x, data.y, data.z,
        data.nx, data.ny, data.nz,
        data.width, data.height,
        tonumber(data.dimension) or 0, tonumber(data.interior) or 0,
        json)

    if not qh then return nil end

    local _, _, lastId = dbPoll(qh, -1)
    return tonumber(lastId)
end

function Db.delete(id)
    if not connection then return false end
    return dbExec(connection, ("DELETE FROM `%s` WHERE id = ?"):format(TABLE), id)
end
