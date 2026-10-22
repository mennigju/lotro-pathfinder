-- Pathfinder.MapWindow: Gebietskarte mit den Zielen der Route, dem Weg zu
-- den naechsten Zielen und dem eigenen Standort.

Pathfinder = Pathfinder or {}

local MapWindow = {}
Pathfinder.MapWindow = MapWindow

local RESOURCES = "Pathfinder/Route/Resources/"
local MARGIN_X = 12
local MARGIN_TOP = 38
local INFO_HEIGHT = 20
-- The trail is drawn from the player through this many open points
local TRAIL_POINTS = 6
local TRAIL_SPACING = 9

local COLOR_OPEN = Turbine.UI.Color(1, 0.95, 0.75, 0.2)
local COLOR_DONE = Turbine.UI.Color(0.6, 0.45, 0.45, 0.45)
local COLOR_CURRENT = Turbine.UI.Color(1, 0.2, 0.95, 0.3)
local COLOR_TRAIL = Turbine.UI.Color(0.9, 1, 1, 1)

-- app: { OnMoved(x, y), OnClosed(), OnTogglePoint(point) }
-- scale must match the JPGs from tools/build_routes.py (Routes.MAP_SCALE):
-- the images are shown 1:1, the game doesn't scale them
function MapWindow.Create(app, x, y, scale)
    local self = setmetatable({}, { __index = MapWindow })
    self.app = app
    self.scale = scale
    self.width = math.floor(Pathfinder.Routes.MAP_WIDTH * scale + 0.5)
    self.height = math.floor(Pathfinder.Routes.MAP_HEIGHT * scale + 0.5)

    local window = Turbine.UI.Lotro.Window()
    window:SetText("Pathfinder")
    window:SetSize(self.width + 2 * MARGIN_X, self.height + MARGIN_TOP + INFO_HEIGHT + 14)
    window:SetPosition(x, y)
    window.PositionChanged = function()
        app.OnMoved(window:GetPosition())
    end
    window.VisibleChanged = function()
        if not window:IsVisible() then
            app.OnClosed()
        end
    end
    self.window = window

    self.info = Turbine.UI.Label()
    self.info:SetParent(window)
    self.info:SetPosition(MARGIN_X, MARGIN_TOP + self.height + 4)
    self.info:SetSize(self.width, INFO_HEIGHT)
    self.info:SetFont(Turbine.UI.Lotro.Font.Verdana12)
    self.info:SetForeColor(Turbine.UI.Color(1, 0.9, 0.85, 0.7))
    self.info:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleLeft)

    -- Dark backdrop in its own control: a back colour on the image control
    -- itself would cover the image
    local backdrop = Turbine.UI.Control()
    backdrop:SetParent(window)
    backdrop:SetPosition(MARGIN_X, MARGIN_TOP)
    backdrop:SetSize(self.width, self.height)
    backdrop:SetBackColor(Turbine.UI.Color(1, 0.12, 0.1, 0.08))
    backdrop:SetMouseVisible(false)

    self.dots = {}
    self.markers = {}
    return self
end

function MapWindow:SetVisible(visible)
    self.window:SetVisible(visible)
end

function MapWindow:IsVisible()
    return self.window:IsVisible()
end

-- New map image for a route (or none)
function MapWindow:SetRoute(route)
    if self.route == route then
        return
    end
    self.route = route
    if self.image ~= nil then
        self.image:SetParent(nil)
    end
    if self.layer ~= nil then
        self.layer:SetParent(nil)
    end
    self.dots = {}
    self.markers = {}
    self.player = nil

    local image = Turbine.UI.Control()
    image:SetParent(self.window)
    image:SetPosition(MARGIN_X, MARGIN_TOP)
    image:SetSize(self.width, self.height)
    image:SetMouseVisible(false)
    if route ~= nil and route.map ~= nil then
        self.window:SetText("Pathfinder - " .. route.name)
        local ok = route.map.file ~= nil and pcall(function()
            image:SetBackground(route.map.file)
        end)
        if not ok then
            self.info:SetText(Pathfinder.L("noMapImage"))
        end
    else
        self.window:SetText("Pathfinder")
    end
    self.image = image

    -- Separate layer so markers stay above the image
    local layer = Turbine.UI.Control()
    layer:SetParent(self.window)
    layer:SetPosition(MARGIN_X, MARGIN_TOP)
    layer:SetSize(self.width, self.height)
    layer:SetMouseVisible(false)
    self.layer = layer
end

