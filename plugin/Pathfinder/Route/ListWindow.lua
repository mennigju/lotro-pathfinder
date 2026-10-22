-- Pathfinder.ListWindow: alle Taten der Route mit ihren Zielen zum Abhaken.
-- Das Spiel gibt Plugins keinen Zugriff aufs Tatenbuch, deshalb stellt man
-- hier ein, was schon erledigt ist. Ein Haken an der Tat setzt alle Ziele.

Pathfinder = Pathfinder or {}

local ListWindow = {}
Pathfinder.ListWindow = ListWindow

local WIDTH = 380
local HEIGHT = 520
local MARGIN_X = 12
local MARGIN_TOP = 38
local ROW_HEIGHT = 20
local SCROLL_WIDTH = 10

local COLOR_DEED = Turbine.UI.Color(1, 0.95, 0.8, 0.4)
local COLOR_POINT = Turbine.UI.Color(1, 0.9, 0.9, 0.9)
local COLOR_CURRENT = Turbine.UI.Color(1, 0.3, 1, 0.4)

-- app: { OnChanged(), OnMoved(x, y), OnClosed() }
function ListWindow.Create(app, x, y)
    local self = setmetatable({}, { __index = ListWindow })
    self.app = app

    local window = Turbine.UI.Lotro.Window()
    window:SetText(Pathfinder.L("deedsTitle"))
    window:SetSize(WIDTH, HEIGHT)
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

    local hint = Turbine.UI.Label()
    hint:SetParent(window)
    hint:SetPosition(MARGIN_X, MARGIN_TOP)
    hint:SetSize(WIDTH - 2 * MARGIN_X, 18)
    hint:SetFont(Turbine.UI.Lotro.Font.Verdana10)
    hint:SetForeColor(Turbine.UI.Color(1, 0.75, 0.75, 0.75))
    hint:SetText(Pathfinder.L("deedsHint"))

    local listHeight = HEIGHT - MARGIN_TOP - 18 - 20
    local list = Turbine.UI.ListBox()
    list:SetParent(window)
    list:SetPosition(MARGIN_X, MARGIN_TOP + 20)
    list:SetSize(WIDTH - 2 * MARGIN_X - SCROLL_WIDTH - 2, listHeight)
    self.list = list

    local scroll = Turbine.UI.Lotro.ScrollBar()
    scroll:SetParent(window)
    scroll:SetOrientation(Turbine.UI.Orientation.Vertical)
    scroll:SetPosition(WIDTH - MARGIN_X - SCROLL_WIDTH, MARGIN_TOP + 20)
    scroll:SetSize(SCROLL_WIDTH, listHeight)
    list:SetVerticalScrollBar(scroll)

    self.rows = {}
    return self
end

function ListWindow:SetVisible(visible)
    self.window:SetVisible(visible)
end

function ListWindow:IsVisible()
    return self.window:IsVisible()
end

function ListWindow:Row(text, indent, color, onChange)
    local box = Turbine.UI.Lotro.CheckBox()
    box:SetSize(self.list:GetWidth() - indent, ROW_HEIGHT)
    box:SetFont(Turbine.UI.Lotro.Font.Verdana12)
    box:SetForeColor(color)
    box:SetText(" " .. text)
    box.CheckedChanged = function()
        -- Ignore our own SetChecked calls in Refresh
        if not self.updating then
            onChange(box:IsChecked())
        end
    end
    local row = Turbine.UI.Control()
    row:SetSize(self.list:GetWidth(), ROW_HEIGHT)
    box:SetParent(row)
    box:SetPosition(indent, 0)
    self.list:AddItem(row)
    return box
end

-- Rebuilds the rows for a new route
function ListWindow:Build(state)
    self.list:ClearItems()
    self.rows = {}
    self.state = state
    if state == nil then
        return
    end
    for _, deed in ipairs(state:Deeds()) do
        local deedBox = self:Row(deed.name, 0, COLOR_DEED, function(checked)
            for _, point in ipairs(deed.points) do
                state:SetDone(point, checked)
            end
            self.app.OnChanged()
        end)
        table.insert(self.rows, { box = deedBox, deed = deed })
        for _, point in ipairs(deed.points) do
            local box = self:Row(point.name, 18, COLOR_POINT, function(checked)
                state:SetDone(point, checked)
                self.app.OnChanged()
            end)
            table.insert(self.rows, { box = box, point = point })
        end
    end
end

function ListWindow:Refresh(state)
    if state ~= self.state then
        self:Build(state)
    end
    if state == nil then
        return
    end
    local current = state:Current()
    self.updating = true
    for _, row in ipairs(self.rows) do
        if row.point ~= nil then
            row.box:SetChecked(state:IsDone(row.point))
            row.box:SetForeColor(row.point == current and COLOR_CURRENT or COLOR_POINT)
        else
            local all = true
            for _, point in ipairs(row.deed.points) do
                all = all and state:IsDone(point)
            end
            row.box:SetChecked(all)
        end
    end
    self.updating = false
end
