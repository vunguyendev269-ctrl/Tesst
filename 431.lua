-- MYSTERIOUS FORCE - REAL BUTTON PATH FINDER V3
-- Mục tiêu: tìm GuiButton thật bên trong DialogueGui, không bị lẫn TranslationContext.

local Players = game:GetService("Players")
local LP = Players.LocalPlayer
if not LP then
    warn("[V3] LocalPlayer missing")
    return
end

local PlayerGui = LP:WaitForChild("PlayerGui", 10)
local DialogueGui = PlayerGui:FindFirstChild("DialogueGui")

if not DialogueGui then
    warn("[V3] DialogueGui not found. Open Mysterious Force dialogue first.")
    return
end

local function esc(s)
    s = tostring(s)
    s = s:gsub("\\", "\\\\")
    s = s:gsub('"', '\\"')
    return s
end

local function pathOf(obj)
    local chain = {}
    local cur = obj

    while cur and cur ~= game do
        table.insert(chain, 1, cur.Name)
        cur = cur.Parent
    end

    if cur ~= game or #chain == 0 then
        return "nil"
    end

    local expr = 'game:GetService("' .. esc(chain[1]) .. '")'

    for i = 2, #chain do
        expr = expr .. ':WaitForChild("' .. esc(chain[i]) .. '")'
    end

    return expr
end

local function safeText(obj)
    local ok, text = pcall(function()
        return tostring(obj.Text or "")
    end)
    return ok and text or ""
end

local function collectDescendantTexts(root)
    local out = {}

    for _,obj in ipairs(root:GetDescendants()) do
        if obj:IsA("TextLabel")
            or obj:IsA("TextButton")
            or obj:IsA("TextBox")
        then
            local t = safeText(obj)

            if t ~= "" then
                out[#out+1] =
                    obj.ClassName
                    .. ":"
                    .. obj.Name
                    .. "="
                    .. string.format("%q", t)
            end
        end
    end

    return out
end

local function isVisibleGui(obj)
    local cur = obj

    while cur and cur ~= PlayerGui do
        if cur:IsA("GuiObject") then
            local ok, visible = pcall(function()
                return cur.Visible
            end)

            if ok and not visible then
                return false
            end
        end

        cur = cur.Parent
    end

    return true
end

local lines = {}
local buttons = {}

for _,obj in ipairs(DialogueGui:GetDescendants()) do
    if obj:IsA("GuiButton") then
        buttons[#buttons+1] = obj
    end
end

table.sort(buttons, function(a,b)
    local ay = 0
    local by = 0

    pcall(function() ay = a.AbsolutePosition.Y end)
    pcall(function() by = b.AbsolutePosition.Y end)

    return ay < by
end)

lines[#lines+1] = "============================================================"
lines[#lines+1] = "DIALOGUE GUI REAL BUTTON FINDER V3"
lines[#lines+1] = "============================================================"
lines[#lines+1] = "DialogueGui: " .. DialogueGui:GetFullName()
lines[#lines+1] = "GuiButtons found: " .. tostring(#buttons)
lines[#lines+1] = ""

for i,button in ipairs(buttons) do
    local visible = isVisibleGui(button)

    local pos = Vector2.zero
    local size = Vector2.zero
    local active = nil

    pcall(function()
        pos = button.AbsolutePosition
        size = button.AbsoluteSize
        active = button.Active
    end)

    local ownText = ""
    if button:IsA("TextButton") then
        ownText = safeText(button)
    end

    local descendantTexts = collectDescendantTexts(button)

    lines[#lines+1] = "------------------------------------------------------------"
    lines[#lines+1] = "#" .. tostring(i)
    lines[#lines+1] = "CLASS: " .. button.ClassName
    lines[#lines+1] = "NAME: " .. button.Name
    lines[#lines+1] = "VISIBLE_CHAIN: " .. tostring(visible)
    lines[#lines+1] = "ACTIVE: " .. tostring(active)
    lines[#lines+1] = string.format(
        "POS=(%.0f, %.0f) SIZE=(%.0f, %.0f)",
        pos.X, pos.Y, size.X, size.Y
    )

    if ownText ~= "" then
        lines[#lines+1] = "OWN_TEXT: " .. string.format("%q", ownText)
    end

    lines[#lines+1] = "PATH:"
    lines[#lines+1] = pathOf(button)

    lines[#lines+1] = "PARENT:"
    lines[#lines+1] = button.Parent and pathOf(button.Parent) or "nil"

    if #descendantTexts > 0 then
        lines[#lines+1] = "DESCENDANT_TEXTS:"
        for _,t in ipairs(descendantTexts) do
            lines[#lines+1] = "  " .. t
        end
    else
        lines[#lines+1] = "DESCENDANT_TEXTS: <none>"
    end
end

-- Also describe the currently visible dialogue root(s) that contain title Mysterious Force.
lines[#lines+1] = ""
lines[#lines+1] = "============================================================"
lines[#lines+1] = "VISIBLE MYSTERIOUS FORCE ROOT CANDIDATES"
lines[#lines+1] = "============================================================"

for _,obj in ipairs(DialogueGui:GetDescendants()) do
    if obj:IsA("TextLabel") then
        local text = safeText(obj):lower()

        if text:find("mysterious force", 1, true) then
            local cur = obj
            local depth = 0

            while cur and cur ~= DialogueGui and depth < 5 do
                lines[#lines+1] =
                    tostring(depth)
                    .. " | "
                    .. cur.ClassName
                    .. " | "
                    .. cur.Name
                    .. " | "
                    .. pathOf(cur)

                cur = cur.Parent
                depth += 1
            end

            lines[#lines+1] = ""
        end
    end
end

local output = table.concat(lines, "\n")

print(output)

if type(writefile) == "function" then
    pcall(function()
        writefile("dialogue_buttons.txt", output)
    end)
end

if type(setclipboard) == "function" then
    pcall(function()
        setclipboard(output)
    end)
end

warn("[V3] Done -> workspace/dialogue_buttons.txt + clipboard")
