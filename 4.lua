-- UI PATH FINDER - MYSTERIOUS FORCE / USE IT
-- Mở UI NPC trước, rồi chạy script này.
-- Nó sẽ tìm TextButton/TextLabel có text "Use it" / "Mysterious Force"
-- và in/copy path đầy đủ + ancestor tree.

local Players = game:GetService("Players")
local LP = Players.LocalPlayer
local PlayerGui = LP:WaitForChild("PlayerGui")

local KEYWORDS = {
    "use it",
    "mysterious force",
    "remnant of the past",
}

local function getText(obj)
    local ok, text = pcall(function()
        return tostring(obj.Text or "")
    end)
    return ok and text or ""
end

local function matched(text)
    local s = text:lower()

    for _,keyword in ipairs(KEYWORDS) do
        if s:find(keyword, 1, true) then
            return true, keyword
        end
    end

    return false
end

local function luaPath(inst)
    local parts = {}
    local cur = inst

    while cur and cur ~= game do
        table.insert(parts, 1, cur.Name)
        cur = cur.Parent
    end

    if not cur or #parts == 0 then
        return "nil"
    end

    local expr =
        'game:GetService("'
        .. parts[1]
        .. '")'

    for i = 2, #parts do
        expr =
            expr
            .. ':WaitForChild("'
            .. parts[i]:gsub('"', '\\"')
            .. '")'
    end

    return expr
end

local function ancestorTree(inst)
    local lines = {}
    local cur = inst
    local depth = 0

    while cur and cur ~= game and depth < 12 do
        local extra = ""

        if cur:IsA("GuiObject") then
            local ok, visible, pos, size =
                pcall(function()
                    return cur.Visible, cur.AbsolutePosition, cur.AbsoluteSize
                end)

            if ok then
                extra =
                    string.format(
                        " | Visible=%s | AbsPos=(%.0f,%.0f) | AbsSize=(%.0f,%.0f)",
                        tostring(visible),
                        pos.X,
                        pos.Y,
                        size.X,
                        size.Y
                    )
            end
        end

        lines[#lines+1] =
            string.rep("  ", depth)
            .. cur.ClassName
            .. " : "
            .. cur.Name
            .. extra

        cur = cur.Parent
        depth += 1
    end

    return table.concat(lines, "\n")
end

local results = {}

for _,obj in ipairs(PlayerGui:GetDescendants()) do
    if obj:IsA("TextButton")
        or obj:IsA("TextLabel")
        or obj:IsA("TextBox")
    then
        local text = getText(obj)
        local ok, keyword = matched(text)

        if ok then
            results[#results+1] =
                "============================================================\n"
                .. "MATCH: "
                .. tostring(keyword)
                .. "\n"
                .. "CLASS: "
                .. obj.ClassName
                .. "\n"
                .. "NAME: "
                .. obj.Name
                .. "\n"
                .. "TEXT: "
                .. text
                .. "\n"
                .. "FULLNAME: "
                .. obj:GetFullName()
                .. "\n"
                .. "LUA PATH:\n"
                .. luaPath(obj)
                .. "\n\nANCESTORS:\n"
                .. ancestorTree(obj)
                .. "\n"
    end
end

local output

if #results == 0 then
    output =
        "Không tìm thấy UI chứa Use it / Mysterious Force.\n"
        .. "Hãy mở menu NPC trước rồi chạy lại."
else
    output = table.concat(results, "\n")
end

print(output)

if type(writefile) == "function" then
    pcall(function()
        writefile("ui_path.txt", output)
    end)
end

if type(setclipboard) == "function" then
    pcall(function()
        setclipboard(output)
    end)
end

warn("[UI PATH FINDER] Done. workspace/ui_path.txt + clipboard")
