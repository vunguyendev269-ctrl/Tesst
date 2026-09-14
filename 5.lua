-- MYSTERIOUS FORCE UI OPENER - ENV / DECOMPILE FINDER
-- One-shot. No network hook. No background loop.
-- Output: workspace/ui_opener_env_scan.txt

local okMain, errMain = pcall(function()
    local Players = game:GetService("Players")
    local RS = game:GetService("ReplicatedStorage")
    local lp = Players.LocalPlayer

    if not lp then
        print("[ENV FINDER] LocalPlayer missing")
        return
    end

    local pg = lp:WaitForChild("PlayerGui", 10)
    local ps = lp:WaitForChild("PlayerScripts", 10)

    local lines = {}
    local seenFunctions = {}
    local functionHits = 0

    local function add(s)
        s = tostring(s)
        lines[#lines+1] = s
        print("[ENV FINDER] "..s)
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

    local function globalFn(name)
        local ok, fn = pcall(function()
            return _G[name]
        end)

        if ok and type(fn) == "function" then
            return fn
        end

        return nil
    end

    local apiGetsEnv = globalFn("getsenv")
    local apiGetREnv = globalFn("getrenv")
    local apiGetMEnv = globalFn("getmenv")
    local apiDecompile = globalFn("decompile")
    local apiGetScriptBytecode = globalFn("getscriptbytecode")
    local apiGetConstants = globalFn("getconstants")
    local apiGetUpvalues = globalFn("getupvalues")
    local apiGetProtos = globalFn("getprotos")
    local apiGetRunningScripts = globalFn("getrunningscripts")
    local apiGetScripts = globalFn("getscripts")
    local apiFireSignal = globalFn("firesignal")
    local apiGetConnections = globalFn("getconnections")
    local apiGetCallbackValue = globalFn("getcallbackvalue")

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
    end

    add("============================================================")
    add("MYSTERIOUS FORCE UI OPENER ENV/DECOMPILE FINDER")
    add("============================================================")
    add("CAPABILITIES:")
    add("getsenv="..tostring(apiGetsEnv ~= nil))
    add("getrenv="..tostring(apiGetREnv ~= nil))
    add("getmenv="..tostring(apiGetMEnv ~= nil))
    add("decompile="..tostring(apiDecompile ~= nil))
    add("getscriptbytecode="..tostring(apiGetScriptBytecode ~= nil))
    add("getconstants="..tostring(apiGetConstants ~= nil))
    add("getupvalues="..tostring(apiGetUpvalues ~= nil))
    add("getprotos="..tostring(apiGetProtos ~= nil))
    add("getrunningscripts="..tostring(apiGetRunningScripts ~= nil))
    add("getscripts="..tostring(apiGetScripts ~= nil))
    add("firesignal="..tostring(apiFireSignal ~= nil))
    add("getconnections="..tostring(apiGetConnections ~= nil))
    add("getcallbackvalue="..tostring(apiGetCallbackValue ~= nil))
    add("")

    local function inspectFunction(fn, origin, depth)
        depth = depth or 0

        if type(fn) ~= "function" then
            return
        end

        if seenFunctions[fn] then
            return
        end

        seenFunctions[fn] = true

        if not apiGetConstants then
            return
        end

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
                    matches[#matches+1] =
                        "#"
                        ..tostring(i)
                        .."="
                        ..string.format("%q", v)
                        .."["
                        ..tostring(kw)
                        .."]"
                end
            end
        end

        if #matches > 0 then
            functionHits = functionHits + 1

            add("")
            add("------------------------------------------------------------")
            add("FUNCTION HIT #"..tostring(functionHits))
            add("ORIGIN="..tostring(origin))
            add("FUNCTION="..tostring(fn))
            add("MATCHES="..table.concat(matches, " | "))

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
                                    ..tostring(kw)
                            end

                        elseif typeof(v) == "Instance" then
                            local n = lower(v.Name)

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
                                ..tostring(k)
                                .." = "
                                ..tostring(v)
                                ..why
                            )
                        end
                    end
                end
            end
        end

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
                            ..".proto#"
                            ..tostring(i),
                            depth + 1
                        )
                    end
                end
            end
        end
    end

    local function scanEnvTable(env, origin)
        if type(env) ~= "table" then
            return
        end

        local visited = {}
        local function walk(tbl, depth, prefix)
            if type(tbl) ~= "table"
                or visited[tbl]
                or depth > 2
            then
                return
            end

            visited[tbl] = true

            local count = 0

            for k,v in pairs(tbl) do
                count = count + 1

                if count > 2000 then
                    break
                end

                if type(v) == "function" then
                    inspectFunction(
                        v,
                        prefix
                        .."["
                        ..tostring(k)
                        .."]",
                        0
                    )

                elseif type(v) == "table"
                    and depth < 2
                then
                    walk(
                        v,
                        depth + 1,
                        prefix
                        .."["
                        ..tostring(k)
                        .."]"
                    )
                end
            end
        end

        walk(env, 0, origin)
    end

    local function scriptLooksRelevant(scriptObj)
        if typeof(scriptObj) ~= "Instance" then
            return false
        end

        local name = lower(scriptObj.Name)
        local full = lower(scriptObj:GetFullName())

        if string.find(name, "dialog", 1, true)
            or string.find(name, "npc", 1, true)
            or string.find(full, "dialog", 1, true)
            or string.find(full, "npc", 1, true)
        then
            return true
        end

        return false
    end

    local candidateScripts = {}
    local candidateSet = {}

    local function addScriptCandidate(s, reason)
        if typeof(s) ~= "Instance" then
            return
        end

        if not (
            s:IsA("LocalScript")
            or s:IsA("ModuleScript")
        ) then
            return
        end

        if candidateSet[s] then
            return
        end

        candidateSet[s] = true

        candidateScripts[#candidateScripts+1] = {
            script = s,
            reason = reason,
        }
    end

    -- PlayerScripts + PlayerGui + ReplicatedStorage by path/name.
    local roots = {
        {obj = ps, label = "PlayerScripts"},
        {obj = pg, label = "PlayerGui"},
        {obj = RS, label = "ReplicatedStorage"},
    }

    for _,entry in ipairs(roots) do
        if entry.obj then
            local desc =
                entry.obj:GetDescendants()

            for _,obj in ipairs(desc) do
                if (
                    obj:IsA("LocalScript")
                    or obj:IsA("ModuleScript")
                )
                    and scriptLooksRelevant(obj)
                then
                    addScriptCandidate(
                        obj,
                        entry.label
                    )
                end
            end
        end
    end

    -- Executor script lists, if available.
    if apiGetRunningScripts then
        local ok, scripts =
            pcall(apiGetRunningScripts)

        if ok and type(scripts) == "table" then
            for _,s in ipairs(scripts) do
                if scriptLooksRelevant(s) then
                    addScriptCandidate(
                        s,
                        "getrunningscripts"
                    )
                end
            end
        end
    end

    if apiGetScripts then
        local ok, scripts =
            pcall(apiGetScripts)

        if ok and type(scripts) == "table" then
            for _,s in ipairs(scripts) do
                if scriptLooksRelevant(s) then
                    addScriptCandidate(
                        s,
                        "getscripts"
                    )
                end
            end
        end
    end

    add("")
    add("============================================================")
    add("SCRIPT CANDIDATES")
    add("============================================================")
    add("COUNT="..tostring(#candidateScripts))

    for i,entry in ipairs(candidateScripts) do
        add(
            "#"
            ..tostring(i)
            .." "
            ..pathOf(entry.script)
            .." | reason="
            ..tostring(entry.reason)
        )
    end

    -- --------------------------------------------------------
    -- getsenv(LocalScript)
    -- --------------------------------------------------------
    if apiGetsEnv then
        add("")
        add("============================================================")
        add("GETSENV SCAN")
        add("============================================================")

        for _,entry in ipairs(candidateScripts) do
            local s = entry.script

            if s:IsA("LocalScript") then
                local okEnv, env =
                    pcall(
                        apiGetsEnv,
                        s
                    )

                if okEnv
                    and type(env) == "table"
                then
                    add(
                        "ENV OK "
                        ..pathOf(s)
                    )

                    scanEnvTable(
                        env,
                        "ENV "
                        ..pathOf(s)
                    )
                end
            end
        end
    end

    -- --------------------------------------------------------
    -- decompile candidates
    -- --------------------------------------------------------
    if apiDecompile then
        add("")
        add("============================================================")
        add("DECOMPILE HITS")
        add("============================================================")

        for _,entry in ipairs(candidateScripts) do
            local s = entry.script

            local okDec, source =
                pcall(
                    apiDecompile,
                    s
                )

            if okDec
                and type(source) == "string"
            then
                local sourceLower =
                    lower(source)

                local hits = {}

                for _,kw in ipairs(KEYWORDS) do
                    if string.find(
                        sourceLower,
                        kw,
                        1,
                        true
                    ) then
                        hits[#hits+1] = kw
                    end
                end

                if #hits > 0 then
                    add("")
                    add(
                        "DECOMPILE HIT "
                        ..pathOf(s)
                    )

                    add(
                        "KEYWORDS="
                        ..table.concat(
                            hits,
                            ", "
                        )
                    )

                    -- Print short matching-context snippets only.
                    for _,kw in ipairs(hits) do
                        local p =
                            string.find(
                                sourceLower,
                                kw,
                                1,
                                true
                            )

                        if p then
                            local a =
                                math.max(
                                    1,
                                    p - 180
                                )

                            local b =
                                math.min(
                                    #source,
                                    p
                                    + #kw
                                    + 260
                                )

                            add(
                                "SNIPPET["
                                ..kw
                                .."]="
                                ..string.sub(
                                    source,
                                    a,
                                    b
                                )
                            )
                        end
                    end
                end
            end
        end
    end

    -- --------------------------------------------------------
    -- getscriptbytecode keyword scan (only if result is string).
    -- --------------------------------------------------------
    if apiGetScriptBytecode then
        add("")
        add("============================================================")
        add("BYTECODE STRING HITS")
        add("============================================================")

        for _,entry in ipairs(candidateScripts) do
            local s = entry.script

            local okBc, bc =
                pcall(
                    apiGetScriptBytecode,
                    s
                )

            if okBc
                and type(bc) == "string"
            then
                local lbc = lower(bc)
                local hits = {}

                for _,kw in ipairs(KEYWORDS) do
                    if string.find(
                        lbc,
                        kw,
                        1,
                        true
                    ) then
                        hits[#hits+1] = kw
                    end
                end

                if #hits > 0 then
                    add(
                        "BYTECODE HIT "
                        ..pathOf(s)
                        .." => "
                        ..table.concat(
                            hits,
                            ", "
                        )
                    )
                end
            end
        end
    end

    -- --------------------------------------------------------
    -- getrenv / getmenv scan.
    -- --------------------------------------------------------
    if apiGetREnv then
        local okEnv, env =
            pcall(apiGetREnv)

        if okEnv
            and type(env) == "table"
        then
            add("")
            add("============================================================")
            add("GETRENV SCAN")
            add("============================================================")

            scanEnvTable(
                env,
                "GETRENV"
            )
        end
    end

    if apiGetMEnv then
        local okEnv, env =
            pcall(apiGetMEnv)

        if okEnv
            and type(env) == "table"
        then
            add("")
            add("============================================================")
            add("GETMENV SCAN")
            add("============================================================")

            scanEnvTable(
                env,
                "GETMENV"
            )
        end
    end

    add("")
    add("============================================================")
    add("SUMMARY")
    add("============================================================")
    add("SCRIPT_CANDIDATES="..tostring(#candidateScripts))
    add("FUNCTION_HITS="..tostring(functionHits))

    if not apiGetsEnv
        and not apiDecompile
        and not apiGetScriptBytecode
        and not apiGetREnv
        and not apiGetMEnv
    then
        add(
            "NO ALTERNATE SCRIPT/ENV ACCESS API AVAILABLE."
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
                    "ui_opener_env_scan.txt",
                    final
                )
            end)

        print(
            "[ENV FINDER] writefile=",
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
            "[ENV FINDER] clipboard=",
            okCopy,
            errCopy
        )
    end

    print(
        "[ENV FINDER] DONE -> workspace/ui_opener_env_scan.txt"
    )
end)

if not okMain then
    print(
        "[ENV FINDER FATAL] "
        .. tostring(errMain)
    )
end