-- lon/lat -> pixel on the scaled map, nil if outside
function MapWindow:Project(lon, lat)
    local map = self.route and self.route.map
    if map == nil then
        return nil
    end
    local x = (lon - map.lon) * map.factor * self.scale
    local y = (map.lat - lat) * map.factor * self.scale
    if x < 0 or y < 0 or x > self.width or y > self.height then
        return nil
    end
    return x, y
end

function MapWindow:Square(size, color, x, y, mouse)
    local c = Turbine.UI.Control()
    c:SetParent(self.layer)
    c:SetSize(size, size)
    c:SetPosition(math.floor(x - size / 2), math.floor(y - size / 2))
    c:SetBackColor(color)
    c:SetMouseVisible(mouse or false)
    return c
end

-- Dots from (x1, y1) to (x2, y2), reusing controls from the pool
function MapWindow:Line(x1, y1, x2, y2)
    local length = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
    local steps = math.floor(length / TRAIL_SPACING)
    for i = 1, steps - 1 do
        local t = i / steps
        self.dotCount = self.dotCount + 1
        local dot = self.dots[self.dotCount]
        if dot == nil then
            dot = self:Square(3, COLOR_TRAIL, 0, 0)
            self.dots[self.dotCount] = dot
        end
        dot:SetPosition(math.floor(x1 + (x2 - x1) * t - 1), math.floor(y1 + (y2 - y1) * t - 1))
        dot:SetVisible(true)
    end
end

function MapWindow:Refresh(state, pos, flip)
    self:SetRoute(state and state.route)
    self.state = state
    if state == nil or self.layer == nil then
        self.info:SetText(Pathfinder.L("noRouteSelected"))
        return
    end

    -- Markers: one per point, recoloured on every refresh
    local current = state:Current()
    for i, point in ipairs(state.route.points) do
        local marker = self.markers[i]
        local x, y = self:Project(point.lon, point.lat)
        if marker == nil and x ~= nil then
            marker = self:Square(7, COLOR_OPEN, x, y, true)
            marker.MouseEnter = function()
                -- Number in the walking order, which /pf neu may change
                local number = self.state and self.state:Number(point) or i
                self.info:SetText(Pathfinder.L("mapHover", number, point.name, point.deed))
            end
            marker.MouseClick = function()
                self.app.OnTogglePoint(point)
            end
            self.markers[i] = marker
        end
        if marker ~= nil then
            local size, color = 7, COLOR_OPEN
            if point == current then
                size, color = 11, COLOR_CURRENT
            elseif state.done[point.key] then
                size, color = 5, COLOR_DONE
            end
            marker:SetSize(size, size)
            marker:SetPosition(math.floor(x - size / 2), math.floor(y - size / 2))
            marker:SetBackColor(color)
        end
    end

    -- Trail: player -> current -> next open points
    self.dotCount = 0
    local path = {}
    local px, py
    if pos ~= nil and pos.region == state.route.region then
        px, py = self:Project(pos.lon, pos.lat)
        if px ~= nil then
            table.insert(path, { px, py })
        end
    end
    for _, point in ipairs(state:Upcoming(TRAIL_POINTS)) do
        local x, y = self:Project(point.lon, point.lat)
        if x ~= nil then
            table.insert(path, { x, y })
        end
    end
    for i = 1, #path - 1 do
        self:Line(path[i][1], path[i][2], path[i + 1][1], path[i + 1][2])
    end
    for i = self.dotCount + 1, #self.dots do
        self.dots[i]:SetVisible(false)
    end

    -- Player marker above everything else
    if px ~= nil then
        if self.player == nil then
            self.player = Turbine.UI.Control()
            self.player:SetParent(self.layer)
            self.player:SetSize(24, 24)
            self.player:SetBlendMode(Turbine.UI.BlendMode.AlphaBlend)
            self.player:SetMouseVisible(false)
        end
        self.player:SetPosition(math.floor(px - 12), math.floor(py - 12))
        self.player:SetZOrder(10)
        -- North is up on the map: turn by the heading alone
        local frame = Pathfinder.Loc.Frame(Pathfinder.Loc.ArrowRotation(0, pos.heading or 0, flip))
        self.player:SetBackground(RESOURCES .. "player_" .. frame .. ".tga")
        self.player:SetVisible(true)
    elseif self.player ~= nil then
        self.player:SetVisible(false)
    end

    if current == nil then
        self.info:SetText(Pathfinder.L("mapFinished", state:DoneCount(), state:Total()))
    else
        self.info:SetText(Pathfinder.L("mapNext", current.name, state:DoneCount(), state:Total()))
    end
end
