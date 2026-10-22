-- Pathfinder.Loc
--
-- Liest die Ausgabe von /pos (deutsch) bzw. /loc (englisch) und rechnet sie
-- in die Laengen-/Breitengrade von LotroCompanion um. Reine Funktionen ohne
-- Turbine-Aufrufe, damit sie sich ausserhalb des Spiels testen lassen.
--
--   Ihr seid auf dem Server "Landroval" (61) in r2 lx789 ly653 i59
--   ox114.27 oy110.14 oz216.05 h291.1. Spiel-Zeitstempel 418163081.150.

Pathfinder = Pathfinder or {}

local Loc = {}
Pathfinder.Loc = Loc

-- Eine Einheit Laenge/Breite sind 200 m
Loc.METERS_PER_UNIT = 200

-- The German client's tonumber() only understands a comma as decimal point
function Loc.ToNumber(text)
    if text == nil then
        return nil
    end
    return tonumber(text) or tonumber((text:gsub("%.", ","))) or tonumber((text:gsub(",", ".")))
end

-- Returns { region, lon, lat, heading } or nil if the message is no position
function Loc.Parse(message)
    if type(message) ~= "string" then
        return nil
    end
    local r, lx, ly = message:match("r(%d+)%s+lx(%d+)%s+ly(%d+)")
    if r == nil then
        return nil
    end
    local ox = message:match("ox(%-?[%d%.,]+)")
    local oy = message:match("oy(%-?[%d%.,]+)")
    if ox == nil or oy == nil then
        return nil
    end
    -- Strip a trailing sentence dot ("h291.1.")
    local h = message:match("oz%-?[%d%.,]+%s+h([%d%.,]+)")
    if h ~= nil then
        h = h:gsub("[%.,]$", "")
    end
    local lon, lat = Loc.ToLonLat(tonumber(lx), tonumber(ly), Loc.ToNumber(ox), Loc.ToNumber(oy))
    if lon == nil then
        return nil
    end
    return {
        region = tonumber(r),
        lon = lon,
        lat = lat,
        heading = Loc.ToNumber(h),
    }
end

-- Same formula as the Waypoint plugin and LotroCompanion
function Loc.ToLonLat(lx, ly, ox, oy)
    if lx == nil or ly == nil or ox == nil or oy == nil then
        return nil
    end
    local lon = (math.floor(lx / 8) * 160 + ox - 29360) / 200
    local lat = (math.floor(ly / 8) * 160 + oy - 24880) / 200
    return lon, lat
end

function Loc.Distance(lon1, lat1, lon2, lat2)
    local dx = lon2 - lon1
    local dy = lat2 - lat1
    return math.sqrt(dx * dx + dy * dy) * Loc.METERS_PER_UNIT
end

-- Meters from point p to the segment a-b
function Loc.SegmentDistance(plon, plat, alon, alat, blon, blat)
    local dx, dy = blon - alon, blat - alat
    local len2 = dx * dx + dy * dy
    local t = 0
    if len2 > 0 then
        t = math.max(0, math.min(1, ((plon - alon) * dx + (plat - alat) * dy) / len2))
    end
    return Loc.Distance(plon, plat, alon + t * dx, alat + t * dy)
end

-- Compass bearing from 1 to 2: 0 = north, 90 = east
function Loc.Bearing(lon1, lat1, lon2, lat2)
    local deg = math.deg(math.atan2(lon2 - lon1, lat2 - lat1))
    return deg % 360
end

-- Rotation for an arrow image that points up at 0 degrees, as in the
-- Waypoint plugin: heading minus bearing. flip mirrors it in case the
-- game turns the other way.
function Loc.ArrowRotation(heading, bearing, flip)
    local rotation = ((heading or 0) - bearing) % 360
    if flip then
        rotation = (360 - rotation) % 360
    end
    return rotation
end

-- Controls can't be rotated, the arrows exist as 36 images (10 degrees
-- each, counterclockwise). Returns the image suffix, e.g. "09".
Loc.FRAMES = 36

function Loc.Frame(rotation)
    local k = math.floor((rotation or 0) * Loc.FRAMES / 360 + 0.5) % Loc.FRAMES
    return string.format("%02d", k)
end

-- "30,2S, 51,4W" in German notation (O for east), "30.2S, 51.4W" in English
function Loc.Format(lon, lat)
    local english = Pathfinder.Lang == "en"
    local function num(v)
        return (string.format("%.1f", math.abs(v)):gsub("[%.,]", english and "." or ","))
    end
    return num(lat) .. (lat < 0 and "S" or "N") .. ", " .. num(lon) .. (lon < 0 and "W" or (english and "E" or "O"))
end
