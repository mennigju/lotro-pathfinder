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

-- done: table key -> true, shared with the caller for saving
function RouteState.New(route, done)
    local self = setmetatable({}, RouteState)
    self.route = route
    self.done = done or {}
    self.index = 1
    return self
end

function RouteState:Total()
    return #self.route.points
end

function RouteState:DoneCount()
    local count = 0
    for _, point in ipairs(self.route.points) do
        if self.done[point.key] then
            count = count + 1
        end
    end
    return count
end

-- Index of the first open point from start on, wrapping around once
function RouteState:NextOpen(start)
    local points = self.route.points
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
    return self.route.points[i], i
end

-- Up to count open points starting with the current one
function RouteState:Upcoming(count)
    local result = {}
    local points = self.route.points
    local _, i = self:Current()
    if i == nil then
        return result
    end
    for j = i, #points do
        if #result >= count then
            break
        end
        if not self.done[points[j].key] then
            table.insert(result, points[j])
        end
    end
    return result
end

local function inRegion(self, pos)
    return pos ~= nil and (self.route.region == nil or pos.region == self.route.region)
end

-- Makes the open point nearest to pos the current one. False if pos is
-- elsewhere or nothing is open.
function RouteState:StartNear(pos)
    if not inRegion(self, pos) then
        return false
    end
    local Loc = Pathfinder.Loc
    local best, bestDistance = nil, nil
    for i, point in ipairs(self.route.points) do
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
    for _, point in ipairs(self.route.points) do
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
    for _, point in ipairs(self.route.points) do
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
    for _, point in ipairs(self.route.points) do
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
        self.index = self:NextOpen(i % #self.route.points + 1) or i
    end
end

-- Goes back one point and reopens it
function RouteState:Back()
    local _, i = self:Current()
    i = i or self.index
    local prev = (i - 2) % #self.route.points + 1
    self.done[self.route.points[prev].key] = nil
    self.index = prev
end

function RouteState:Reset()
    for key in pairs(self.done) do
        self.done[key] = nil
    end
    self.index = 1
end
