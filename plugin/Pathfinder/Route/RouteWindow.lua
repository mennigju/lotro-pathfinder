-- Pathfinder.RouteWindow: Routen suchen und waehlen, mit Fortschritt.
-- "Nur hier" zeigt die Routen an der letzten Position (wie /pf hier).

Pathfinder = Pathfinder or {}

local RouteWindow = {}
Pathfinder.RouteWindow = RouteWindow

local WIDTH = 360
local HEIGHT = 440
local MARGIN_X = 12
local MARGIN_TOP = 38
local ROW_HEIGHT = 18
local SCROLL_WIDTH = 10

local COLOR_ROUTE = Turbine.UI.Color(1, 0.9, 0.9, 0.9)
local COLOR_ACTIVE = Turbine.UI.Color(1, 0.3, 1, 0.4)
local COLOR_FINISHED = Turbine.UI.Color(1, 0.55, 0.55, 0.55)
local COLOR_HOVER = Turbine.UI.Color(1, 1, 0.85, 0.4)

-- app: { Find(text, hereOnly) -> routes, Progress(route) -> done, total,
--        OnSelect(route), OnMoved(x, y), OnClosed() }
function RouteWindow.Create(app, x, y)
    local self = setmetatable({}, { __index = RouteWindow })
    self.app = app

    local window = Turbine.UI.Lotro.Window()
    window:SetText(Pathfinder.L("routesTitle"))
    window:SetSize(WIDTH, HEIGHT)
    window:SetPosition(x, y)
    window.PositionChanged = function()
        app.OnMoved(window:GetPosition())
    end
    window.VisibleChanged = function()
        if window:IsVisible() then
            self:Fill()
        else
            app.OnClosed()
        end
    end
    self.window = window

    local search = Turbine.UI.Lotro.TextBox()
    search:SetParent(window)
    search:SetPosition(MARGIN_X, MARGIN_TOP)
    search:SetSize(WIDTH - 2 * MARGIN_X - 110, 20)
    search:SetFont(Turbine.UI.Lotro.Font.Verdana14)
    search:SetMultiline(false)
    search.TextChanged = function()
        self:Fill()
    end
    self.search = search

    local here = Turbine.UI.Lotro.CheckBox()
    here:SetParent(window)
    here:SetPosition(WIDTH - MARGIN_X - 104, MARGIN_TOP)
    here:SetSize(104, 20)
    here:SetFont(Turbine.UI.Lotro.Font.Verdana12)
    here:SetText(" " .. Pathfinder.L("hereOnly"))
    here.CheckedChanged = function()
        self:Fill()
    end
    self.here = here

    self.status = Turbine.UI.Label()
    self.status:SetParent(window)
    self.status:SetPosition(MARGIN_X, HEIGHT - 26)
    self.status:SetSize(WIDTH - 2 * MARGIN_X, 16)
    self.status:SetFont(Turbine.UI.Lotro.Font.Verdana10)
    self.status:SetForeColor(Turbine.UI.Color(1, 0.75, 0.75, 0.75))

    local top = MARGIN_TOP + 26
    local listHeight = HEIGHT - top - 30
    local list = Turbine.UI.ListBox()
    list:SetParent(window)
    list:SetPosition(MARGIN_X, top)
    list:SetSize(WIDTH - 2 * MARGIN_X - SCROLL_WIDTH - 2, listHeight)
    self.list = list

    local scroll = Turbine.UI.Lotro.ScrollBar()
    scroll:SetParent(window)
    scroll:SetOrientation(Turbine.UI.Orientation.Vertical)
    scroll:SetPosition(WIDTH - MARGIN_X - SCROLL_WIDTH, top)
    scroll:SetSize(SCROLL_WIDTH, listHeight)
    list:SetVerticalScrollBar(scroll)

    return self
end

function RouteWindow:SetVisible(visible)
    self.window:SetVisible(visible)
end

function RouteWindow:IsVisible()
    return self.window:IsVisible()
end

function RouteWindow:Row(route, active)
    local done, total = self.app.Progress(route)
    local color = COLOR_ROUTE
    if route == active then
        color = COLOR_ACTIVE
    elseif done == total then
        color = COLOR_FINISHED
    end
    local row = Turbine.UI.Label()
    row:SetSize(self.list:GetWidth(), ROW_HEIGHT)
    row:SetFont(Turbine.UI.Lotro.Font.Verdana12)
    row:SetForeColor(color)
    row:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleLeft)
    row:SetText(string.format(" %s  (%d/%d)", route.name, done, total))
    row.MouseEnter = function()
        row:SetForeColor(COLOR_HOVER)
    end
    row.MouseLeave = function()
        row:SetForeColor(color)
    end
    row.MouseClick = function()
        self.app.OnSelect(route)
    end
    self.list:AddItem(row)
end

-- Rebuilds the list from the search text and the "here" filter
function RouteWindow:Fill()
    if not self:IsVisible() then
        return
    end
    self.list:ClearItems()
    local routes, problem = self.app.Find(self.search:GetText(), self.here:IsChecked())
    for _, route in ipairs(routes) do
        self:Row(route, self.active)
    end
    self.status:SetText(problem or Pathfinder.L("routesCount", #routes))
end

-- active: the selected route, highlighted. done: its done count, the
-- progress shown changes with it
function RouteWindow:Refresh(active, done)
    if active ~= self.active or done ~= self.done then
        self.active, self.done = active, done
        self:Fill()
    end
end
