local _, MP = ...
-- Addon-owned surfaces only. No templates, framework or gameplay hooks.
local Theme = {}
MP.UITheme = Theme
Theme.colors = {
    canvas = { 0.043, 0.055, 0.071, 1 }, card = { 0.086, 0.102, 0.137, 1 },
    border = { 0.18, 0.21, 0.28, 1 }, button = { 0.14, 0.17, 0.23, 1 },
    selected = { 0.20, 0.25, 0.37, 1 }, gold = { 1, 0.79, 0.25, 1 },
    text = { 0.91, 0.94, 1, 1 }, muted = { 0.56, 0.64, 0.76, 1 },
    green = { 0.32, 0.82, 0.63, 1 }, blue = { 0.40, 0.67, 1, 1 },
}
function Theme.Color(widget, color)
    if widget.SetTextColor then widget:SetTextColor(unpack(Theme.colors[color])) end
end
function Theme.Surface(frame, color)
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame); bg:SetColorTexture(unpack(Theme.colors[color or "card"]))
    for _, edge in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local line = frame:CreateTexture(nil, "BORDER")
        if edge == "TOP" or edge == "BOTTOM" then
            line:SetPoint(edge .. "LEFT", frame, edge .. "LEFT", 0, 0)
            line:SetPoint(edge .. "RIGHT", frame, edge .. "RIGHT", 0, 0); line:SetHeight(1)
        else
            line:SetPoint("TOP" .. edge, frame, "TOP" .. edge, 0, 0)
            line:SetPoint("BOTTOM" .. edge, frame, "BOTTOM" .. edge, 0, 0); line:SetWidth(1)
        end
        line:SetColorTexture(unpack(Theme.colors.border))
    end
    return bg
end
function Theme.Paint(button, active)
    if active ~= nil then button.active = active end
    local enabled = button:IsEnabled()
    button.surface:SetColorTexture(unpack(Theme.colors[button.active and "selected" or (enabled and "button" or "card")]))
    Theme.Color(button.caption, button.active and "gold" or (enabled and "text" or "muted"))
end
function Theme.Button(parent, text, width, height, callback)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, height)
    b.surface = Theme.Surface(b, "button")
    b.caption = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.caption:SetPoint("CENTER", b, "CENTER", 0, 0); b.caption:SetWidth(width - 10)
    b.caption:SetJustifyH("CENTER")
    b.caption:SetWordWrap(false)
    b:SetFontString(b.caption); b:SetText(text)
    local enable, disable = b.Enable, b.Disable
    b.Enable = function(self) enable(self); Theme.Paint(self) end
    b.Disable = function(self) disable(self); Theme.Paint(self) end
    b:SetScript("OnClick", callback)
    b:SetScript("OnEnter", function() if b:IsEnabled() then b.surface:SetColorTexture(unpack(Theme.colors.selected)) end end)
    b:SetScript("OnLeave", function() Theme.Paint(b) end)
    Theme.Paint(b)
    return b
end
