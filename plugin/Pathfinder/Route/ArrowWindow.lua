-- Pathfinder.ArrowWindow: kleines Fenster mit Pfeil zum naechsten Ziel.
-- Ein Klick auf den Pfeil fuehrt /pos aus (Quickslot unter dem Pfeil).

Pathfinder = Pathfinder or {}

local ArrowWindow = {}
Pathfinder.ArrowWindow = ArrowWindow

local RESOURCES = "Pathfinder/Route/Resources/"
local WIDTH = 240
local HEIGHT = 164
-- Window buttons along the bottom
local BUTTON_Y = HEIGHT - 22
-- After this many seconds the arrow is greyed out: you have moved on since.
-- Changed with /pf alter.
ArrowWindow.DEFAULT_STALE_SECONDS = 15

local function label(parent, x, y, w, h, font, color)
    local l = Turbine.UI.Label()
    l:SetParent(parent)
    l:SetPosition(x, y)
    l:SetSize(w, h)
    l:SetFont(font)
    l:SetForeColor(color or Turbine.UI.Color(1, 1, 1, 1))
    l:SetFontStyle(Turbine.UI.FontStyle.Outline)
    l:SetOutlineColor(Turbine.UI.Color(1, 0, 0, 0))
    l:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleCenter)
    l:SetMouseVisible(false)
    return l
end

local function button(parent, x, y, w, text, onClick)
    local b = Turbine.UI.Lotro.Button()
    b:SetParent(parent)
    b:SetPosition(x, y)
    b:SetSize(w, 20)
    b:SetText(text)
    b.Click = onClick
    return b
end

-- Lets the user drag a borderless window and reports the new position
function ArrowWindow.MakeDraggable(window, control, onMoved)
    control.MouseDown = function(sender, args)
        if args.Button == Turbine.UI.MouseButton.Left then
            window.dragX, window.dragY = args.X, args.Y
        end
    end
    control.MouseMove = function(sender, args)
        if window.dragX ~= nil then
            local x, y = window:GetPosition()
            window:SetPosition(x + args.X - window.dragX, y + args.Y - window.dragY)
        end
    end
    control.MouseUp = function(sender, args)
        if window.dragX ~= nil then
            window.dragX, window.dragY = nil, nil
            onMoved(window:GetPosition())
        end
    end
end

-- app: { posCommand, OnSkip(), OnBack(), OnToggleRoutes(), OnToggleList(),
--        OnToggleMap(), OnMoved(x, y) }
function ArrowWindow.Create(app, x, y)
    local self = {}
    local window = Turbine.UI.Window()
    window:SetSize(WIDTH, HEIGHT)
    window:SetPosition(x, y)
    window:SetBackColor(Turbine.UI.Color(0.55, 0, 0, 0))
    window:SetText("Pathfinder")
    self.window = window
    ArrowWindow.MakeDraggable(window, window, app.OnMoved)

    -- /pos quickslot under the arrow: clicking the arrow refreshes the position.
    -- It can also be dragged onto a quickbar and bound to a key there.
    local quick = Turbine.UI.Lotro.Quickslot()
    quick:SetParent(window)
    quick:SetSize(36, 36)
    quick:SetPosition((WIDTH - 36) / 2, 18)
    quick:SetAllowDrop(false)
    local function setAlias()
        local shortcut = Turbine.UI.Lotro.Shortcut(Turbine.UI.Lotro.ShortcutType.Alias, "")
        shortcut:SetData(app.posCommand)
        quick:SetShortcut(shortcut)
    end
    setAlias()
    -- Dragging the slot away empties it, put the alias back
    quick.DragDrop = setAlias
    self.quick = quick

    local arrow = Turbine.UI.Control()
    arrow:SetParent(window)
    arrow:SetSize(64, 64)
    arrow:SetPosition((WIDTH - 64) / 2, 4)
    arrow:SetBlendMode(Turbine.UI.BlendMode.AlphaBlend)
    arrow:SetMouseVisible(false)
    self.arrow = arrow
    self.frame = "00"
    self.stale = true
    arrow:SetBackground(RESOURCES .. "arrow_stale_00.tga")

    self.routeLabel = label(window, 4, 2, WIDTH - 8, 14, Turbine.UI.Lotro.Font.Verdana10,
        Turbine.UI.Color(1, 0.8, 0.75, 0.6))
    self.routeLabel:SetTextAlignment(Turbine.UI.ContentAlignment.TopLeft)
    self.nameLabel = label(window, 4, 70, WIDTH - 8, 18, Turbine.UI.Lotro.Font.Verdana14,
        Turbine.UI.Color(1, 1, 0.85, 0.4))
    self.deedLabel = label(window, 4, 88, WIDTH - 8, 14, Turbine.UI.Lotro.Font.Verdana10,
        Turbine.UI.Color(1, 0.85, 0.85, 0.85))
    self.distLabel = label(window, 34, 106, WIDTH - 68, 16, Turbine.UI.Lotro.Font.Verdana12)
    self.ageLabel = label(window, 34, 122, WIDTH - 68, 14, Turbine.UI.Lotro.Font.Verdana10,
        Turbine.UI.Color(1, 0.7, 0.7, 0.7))

    button(window, 4, 112, 28, "<", function() app.OnBack() end)
    button(window, WIDTH - 32, 112, 28, ">", function() app.OnSkip() end)
    button(window, 4, BUTTON_Y, 58, Pathfinder.L("routesButton"), function() app.OnToggleRoutes() end)
    button(window, 66, BUTTON_Y, 50, Pathfinder.L("list"), function() app.OnToggleList() end)
    button(window, 120, BUTTON_Y, 50, Pathfinder.L("map"), function() app.OnToggleMap() end)

    -- Refresh the "x s ago" text once a second
    local lastTick = 0
    window.Update = function()
        local now = Turbine.Engine.GetGameTime()
        if now - lastTick >= 1 then
            lastTick = now
            self:UpdateAge()
        end
    end
    window:SetWantsUpdates(true)

    setmetatable(self, { __index = ArrowWindow })
    return self
