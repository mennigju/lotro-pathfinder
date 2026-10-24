-- Pathfinder.SettingsWindow: die Einstellungen der /pf-Befehle als Fenster.
-- Aenderungen wirken sofort; Main.lua speichert sie.

Pathfinder = Pathfinder or {}

local SettingsWindow = {}
Pathfinder.SettingsWindow = SettingsWindow

local WIDTH = 300
local MARGIN_X = 14
local MARGIN_TOP = 40
local ROW = 24
local RADIUS_STEP = 5
local AGE_STEP = 5

local COLOR_TEXT = Turbine.UI.Color(1, 0.9, 0.85, 0.7)
local COLOR_HINT = Turbine.UI.Color(1, 0.7, 0.7, 0.7)

local function label(parent, x, y, w, text, color, font)
    local l = Turbine.UI.Label()
    l:SetParent(parent)
    l:SetPosition(x, y)
    l:SetSize(w, ROW - 4)
    l:SetFont(font or Turbine.UI.Lotro.Font.Verdana12)
    l:SetForeColor(color or COLOR_TEXT)
    l:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleLeft)
    l:SetText(text or "")
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

-- app: { Values() -> { radius, age, flip, areas, lang, arrow, map, list, routes },
--        SetRadius(m), SetAge(s), SetFlip(on), SetAreas(on), SetLang("de"|"en"),
--        SetWindow(name, visible), OnMoved(x, y), OnClosed() }
function SettingsWindow.Create(app, x, y)
    local self = setmetatable({}, { __index = SettingsWindow })
    self.app = app
    self.checks = {}

    local window = Turbine.UI.Lotro.Window()
    window:SetText(Pathfinder.L("settingsTitle"))
    window:SetPosition(x, y)
    window.PositionChanged = function()
        app.OnMoved(window:GetPosition())
    end
    window.VisibleChanged = function()
        if window:IsVisible() then
            self:Refresh()
        else
            app.OnClosed()
        end
    end
    self.window = window

    local top = MARGIN_TOP
    local valueX = WIDTH - MARGIN_X - 120

    -- Number with -/+ buttons
    local function stepper(text, step, minimum, set, field)
        label(window, MARGIN_X, top, valueX - MARGIN_X, text)
        local value = label(window, valueX + 26, top, 68, "", Turbine.UI.Color(1, 1, 1, 1))
        value:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleCenter)
        button(window, valueX, top, 24, "-", function()
            set(math.max(minimum, self.app.Values()[field] - step))
            self:Refresh()
        end)
        button(window, valueX + 96, top, 24, "+", function()
            set(self.app.Values()[field] + step)
            self:Refresh()
        end)
        top = top + ROW
        return value
    end

    self.radius = stepper(Pathfinder.L("settingRadius"), RADIUS_STEP, RADIUS_STEP, app.SetRadius, "radius")
    self.age = stepper(Pathfinder.L("settingAge"), AGE_STEP, AGE_STEP, app.SetAge, "age")

    local function check(text, field, onChange)
        local box = Turbine.UI.Lotro.CheckBox()
        box:SetParent(window)
        box:SetPosition(MARGIN_X, top)
        box:SetSize(WIDTH - 2 * MARGIN_X, ROW - 4)
        box:SetFont(Turbine.UI.Lotro.Font.Verdana12)
        box:SetForeColor(COLOR_TEXT)
        box:SetText(" " .. text)
        box.CheckedChanged = function()
            if not self.updating then
                onChange(box:IsChecked())
            end
        end
        self.checks[field] = box
        top = top + ROW
    end

    check(Pathfinder.L("settingFlip"), "flip", app.SetFlip)
    check(Pathfinder.L("settingAreas"), "areas", app.SetAreas)
    top = top + 6
    label(window, MARGIN_X, top, WIDTH - 2 * MARGIN_X, Pathfinder.L("settingWindows"))
    top = top + ROW
    for _, name in ipairs({ "arrow", "routes", "list", "map" }) do
        check(Pathfinder.L("window_" .. name), name, function(visible)
            app.SetWindow(name, visible)
        end)
    end

    top = top + 6
    label(window, MARGIN_X, top, valueX - MARGIN_X, Pathfinder.L("settingLang"))
    self.langDe = button(window, valueX, top, 58, "Deutsch", function()
        app.SetLang("de")
        self:Refresh()
    end)
    self.langEn = button(window, valueX + 62, top, 58, "English", function()
        app.SetLang("en")
        self:Refresh()
    end)
    top = top + ROW
    self.langHint = label(window, MARGIN_X, top, WIDTH - 2 * MARGIN_X, "", COLOR_HINT,
        Turbine.UI.Lotro.Font.Verdana10)
    top = top + ROW

    window:SetSize(WIDTH, top + 10)
    return self
end

function SettingsWindow:SetVisible(visible)
    self.window:SetVisible(visible)
end

function SettingsWindow:IsVisible()
    return self.window:IsVisible()
end

-- Shows the current values, also after changes by /pf commands
function SettingsWindow:Refresh()
    if not self:IsVisible() then
        return
    end
    local values = self.app.Values()
    self.radius:SetText(values.radius .. " m")
    self.age:SetText(values.age .. " s")
    self.updating = true
    for field, box in pairs(self.checks) do
        box:SetChecked(values[field] and true or false)
    end
    self.updating = false
    self.langDe:SetEnabled(values.lang ~= "de")
    self.langEn:SetEnabled(values.lang ~= "en")
    self.langHint:SetText(values.lang ~= Pathfinder.Lang and Pathfinder.L("settingLangReload") or "")
end
