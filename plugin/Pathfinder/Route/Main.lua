-- Pathfinder
--
-- Fuehrt auf einer vorberechneten Route von Tat-Ziel zu Tat-Ziel (Erkundung,
-- Wissen). Die Position kommt aus /pos: der Pfeil im Pathfinder-Fenster ist
-- ein Quickslot dafuer, er laesst sich auch auf eine Schnellleiste ziehen und
-- dort auf eine Taste legen.
--
-- Nur lesende API-Aufrufe, keine Spielbefehle ausser /pos per Klick.
--
-- Befehle: /pf (Hilfe). Texte in Strings.lua (Deutsch/Englisch).

import "Turbine"
import "Turbine.Gameplay"
import "Turbine.UI"
import "Turbine.UI.Lotro"
import "Pathfinder.Route.Loc"
import "Pathfinder.Route.RouteState"
import "Pathfinder.Route.Registry"
import "Pathfinder.Route.Strings"
import "Pathfinder.Route.ArrowWindow"
import "Pathfinder.Route.MapWindow"
import "Pathfinder.Route.ListWindow"

local Loc = Pathfinder.Loc
local Routes = Pathfinder.Routes
local L = Pathfinder.L

local SETTINGS_KEY = "PathfinderSettings"
local PROGRESS_KEY = "PathfinderProgress"
local LOG_PREFIX = "PFD1"
local LIST_MAX = 25
-- The way between two /pos clicks counts as walked only for short hops,
-- not for travel by horse or teleport
local TRAIL_MAX_SECONDS = 60
local TRAIL_MAX_METERS = 600

-- Chat that may announce a discovered landmark or a finished deed
local MATCH_CHAT = {
    Standard = true, Quest = true, Advancement = true, Narration = true,
    Localized1 = true, Localized2 = true, Unfiltered = true,
}
-- Never logged in debug mode
local SKIP_DEBUG_CHAT = {
    PlayerCombat = true, EnemyCombat = true, SelfLoot = true, FellowLoot = true,
    Death = true, Trade = true, LFF = true, World = true, OOC = true, Regional = true,
}

local function write(text)
    Turbine.Shell.WriteLine("<rgb=#E8C45C>Pathfinder:</rgb> " .. text)
end

-- Same idiom as TitanBar: keep handlers of other plugins on shared events
local function AddCallback(object, event, callback)
    if object[event] == nil then
        object[event] = callback
    elseif type(object[event]) == "table" then
        table.insert(object[event], callback)
    else
        object[event] = { object[event], callback }
    end
    return callback
end

local function enumNames(enum)
    local names = {}
    pcall(function()
        for name, value in pairs(enum) do
            if type(value) == "number" then
                names[value] = name
            end
        end
    end)
    return names
end

local chatTypeNames = enumNames(Turbine.ChatType)

local function load(scope, key)
    local ok, data = pcall(Turbine.PluginData.Load, scope, key)
    if ok and type(data) == "table" then
        return data
    end
    return {}
end

-- Plain strings only, also as values: the German client writes numbers as
-- "1,000000" and then can't read its own file back
local function save(scope, key, data)
    pcall(Turbine.PluginData.Save, scope, key, data)
end

-- Settings (account wide) ------------------------------------------------

local settings = load(Turbine.DataScope.Account, SETTINGS_KEY)

local function setting(name, default)
    return Loc.ToNumber(settings[name]) or default
end

local function setSetting(name, value)
    if type(value) == "boolean" then
        settings[name] = value and "1" or "0"
    else
        settings[name] = tostring(value)
    end
end

local function saveSettings()
    save(Turbine.DataScope.Account, SETTINGS_KEY, settings)
end

-- Language: /pf lang wins, otherwise the client language
local germanClient = false
pcall(function()
    germanClient = Turbine.Engine.GetLanguage() == Turbine.Language.German
end)
if settings.lang == "de" or settings.lang == "en" then
    Pathfinder.Lang = settings.lang
else
    Pathfinder.Lang = germanClient and "de" or "en"
end

-- Routes register themselves in the chosen language
import "Pathfinder.Route.Routes"

-- Progress (per character) -------------------------------------------------

local progress = load(Turbine.DataScope.Character, PROGRESS_KEY)
progress.done = progress.done or {}

local function saveProgress()
    local done = {}
    for routeId, keys in pairs(progress.done) do
        done[routeId] = {}
        for key, value in pairs(keys) do
            if value then
                done[routeId][key] = "1"
            end
        end
    end
    save(Turbine.DataScope.Character, PROGRESS_KEY, { route = progress.route, done = done })
end

-- State --------------------------------------------------------------------

local state = nil
-- True until the first position after loading a route picks the start
local needsStart = false
local lastPos = nil
local posTime = nil
local lastList = {}
local debugEnabled = false
local arrowWindow, mapWindow, listWindow

-- The command follows the client, not the plugin language
local posCommand = germanClient and "/pos" or "/loc"

local function flip()
    return setting("flip", 0) == 1
