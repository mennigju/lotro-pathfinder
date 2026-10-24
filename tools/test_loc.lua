-- Tests fuer Loc.lua, RouteState.lua und Registry.lua ausserhalb des Spiels: lua5.1 tools/test_loc.lua

local dir = arg[0]:match("^(.*)/tools/") or "."
dofile(dir .. "/plugin/Pathfinder/Route/Loc.lua")
dofile(dir .. "/plugin/Pathfinder/Route/RouteState.lua")
dofile(dir .. "/plugin/Pathfinder/Route/Registry.lua")

local Loc = Pathfinder.Loc
local failures = 0

local function check(name, cond)
    if not cond then
        failures = failures + 1
        print("FAIL " .. name)
    end
end

local function near(a, b, eps)
    return a ~= nil and b ~= nil and math.abs(a - b) < (eps or 1e-3)
end

-- Example lines from the Waypoint plugin (en/de) and a dungeon line
local de = 'Ihr seid auf dem Server "Landroval" (61) in r2 lx789 ly653 i59 ox114.27 oy110.14 oz216.05 h291.1. Spiel-Zeitstempel 418163081.150.'
local en = "You are on Landroval server 54 at r1 lx956 ly939 ox87.20 oy64.15 oz408.09 h60.5. Game timestamp 418155353.194."
local inside = "You are at: r1 lx1046 ly1147 i29 cInside ox-3.50 oy-12.25 oz-417.78 h358.6"
local noHeading = "Vous vous trouvez sur Landroval, serveur 15,   r2 lx773 ly665 i7 ox102.73 oy34.26 oz302.48. Horodatage du jeu 418161754.100."

local p = Loc.Parse(de)
check("de parsed", p ~= nil)
check("de region", p.region == 2)
check("de lon", near(p.lon, (98 * 160 + 114.27 - 29360) / 200))
check("de lat", near(p.lat, (81 * 160 + 110.14 - 24880) / 200))
check("de heading", near(p.heading, 291.1))

p = Loc.Parse(en)
check("en parsed", p ~= nil and p.region == 1 and near(p.heading, 60.5))

p = Loc.Parse(inside)
check("inside parsed", p ~= nil and near(p.lon, (130 * 160 - 3.5 - 29360) / 200) and near(p.heading, 358.6))

p = Loc.Parse(noHeading)
check("no heading", p ~= nil and p.heading == nil)

check("no position", Loc.Parse("Neue Aufgabe: Etwas") == nil)
check("comma number", near(Loc.ToNumber("12,5"), 12.5))

-- Geometry
check("distance", near(Loc.Distance(0, 0, 0.1, 0), 20))
check("bearing north", near(Loc.Bearing(0, 0, 0, 1), 0))
check("bearing east", near(Loc.Bearing(0, 0, 1, 0), 90))
check("bearing south", near(Loc.Bearing(0, 0, 0, -1), 180))
check("bearing west", near(Loc.Bearing(0, 0, -1, 0), 270))
check("arrow ahead", near(Loc.ArrowRotation(90, 90), 0))
check("arrow waypoint formula", near(Loc.ArrowRotation(0, 90), 270))
check("arrow flip", near(Loc.ArrowRotation(0, 90, true), 90))
check("frame 0", Loc.Frame(0) == "00")
check("frame 90", Loc.Frame(90) == "09")
check("frame rounding", Loc.Frame(356) == "00" and Loc.Frame(14) == "01")
check("frame 270", Loc.Frame(270) == "27")
check("format", Loc.Format(-51.43, -30.2) == "30,2S, 51,4W")
Pathfinder.Lang = "en"
check("format en", Loc.Format(51.43, -30.2) == "30.2S, 51.4E")
Pathfinder.Lang = "de"

-- RouteState: advancing, skipping done points, chat matching
local route = {
    id = "test", name = "Test", region = 1,
    points = {
        { key = "a", lon = 0, lat = 0, name = "Alpha", deed = "Erkundung Eins" },
        { key = "b", lon = 0.5, lat = 0, name = "Beta", deed = "Erkundung Eins" },
        { key = "c", lon = 1, lat = 0, name = "Gamma", deed = "Erkundung Zwei" },
    },
}
local state = Pathfinder.RouteState.New(route, {})
check("first target", state:Current().key == "a")
check("arrive marks done", state:UpdatePosition({ region = 1, lon = 0.05, lat = 0 }, 25) == true)
check("advanced to b", state:Current().key == "b")
check("far away stays", state:UpdatePosition({ region = 1, lon = 0.2, lat = 0 }, 25) == false)
check("chat landmark", state:MatchChat("Neuer Ort entdeckt: Gamma") == 1)
check("still b", state:Current().key == "b")
check("chat deed", state:MatchChat("Tat abgeschlossen: Erkundung Eins") == 1)
check("finished", state:Current() == nil)
check("progress", state:DoneCount() == 3)
state:Reset()
check("reset", state:Current().key == "a" and state:DoneCount() == 0)
state:Skip()
check("skip", state:Current().key == "b")
state:Back()
check("back", state:Current().key == "a")

