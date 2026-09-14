-- MYSTERIOUS FORCE REMOTE UI OPENER FINDER V2 COMPAT

local function bootPrint(step, msg)
    pcall(function()
        print("[MF OPENER V2][BOOT "..tostring(step).."] "..tostring(msg))
    end)
end

bootPrint(1, "script started")

local okMain, mainErr = pcall(function()
    local Players = game:GetService("Players")
    local RS = game:GetService("ReplicatedStorage")
    local CoreGui = game:GetService("CoreGui")
    local UIS = game:GetService("UserInputService")

    bootPrint(2, "services ok")

    local LP = Players.LocalPlayer
    if not LP then
        error("LocalPlayer missing")
    end

    local PlayerGui = LP:WaitForChild("PlayerGui", 15)
    if not PlayerGui then
        error("PlayerGui missing")
    end

    local DialogueGui = PlayerGui:FindFirstChild("DialogueGui")
    if not DialogueGui then
        DialogueGui = PlayerGui:WaitForChild("DialogueGui", 15)
    end

    if not DialogueGui then
        error("DialogueGui missing")
    end

    local Remotes = RS:WaitForChild("Remotes", 15)
    if not Remotes then
        error("Remotes missing")
    end

    local CommF = Remotes:WaitForChild("CommF_", 15)
    if not CommF then
        error("CommF_ missing")
    end

    bootPrint(3, "PlayerGui / DialogueGui / CommF_ ok")

    local OUTPUT_FILE = "remote_ui_opener.txt"
    local ARM_SECONDS = 8

    local function packValues(...)
        local n = select("#", ...)
        local t = {n = n}
        for i = 1, n do
            t[i] = select(i, ...)
        end
        return t
    end

    local unpackFn = nil

    if type(table) == "table"
        and type(table.unpack) == "function"
    then
        unpackFn = table.unpack
    elseif type(unpack) == "function" then
        unpackFn = unpack
    end

    if not unpackFn then
        error("no unpack function available")
    end

    local function q(v)
        return string.format("%q", tostring(v))
    end

    local function lower(v)
        return string.lower(tostring(v or ""))
    end

    local function safeFullName(inst)
        local ok, value = pcall(function()
            return inst:GetFullName()
        end)

        if ok then
            return value
        end

        return tostring(inst)
    end

    local function instancePath(inst)
        if typeof(inst) ~= "Instance" then
            return tostring(inst)
        end

        local chain = {}
        local cur = inst

        while cur and cur ~= game do
            table.insert(chain, 1, cur.Name)
            cur = cur.Parent
        end

        if cur ~= game or #chain == 0 then
            return "nil"
        end

        local expr =
            'game:GetService('
            .. q(chain[1])
            .. ')'

        for i = 2, #chain do
            expr =
                expr
                .. ":WaitForChild("
                .. q(chain[i])
                .. ")"
        end

        return expr
    end

    local function simpleValue(v)
        local t = typeof(v)

        if t == "nil" then
            return "nil"
        elseif t == "string" then
            return q(v)
        elseif t == "number"
            or t == "boolean"
        then
            return tostring(v)
        elseif t == "Instance" then
            return instancePath(v)
        elseif t == "Vector3"
            or t == "Vector2"
            or t == "CFrame"
            or t == "Color3"
            or t == "EnumItem"
        then
            return tostring(v)
        elseif t == "function" then
            return "<function>"
        elseif t == "table" then
            local out = {}
            local count = 0

            for k,val in pairs(v) do
                count = count + 1

                if count > 10 then
                    out[#out+1] = "..."
                    break
                end

                out[#out+1] =
                    tostring(k)
                    .. "="
                    .. tostring(val)
            end

            return "{"
                .. table.concat(out, ", ")
                .. "}"
        end

        return tostring(v)
    end

    local function packedText(values)
        if not values then
            return "<none>"
        end

        local out = {}

        for i = 1, values.n or 0 do
            out[#out+1] =
                simpleValue(values[i])
        end

        if #out == 0 then
            return "<no values>"
        end

        return table.concat(out, ", ")
    end

    local function readText(obj)
        local ok, text = pcall(function()
            return tostring(obj.Text or "")
        end)

        if ok then
            return text
        end

        return ""
    end

    local function getMysteriousRoot()
        for _,root in ipairs(DialogueGui:GetChildren()) do
            local titleFrame =
                root:FindFirstChild("dialogueTitleFrame")

            local title =
                titleFrame
                and titleFrame:FindFirstChild("name")

            if title
                and title:IsA("TextLabel")
                and lower(readText(title))
                    == "mysterious force"
            then
                return root
            end
        end
    end

    local function getOption1Button()
        local root = getMysteriousRoot()

        if not root then
            return nil
        end

        local options =
            root:FindFirstChild("optionsList")

        local scroller =
            options
            and options:FindFirstChild("scroller")

        if not scroller then
            return nil
        end

        for _,option in ipairs(scroller:GetChildren()) do
            if string.find(
                lower(option.Name),
                "option1",
                1,
                true
            ) then
                local button =
                    option:FindFirstChild("button")

                if button
                    and button:IsA("GuiButton")
                then
                    return button
                end
            end
        end
    end

    local report = {}
    local lastOutput = ""

    local LogLabel = nil
    local Scroll = nil
    local StatusLabel = nil

    local function refresh()
        if not LogLabel then
            return
        end

        local first =
            math.max(1, #report - 200)

        local view = {}

        for i = first, #report do
            view[#view+1] = report[i]
        end

        LogLabel.Text =
            table.concat(view, "\n")
    end

    local function add(tag, msg)
        local line =
            "["
            .. string.format("%.3f", os.clock())
            .. "]["
            .. tostring(tag)
            .. "] "
            .. tostring(msg)

        report[#report+1] = line

        if #report > 2500 then
            table.remove(report, 1)
        end

        print("[MF OPENER V2] " .. line)

        refresh()

        task.defer(function()
            if Scroll then
                Scroll.CanvasPosition =
                    Vector2.new(
                        0,
                        math.max(
                            0,
                            Scroll.AbsoluteCanvasSize.Y
                                - Scroll.AbsoluteWindowSize.Y
                        )
                    )
            end
        end)
    end

    local function saveReport()
        local text =
            table.concat(report, "\n")

        lastOutput = text

        if type(writefile) == "function" then
            local ok, err = pcall(function()
                writefile(
                    OUTPUT_FILE,
                    text
                )
            end)

            add(
                "SAVE",
                ok
                    and ("workspace/"..OUTPUT_FILE)
                    or tostring(err)
            )
        end
    end

    bootPrint(4, "helpers ok")

    -- --------------------------------------------------------
    -- executor capabilities, loaded carefully
    -- --------------------------------------------------------
    local CAP = {}

    CAP.hookmetamethod =
        type(hookmetamethod) == "function"

    CAP.getnamecallmethod =
        type(getnamecallmethod) == "function"

    CAP.newcclosure =
        type(newcclosure) == "function"

    CAP.getcallingscript =
        type(getcallingscript) == "function"

    CAP.getconnections =
        type(getconnections) == "function"

    CAP.getgc =
        type(getgc) == "function"

    local globalGetConstants = nil
    local globalGetUpvalues = nil

    pcall(function()
        if type(getconstants) == "function" then
            globalGetConstants = getconstants
        end
    end)

    pcall(function()
        if type(getupvalues) == "function" then
            globalGetUpvalues = getupvalues
        end
    end)

    local debugGetConstants = nil
    local debugGetUpvalues = nil
    local debugGetInfo = nil

    if type(debug) == "table" then
        if type(debug.getconstants) == "function" then
            debugGetConstants = debug.getconstants
        end

        if type(debug.getupvalues) == "function" then
            debugGetUpvalues = debug.getupvalues
        end

        if type(debug.getinfo) == "function" then
            debugGetInfo = debug.getinfo
        end
    end

    local getConstants =
        debugGetConstants
        or globalGetConstants

    local getUpvalues =
        debugGetUpvalues
        or globalGetUpvalues

    CAP.getconstants =
        type(getConstants) == "function"

    CAP.getupvalues =
        type(getUpvalues) == "function"

    CAP.getinfo =
        type(debugGetInfo) == "function"

    bootPrint(
        5,
        "capabilities loaded"
    )

    -- --------------------------------------------------------
    -- function analysis
    -- --------------------------------------------------------
    local KEYWORDS = {
        "mysterious force",
        "dialoguegui",
        "dialoguetitleframe",
        "optionslist",
        "use it",
        "remnant of the past",
        "racev4progress",
    }

    local function matchKeyword(v)
        local s = lower(v)

        for _,keyword in ipairs(KEYWORDS) do
            if string.find(
                s,
                keyword,
                1,
                true
            ) then
                return true, keyword
            end
        end

        return false
    end

    local function functionScript(fn)
        if type(getfenv) ~= "function" then
            return nil
        end

        local ok, env =
            pcall(getfenv, fn)

        if ok
            and type(env) == "table"
        then
            local scriptObj =
                env.script

            if typeof(scriptObj)
                == "Instance"
            then
                return scriptObj
            end
        end
    end

    local function describeFunction(fn)
        local parts = {}

        local s =
            functionScript(fn)

        if s then
            parts[#parts+1] =
                "SCRIPT="
                .. safeFullName(s)
        end

        if CAP.getinfo then
            local ok, info =
                pcall(
                    debugGetInfo,
                    fn
                )

            if ok
                and type(info)
                    == "table"
            then
                if info.name then
                    parts[#parts+1] =
                        "NAME="
                        .. tostring(
                            info.name
                        )
                end

                if info.source then
                    parts[#parts+1] =
                        "SOURCE="
                        .. tostring(
                            info.source
                        )
                end

                if info.linedefined then
                    parts[#parts+1] =
                        "LINE="
                        .. tostring(
                            info.linedefined
                        )
                end
            end
        end

        if #parts == 0 then
            return tostring(fn)
        end

        return table.concat(
            parts,
            " | "
        )
    end

    local function inspectFunction(fn, prefix)
        if type(fn) ~= "function" then
            return
        end

        add(
            prefix,
            describeFunction(fn)
        )

        if CAP.getconstants then
            local ok, constants =
                pcall(
                    getConstants,
                    fn
                )

            if ok
                and type(constants)
                    == "table"
            then
                for i,v in ipairs(constants) do
                    local matched, keyword =
                        matchKeyword(v)

                    if matched then
                        add(
                            prefix.." CONST",
                            "#"
                            .. tostring(i)
                            .. "="
                            .. simpleValue(v)
                            .. " ["
                            .. tostring(keyword)
                            .. "]"
                        )
                    end
                end
            end
        end

        if CAP.getupvalues then
            local ok, ups =
                pcall(
                    getUpvalues,
                    fn
                )

            if ok
                and type(ups)
                    == "table"
            then
                local shown = 0

                for k,v in pairs(ups) do
                    if shown >= 12 then
                        break
                    end

                    local matched =
                        false

                    if type(v)
                        == "string"
                    then
                        matched =
                            matchKeyword(v)

                    elseif type(v)
                        == "table"
                    then
                        local tested = 0

                        for tk,tv in pairs(v) do
                            tested =
                                tested + 1

                            if tested > 25 then
                                break
                            end

                            if matchKeyword(tk)
                                or matchKeyword(tv)
                            then
                                matched = true
                                break
                            end
                        end
                    end

                    if matched then
                        shown =
                            shown + 1

                        add(
                            prefix.." UP",
                            tostring(k)
                            .. "="
                            .. simpleValue(v)
                        )
                    end
                end
            end
        end
    end

    -- --------------------------------------------------------
    -- option1 callbacks
    -- --------------------------------------------------------
    local function scanOption1Callbacks()
        local button =
            getOption1Button()

        if not button then
            add(
                "OPTION1",
                "not found"
            )
            return
        end

        add(
            "OPTION1 PATH",
            instancePath(button)
        )

        if not CAP.getconnections then
            add(
                "OPTION1",
                "getconnections unavailable"
            )
            return
        end

        local signalNames = {
            "Activated",
            "MouseButton1Click",
            "MouseButton1Down",
        }

        for _,signalName in ipairs(signalNames) do
            local signal = nil

            pcall(function()
                signal =
                    button[signalName]
            end)

            if signal then
                local ok, conns =
                    pcall(
                        getconnections,
                        signal
                    )

                if ok
                    and type(conns)
                        == "table"
                then
                    add(
                        "CONNECTIONS",
                        signalName
                        .. "="
                        .. tostring(
                            #conns
                        )
                    )

                    for i,conn in ipairs(conns) do
                        local fn = nil

                        pcall(function()
                            fn =
                                conn.Function
                        end)

                        if type(fn)
                            ~= "function"
                        then
                            pcall(function()
                                fn =
                                    conn.function
                            end)
                        end

                        if type(fn)
                            == "function"
                        then
                            inspectFunction(
                                fn,
                                "CALLBACK "
                                .. signalName
                                .. "#"
                                .. tostring(i)
                            )
                        else
                            add(
                                "CALLBACK",
                                signalName
                                .. "#"
                                .. tostring(i)
                                .. " no function exposed"
                            )
                        end
                    end
                end
            end
        end
    end

    -- --------------------------------------------------------
    -- safe getgc function-only scan
    -- --------------------------------------------------------
    local function scanGc()
        if not CAP.getgc then
            add(
                "GC",
                "getgc unavailable"
            )
            return
        end

        if not CAP.getconstants then
            add(
                "GC",
                "getconstants unavailable; skipping"
            )
            return
        end

        add(
            "GC",
            "function scan start"
        )

        local ok, objects =
            pcall(getgc, true)

        if not ok
            or type(objects)
                ~= "table"
        then
            add(
                "GC",
                "getgc failed"
            )
            return
        end

        local hits = 0

        for _,obj in ipairs(objects) do
            if type(obj)
                == "function"
            then
                local okConst, constants =
                    pcall(
                        getConstants,
                        obj
                    )

                if okConst
                    and type(constants)
                        == "table"
                then
                    local matched =
                        false

                    for _,v in ipairs(constants) do
                        if type(v) == "string"
                            and matchKeyword(v)
                        then
                            matched = true
                            break
                        end
                    end

                    if matched then
                        hits =
                            hits + 1

                        inspectFunction(
                            obj,
                            "GC HIT #"
                            .. tostring(hits)
                        )

                        if hits >= 50 then
                            break
                        end
                    end
                end
            end
        end

        add(
            "GC",
            "done | hits="
            .. tostring(hits)
        )
    end

    -- --------------------------------------------------------
    -- temporary Check remote hook
    -- --------------------------------------------------------
    local hookInstalled = false
    local oldNamecall = nil
    local armed = false
    local armEndsAt = 0
    local rawRecords = {}

    local function restoreHook(reason)
        armed = false
        armEndsAt = 0

        if not hookInstalled then
            return
        end

        if CAP.hookmetamethod
            and type(oldNamecall)
                == "function"
        then
            pcall(function()
                hookmetamethod(
                    game,
                    "__namecall",
                    oldNamecall
                )
            end)
        end

        hookInstalled = false

        add(
            "TRACE",
            "HOOK OFF | "
            .. tostring(reason or "")
        )
    end

    local function installHook()
        if hookInstalled then
            return true
        end

        if not CAP.hookmetamethod
            or not CAP.getnamecallmethod
        then
            add(
                "ERROR",
                "hook APIs unavailable"
            )
            return false
        end

        local wrap =
            CAP.newcclosure
            and newcclosure
            or function(f)
                return f
            end

        local ok, err =
            pcall(function()
                oldNamecall =
                    hookmetamethod(
                        game,
                        "__namecall",
                        wrap(function(self, ...)
                            if not armed
                                or os.clock()
                                    > armEndsAt
                            then
                                return oldNamecall(
                                    self,
                                    ...
                                )
                            end

                            if self ~= CommF then
                                return oldNamecall(
                                    self,
                                    ...
                                )
                            end

                            local method =
                                getnamecallmethod()

                            if method
                                ~= "InvokeServer"
                            then
                                return oldNamecall(
                                    self,
                                    ...
                                )
                            end

                            local args =
                                packValues(...)

                            if args[1]
                                ~= "RaceV4Progress"
                            then
                                return oldNamecall(
                                    self,
                                    ...
                                )
                            end

                            local caller = nil

                            if CAP.getcallingscript then
                                pcall(function()
                                    caller =
                                        getcallingscript()
                                end)
                            end

                            local started =
                                os.clock()

                            local results =
                                packValues(
                                    oldNamecall(
                                        self,
                                        ...
                                    )
                                )

                            rawRecords[
                                #rawRecords+1
                            ] = {
                                time =
                                    started,
                                action =
                                    args[2],
                                returns =
                                    results,
                                duration =
                                    os.clock()
                                    - started,
                                caller =
                                    caller,
                            }

                            return unpackFn(
                                results,
                                1,
                                results.n
                            )
                        end)
                    )
            end)

        if not ok then
            add(
                "ERROR",
                "hook install: "
                .. tostring(err)
            )
            return false
        end

        hookInstalled = true

        add(
            "TRACE",
            "RaceV4Progress hook ON"
        )

        return true
    end

    local function arm()
        rawRecords = {}

        if hookInstalled then
            restoreHook("rearm")
            task.wait(0.05)
        end

        if not installHook() then
            return
        end

        armed = true
        armEndsAt =
            os.clock()
            + ARM_SECONDS

        add(
            "ARM",
            "CLICK NPC NOW | "
            .. tostring(ARM_SECONDS)
            .. "s"
        )
    end

    task.spawn(function()
        local processed = 0

        while true do
            task.wait(0.03)

            while processed
                < #rawRecords
            do
                processed =
                    processed + 1

                local r =
                    rawRecords[
                        processed
                    ]

                add(
                    "REMOTE",
                    "RaceV4Progress("
                    .. q(r.action)
                    .. ") RETURN="
                    .. packedText(
                        r.returns
                    )
                    .. " dt="
                    .. string.format(
                        "%.4fs",
                        r.duration
                    )
                    .. " CALLER="
                    .. (
                        r.caller
                        and safeFullName(
                            r.caller
                        )
                        or "unknown"
                    )
                )
            end

            if armed
                and os.clock()
                    > armEndsAt
            then
                restoreHook(
                    "timeout"
                )
                saveReport()
                processed = 0
            end
        end
    end)

    -- --------------------------------------------------------
    -- UI open watcher
    -- --------------------------------------------------------
    local lastRoot = nil
    local scanning = false

    task.spawn(function()
        while true do
            task.wait(0.06)

            local root =
                getMysteriousRoot()

            if root
                and root ~= lastRoot
            then
                lastRoot = root

                add(
                    "UI OPEN",
                    instancePath(root)
                )

                if not scanning then
                    scanning = true

                    task.spawn(function()
                        task.wait(0.15)

                        local okCallbacks, callbackErr =
                            pcall(
                                scanOption1Callbacks
                            )

                        if not okCallbacks then
                            add(
                                "CALLBACK ERROR",
                                tostring(callbackErr)
                            )
                        end

                        saveReport()

                        scanning = false
                    end)
                end
            elseif not root then
                lastRoot = nil
            end
        end
    end)

    bootPrint(6, "runtime logic ok")

    -- --------------------------------------------------------
    -- GUI
    -- --------------------------------------------------------
    local parent = CoreGui

    if type(gethui) == "function" then
        pcall(function()
            local h = gethui()
            if h then
                parent = h
            end
        end)
    end

    local old =
        parent:FindFirstChild(
            "MFRemoteUiOpenerFinderV2"
        )

    if old then
        old:Destroy()
    end

    local Gui =
        Instance.new("ScreenGui")

    Gui.Name =
        "MFRemoteUiOpenerFinderV2"

    Gui.ResetOnSpawn = false
    Gui.Parent = parent

    local Frame =
        Instance.new("Frame")

    Frame.Size =
        UDim2.fromOffset(
            840,
            500
        )

    Frame.Position =
        UDim2.new(
            0.5,
            -420,
            0.5,
            -250
        )

    Frame.BackgroundColor3 =
        Color3.fromRGB(18,21,29)

    Frame.BorderSizePixel = 0
    Frame.Active = true
    Frame.Parent = Gui

    local corner =
        Instance.new("UICorner")

    corner.CornerRadius =
        UDim.new(0,10)

    corner.Parent = Frame

    local Header =
        Instance.new("TextLabel")

    Header.BackgroundTransparency = 1
    Header.Position =
        UDim2.fromOffset(12,7)

    Header.Size =
        UDim2.new(1,-260,0,30)

    Header.Font =
        Enum.Font.GothamBold

    Header.TextSize = 14

    Header.TextColor3 =
        Color3.new(1,1,1)

    Header.TextXAlignment =
        Enum.TextXAlignment.Left

    Header.Text =
        "MYSTERIOUS FORCE - REMOTE UI OPENER FINDER V2"

    Header.Active = true
    Header.Parent = Frame

    StatusLabel =
        Instance.new("TextLabel")

    StatusLabel.BackgroundTransparency = 1

    StatusLabel.AnchorPoint =
        Vector2.new(1,0)

    StatusLabel.Position =
        UDim2.new(1,-12,0,7)

    StatusLabel.Size =
        UDim2.fromOffset(245,30)

    StatusLabel.Font =
        Enum.Font.Code

    StatusLabel.TextSize = 11

    StatusLabel.TextXAlignment =
        Enum.TextXAlignment.Right

    StatusLabel.TextColor3 =
        Color3.fromRGB(170,220,255)

    StatusLabel.Parent = Frame

    Scroll =
        Instance.new(
            "ScrollingFrame"
        )

    Scroll.Position =
        UDim2.fromOffset(12,44)

    Scroll.Size =
        UDim2.new(1,-24,1,-126)

    Scroll.BackgroundColor3 =
        Color3.fromRGB(8,11,17)

    Scroll.BorderSizePixel = 0
    Scroll.ScrollBarThickness = 12
    Scroll.AutomaticCanvasSize =
        Enum.AutomaticSize.Y
    Scroll.CanvasSize =
        UDim2.new(0,0,0,0)
    Scroll.Active = true
    Scroll.Parent = Frame

    LogLabel =
        Instance.new("TextLabel")

    LogLabel.BackgroundTransparency = 1
    LogLabel.Position =
        UDim2.fromOffset(8,6)

    LogLabel.Size =
        UDim2.new(1,-24,0,0)

    LogLabel.AutomaticSize =
        Enum.AutomaticSize.Y

    LogLabel.Font =
        Enum.Font.Code

    LogLabel.TextSize = 11

    LogLabel.TextColor3 =
        Color3.fromRGB(215,225,240)

    LogLabel.TextWrapped = true
    LogLabel.TextXAlignment =
        Enum.TextXAlignment.Left
    LogLabel.TextYAlignment =
        Enum.TextYAlignment.Top
    LogLabel.Text = ""
    LogLabel.Parent = Scroll

    local function button(text,x,callback)
        local b =
            Instance.new("TextButton")

        b.AnchorPoint =
            Vector2.new(0,1)

        b.Position =
            UDim2.new(x,8,1,-12)

        b.Size =
            UDim2.new(0.24,-10,0,54)

        b.BackgroundColor3 =
            Color3.fromRGB(40,47,64)

        b.BorderSizePixel = 0
        b.Font =
            Enum.Font.GothamBold
        b.TextSize = 11
        b.TextWrapped = true
        b.TextColor3 =
            Color3.new(1,1,1)
        b.Text = text
        b.Parent = Frame

        local c =
            Instance.new("UICorner")

        c.CornerRadius =
            UDim.new(0,7)

        c.Parent = b

        b.MouseButton1Click:Connect(
            callback
        )

        return b
    end

    local armButton =
        button(
            "ARM CLICK TRACE\n8 sec",
            0,
            arm
        )

    armButton.BackgroundColor3 =
        Color3.fromRGB(45,95,70)

    button(
        "SCAN OPTION1\nCALLBACK",
        0.25,
        function()
            task.spawn(function()
                local ok, err =
                    pcall(
                        scanOption1Callbacks
                    )

                if not ok then
                    add(
                        "ERROR",
                        tostring(err)
                    )
                end

                saveReport()
            end)
        end
    )

    button(
        "SCAN GC\nSAFE",
        0.5,
        function()
            task.spawn(function()
                local ok, err =
                    pcall(scanGc)

                if not ok then
                    add(
                        "GC ERROR",
                        tostring(err)
                    )
                end

                saveReport()
            end)
        end
    )

    button(
        "COPY REPORT",
        0.75,
        function()
            local text =
                lastOutput ~= ""
                and lastOutput
                or table.concat(
                    report,
                    "\n"
                )

            if type(setclipboard)
                == "function"
            then
                local ok, err =
                    pcall(function()
                        setclipboard(text)
                    end)

                add(
                    "COPY",
                    ok
                    and "copied"
                    or tostring(err)
                )
            else
                add(
                    "COPY",
                    "setclipboard unavailable"
                )
            end
        end
    )

    local dragging = false
    local dragStart = nil
    local startPos = nil

    Header.InputBegan:Connect(function(input)
        if input.UserInputType
            == Enum.UserInputType.MouseButton1
            or input.UserInputType
            == Enum.UserInputType.Touch
        then
            dragging = true
            dragStart = input.Position
            startPos = Frame.Position
        end
    end)

    UIS.InputChanged:Connect(function(input)
        if dragging
            and (
                input.UserInputType
                    == Enum.UserInputType.MouseMovement
                or input.UserInputType
                    == Enum.UserInputType.Touch
            )
        then
            local d =
                input.Position
                - dragStart

            Frame.Position =
                UDim2.new(
                    startPos.X.Scale,
                    startPos.X.Offset+d.X,
                    startPos.Y.Scale,
                    startPos.Y.Offset+d.Y
                )
        end
    end)

    UIS.InputEnded:Connect(function(input)
        if input.UserInputType
            == Enum.UserInputType.MouseButton1
            or input.UserInputType
            == Enum.UserInputType.Touch
        then
            dragging = false
        end
    end)

    task.spawn(function()
        while Gui.Parent do
            task.wait(0.1)

            if armed then
                StatusLabel.Text =
                    "ARM "
                    .. string.format(
                        "%.1fs",
                        math.max(
                            0,
                            armEndsAt-os.clock()
                        )
                    )

                StatusLabel.TextColor3 =
                    Color3.fromRGB(80,255,150)
            else
                StatusLabel.Text =
                    "HOOK OFF | READY"

                StatusLabel.TextColor3 =
                    Color3.fromRGB(170,220,255)
            end
        end
    end)

    Gui.AncestryChanged:Connect(function(_,p)
        if p == nil then
            restoreHook(
                "gui destroyed"
            )
        end
    end)

    bootPrint(7, "GUI created")

    add(
        "READY",
        "V2 COMPAT loaded successfully"
    )

    add(
        "HOWTO",
        "ARM CLICK TRACE -> click NPC -> wait UI"
    )

    add(
        "CAP",
        "hook="
        .. tostring(
            CAP.hookmetamethod
            and CAP.getnamecallmethod
        )
        .. " getconnections="
        .. tostring(CAP.getconnections)
        .. " getgc="
        .. tostring(CAP.getgc)
        .. " getconstants="
        .. tostring(CAP.getconstants)
        .. " getupvalues="
        .. tostring(CAP.getupvalues)
    )

    add(
        "OUTPUT",
        "workspace/remote_ui_opener.txt"
    )
end)

if not okMain then
    pcall(function()
        print(
            "[MF OPENER V2][FATAL] "
            .. tostring(mainErr)
        )
    end)
end