end

local function refresh()
    arrowWindow:Refresh(state, lastPos, posTime, flip())
    if mapWindow:IsVisible() then
        mapWindow:Refresh(state, lastPos, flip())
    end
    if listWindow:IsVisible() then
        listWindow:Refresh(state)
    end
end

local function toggleWindow(window, name)
    window:SetVisible(not window:IsVisible())
    setSetting(name, window:IsVisible())
    saveSettings()
    refresh()
end

local function newState(route)
    progress.done[route.id] = progress.done[route.id] or {}
    return Pathfinder.RouteState.New(route, progress.done[route.id])
end

local function selectRoute(route)
    progress.route = route and route.id or nil
    if route == nil then
        state = nil
    else
        state = newState(route)
        needsStart = not state:StartNear(lastPos)
        write(L("routeSelected", route.name, state:DoneCount(), state:Total()))
    end
    saveProgress()
    refresh()
end

local function log(...)
    local parts = { LOG_PREFIX }
    for _, value in ipairs({ ... }) do
        local text = tostring(value or ""):gsub("\r", ""):gsub("\n", "\\n"):gsub("\t", " ")
        table.insert(parts, text)
    end
    Turbine.Engine.ScriptLog(table.concat(parts, "\t"))
end

-- Windows ------------------------------------------------------------------

arrowWindow = Pathfinder.ArrowWindow.Create({
    posCommand = posCommand,
    OnSkip = function()
        if state ~= nil then
            state:Skip()
            refresh()
        end
    end,
    OnBack = function()
        if state ~= nil then
            state:Back()
            saveProgress()
            refresh()
        end
    end,
    OnToggleList = function()
        toggleWindow(listWindow, "listVisible")
    end,
    OnToggleMap = function()
        toggleWindow(mapWindow, "mapVisible")
    end,
    OnMoved = function(x, y)
        setSetting("arrowX", x)
        setSetting("arrowY", y)
        saveSettings()
    end,
}, setting("arrowX", math.floor(Turbine.UI.Display.GetWidth() / 2 - 120)), setting("arrowY", 120))

mapWindow = Pathfinder.MapWindow.Create({
    OnMoved = function(x, y)
        setSetting("mapX", x)
        setSetting("mapY", y)
    end,
    OnClosed = function()
        setSetting("mapVisible", false)
        saveSettings()
    end,
    OnTogglePoint = function(point)
        if state ~= nil then
            state:SetDone(point, not state:IsDone(point))
            saveProgress()
            refresh()
        end
    end,
}, setting("mapX", 100), setting("mapY", 150), Routes.MAP_SCALE or 0.6)

listWindow = Pathfinder.ListWindow.Create({
    OnChanged = function()
        saveProgress()
        refresh()
    end,
    OnMoved = function(x, y)
        setSetting("listX", x)
        setSetting("listY", y)
    end,
    OnClosed = function()
        setSetting("listVisible", false)
        saveSettings()
    end,
}, setting("listX", 120), setting("listY", 170))

-- Chat ---------------------------------------------------------------------

local function onPosition(pos)
    local now = Turbine.Engine.GetGameTime()
    local prev = nil
    if lastPos ~= nil and posTime ~= nil and now - posTime <= TRAIL_MAX_SECONDS
        and Loc.Distance(lastPos.lon, lastPos.lat, pos.lon, pos.lat) <= TRAIL_MAX_METERS then
        prev = lastPos
    end
    lastPos = pos
    posTime = now
    if state ~= nil then
        local before = state:DoneCount()
        if state:UpdatePosition(pos, setting("radius", 25), prev) then
            write(L("reached", state:DoneCount() - before, state:DoneCount(), state:Total()))
            saveProgress()
        end
        if needsStart and state:StartNear(pos) then
            needsStart = false
        end
    elseif #Routes.At(pos) > 0 then
        write(L("routesHereHint"))
    end
    refresh()
end

AddCallback(Turbine.Chat, "Received", function(sender, args)
    local typeName = chatTypeNames[args.ChatType] or tostring(args.ChatType)
    local message = args.Message or ""
    if debugEnabled and not SKIP_DEBUG_CHAT[typeName] then
        log("CHAT", typeName, message)
    end
    if typeName == "Standard" then
        local pos = Loc.Parse(message)
        if pos ~= nil then
            if debugEnabled then
                log("POS", pos.region, pos.lon, pos.lat, pos.heading)
            end
            onPosition(pos)
            return
        end
    end
    if state ~= nil and MATCH_CHAT[typeName] then
        local count = state:MatchChat(message)
        if count > 0 then
            write(L("chatTicked", count, state:DoneCount(), state:Total()))
            saveProgress()
            refresh()
        elseif typeName == "Quest" and not debugEnabled then
            -- Unknown progress texts end up in Script.log to improve matching
            log("MISS", typeName, message)
        end
    end
end)

-- Command ------------------------------------------------------------------

