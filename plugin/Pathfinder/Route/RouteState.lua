-- Pathfinder.RouteState
--
-- Fortschritt auf einer Route: welches Ziel als naechstes kommt, was erledigt
-- ist. Reine Logik ohne Turbine-Aufrufe (testbar mit tools/test_loc.lua).

Pathfinder = Pathfinder or {}

local RouteState = {}
RouteState.__index = RouteState
Pathfinder.RouteState = RouteState

-- Shorter names would match too much chat ("Tor", "Hof")
local MIN_CHAT_NAME = 4

-- done: table key -> true, shared with the caller for saving and with the
-- other routes: map and region routes have the same point keys.
-- order: optional point keys in walking order (from /pf neu), see Order()
function RouteState.New(route, done, order)
    local self = setmetatable({}, RouteState)
    self.route = route
    self.done = done or {}
    self.points = route.points
    self.index = 1
    if order ~= nil then
        self:SetOrder(order)
    end
    return self
end

-- Walking order from keys; unknown keys are ignored, points missing from the
-- list (new in a data update) go to the end
function RouteState:SetOrder(keys)
    local byKey, used, points = {}, {}, {}
    for _, point in ipairs(self.route.points) do
        byKey[point.key] = point
    end
    for _, key in ipairs(keys) do
        local point = byKey[key]
        if point ~= nil and not used[key] then
            used[key] = true
            table.insert(points, point)
        end
    end
    for _, point in ipairs(self.route.points) do
        if not used[point.key] then
            table.insert(points, point)
        end
    end
    self.points = points
    self.index = 1
end

-- Keys in walking order, nil while the route has its built order
function RouteState:Order()
    if self.points == self.route.points then
        return nil
    end
    local keys = {}
    for i, point in ipairs(self.points) do
        keys[i] = point.key
    end
    return keys
end

-- Saved progress -> set of done keys. Before 0.5 it was saved per route
-- (route id -> key -> "1"), now it is one set (key -> "1").
function RouteState.FlattenDone(saved)
    local done = {}
    for name, value in pairs(saved or {}) do
        if type(value) == "table" then
            for key in pairs(value) do
                done[key] = true
            end
        elseif value then
            done[name] = true
        end
    end
    return done
end

-- Map a point lies on: region routes name it per point
function RouteState:MapOf(point)
    local maps = self.route.maps
    return point ~= nil and maps ~= nil and maps[point.map] or self.route.map
end

-- Number of a point in the walking order (1-based)
function RouteState:Number(point)
    for i, p in ipairs(self.points) do
        if p == point then
            return i
        end
    end
    return nil
end

function RouteState:Total()
    return #self.points
end

function RouteState:DoneCount()
    local count = 0
    for _, point in ipairs(self.points) do
        if self.done[point.key] then
            count = count + 1
        end
    end
    return count
end

-- Index of the first open point from start on, wrapping around once
function RouteState:NextOpen(start)
    local points = self.points
    local n = #points
    for step = 0, n - 1 do
        local i = (start - 1 + step) % n + 1
        if not self.done[points[i].key] then
            return i
        end
    end
    return nil
end

function RouteState:Current()
    local i = self:NextOpen(self.index)
    if i == nil then
        return nil
    end
    self.index = i
    return self.points[i], i
end

-- Up to count open points in walking order, starting with the current one
-- and wrapping around like NextOpen
function RouteState:Upcoming(count)
    local result = {}
    local points = self.points
    local n = #points
    local _, i = self:Current()
    if i == nil then
        return result
    end
    for step = 0, n - 1 do
        if count ~= nil and #result >= count then
            break
        end
        local point = points[(i - 1 + step) % n + 1]
        if not self.done[point.key] then
            table.insert(result, point)
        end
    end
    return result
end

local function inRegion(self, pos)
    return pos ~= nil and (self.route.region == nil or pos.region == self.route.region)
end

-- Meters still to walk: from pos (if in the region) to the current target,
-- then along all open points
function RouteState:Remaining(pos)
    local Loc = Pathfinder.Loc
    local meters = 0
    local prev = inRegion(self, pos) and pos or nil
    for _, point in ipairs(self:Upcoming()) do
        if prev ~= nil then
            meters = meters + Loc.Distance(prev.lon, prev.lat, point.lon, point.lat)
        end
        prev = point
    end
    return meters
end

-- Makes the open point nearest to pos the current one. False if pos is
-- elsewhere or nothing is open.
function RouteState:StartNear(pos)
    if not inRegion(self, pos) then
        return false
    end
    local Loc = Pathfinder.Loc
    local best, bestDistance = nil, nil
    for i, point in ipairs(self.points) do
        if not self.done[point.key] then
            local d = Loc.Distance(pos.lon, pos.lat, point.lon, point.lat)
            if bestDistance == nil or d < bestDistance then
                best, bestDistance = i, d
            end
        end
    end
    if best == nil then
        return false
    end
    self.index = best
    return true
end

-- Upper bound for the 2-opt passes and their work (passes * n^2), keeps
-- big routes (region routes have hundreds of points) from stalling the game
local MAX_PASSES = 20
local MAX_WORK = 2000000

