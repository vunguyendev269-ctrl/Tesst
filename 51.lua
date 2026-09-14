-- MYSTERIOUS FORCE - MODULE API FINDER
-- One-shot, standard require()-based inspection.
-- Does NOT invoke exported gameplay functions.
-- Output: workspace/mysterious_force_module_api.txt

local okMain, errMain = pcall(function()
    local RS = game:GetService("ReplicatedStorage")

    local lines = {}
    local seenTables = {}
    local seenFunctions = {}

    local function add(s)
        s = tostring(s)
        lines[#lines + 1] = s
        print("[MODULE API] " .. s)
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
        "racev4progress",
        "dialogue",
        "open",
        "show",
        "start",
        "interact",
        "interaction",
        "option",
        "response",
        "npc",
        "window",
        "render",
        "use it",
        "remnant of the past",
        "waitingfordialogue",
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

    local apiGetConstants = globalFn("getconstants")
    local apiGetUpvalues = globalFn("getupvalues")
    local apiGetProtos = globalFn("getprotos")

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

    local function valueSummary(v)
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
            return "<function:" .. tostring(v) .. ">"
        elseif t == "table" then
            return "<table:" .. tostring(v) .. ">"
        end

        return "<" .. t .. ":" .. tostring(v) .. ">"
    end

    local function inspectFunction(fn, label, depth)
        depth = depth or 0

        if type(fn) ~= "function" then
            return
        end

        if seenFunctions[fn] then
            add(label .. " = <function already inspected>")
            return
        end

        seenFunctions[fn] = true

        add(label .. " = " .. tostring(fn))

        if apiGetConstants then
            local ok, constants =
                pcall(apiGetConstants, fn)

            if ok and type(constants) == "table" then
                local hits = {}

                for i,v in ipairs(constants) do
                    if type(v) == "string" then
                        local hit, kw = keywordMatch(v)

                        if hit then
                            hits[#hits+1] =
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

                if #hits > 0 then
                    add(
                        label
                        .. ".CONSTANT_HITS = "
                        .. table.concat(hits, " | ")
                    )
                end
            end
        end

        if apiGetUpvalues then
            local ok, ups =
                pcall(apiGetUpvalues, fn)

            if ok and type(ups) == "table" then
                local shown = 0

                for k,v in pairs(ups) do
                    if shown >= 16 then
                        break
                    end

                    local interesting = false
                    local why = ""

                    if type(v) == "string" then
                        local hit, kw = keywordMatch(v)

                        if hit then
                            interesting = true
                            why = " keyword=" .. tostring(kw)
                        end

                    elseif typeof(v) == "Instance" then
                        local n = lower(v.Name)

                        if string.find(n, "dialog", 1, true)
                            or string.find(n, "npc", 1, true)
                        then
                            interesting = true
                            why = " instance"
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
                                interesting = true
                                why = " table-keyword"
                                break
                            end
                        end
                    end

                    if interesting then
                        shown = shown + 1

                        add(
                            label
                            .. ".UPVALUE["
                            .. tostring(k)
                            .. "] = "
                            .. valueSummary(v)
                            .. why
                        )
                    end
                end
            end
        end

        if apiGetProtos and depth < 2 then
            local ok, protos =
                pcall(apiGetProtos, fn)

            if ok and type(protos) == "table" then
                for i,proto in ipairs(protos) do
                    if type(proto) == "function" then
                        -- Only recurse into protos with a relevant string constant.
                        local relevant = false

                        if apiGetConstants then
                            local okC, constants =
                                pcall(apiGetConstants, proto)

                            if okC and type(constants) == "table" then
                                for _,v in ipairs(constants) do
                                    if type(v) == "string"
                                        and keywordMatch(v)
                                    then
                                        relevant = true
                                        break
                                    end
                                end
                            end
                        end

                        if relevant then
                            inspectFunction(
                                proto,
                                label
                                .. ".PROTO["
                                .. tostring(i)
                                .. "]",
                                depth + 1
                            )
                        end
                    end
                end
            end
        end
    end

    local function inspectTable(tbl, label, depth)
        depth = depth or 0

        if type(tbl) ~= "table" then
            return
        end

        if seenTables[tbl] then
            add(label .. " = <table already inspected>")
            return
        end

        seenTables[tbl] = true

        add(label .. " = " .. tostring(tbl))

        if depth > 4 then
            return
        end

        local entries = {}
        local count = 0

        for k,v in pairs(tbl) do
            count = count + 1

            if count > 300 then
                break
            end

            entries[#entries+1] = {
                key = k,
                value = v,
                keyText = tostring(k),
            }
        end

        table.sort(entries, function(a,b)
            return a.keyText < b.keyText
        end)

        for _,entry in ipairs(entries) do
            local k = entry.key
            local v = entry.value
            local childLabel =
                label
                .. "["
                .. string.format("%q", tostring(k))
                .. "]"

            local tv = type(v)

            if tv == "function" then
                inspectFunction(
                    v,
                    childLabel,
                    0
                )

            elseif tv == "table" then
                local keyHit =
                    keywordMatch(tostring(k))

                local recurse =
                    depth < 2
                    or keyHit

                if recurse then
                    inspectTable(
                        v,
                        childLabel,
                        depth + 1
                    )
                else
                    add(
                        childLabel
                        .. " = "
                        .. valueSummary(v)
                    )
                end

            else
                local keyHit =
                    keywordMatch(tostring(k))

                local valueHit = false

                if type(v) == "string" then
                    valueHit =
                        keywordMatch(v)
                end

                if keyHit or valueHit then
                    add(
                        childLabel
                        .. " = "
                        .. valueSummary(v)
                    )
                end
            end
        end
    end

    local function findPath(root, parts)
        local cur = root

        for _,name in ipairs(parts) do
            if not cur then
                return nil
            end

            cur =
                cur:FindFirstChild(name)
        end

        return cur
    end

    local TARGETS = {
        {
            "DialogueController",
        },
        {
            "DialogueController",
            "Dialogue",
        },
        {
            "DialogueController",
            "Dialogue",
            "Option",
        },
        {
            "DialogueController",
            "Dialogue",
            "Window",
        },
        {
            "DialogueController",
            "Legacy",
        },
        {
            "DialogueController",
            "OldDialogueController",
        },
        {
            "DialogueController",
            "ReactComponents",
            "Responses",
            "OptionButton",
        },
        {
            "NPCManager",
        },
        {
            "NPCManager",
            "NPC",
        },
        {
            "NPCManager",
            "NPC",
            "NPCInitialization",
        },
        {
            "NPCManager",
            "NPC",
            "NPCInitialization",
            "InteractionController",
        },
        {
            "NPCManager",
            "NPCInteractionConfig",
        },
        {
            "DialoguesList",
        },
        {
            "DialoguesList",
            "NPCs",
            "MysteriousEntity",
        },
        {
            "DialoguesList",
            "NPCs",
            "RaceV4Upgrader",
        },
    }

    add("============================================================")
    add("MYSTERIOUS FORCE - MODULE API FINDER")
    add("============================================================")
    add("getconstants=" .. tostring(apiGetConstants ~= nil))
    add("getupvalues=" .. tostring(apiGetUpvalues ~= nil))
    add("getprotos=" .. tostring(apiGetProtos ~= nil))
    add("")

    local successCount = 0
    local failCount = 0

    for index,parts in ipairs(TARGETS) do
        local module =
            findPath(
                RS,
                parts
            )

        add("")
        add("============================================================")
        add(
            "TARGET #"
            .. tostring(index)
            .. " "
            .. table.concat(parts, ".")
        )
        add("============================================================")

        if not module then
            failCount = failCount + 1
            add("STATUS=NOT_FOUND")

        elseif not module:IsA("ModuleScript") then
            failCount = failCount + 1
            add(
                "STATUS=NOT_MODULE | "
                .. module.ClassName
                .. " | "
                .. pathOf(module)
            )

        else
            add(
                "MODULE="
                .. pathOf(module)
            )

            -- Only read the module export.
            local okReq, exported =
                pcall(
                    require,
                    module
                )

            if not okReq then
                failCount = failCount + 1

                add(
                    "REQUIRE=FAILED | "
                    .. tostring(exported)
                )
            else
                successCount = successCount + 1

                add(
                    "REQUIRE=OK"
                )

                add(
                    "EXPORT_TYPE="
                    .. typeof(exported)
                )

                if type(exported) == "table" then
                    inspectTable(
                        exported,
                        "EXPORT",
                        0
                    )

                elseif type(exported) == "function" then
                    inspectFunction(
                        exported,
                        "EXPORT_FUNCTION",
                        0
                    )

                else
                    add(
                        "EXPORT="
                        .. valueSummary(exported)
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
        "REQUIRE_OK="
        .. tostring(successCount)
    )
    add(
        "REQUIRE_FAILED_OR_MISSING="
        .. tostring(failCount)
    )

    local final =
        table.concat(
            lines,
            "\n"
        )

    if type(writefile) == "function" then
        local okWrite, errWrite =
            pcall(function()
                writefile(
                    "mysterious_force_module_api.txt",
                    final
                )
            end)

        print(
            "[MODULE API] writefile=",
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
            "[MODULE API] clipboard=",
            okCopy,
            errCopy
        )
    end

    print(
        "[MODULE API] DONE -> workspace/mysterious_force_module_api.txt"
    )
end)

if not okMain then
    print(
        "[MODULE API FATAL] "
        .. tostring(errMain)
    )
end
