-- MYSTERIOUS FORCE UI OPENER DEEP FINDER - ONE SHOT
-- Open Mysterious Force UI first, then run this script.
-- Output: workspace/ui_opener_deep.txt

local okMain, errMain = pcall(function()
    local Players = game:GetService("Players")
    local lp = Players.LocalPlayer
    if not lp then
        print("[DEEP FINDER] LocalPlayer missing")
        return
    end

    local pg = lp:WaitForChild("PlayerGui", 10)
    if not pg then
        print("[DEEP FINDER] PlayerGui missing")
        return
    end

    local dg = pg:FindFirstChild("DialogueGui")
    if not dg then
        print("[DEEP FINDER] DialogueGui missing - open NPC UI first")
        return
    end

    local lines = {}

    local function add(s)
        s = tostring(s)
        lines[#lines+1] = s
        print("[DEEP FINDER] "..s)
    end

    local function esc(s)
        s = tostring(s)
        s = string.gsub(s, "\\", "\\\\")
        s = string.gsub(s, "\"", "\\\"")
        return s
    end

    local function lower(v)
        return string.lower(tostring(v or ""))
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

        local expr = 'game:GetService("'..esc(chain[1])..'")'

        for i = 2, #chain do
            expr = expr..':WaitForChild("'..esc(chain[i])..'")'
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

    local function getRoot()
        for _,root in ipairs(dg:GetChildren()) do
            local tf = root:FindFirstChild("dialogueTitleFrame")
            local title = tf and tf:FindFirstChild("name")

            if title
                and title:IsA("TextLabel")
                and lower(safeText(title)) == "mysterious force"
            then
                return root
            end
        end
    end

    local function getOption1(root)
        local options = root and root:FindFirstChild("optionsList")
        local scroller = options and options:FindFirstChild("scroller")

        if not scroller then
            return nil
        end

        for _,child in ipairs(scroller:GetChildren()) do
            if string.find(lower(child.Name), "option1", 1, true) then
                local button = child:FindFirstChild("button")
                if button and button:IsA("GuiButton") then
                    return button
                end
            end
        end
    end

    local KEYWORDS = {
        "mysterious force",
        "dialoguegui",
        "dialoguetitleframe",
        "optionslist",
        "option1",
        "use it",
        "remnant of the past",
        "racev4progress",
        "waitingfordialogue",
        "npcready",
        "npcloaded",
        "dialogue",
        "npc",
    }

    local function keywordMatch(v)
        if type(v) ~= "string" then
            return false, nil
        end

        local s = lower(v)

        for _,kw in ipairs(KEYWORDS) do
            if string.find(s, kw, 1, true) then
                return true, kw
            end
        end

        return false, nil
    end

    local function getGlobalFunction(name)
        local ok, fn = pcall(function()
            return _G[name]
        end)

        if ok and type(fn) == "function" then
            return fn
        end

        return nil
    end

    local apiGetConnections = getGlobalFunction("getconnections")
    local apiGetGc = getGlobalFunction("getgc")
    local apiGetConstants = getGlobalFunction("getconstants")
    local apiGetUpvalues = getGlobalFunction("getupvalues")
    local apiGetProtos = getGlobalFunction("getprotos")
    local apiGetFenv = getGlobalFunction("getfenv")
    local apiGetLoadedModules = getGlobalFunction("getloadedmodules")

    if type(debug) == "table" then
        if not apiGetConstants and type(debug.getconstants) == "function" then
            apiGetConstants = debug.getconstants
        end

        if not apiGetUpvalues and type(debug.getupvalues) == "function" then
            apiGetUpvalues = debug.getupvalues
        end

        if not apiGetProtos and type(debug.getprotos) == "function" then
            apiGetProtos = debug.getprotos
        end
    end

    local function scriptOf(fn)
        if not apiGetFenv then
            return nil
        end

        local ok, env = pcall(apiGetFenv, fn)

        if ok and type(env) == "table" then
            local s = env.script
            if typeof(s) == "Instance" then
                return s
            end
        end

        return nil
    end

    local function shallowValue(v)
        local t = typeof(v)

        if t == "nil" then
            return "nil"
        elseif t == "string" then
            return string.format("%q", v)
        elseif t == "number" or t == "boolean" then
            return tostring(v)
        elseif t == "Instance" then
            return pathOf(v)
        elseif t == "function" then
            return "<function:"..tostring(v)..">"
        elseif t == "table" then
            return "<table:"..tostring(v)..">"
        end

        return tostring(v)
    end

    local visitedFunctions = {}

    local function inspectFunction(fn, label, depth)
        depth = depth or 0

        if type(fn) ~= "function" then
            return
        end

        if visitedFunctions[fn] then
            add(label.." ALREADY_VISITED "..tostring(fn))
            return
        end

        visitedFunctions[fn] = true

        add("")
        add("------------------------------------------------------------")
        add(label)
        add("FUNCTION="..tostring(fn))

        local scriptObj = scriptOf(fn)

        if scriptObj then
            add("SCRIPT="..pathOf(scriptObj))
        else
            add("SCRIPT=<unknown>")
        end

        if apiGetConstants then
            local ok, constants = pcall(apiGetConstants, fn)

            if ok and type(constants) == "table" then
                add("CONSTANTS_COUNT="..tostring(#constants))

                for i,v in ipairs(constants) do
                    local hit, kw = keywordMatch(v)

                    if hit then
                        add(
                            "CONST_HIT #"
                            ..tostring(i)
                            .." = "
                            ..shallowValue(v)
                            .." ["
                            ..tostring(kw)
                            .."]"
                        )
                    end
                end
            else
                add("CONSTANTS=<failed>")
            end
        else
            add("CONSTANTS_API=<unavailable>")
        end

        if apiGetUpvalues then
            local ok, ups = pcall(apiGetUpvalues, fn)

            if ok and type(ups) == "table" then
                local count = 0

                for k,v in pairs(ups) do
                    count = count + 1

                    local show = false
                    local reason = ""

                    if type(v) == "string" then
                        local hit, kw = keywordMatch(v)
                        if hit then
                            show = true
                            reason = " keyword="..tostring(kw)
                        end

                    elseif typeof(v) == "Instance" then
                        local n = lower(v.Name)
                        if string.find(n, "dialog", 1, true)
                            or string.find(n, "npc", 1, true)
                        then
                            show = true
                            reason = " instance"
                        end

                    elseif type(v) == "table" then
                        local tested = 0

                        for tk,tv in pairs(v) do
                            tested = tested + 1

                            if tested > 40 then
                                break
                            end

                            local hk = false
                            local hv = false

                            if type(tk) == "string" then
                                hk = keywordMatch(tk)
                            end

                            if type(tv) == "string" then
                                hv = keywordMatch(tv)
                            end

                            if hk or hv then
                                show = true
                                reason = " table-keyword"
                                break
                            end
                        end
                    end

                    if show then
                        add(
                            "UPVALUE "
                            ..tostring(k)
                            .." = "
                            ..shallowValue(v)
                            ..reason
                        )
                    end
                end

                add("UPVALUES_TOTAL="..tostring(count))
            else
                add("UPVALUES=<failed>")
            end
        else
            add("UPVALUES_API=<unavailable>")
        end

        if apiGetProtos and depth < 2 then
            local ok, protos = pcall(apiGetProtos, fn)

            if ok and type(protos) == "table" then
                add("PROTOS_COUNT="..tostring(#protos))

                for i,proto in ipairs(protos) do
                    if type(proto) == "function" then
                        local shouldInspect = false

                        if apiGetConstants then
                            local okC, c = pcall(apiGetConstants, proto)

                            if okC and type(c) == "table" then
                                for _,cv in ipairs(c) do
                                    if type(cv) == "string" and keywordMatch(cv) then
                                        shouldInspect = true
                                        break
                                    end
                                end
                            end
                        end

                        if shouldInspect then
                            inspectFunction(
                                proto,
                                label..".PROTO#"..tostring(i),
                                depth+1
                            )
                        end
                    end
                end
            end
        end
    end

    local root = getRoot()

    if not root then
        print("[DEEP FINDER] Mysterious Force root not found")
        return
    end

    local button = getOption1(root)

    add("============================================================")
    add("MYSTERIOUS FORCE UI OPENER DEEP FINDER")
    add("============================================================")
    add("ROOT="..pathOf(root))
    add("OPTION1="..tostring(button and pathOf(button) or "nil"))
    add("")
    add("CAPABILITIES:")
    add("getconnections="..tostring(apiGetConnections ~= nil))
    add("getgc="..tostring(apiGetGc ~= nil))
    add("getconstants="..tostring(apiGetConstants ~= nil))
    add("getupvalues="..tostring(apiGetUpvalues ~= nil))
    add("getprotos="..tostring(apiGetProtos ~= nil))
    add("getfenv="..tostring(apiGetFenv ~= nil))
    add("getloadedmodules="..tostring(apiGetLoadedModules ~= nil))

    -- 1) Inspect option1 Activated callback.
    if button and apiGetConnections then
        add("")
        add("============================================================")
        add("OPTION1 ACTIVATED CALLBACK")
        add("============================================================")

        local okConn, conns =
            pcall(
                apiGetConnections,
                button.Activated
            )

        if okConn and type(conns) == "table" then
            add("CONNECTIONS="..tostring(#conns))

            for i,conn in ipairs(conns) do
                local fn = nil

                pcall(function()
                    fn = conn.Function
                end)

                if type(fn) ~= "function" then
                    pcall(function()
                        fn = conn["function"]
                    end)
                end

                if type(fn) == "function" then
                    inspectFunction(
                        fn,
                        "OPTION1_CALLBACK#"..tostring(i),
                        0
                    )
                else
                    add(
                        "OPTION1_CALLBACK#"
                        ..tostring(i)
                        .."=<function hidden>"
                    )
                end
            end
        else
            add("getconnections(button.Activated) failed")
        end
    else
        add("")
        add("OPTION1 callback scan unavailable")
    end

    -- 2) getloadedmodules candidates.
    if apiGetLoadedModules then
        add("")
        add("============================================================")
        add("LOADED MODULE CANDIDATES")
        add("============================================================")

        local okMods, modules =
            pcall(apiGetLoadedModules)

        if okMods and type(modules) == "table" then
            local hits = 0

            for _,mod in ipairs(modules) do
                if typeof(mod) == "Instance" then
                    local full = lower(safeFullName(mod))
                    local name = lower(mod.Name)

                    if string.find(full, "dialog", 1, true)
                        or string.find(full, "npc", 1, true)
                        or string.find(name, "dialog", 1, true)
                        or string.find(name, "npc", 1, true)
                    then
                        hits = hits + 1
                        add(
                            "#"
                            ..tostring(hits)
                            .." "
                            ..pathOf(mod)
                        )

                        if hits >= 100 then
                            break
                        end
                    end
                end
            end

            add("MODULE_HITS="..tostring(hits))
        else
            add("getloadedmodules failed")
        end
    end

    -- 3) getgc function candidates.
    if apiGetGc and apiGetConstants then
        add("")
        add("============================================================")
        add("GETGC FUNCTION CANDIDATES")
        add("============================================================")

        local okGc, objects =
            pcall(apiGetGc, true)

        if okGc and type(objects) == "table" then
            local hits = 0
            local checked = 0

            for _,obj in ipairs(objects) do
                if type(obj) == "function" then
                    checked = checked + 1

                    local okC, constants =
                        pcall(apiGetConstants, obj)

                    if okC and type(constants) == "table" then
                        local matched = false
                        local matchList = {}

                        for i,v in ipairs(constants) do
                            local hit, kw = keywordMatch(v)

                            if hit then
                                matched = true
                                matchList[#matchList+1] =
                                    "#"
                                    ..tostring(i)
                                    .."="
                                    ..shallowValue(v)
                                    .."["
                                    ..tostring(kw)
                                    .."]"
                            end
                        end

                        if matched then
                            hits = hits + 1

                            add("")
                            add(
                                "GC HIT #"
                                ..tostring(hits)
                                .." "
                                ..tostring(obj)
                            )

                            local scriptObj = scriptOf(obj)

                            if scriptObj then
                                add("SCRIPT="..pathOf(scriptObj))
                            else
                                add("SCRIPT=<unknown>")
                            end

                            add(
                                "MATCHES="
                                ..table.concat(
                                    matchList,
                                    " | "
                                )
                            )

                            inspectFunction(
                                obj,
                                "GC_FUNCTION#"..tostring(hits),
                                0
                            )

                            if hits >= 80 then
                                break
                            end
                        end
                    end
                end
            end

            add("")
            add(
                "GC_SCAN_DONE functionsChecked="
                ..tostring(checked)
                .." hits="
                ..tostring(hits)
            )
        else
            add("getgc failed")
        end
    end

    local final =
        table.concat(
            lines,
            "\n"
        )

    if type(writefile) == "function" then
        local okWrite, errWrite =
            pcall(function()
                writefile(
                    "ui_opener_deep.txt",
                    final
                )
            end)

        print(
            "[DEEP FINDER] writefile=",
            okWrite,
            errWrite
        )
    end

    if type(setclipboard) == "function" then
        local okCopy, errCopy =
            pcall(function()
                setclipboard(final)
            end)

        print(
            "[DEEP FINDER] clipboard=",
            okCopy,
            errCopy
        )
    end

    print("[DEEP FINDER] DONE -> workspace/ui_opener_deep.txt")
end)

if not okMain then
    print(
        "[DEEP FINDER FATAL] "
        .. tostring(errMain)
    )
end