-- New walking order from pos: nearest neighbour through the open points,
-- then 2-opt on the open path that starts at pos (as tools/build_routes.py
-- does for the built order). Done points stay in front in their old order,
-- so Back() reopens the last one. False if pos is elsewhere or nothing is open.
function RouteState:Reorder(pos)
    if not inRegion(self, pos) then
        return false
    end
    local Loc = Pathfinder.Loc
    local function dist(a, b)
        return Loc.Distance(a.lon, a.lat, b.lon, b.lat)
    end
    local done, left = {}, {}
    for _, point in ipairs(self.points) do
        table.insert(self.done[point.key] and done or left, point)
    end
    if #left == 0 then
        return false
    end

    -- path[1] is the player, it never moves
    local path = { pos }
    while #left > 0 do
        local last = path[#path]
        local best = 1
        for j = 2, #left do
            if dist(last, left[j]) < dist(last, left[best]) then
                best = j
            end
        end
        table.insert(path, table.remove(left, best))
    end

    local n = #path
    for _ = 1, math.max(1, math.min(MAX_PASSES, math.floor(MAX_WORK / (n * n)))) do
        local improved = false
        for a = 2, n - 1 do
            for b = a + 1, n do
                local before = dist(path[a - 1], path[a]) + (b < n and dist(path[b], path[b + 1]) or 0)
                local after = dist(path[a - 1], path[b]) + (b < n and dist(path[a], path[b + 1]) or 0)
                if after < before - 1e-6 then
                    local i, j = a, b
                    while i < j do
                        path[i], path[j] = path[j], path[i]
                        i, j = i + 1, j - 1
                    end
                    improved = true
                end
            end
        end
        if not improved then
            break
        end
    end

    local points = done
    for i = 2, n do
        table.insert(points, path[i])
    end
    self.points = points
    self.index = #done + 1
    return true
end

function RouteState:MarkDone(point)
    if self.done[point.key] then
        return false
    end
    self.done[point.key] = true
    return true
end

-- Manual marking from the list or the map
function RouteState:SetDone(point, done)
    self.done[point.key] = done and true or nil
end

function RouteState:IsDone(point)
    return self.done[point.key] and true or false
end

-- Points grouped by deed in route order: { { name, points = {...} }, ... }
function RouteState:Deeds()
    local result, byName = {}, {}
    for _, point in ipairs(self.points) do
        local deed = byName[point.deed]
        if deed == nil then
            deed = { name = point.deed, points = {} }
            byName[point.deed] = deed
            table.insert(result, deed)
        end
        table.insert(deed.points, point)
    end
    return result
end

-- Marks every open point within radius meters. With prev, the way from
-- prev to pos counts too (passed a point between two /pos clicks); the
-- caller only passes prev for short, recent hops. True if anything changed.
function RouteState:UpdatePosition(pos, radius, prev)
    if not inRegion(self, pos) then
        return false
    end
    if prev ~= nil and prev.region ~= pos.region then
        prev = nil
    end
    local Loc = Pathfinder.Loc
    local changed = false
    for _, point in ipairs(self.points) do
        if not self.done[point.key] then
            local d
            if prev ~= nil then
                d = Loc.SegmentDistance(point.lon, point.lat, prev.lon, prev.lat, pos.lon, pos.lat)
            else
                d = Loc.Distance(pos.lon, pos.lat, point.lon, point.lat)
            end
            if d <= radius then
                changed = self:MarkDone(point) or changed
            end
        end
    end
    return changed
end

-- Chat may wrap names in markup like <rgb=...> or <Select:...>
local function plain(text)
    return string.lower((text:gsub("<[^>]*>", "")))
end

local function contains(message, text)
    return text ~= nil and #text >= MIN_CHAT_NAME and message:find(plain(text), 1, true) ~= nil
end

-- The chat comes in the client language, which may differ from the plugin
-- language: check all name variants
local CHAT_FIELDS = { "name", "deed", "name_en", "deed_en", "name_de", "deed_de" }

local function mentions(message, point)
    for _, field in ipairs(CHAT_FIELDS) do
        if contains(message, point[field]) then
            return true
        end
    end
    return false
end

-- Discovery or deed completion messages name the landmark or the deed.
-- Returns the number of newly finished points.
function RouteState:MatchChat(message)
    message = plain(message)
    local count = 0
    for _, point in ipairs(self.points) do
        if not self.done[point.key]
            and mentions(message, point) then
            self:MarkDone(point)
            count = count + 1
        end
    end
    return count
end

function RouteState:Skip()
    local _, i = self:Current()
    if i ~= nil then
        self.index = self:NextOpen(i % #self.points + 1) or i
    end
end

-- Goes back one point and reopens it
function RouteState:Back()
    local _, i = self:Current()
    i = i or self.index
    local prev = (i - 2) % #self.points + 1
    self.done[self.points[prev].key] = nil
    self.index = prev
end

-- Clears the progress of this route (not of others sharing the set) and
-- goes back to the built order
function RouteState:Reset()
    for _, point in ipairs(self.route.points) do
        self.done[point.key] = nil
    end
    self.points = self.route.points
    self.index = 1
end