end

function ArrowWindow:SetVisible(visible)
    self.window:SetVisible(visible)
end

function ArrowWindow:IsVisible()
    return self.window:IsVisible()
end

-- Shows the image for the current frame, grey while the position is old
function ArrowWindow:ShowArrow()
    local name = (self.stale and "arrow_stale_" or "arrow_") .. self.frame .. ".tga"
    if name ~= self.arrowImage then
        self.arrowImage = name
        self.arrow:SetBackground(RESOURCES .. name)
    end
end

function ArrowWindow:SetRotation(rotation)
    self.frame = Pathfinder.Loc.Frame(rotation)
    self:ShowArrow()
end

function ArrowWindow:UpdateAge()
    if self.posTime == nil then
        self.ageLabel:SetText(Pathfinder.L("clickArrow"))
        self.stale = true
    else
        local age = math.floor(Turbine.Engine.GetGameTime() - self.posTime)
        self.ageLabel:SetText(Pathfinder.L("posAge", age))
        self.stale = age > (self.staleSeconds or ArrowWindow.DEFAULT_STALE_SECONDS)
    end
    -- A distance from an old position is only a rough guide
    if self.measured and self.stale then
        self.distLabel:SetText("~ " .. self.distText)
    else
        self.distLabel:SetText(self.distText or "")
    end
    self:ShowArrow()
end

function ArrowWindow:SetDistance(text, measured)
    self.distText = text
    self.measured = measured
end

-- state: RouteState or nil, pos: last parsed position or nil
function ArrowWindow:Refresh(state, pos, posTime, flip)
    self.posTime = posTime
    if state == nil then
        self.routeLabel:SetText("")
        self.nameLabel:SetText(Pathfinder.L("noRoute"))
        self.deedLabel:SetText(Pathfinder.L("noRouteHint"))
        self:SetDistance("")
        self:SetRotation(0)
        self:UpdateAge()
        return
    end
    self.routeLabel:SetText(state.route.name .. "  " .. state:DoneCount() .. "/" .. state:Total())
    local point = state:Current()
    if point == nil then
        self.nameLabel:SetText(Pathfinder.L("routeFinished"))
        self.deedLabel:SetText("")
        self:SetDistance("")
        self:SetRotation(0)
        self:UpdateAge()
        return
    end
    self.nameLabel:SetText(point.name)
    self.deedLabel:SetText(point.deed)
    local Loc = Pathfinder.Loc
    if pos == nil then
        self:SetDistance(Loc.Format(point.lon, point.lat))
    elseif state.route.region ~= nil and pos.region ~= state.route.region then
        self:SetDistance(Pathfinder.L("otherRegion"))
    else
        local meters = Loc.Distance(pos.lon, pos.lat, point.lon, point.lat)
        self:SetDistance(Pathfinder.L("distance", math.floor(meters + 0.5),
            Pathfinder.FormatKm(state:Remaining(pos))), true)
        if pos.heading ~= nil then
            local bearing = Loc.Bearing(pos.lon, pos.lat, point.lon, point.lat)
            self:SetRotation(Loc.ArrowRotation(pos.heading, bearing, flip))
        end
    end
    self:UpdateAge()
end