-- Passing a point between two clicks
state:Reset()
check("segment distance", near(Loc.SegmentDistance(0.5, 0.05, 0, 0, 1, 0), 10))
check("segment end", near(Loc.SegmentDistance(2, 0, 0, 0, 1, 0), 200))
check("passed b", state:UpdatePosition({ region = 1, lon = 0.6, lat = 0.05 }, 25, { region = 1, lon = 0.4, lat = 0.05 }) == true
    and state:IsDone(route.points[2]) and not state:IsDone(route.points[1]))
check("no prev other region", state:UpdatePosition({ region = 1, lon = 1.6, lat = 0 }, 25, { region = 2, lon = 0, lat = 0 }) == false)
state:Reset()

-- Chat matching ignores case and markup
state:Reset()
check("chat markup", state:MatchChat("<rgb=#FFFF00>Neuer Ort: GAMMA</rgb>") == 1)
state:Reset()

-- Chat in the other language: English deed name on a German route
route.points[3].deed_en = "Second Exploration"
check("chat english name", state:MatchChat("Completed:\nSecond Exploration") == 1)
state:Reset()

-- Manual marking and deed grouping
state:SetDone(route.points[1], true)
check("manual done", state:IsDone(route.points[1]) and state:Current().key == "b")
state:SetDone(route.points[1], false)
check("manual undone", not state:IsDone(route.points[1]) and state:DoneCount() == 0)
local deeds = state:Deeds()
check("deeds grouped", #deeds == 2 and deeds[1].name == "Erkundung Eins" and #deeds[1].points == 2
    and deeds[2].points[1].key == "c")
state:Reset()

-- Start at the nearest open target
check("start near c", state:StartNear({ region = 1, lon = 0.9, lat = 0 }) and state:Current().key == "c")
check("start near other region", state:StartNear({ region = 2, lon = 0, lat = 0 }) == false)
state:SetDone(route.points[2], true)
check("start near skips done", state:StartNear({ region = 1, lon = 0.5, lat = 0 }) and state:Current().key ~= "b")
state:Reset()

-- Remaining way: player -> current -> open points
check("remaining all", near(state:Remaining(nil), 200))
check("remaining from pos", near(state:Remaining({ region = 1, lon = -0.5, lat = 0 }), 300))
check("remaining other region", near(state:Remaining({ region = 2, lon = -0.5, lat = 0 }), 200))
state:SetDone(route.points[3], true)
check("remaining open only", near(state:Remaining(nil), 100))
check("upcoming wraps", (function()
    state:Skip()
    local up = state:Upcoming()
    return #up == 2 and up[1].key == "b" and up[2].key == "a"
end)())
state:Reset()

-- Reorder from the player's position
local big = { id = "big", name = "Big", region = 1, points = {} }
for i = 1, 8 do
    -- Built order zigzags along a line: 1, 8, 2, 7, ...
    local x = (i % 2 == 1) and (i - 1) / 2 or 8 - i / 2
    table.insert(big.points, { key = "p" .. i, lon = x * 0.1, lat = 0, name = "P" .. i, deed = "D" })
