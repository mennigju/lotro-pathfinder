-- Tests fuer Loc.lua und RouteState.lua ausserhalb des Spiels: lua5.1 tools/test_loc.lua

local dir = arg[0]:match("^(.*)/tools/") or "."
dofile(dir .. "/plugin/Pathfinder/Route/Loc.lua")
dofile(dir .. "/plugin/Pathfinder/Route/RouteState.lua")

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

if failures == 0 then
    print("OK")
else
    print(failures .. " failures")
    os.exit(1)
end
