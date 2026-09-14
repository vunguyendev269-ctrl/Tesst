-- MYSTERIOUS FORCE UI PATH FINDER V2
-- Mo menu NPC truoc, sau do chay script nay.

local okMain, errMain = pcall(function()
    local Players = game:GetService("Players")
    local lp = Players.LocalPlayer

    if not lp then
        print("[UI FINDER] LocalPlayer = nil")
        return
    end

    local pg = lp:FindFirstChild("PlayerGui")
    if not pg then
        pg = lp:WaitForChild("PlayerGui", 10)
    end

    if not pg then
        print("[UI FINDER] PlayerGui = nil")
        return
    end

    local function safeText(obj)
        local ok, value = pcall(function()
            return obj.Text
        end)

        if ok and value ~= nil then
            return tostring(value)
        end

        return ""
    end

    local function esc(s)
        s = tostring(s)
        s = string.gsub(s, "\\", "\\\\")
        s = string.gsub(s, "\"", "\\\"")
        return s
    end

    local function makePath(obj)
        local chain = {}
        local cur = obj

        while cur and cur ~= game do
            table.insert(chain, 1, cur.Name)
            cur = cur.Parent
        end

        if cur ~= game or #chain == 0 then
            return "nil"
        end

        local result =
            'game:GetService("' .. esc(chain[1]) .. '")'

        for i = 2, #chain do
            result =
                result
                .. ':WaitForChild("'
                .. esc(chain[i])
                .. '")'
        end

        return result
    end

    local function containsTarget(text)
        local s = string.lower(text)

        if string.find(s, "use it", 1, true) then
            return true, "use it"
        end

        if string.find(s, "mysterious force", 1, true) then
            return true, "mysterious force"
        end

        if string.find(s, "remnant of the past", 1, true) then
            return true, "remnant of the past"
        end

        return false, nil
    end

    local output = {}
    local found = 0

    local descendants = pg:GetDescendants()

    for i = 1, #descendants do
        local obj = descendants[i]

        local isTextObject =
            obj:IsA("TextButton")
            or obj:IsA("TextLabel")
            or obj:IsA("TextBox")

        if isTextObject then
            local text = safeText(obj)
            local matched, keyword = containsTarget(text)

            if matched then
                found = found + 1

                output[#output + 1] =
                    "============================================================"

                output[#output + 1] =
                    "MATCH #" .. tostring(found)

                output[#output + 1] =
                    "KEYWORD: " .. tostring(keyword)

                output[#output + 1] =
                    "CLASS: " .. tostring(obj.ClassName)

                output[#output + 1] =
                    "NAME: " .. tostring(obj.Name)

                output[#output + 1] =
                    "TEXT: " .. tostring(text)

                output[#output + 1] =
                    "PATH:"

                output[#output + 1] =
                    makePath(obj)

                if obj:IsA("GuiObject") then
                    local okGui, guiInfo = pcall(function()
                        return string.format(
                            "VISIBLE=%s | POS=(%.0f, %.0f) | SIZE=(%.0f, %.0f)",
                            tostring(obj.Visible),
                            obj.AbsolutePosition.X,
                            obj.AbsolutePosition.Y,
                            obj.AbsoluteSize.X,
                            obj.AbsoluteSize.Y
                        )
                    end)

                    if okGui then
                        output[#output + 1] = guiInfo
                    end
                end

                output[#output + 1] =
                    "PARENT: "
                    .. (
                        obj.Parent
                        and makePath(obj.Parent)
                        or "nil"
                    )

                output[#output + 1] = ""
            end
        end
    end

    if found == 0 then
        output[#output + 1] =
            "KHONG TIM THAY UI."

        output[#output + 1] =
            "Mo Mysterious Force menu truoc roi chay lai."
    end

    local final = table.concat(output, "\n")

    print(final)

    if type(writefile) == "function" then
        local okWrite, errWrite = pcall(function()
            writefile("ui_path.txt", final)
        end)

        print(
            "[UI FINDER] writefile:",
            okWrite,
            errWrite
        )
    end

    if type(setclipboard) == "function" then
        local okCopy, errCopy = pcall(function()
            setclipboard(final)
        end)

        print(
            "[UI FINDER] clipboard:",
            okCopy,
            errCopy
        )
    end

    print(
        "[UI FINDER] DONE | found = "
        .. tostring(found)
    )
end)

if not okMain then
    print(
        "[UI FINDER ERROR] "
        .. tostring(errMain)
    )
end