local function printList(list, title)
    lastList = list
    if #list == 0 then
        write(L("noMatches", title))
        return
    end
    write(L("listHeader", title))
    for i, route in ipairs(list) do
        if i > LIST_MAX then
            write(L("listMore", #list - LIST_MAX))
            break
        end
        local done = 0
        for _ in pairs(progress.done[route.id] or {}) do
            done = done + 1
        end
        Turbine.Shell.WriteLine(string.format("  %d. %s  (%d/%d)", i, route.name, done, #route.points))
    end
end

local function help()
    local lines = L("help")
    for i, line in ipairs(lines) do
        line = line:gsub("%%RADIUS%%", tostring(setting("radius", 25)))
        line = line:gsub("%%AGE%%", tostring(setting("stale", Pathfinder.ArrowWindow.DEFAULT_STALE_SECONDS)))
        line = line:gsub("%%POS%%", posCommand)
        if i == 1 then
            write(line)
        else
            Turbine.Shell.WriteLine(line)
        end
    end
end

-- Global: a local command object gets garbage collected ("Unbekannter Befehl")
PathfinderCommand = Turbine.ShellCommand()

function PathfinderCommand:Execute(cmd, arguments)
    arguments = arguments or ""
    local word, rest = arguments:match("^%s*(%S*)%s*(.-)%s*$")
    local verb = Pathfinder.COMMANDS[string.lower(word or "")]
    local number = Loc.ToNumber(rest)
    if verb == "here" then
        if lastPos == nil then
            write(L("posUnknown", posCommand))
        else
            printList(Routes.At(lastPos), L("routesHere"))
        end
    elseif verb == "list" then
        printList(Routes.Find(rest), L("routes"))
    elseif verb == "route" then
        local n = tonumber(rest)
        local route = n and lastList[n] or Routes.Find(rest)[1]
        if route == nil then
            write(L("routeNotFound", rest))
        else
            selectRoute(route)
        end
    elseif verb == "next" then
        if state then state:Skip() end
        refresh()
    elseif verb == "back" then
        if state then state:Back() saveProgress() end
        refresh()
    elseif verb == "reset" then
        if state then
            state:Reset()
            saveProgress()
            write(L("routeReset"))
        end
        refresh()
    elseif verb == "map" then
        toggleWindow(mapWindow, "mapVisible")
    elseif verb == "deeds" then
        toggleWindow(listWindow, "listVisible")
    elseif verb == "done" then
        local point = state and state:Current()
        if point ~= nil then
            state:SetDone(point, true)
            saveProgress()
            write(L("ticked", point.name))
        end
        refresh()
    elseif verb == "arrow" then
        arrowWindow:SetVisible(not arrowWindow:IsVisible())
        setSetting("arrowVisible", arrowWindow:IsVisible())
        saveSettings()
    elseif verb == "radius" and number then
        setSetting("radius", math.floor(number))
        saveSettings()
        write(L("radiusSet", setting("radius", 25)))
    elseif verb == "age" and number and number >= 1 then
        setSetting("stale", math.floor(number))
        saveSettings()
        arrowWindow.staleSeconds = setting("stale", Pathfinder.ArrowWindow.DEFAULT_STALE_SECONDS)
        arrowWindow:UpdateAge()
        write(L("ageSet", arrowWindow.staleSeconds))
    elseif verb == "flip" then
        setSetting("flip", not flip())
        saveSettings()
        write(L(flip() and "flipped" or "notFlipped"))
        refresh()
    elseif verb == "lang" and (rest == "de" or rest == "en") then
        settings.lang = rest
        saveSettings()
        local current = Pathfinder.Lang
        Pathfinder.Lang = rest
        write(L("langSet"))
        Pathfinder.Lang = current
    elseif verb == "debug" then
        debugEnabled = not debugEnabled
        write(debugEnabled and L("debugOn", LOG_PREFIX) or L("debugOff"))
    else
        help()
    end
end

function PathfinderCommand:GetHelp()
    return L("commandHelp")
end

function PathfinderCommand:GetShortHelp()
    return L("shortHelp")
end

Turbine.Shell.AddCommand("pf;pathfinder", PathfinderCommand)

-- Start --------------------------------------------------------------------

if Plugins ~= nil and Plugins.Pathfinder ~= nil then
    Plugins.Pathfinder.Unload = function()
        saveSettings()
        saveProgress()
    end
end

arrowWindow.staleSeconds = setting("stale", Pathfinder.ArrowWindow.DEFAULT_STALE_SECONDS)
arrowWindow:SetVisible(setting("arrowVisible", 1) == 1)
mapWindow:SetVisible(setting("mapVisible", 0) == 1)
listWindow:SetVisible(setting("listVisible", 0) == 1)
if progress.route ~= nil and Routes.byId[progress.route] ~= nil then
    state = newState(Routes.byId[progress.route])
    needsStart = true
end
refresh()
local version = ""
pcall(function() version = L("version", Plugins.Pathfinder:GetVersion()) end)
write(version .. L("loaded", #Routes.list))
