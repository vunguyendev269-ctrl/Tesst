-- MYSTERIOUS FORCE REMOTE UI OPENER FINDER - ULTRA COMPAT
-- Run this script, then click Mysterious Force within 10 seconds.
-- Output: workspace/remote_ui_opener.txt

local okMain, errMain = pcall(function()
    local Players = game:GetService("Players")
    local lp = Players.LocalPlayer

    if not lp then
        print("[OPENER FINDER] LocalPlayer missing")
        return
    end

    local pg = lp:WaitForChild("PlayerGui", 10)

    if not pg then
        print("[OPENER FINDER] PlayerGui missing")
        return
    end

    local output = {}
    local finished = false
    local deadline = os.clock() + 10

    local function add(s)
        s = tostring(s)
        output[#output + 1] = s
        print("[OPENER FINDER] " .. s)
    end

    local function esc(s)
        s = tostring(s)
        s = string.gsub(s, "\\", "\\\\")
        s = string.gsub(s, "\"", "\\\"")
        return s
    end

    local function pathOf(obj)
        if typeof(obj) ~= "Instance" then
            return tostring(obj)
        end

        local chain = {}
        local cur = obj

        while cur and cur ~= game do
            table.insert(chain, 1, cur.Name)
            cur = cur.Parent
        end

        if cur ~= game or #chain == 0 then
            return "nil"
        end

        local expr =
            'game:GetService("' .. esc(chain[1]) .. '")'

        for i = 2, #chain do
            expr =
                expr
                .. ':WaitForChild("'
                .. esc(chain[i])
                .. '")'
        end

        return expr
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

    local function isMysteriousRoot(root)
        if not root then
            return false
        end

        local titleFrame =
            root:FindFirstChild("dialogueTitleFrame")

        if not titleFrame then
            return false
        end

        local title =
            titleFrame:FindFirstChild("name")

        if not title
            or not title:IsA("TextLabel")
        then
            return false
        end

        return string.lower(
            safeText(title)
        ) == "mysterious force"
    end

    local function findRoot()
        local dg =
            pg:FindFirstChild("DialogueGui")

        if not dg then
            return nil
        end

        local children =
            dg:GetChildren()

        for i = 1, #children do
            local root =
                children[i]

            if isMysteriousRoot(root) then
                return root
            end
        end

        return nil
    end

    local function findOption1(root)
        local options =
            root:FindFirstChild("optionsList")

        if not options then
            return nil
        end

        local scroller =
            options:FindFirstChild("scroller")

        if not scroller then
            return nil
        end

        local children =
            scroller:GetChildren()

        for i = 1, #children do
            local option =
                children[i]

            local name =
                string.lower(
                    tostring(option.Name)
                )

            if string.find(
                name,
                "option1",
                1,
                true
            ) then
                local button =
                    option:FindFirstChild("button")

                if button
                    and button:IsA("GuiButton")
                then
                    return button, option
                end
            end
        end

        return nil
    end

    local function dumpTree(root)
        add("")
        add("============================================================")
        add("DIALOGUE ROOT TREE")
        add("============================================================")

        local list =
            root:GetDescendants()

        for i = 1, #list do
            local obj = list[i]

            local text = ""

            if obj:IsA("TextLabel")
                or obj:IsA("TextButton")
                or obj:IsA("TextBox")
            then
                local t = safeText(obj)

                if t ~= "" then
                    text =
                        ' | TEXT="'
                        .. t
                        .. '"'
                end
            end

            add(
                tostring(i)
                .. " | "
                .. obj.ClassName
                .. " | "
                .. obj.Name
                .. text
                .. " | "
                .. pathOf(obj)
            )
        end
    end

    local function dumpScripts(root)
        add("")
        add("============================================================")
        add("SCRIPT / MODULE CANDIDATES")
        add("============================================================")

        local found = 0

        -- Dialogue root itself.
        local list =
            root:GetDescendants()

        for i = 1, #list do
            local obj = list[i]

            if obj:IsA("LocalScript")
                or obj:IsA("ModuleScript")
            then
                found = found + 1

                add(
                    "#"
                    .. tostring(found)
                    .. " | "
                    .. obj.ClassName
                    .. " | "
                    .. pathOf(obj)
                )
            end
        end

        -- Also list likely dialogue-related scripts/modules in PlayerGui.
        local all =
            pg:GetDescendants()

        for i = 1, #all do
            local obj = all[i]

            if obj:IsA("LocalScript")
                or obj:IsA("ModuleScript")
            then
                local n =
                    string.lower(
                        tostring(obj.Name)
                    )

                if string.find(
                    n,
                    "dialog",
                    1,
                    true
                )
                    or string.find(
                        n,
                        "npc",
                        1,
                        true
                    )
                then
                    found = found + 1

                    add(
                        "#"
                        .. tostring(found)
                        .. " | "
                        .. obj.ClassName
                        .. " | "
                        .. pathOf(obj)
                    )
                end
            end
        end

        add(
            "TOTAL SCRIPT CANDIDATES = "
            .. tostring(found)
        )
    end

    local function dumpConnections(button)
        add("")
        add("============================================================")
        add("OPTION1 CONNECTIONS")
        add("============================================================")

        if type(getconnections)
            ~= "function"
        then
            add(
                "getconnections unavailable"
            )
            return
        end

        local signals = {
            "Activated",
            "MouseButton1Click",
            "MouseButton1Down",
        }

        for i = 1, #signals do
            local signalName =
                signals[i]

            local signal = nil

            local okSignal =
                pcall(function()
                    signal =
                        button[signalName]
                end)

            if okSignal and signal then
                local okConn, conns =
                    pcall(
                        getconnections,
                        signal
                    )

                if okConn
                    and type(conns)
                        == "table"
                then
                    add(
                        signalName
                        .. " COUNT="
                        .. tostring(#conns)
                    )

                    for j = 1, #conns do
                        local conn =
                            conns[j]

                        local fn = nil

                        pcall(function()
                            fn =
                                conn.Function
                        end)

                        add(
                            "  #"
                            .. tostring(j)
                            .. " FUNCTION="
                            .. tostring(fn)
                        )
                    end
                else
                    add(
                        signalName
                        .. " getconnections failed"
                    )
                end
            end
        end
    end

    local function finish(root)
        if finished then
            return
        end

        finished = true

        add("============================================================")
        add("MYSTERIOUS FORCE UI FOUND")
        add("============================================================")

        add(
            "ROOT="
            .. pathOf(root)
        )

        local button, option =
            findOption1(root)

        if button then
            add(
                "OPTION1_CONTAINER="
                .. pathOf(option)
            )

            add(
                "OPTION1_BUTTON="
                .. pathOf(button)
            )

            local okInfo, info =
                pcall(function()
                    return string.format(
                        "Visible=%s Active=%s Pos=(%.0f,%.0f) Size=(%.0f,%.0f)",
                        tostring(button.Visible),
                        tostring(button.Active),
                        button.AbsolutePosition.X,
                        button.AbsolutePosition.Y,
                        button.AbsoluteSize.X,
                        button.AbsoluteSize.Y
                    )
                end)

            if okInfo then
                add(
                    "OPTION1_INFO="
                    .. info
                )
            end
        else
            add(
                "OPTION1_BUTTON=NOT FOUND"
            )
        end

        dumpTree(root)
        dumpScripts(root)

        if button then
            dumpConnections(button)
        end

        local final =
            table.concat(
                output,
                "\n"
            )

        if type(writefile)
            == "function"
        then
            local okWrite, errWrite =
                pcall(function()
                    writefile(
                        "remote_ui_opener.txt",
                        final
                    )
                end)

            add(
                "WRITEFILE="
                .. tostring(okWrite)
                .. " "
                .. tostring(errWrite)
            )
        end

        if type(setclipboard)
            == "function"
        then
            local okCopy, errCopy =
                pcall(function()
                    setclipboard(final)
                end)

            add(
                "CLIPBOARD="
                .. tostring(okCopy)
                .. " "
                .. tostring(errCopy)
            )
        end

        print(
            "[OPENER FINDER] DONE -> workspace/remote_ui_opener.txt"
        )
    end

    add(
        "READY - CLICK Mysterious Force within 10 seconds"
    )

    -- Check if UI is already open.
    local existing =
        findRoot()

    if existing then
        finish(existing)
        return
    end

    while not finished
        and os.clock() < deadline
    do
        local root =
            findRoot()

        if root then
            finish(root)
            break
        end

        task.wait(0.05)
    end

    if not finished then
        add(
            "TIMEOUT - Mysterious Force UI not found"
        )

        local final =
            table.concat(
                output,
                "\n"
            )

        if type(writefile)
            == "function"
        then
            pcall(function()
                writefile(
                    "remote_ui_opener.txt",
                    final
                )
            end)
        end
    end
end)

if not okMain then
    print(
        "[OPENER FINDER FATAL] "
        .. tostring(errMain)
    )
end
