-- Pathfinder.ListWindow: alle Taten der Route mit ihren Zielen zum Abhaken.
-- Das Spiel gibt Plugins keinen Zugriff aufs Tatenbuch, deshalb stellt man
-- hier ein, was schon erledigt ist. Ein Haken an der Tat setzt alle Ziele.
-- Taten lassen sich einklappen, erledigte Ziele ausblenden.

Pathfinder = Pathfinder or {}

local ListWindow = {}
Pathfinder.ListWindow = ListWindow

local WIDTH = 380
local HEIGHT = 520
local MARGIN_X = 12
local MARGIN_TOP = 38
local ROW_HEIGHT = 20
local SCROLL_WIDTH = 10
local TOGGLE_WIDTH = 16
local POINT_INDENT = 34

local COLOR_DEED = Turbine.UI.Color(1, 0.95, 0.8, 0.4)
local COLOR_POINT = Turbine.UI.Color(1, 0.9, 0.9, 0.9)
local COLOR_CURRENT = Turbine.UI.Color(1, 0.3, 1, 0.4)

-- app: { OnChanged(), OnFilterChanged(openOnly), OnMoved(x, y), OnClosed() }
-- openOnly: hide finished targets
function ListWindow.Create(app, x, y, openOnly)
    local self = setmetatable({}, { __index = ListWindow })
    self.app = app
    self.openOnly = openOnly and true or false
    self.collapsed = {}

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

    local filter = Turbine.UI.Lotro.CheckBox()
    filter:SetParent(window)
    filter:SetPosition(MARGIN_X, MARGIN_TOP + 18)
    filter:SetSize(WIDTH - 2 * MARGIN_X, ROW_HEIGHT)
    filter:SetFont(Turbine.UI.Lotro.Font.Verdana12)
    filter:SetText(" " .. Pathfinder.L("hideDone"))
    filter:SetChecked(self.openOnly)
    filter.CheckedChanged = function()
        self.openOnly = filter:IsChecked()
        app.OnFilterChanged(self.openOnly)
        self:Build(self.state)
        self:Refresh(self.state)
    end

    local top = MARGIN_TOP + 18 + ROW_HEIGHT + 2
    local listHeight = HEIGHT - top - 20
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

    self.rows = {}
    return self
end

function ListWindow:SetVisible(visible)
    self.window:SetVisible(visible)
end

function ListWindow:IsVisible()
    return self.window:IsVisible()
end

-- One row: optional +/- toggle in front, then a check box
function ListWindow:Row(text, indent, color, onChange, onToggle)
    local row = Turbine.UI.Control()
    row:SetSize(self.list:GetWidth(), ROW_HEIGHT)
    local toggle
    if onToggle ~= nil then
        toggle = Turbine.UI.Label()
        toggle:SetParent(row)
        toggle:SetPosition(indent, 0)
        toggle:SetSize(TOGGLE_WIDTH, ROW_HEIGHT)
        toggle:SetFont(Turbine.UI.Lotro.Font.Verdana14)
        toggle:SetForeColor(color)
        toggle:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleCenter)
        toggle.MouseClick = onToggle
        indent = indent + TOGGLE_WIDTH + 2
    end
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
    box:SetParent(row)
    box:SetPosition(indent, 0)
    self.list:AddItem(row)
    return box, toggle
end

local function deedProgress(state, deed)
    local done = 0
    for _, point in ipairs(deed.points) do
        if state:IsDone(point) then
            done = done + 1
        end
    end
    return done, #deed.points
end

-- Rebuilds the rows: for a new route, after filtering or folding
function ListWindow:Build(state)
    if state ~= self.state then
        self.collapsed = {}
    end
    self.list:ClearItems()
    self.rows = {}
    self.state = state
    if state == nil then
        return
    end
    for _, deed in ipairs(state:Deeds()) do
        local done, total = deedProgress(state, deed)
        -- Finished deeds start folded
        if self.collapsed[deed.name] == nil then
            self.collapsed[deed.name] = done == total
        end
        local collapsed = self.collapsed[deed.name]
        local deedBox, toggle = self:Row(deed.name, 0, COLOR_DEED, function(checked)
            for _, point in ipairs(deed.points) do
                state:SetDone(point, checked)
            end
            self.app.OnChanged()
        end, function()
            self.collapsed[deed.name] = not self.collapsed[deed.name]
            self:Build(state)
            self:Refresh(state)
        end)
        toggle:SetText(collapsed and "+" or "-")
        table.insert(self.rows, { box = deedBox, deed = deed })
        if not collapsed then
            for _, point in ipairs(deed.points) do
                if not (self.openOnly and state:IsDone(point)) then
                    local box = self:Row(point.name, POINT_INDENT, COLOR_POINT, function(checked)
                        state:SetDone(point, checked)
                        self.app.OnChanged()
                    end)
                    table.insert(self.rows, { box = box, point = point })
                end
            end
        end
    end
    self.builtDone = state:DoneCount()
end

function ListWindow:Refresh(state)
    -- With the filter on, ticked targets have to disappear
    if state ~= self.state or (self.openOnly and state ~= nil and state:DoneCount() ~= self.builtDone) then
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
            local done, total = deedProgress(state, row.deed)
            row.box:SetChecked(done == total)
            row.box:SetText(" " .. row.deed.name .. "  " .. done .. "/" .. total)
        end
    end
    self.updating = false
end