end
local bigState = Pathfinder.RouteState.New(big, {})
bigState:SetDone(big.points[1], true)
local before = bigState:Remaining({ region = 1, lon = 0.75, lat = 0 })
check("reorder", bigState:Reorder({ region = 1, lon = 0.75, lat = 0 }))
local after = bigState:Remaining({ region = 1, lon = 0.75, lat = 0 })
check("reorder shorter", after < before and near(after, 0.65 * 200))
check("reorder done first", bigState.points[1].key == "p1" and bigState:Current().lon > 0.6)
check("reorder keeps all", bigState:Total() == 8 and bigState:DoneCount() == 1)
local order = bigState:Order()
local restored = Pathfinder.RouteState.New(big, bigState.done, order)
check("order restored", restored.points[3] == bigState.points[3] and restored:Number(bigState.points[3]) == 3)
check("order missing keys appended", #Pathfinder.RouteState.New(big, {}, { "p8", "x" }).points == 8)
bigState:Reset()
check("reset built order", bigState:Order() == nil and bigState.points[2].key == "p2")
check("reorder other region", bigState:Reorder({ region = 2, lon = 0, lat = 0 }) == false)

-- Shared progress: map and region routes have the same keys
local flat = Pathfinder.RouteState.FlattenDone({ R1_EXPLORER = { a = "1", b = "1" }, R2_LORE = { c = "1" } })
check("flatten old format", flat.a and flat.b and flat.c)
flat = Pathfinder.RouteState.FlattenDone({ a = "1", x = "1" })
check("flatten new format", flat.a and flat.x and not flat.b)
check("flatten nil", next(Pathfinder.RouteState.FlattenDone(nil)) == nil)
local shared = {}
local mapA = { id = 1, factor = 10, lon = 0, lat = 10 }
local mapB = { id = 2, factor = 20, lon = 5, lat = 10 }
local routeA = { id = "RA", region = 1, map = mapA, points = {
    { key = "k1", lon = 1, lat = 1, name = "Eins", deed = "D" },
    { key = "k2", lon = 2, lat = 1, name = "Zwei", deed = "D" },
} }
local regionRoute = { id = "G1", region = 1, map = mapA, maps = { [1] = mapA, [2] = mapB }, points = {
    { key = "k1", lon = 1, lat = 1, map = 1, name = "Eins", deed = "D" },
    { key = "k2", lon = 2, lat = 1, map = 1, name = "Zwei", deed = "D" },
    { key = "k3", lon = 6, lat = 1, map = 2, name = "Drei", deed = "E" },
} }
local stateA = Pathfinder.RouteState.New(routeA, shared)
local stateG = Pathfinder.RouteState.New(regionRoute, shared)
stateA:SetDone(routeA.points[1], true)
check("shared progress", stateG:IsDone(regionRoute.points[1]) and stateG:DoneCount() == 1)
check("map of point", stateG:MapOf(regionRoute.points[3]) == mapB and stateG:MapOf(regionRoute.points[1]) == mapA)
check("map of point single map", stateA:MapOf(routeA.points[1]) == mapA)
stateG:SetDone(regionRoute.points[2], true)
check("map follows current", stateG:MapOf(stateG:Current()) == mapB)
stateG:SetDone(regionRoute.points[3], true)
stateA:Reset()
check("reset own keys only", not shared.k1 and not shared.k2 and shared.k3)

-- Registry: slayer areas per region, routes without region (instances)
local Routes = Pathfinder.Routes
Routes.RegisterAreas({ map = 1, region = 1, areas = {
    { lon = 1, lat = 2, radius = 100, count = 12, deed = "Wolf-Bezwinger", deed_en = "Wolf-slayer" },
} })
Routes.RegisterAreas({ map = 2, region = 2, areas = { { lon = 0, lat = 0, radius = 50, count = 5, deed = "X" } } })
check("areas in region", #Routes.AreasIn(1) == 1 and Routes.AreasIn(1)[1].region == 1 and #Routes.AreasIn(3) == 0)
local mapInfo = { factor = 10, lon = 0, lat = 10 }
Routes.Register({ id = "inst", name = "Instanz", map = mapInfo, points = {} })
Routes.Register({ id = "r2", name = "Region 2", region = 2, map = mapInfo, points = {} })
local here = Routes.At({ region = 1, lon = 5, lat = 5 })
check("route without region everywhere", #here == 1 and here[1].id == "inst")
check("route in its region", #Routes.At({ region = 2, lon = 5, lat = 5 }) == 2)
-- Region route: found on each of its maps, after the map routes
Routes.Register({ id = "g2", name = "A Region", region = 2, map = mapInfo,
    maps = { [1] = mapInfo, [2] = { factor = 10, lon = 200, lat = 10 } }, points = {} })
local inRegion = Routes.At({ region = 2, lon = 205, lat = 5 })
check("region route on second map", #inRegion == 1 and inRegion[1].id == "g2")
inRegion = Routes.At({ region = 2, lon = 5, lat = 5 })
check("region route last", #inRegion == 3 and inRegion[3].id == "g2")

if failures == 0 then
    print("OK")
else
    print(failures .. " failures")
    os.exit(1)
end
