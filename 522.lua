-- MYSTERIOUS FORCE UI OPENER - REGISTRY / SCRIPT CLOSURE FINDER
-- One-shot, no network hook, no background loop.
-- Output: workspace/ui_opener_registry.txt

local okMain, errMain = pcall(function()
    local Players = game:GetService("Players")
    local lp = Players.LocalPlayer

    if not lp then
        print("[REG FINDER] LocalPlayer missing")
        return
    end

    local pg = lp:WaitForChild("PlayerGui", 10)

    if not pg then
        print("[REG FINDER] PlayerGui missing")
        return
    end

    local lines = {}
    local seenFunctions = {}
    local scannedFunctions = 0
    local hitFunctions = 0

    local function add(s)
        s = tostring(s)
        lines[#lines + 1] = s
        print("[REG FINDER] " .. s)
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

    -- --------------------------------------------------------
    -- Resolve executor/debug APIs safely.
    -- --------------------------------------------------------
    local function globalFn(name)
        local ok, fn = pcall(function()
            return _G[name]
        end)

        if ok and type(fn) == "function" then
            return fn
        end

        return nil
    end

    local apiGetConstants = globalFn("getconstants")
    local apiGetUpvalues = globalFn("getupvalues")
    local apiGetProtos = globalFn("getprotos")
    local apiGetReg = globalFn("getreg")
    local apiGetScripts = globalFn("getscripts")
    local apiGetScriptClosure = globalFn("getscriptclosure")
    local apiGetLoadedModules = globalFn("getloadedmodules")
    local apiGetGc = globalFn("getgc")

    local apiDebugRegistry = nil
    local apiDebugInfo = nil

    if type(debug) == "table" then
        if not apiGetConstants
            and type(debug.getconstants) == "function"
        then
            apiGetConstants = debug.getconstants
        end

        if not apiGetUpvalues
            and type(debug.getupvalues) == "function"
        then
            apiGetUpvalues = debug.getupvalues
        end

        if not apiGetProtos
            and type(debug.getprotos) == "function"
        then
            apiGetProtos = debug.getprotos
        end

        if type(debug.getregistry) == "function" then
            apiDebugRegistry = debug.getregistry
        end

        if type(debug.info) == "function" then
            apiDebugInfo = debug.info
        end
    end

    add("============================================================")
    add("MYSTERIOUS FORCE UI OPENER REGISTRY FINDER")
    add("============================================================")
    add("CAPABILITIES:")
    add("getconstants=" .. tostring(apiGetConstants ~= nil))
    add("getupvalues=" .. tostring(apiGetUpvalues ~= nil))
    add("getprotos=" .. tostring(apiGetProtos ~= nil))
    add("getreg=" .. tostring(apiGetReg ~= nil))
    add("debug.getregistry=" .. tostring(apiDebugRegistry ~= nil))
    add("getscripts=" .. tostring(apiGetScripts ~= nil))
    add("getscriptclosure=" .. tostring(apiGetScriptClosure ~= nil))
    add("getloadedmodules=" .. tostring(apiGetLoadedModules ~= nil))
    add("getgc=" .. tostring(apiGetGc ~= nil))
    add("debug.info=" .. tostring(apiDebugInfo ~= nil))
    add("")

    if not apiGetConstants then
        add("STOP: getconstants unavailable, cannot inspect functions.")
        return
    end

    local function functionInfo(fn)
        if not apiDebugInfo then
            return tostring(fn)
        end

        local src = "?"
        local line = "?"
        local name = "?"

        pcall(function()
            local v = apiDebugInfo(fn, "s")
            if v ~= nil then
                src = tostring(v)
            end
        end)

        pcall(function()
            local v = apiDebugInfo(fn, "l")
            if v ~= nil then
                line = tostring(v)
            end
        end)

        pcall(function()
            local v = apiDebugInfo(fn, "n")
            if v ~= nil then
                name = tostring(v)
            end
        end)

        return
            tostring(fn)
            .. " | source="
            .. src
            .. " | line="
            .. line
            .. " | name="
            .. name
    end

    local function inspectFunction(fn, origin, depth)
        depth = depth or 0

        if type(fn) ~= "function" then
            return
        end

        if seenFunctions[fn] then
            return
        end

        seenFunctions[fn] = true
        scannedFunctions = scannedFunctions + 1

        local okConst, constants =
            pcall(
                apiGetConstants,
                fn
            )

        if not okConst
            or type(constants) ~= "table"
        then
            return
        end

        local matches = {}

        for i,v in ipairs(constants) do
            if type(v) == "string" then
                local hit, kw =
                    keywordMatch(v)

                if hit then
                    matches[#matches + 1] =
                        "#"
                        .. tostring(i)
                        .. "="
                        .. string.format("%q", v)
                        .. "["
                        .. tostring(kw)
                        .. "]"
                end
            end
        end

        if #matches > 0 then
            hitFunctions = hitFunctions + 1

            add("")
            add("------------------------------------------------------------")
            add("HIT #" .. tostring(hitFunctions))
            add("ORIGIN=" .. tostring(origin))
            add("FUNCTION=" .. functionInfo(fn))
            add("MATCHES=" .. table.concat(matches, " | "))

            if apiGetUpvalues then
                local okUp, ups =
                    pcall(
                        apiGetUpvalues,
                        fn
                    )

                if okUp
                    and type(ups) == "table"
                then
                    local shown = 0

                    for k,v in pairs(ups) do
                        if shown >= 20 then
                            break
                        end

                        local show = false
                        local why = ""

                        if type(v) == "string" then
                            local hit, kw =
                                keywordMatch(v)

                            if hit then
                                show = true
                                why =
                                    " keyword="
                                    .. tostring(kw)
                            end

                        elseif typeof(v) == "Instance" then
                            local n =
                                lower(v.Name)

                            if string.find(n, "dialog", 1, true)
                                or string.find(n, "npc", 1, true)
                            then
                                show = true
                                why = " instance"
                            end

                        elseif type(v) == "table" then
                            local tested = 0

                            for tk,tv in pairs(v) do
                                tested = tested + 1

                                if tested > 50 then
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
                                    why = " table-keyword"
                                    break
                                end
                            end
                        end

                        if show then
                            shown = shown + 1

                            add(
                                "UPVALUE "
                                .. tostring(k)
                                .. " = "
                                .. tostring(v)
                                .. why
                            )
                        end
                    end
                end
            end
        end

        -- Even if parent has no hit, inspect protos because useful
        -- dialogue strings may exist only in nested closures.
        if apiGetProtos
            and depth < 3
        then
            local okProto, protos =
                pcall(
                    apiGetProtos,
                    fn
                )

            if okProto
                and type(protos) == "table"
            then
                for i,proto in ipairs(protos) do
                    if type(proto) == "function" then
                        inspectFunction(
                            proto,
                            tostring(origin)
                            .. ".proto#"
                            .. tostring(i),
                            depth + 1
                        )
                    end
                end
            end
        end
    end

    -- --------------------------------------------------------
    -- Scan registry.
    -- --------------------------------------------------------
    local function scanRegistryTable(registry, label)
        if type(registry) ~= "table" then
            add(label .. ": registry is not table")
            return
        end

        add("")
        add("============================================================")
        add(label)
        add("============================================================")

        local visitedTables = {}
        local tablesScanned = 0
        local valuesScanned = 0

        local function walk(tbl, depth, origin)
            if type(tbl) ~= "table"
                or visitedTables[tbl]
                or depth > 3
            then
                return
            end

            visitedTables[tbl] = true
            tablesScanned = tablesScanned + 1

            local count = 0

            for k,v in pairs(tbl) do
                count = count + 1
                valuesScanned = valuesScanned + 1

                if count > 5000 then
                    break
                end

                if type(v) == "function" then
                    inspectFunction(
                        v,
                        origin
                        .. "["
                        .. tostring(k)
                        .. "]",
                        0
                    )

                elseif type(v) == "table"
                    and depth < 3
                then
                    walk(
                        v,
                        depth + 1,
                        origin
                        .. "["
                        .. tostring(k)
                        .. "]"
                    )
                end
            end
        end

        walk(registry, 0, label)

        add(
            label
            .. " DONE tables="
            .. tostring(tablesScanned)
            .. " values="
            .. tostring(valuesScanned)
        )
    end

    if apiGetReg then
        local okReg, reg =
            pcall(apiGetReg)

        if okReg then
            scanRegistryTable(
                reg,
                "GETREG SCAN"
            )
        else
            add("getreg failed: " .. tostring(reg))
        end
    end

    if apiDebugRegistry then
        local okReg, reg =
            pcall(apiDebugRegistry)

        if okReg then
            scanRegistryTable(
                reg,
                "DEBUG.GETREGISTRY SCAN"
            )
        else
            add(
                "debug.getregistry failed: "
                .. tostring(reg)
            )
        end
    end

    -- --------------------------------------------------------
    -- Scan scripts through getscriptclosure if available.
    -- --------------------------------------------------------
    if apiGetScripts
        and apiGetScriptClosure
    then
        add("")
        add("============================================================")
        add("GETSCRIPTS + GETSCRIPTCLOSURE")
        add("============================================================")

        local okScripts, scripts =
            pcall(apiGetScripts)

        if okScripts
            and type(scripts) == "table"
        then
            local tested = 0

            for _,scriptObj in ipairs(scripts) do
                if typeof(scriptObj) == "Instance" then
                    local name =
                        lower(scriptObj.Name)

                    local full =
                        lower(
                            scriptObj:GetFullName()
                        )

                    local interesting =
                        string.find(full, "dialog", 1, true)
                        or string.find(full, "npc", 1, true)
                        or string.find(name, "dialog", 1, true)
                        or string.find(name, "npc", 1, true)

                    if interesting then
                        local okClosure, closure =
                            pcall(
                                apiGetScriptClosure,
                                scriptObj
                            )

                        if okClosure
                            and type(closure) == "function"
                        then
                            tested = tested + 1

                            inspectFunction(
                                closure,
                                "SCRIPT "
                                .. pathOf(scriptObj),
                                0
                            )
                        end
                    end
                end
            end

            add(
                "SCRIPT_CLOSURES_TESTED="
                .. tostring(tested)
            )
        end
    end

    -- --------------------------------------------------------
    -- Fallback: if getgc suddenly exists through another scope,
    -- scan it too.
    -- --------------------------------------------------------
    if apiGetGc then
        add("")
        add("============================================================")
        add("GETGC FALLBACK")
        add("============================================================")

        local okGc, objects =
            pcall(
                apiGetGc,
                true
            )

        if okGc
            and type(objects) == "table"
        then
            for i,obj in ipairs(objects) do
                if type(obj) == "function" then
                    inspectFunction(
                        obj,
                        "getgc#"
                        .. tostring(i),
                        0
                    )
                end
            end
        end
    end

    add("")
    add("============================================================")
    add("SUMMARY")
    add("============================================================")
    add(
        "FUNCTIONS_SCANNED="
        .. tostring(scannedFunctions)
    )
    add(
        "FUNCTION_HITS="
        .. tostring(hitFunctions)
    )

    if not apiGetReg
        and not apiDebugRegistry
        and not (
            apiGetScripts
            and apiGetScriptClosure
        )
        and not apiGetGc
    then
        add("")
        add(
            "NO FUNCTION ENUMERATOR AVAILABLE."
        )
        add(
            "Executor can inspect a known function, but currently exposes no API to enumerate/get the dialogue callback closure."
        )
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
                    "ui_opener_registry.txt",
                    final
                )
            end)

        print(
            "[REG FINDER] writefile=",
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
            "[REG FINDER] clipboard=",
            okCopy,
            errCopy
        )
    end

    print(
        "[REG FINDER] DONE -> workspace/ui_opener_registry.txt"
    )
end)

if not okMain then
    print(
        "[REG FINDER FATAL] "
        .. tostring(errMain)
    )
end
