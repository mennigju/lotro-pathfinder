-- Pathfinder.Routes: Verzeichnis aller Routen. Die generierten Dateien in
-- Routes/ melden sich hier mit Register() an.

Pathfinder = Pathfinder or {}

local Routes = { list = {}, byId = {}, areas = {} }
Pathfinder.Routes = Routes

-- The map images are 1024x768 pixels, factor = pixels per lon/lat unit
Routes.MAP_WIDTH = 1024
Routes.MAP_HEIGHT = 768

-- English texts are stored only where they differ (name_en, deed_en).
-- The German ones stay available as name_de/deed_de for chat matching.
local function localize(route)
    if Pathfinder.Lang ~= "en" then
        return
    end
    route.name = route.name_en or route.name
    for _, point in ipairs(route.points) do
        point.name_de, point.deed_de = point.name, point.deed
        point.name = point.name_en or point.name
        point.deed = point.deed_en or point.deed
    end
end

function Routes.Register(route)
    if Routes.byId[route.id] ~= nil then
        return
    end
    localize(route)
    table.insert(Routes.list, route)
    Routes.byId[route.id] = route
end

-- Slayer farming areas of a map: circles where many monsters of a deed are
function Routes.RegisterAreas(group)
    for _, area in ipairs(group.areas) do
        if Pathfinder.Lang == "en" then
            area.deed = area.deed_en or area.deed
        end
        area.region = group.region
        table.insert(Routes.areas, area)
    end
end

function Routes.AreasIn(region)
    local result = {}
    for _, area in ipairs(Routes.areas) do
        if area.region == region then
            table.insert(result, area)
        end
    end
    return result
end

function Routes.Contains(route, lon, lat)
    local map = route.map
    if map == nil then
        return false
    end
    local x = (lon - map.lon) * map.factor
    local y = (map.lat - lat) * map.factor
    return x >= 0 and y >= 0 and x <= Routes.MAP_WIDTH and y <= Routes.MAP_HEIGHT
end

-- Routes whose map contains the position, most detailed map first.
-- Routes without region (instances) count in every region.
function Routes.At(pos)
    local result = {}
    for _, route in ipairs(Routes.list) do
        if (route.region == nil or route.region == pos.region) and Routes.Contains(route, pos.lon, pos.lat) then
            table.insert(result, route)
        end
    end
    table.sort(result, function(a, b)
        if a.map.factor ~= b.map.factor then
            return a.map.factor > b.map.factor
        end
        return a.name < b.name
    end)
    return result
end

-- Case-insensitive search in the route names
function Routes.Find(text)
    local result = {}
    local needle = string.lower(text or "")
    for _, route in ipairs(Routes.list) do
        if needle == "" or string.find(string.lower(route.name), needle, 1, true) then
            table.insert(result, route)
        end
    end
    table.sort(result, function(a, b) return a.name < b.name end)
    return result
end
