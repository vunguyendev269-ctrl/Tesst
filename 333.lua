--[[
    MYSTERIOUS FORCE - FULL FLOW DEBUGGER V6
    =========================================
    Flow chuẩn:
        ARM FULL FLOW
        -> click NPC
        -> capture RaceV4Progress("Check")
        -> Mysterious Force UI OPEN
        -> bấm Use it
        -> capture RaceV4Progress("Teleport")
        -> wait 0.35s
        -> auto stop
        -> write workspace/service.txt

    Capture:
        RemoteFunction:InvokeServer
        RemoteEvent:FireServer
        UnreliableRemoteEvent:FireServer
        BindableFunction:Invoke
        BindableEvent:Fire

    Safety:
        - No hook at startup.
        - __namecall hook only shallow-copies raw data.
        - No print / formatting / file IO inside hook.
        - Original call passes through immediately.
        - Auto unhook after Teleport or timeout.
]]

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")

local LP = Players.LocalPlayer
if not LP then
    warn("[MF FLOW V6] LocalPlayer missing")
    return
end

local PlayerGui = LP:WaitForChild("PlayerGui", 15)

local Remotes = RS:WaitForChild("Remotes")
local CommF = Remotes:WaitForChild("CommF_")

local OUTPUT_FILE = "service.txt"

-- Long enough to:
-- ARM -> click NPC -> menu open -> click Use it.
local MAX_CAPTURE_SECONDS = 8.0

-- After Teleport appears, wait a little to collect post-click traffic.
local POST_TELEPORT_SETTLE = 0.35

-- ============================================================
-- STATE
-- ============================================================
local State = {
    active = false,
    installed = false,
    restoring = false,

    startedAt = 0,
    endsAt = 0,

    menuOpen = false,

    sawCheck = false,
    sawTeleport = false,
    checkAt = nil,
    teleportAt = nil,

    checkReturn = nil,
    teleportReturn = nil,
}

local oldNamecall = nil
local rawCalls = {}
local captureGeneration = 0

local lastOutput = ""
local lastV4Summary = ""

local uiLines = {}
local LogLabel
local Scroll
local StatusLabel

-- ============================================================
-- BASIC HELPERS
-- ============================================================
local function q(v)
    return string.format("%q", tostring(v))
end

local function safeFullName(inst)
    if typeof(inst) ~= "Instance" then
        return tostring(inst)
    end

    local ok, name = pcall(function()
        return inst:GetFullName()
    end)

    return ok and name or tostring(inst)
end

local function instancePath(inst)
    if typeof(inst) ~= "Instance" then
        return tostring(inst)
    end

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
        'game:GetService('
        .. q(parts[1])
        .. ')'

    for i = 2, #parts do
        expr =
            expr
            .. ":WaitForChild("
            .. q(parts[i])
            .. ")"
    end

    return expr
end

local function valueToLua(v, depth, seen)
    depth = depth or 0
    seen = seen or {}

    if depth >= 3 then
        return "nil --[[depth-limit]]"
    end

    local t = typeof(v)

    if t == "nil" then
        return "nil"

    elseif t == "boolean"
        or t == "number"
    then
        return tostring(v)

    elseif t == "string" then
        return q(v)

    elseif t == "Vector3" then
        return string.format(
            "Vector3.new(%.6f, %.6f, %.6f)",
            v.X, v.Y, v.Z
        )

    elseif t == "Vector2" then
        return string.format(
            "Vector2.new(%.6f, %.6f)",
            v.X, v.Y
        )

    elseif t == "CFrame" then
        local comps = {v:GetComponents()}
        local out = {}

        for i,n in ipairs(comps) do
            out[i] = string.format("%.6f", n)
        end

        return "CFrame.new("
            .. table.concat(out, ", ")
            .. ")"

    elseif t == "Color3" then
        return string.format(
            "Color3.new(%.6f, %.6f, %.6f)",
            v.R, v.G, v.B
        )

    elseif t == "EnumItem" then
        return tostring(v)

    elseif t == "Instance" then
        return instancePath(v)

    elseif t == "table" then
        if seen[v] then
            return "{} --[[recursive]]"
        end

        seen[v] = true

        local out = {}
        local count = 0

        for k,val in pairs(v) do
            count += 1

            if count > 18 then
                out[#out+1] = "--[[...]]"
                break
            end

            out[#out+1] =
                "["
                .. valueToLua(k, depth+1, seen)
                .. "]="
                .. valueToLua(val, depth+1, seen)
        end

        seen[v] = nil

        return "{"
            .. table.concat(out, ", ")
            .. "}"
    end

    return q(tostring(v))
end

local function copyArgs(...)
    local n = select("#", ...)
    local args = {n = n}

    for i = 1, n do
        args[i] = select(i, ...)
    end

    return args
end

local function argsToLua(args)
    local out = {}

    for i = 1, args.n or 0 do
        out[#out+1] =
            valueToLua(args[i])
    end

    return table.concat(out, ", ")
end

local function returnsToLua(results)
    if not results then
        return "<not captured>"
    end

    if (results.n or 0) == 0 then
        return "<no return values>"
    end

    local out = {}

    for i = 1, results.n do
        out[#out+1] =
            valueToLua(results[i])
    end

    return table.concat(out, ", ")
end

local function returnsTypeText(results)
    if not results then
        return "not-captured"
    end

    if (results.n or 0) == 0 then
        return "none"
    end

    local out = {}

    for i = 1, results.n do
        out[#out+1] =
            typeof(results[i])
    end

    return table.concat(out, ", ")
end

-- ============================================================
-- UI LOG
-- ============================================================
local function refreshUi()
    if not LogLabel then
        return
    end

    local first =
        math.max(
            1,
            #uiLines - 220
        )

    local view = {}

    for i = first, #uiLines do
        view[#view+1] = uiLines[i]
    end

    LogLabel.Text =
        table.concat(view, "\n")
end

local function scrollBottom()
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

local function uiLog(tag, msg, autoScroll)
    local line =
        string.format(
            "[%.3f][%s] %s",
            os.clock(),
            tostring(tag),
            tostring(msg)
        )

    uiLines[#uiLines+1] = line

    if #uiLines > 1200 then
        table.remove(uiLines, 1)
    end

    print("[MF FLOW V6] " .. line)

    refreshUi()

    if autoScroll ~= false then
        scrollBottom()
    end
end

-- ============================================================
-- CALL CLASSIFICATION
-- ============================================================
local function isRaceV4Call(item, action)
    if item.target ~= CommF then
        return false
    end

    if item.method ~= "InvokeServer"
        and item.method ~= "FireServer"
    then
        return false
    end

    if (item.args.n or 0) < 2 then
        return false
    end

    return item.args[1] == "RaceV4Progress"
        and item.args[2] == action
end

local function makeCommand(item)
    return
        instancePath(item.target)
        .. ":"
        .. item.method
        .. "("
        .. argsToLua(item.args)
        .. ")"
end

-- ============================================================
-- OUTPUT
-- ============================================================
local function buildSummary(records, startedAt, endedAt)
    local lines = {}

    lines[#lines+1] =
        "============================================================"

    lines[#lines+1] =
        "V4 SUMMARY"

    lines[#lines+1] =
        "============================================================"

    lines[#lines+1] =
        "CaptureSeconds: "
        .. string.format(
            "%.3f",
            endedAt - startedAt
        )

    lines[#lines+1] =
        "TotalCalls: "
        .. tostring(#records)

    lines[#lines+1] =
        "SawCheck: "
        .. tostring(State.sawCheck)

    lines[#lines+1] =
        "SawTeleport: "
        .. tostring(State.sawTeleport)

    lines[#lines+1] = ""

    local v4Index = 0

    for i,item in ipairs(records) do
        if item.target == CommF
            and (
                item.args[1]
                    == "RaceV4Progress"
            )
        then
            v4Index += 1

            lines[#lines+1] =
                "V4 #"
                .. tostring(v4Index)
                .. "  +"
                .. string.format(
                    "%.4fs",
                    item.time - startedAt
                )

            lines[#lines+1] =
                "CMD: "
                .. makeCommand(item)

            lines[#lines+1] =
                "RETURN: "
                .. returnsToLua(
                    item.returns
                )

            lines[#lines+1] =
                "RETURN_TYPE: "
                .. returnsTypeText(
                    item.returns
                )

            lines[#lines+1] =
                "REMOTE_TIME: "
                .. (
                    item.duration
                    and string.format(
                        "%.6fs",
                        item.duration
                    )
                    or "n/a"
                )

            lines[#lines+1] =
                "CALLER: "
                .. (
                    item.caller
                    and instancePath(item.caller)
                    or "unknown"
                )

            lines[#lines+1] = ""
        end
    end

    if v4Index == 0 then
        lines[#lines+1] =
            "No RaceV4Progress calls captured."
    end

    lines[#lines+1] =
        "============================================================"

    return table.concat(lines, "\n")
end

local function buildFullOutput(records, startedAt, endedAt)
    local lines = {}

    local summary =
        buildSummary(
            records,
            startedAt,
            endedAt
        )

    lines[#lines+1] = summary
    lines[#lines+1] = ""
    lines[#lines+1] =
        "============================================================"
    lines[#lines+1] =
        "ALL CAPTURED COMMANDS"
    lines[#lines+1] =
        "============================================================"

    for i,item in ipairs(records) do
        local className = "?"

        pcall(function()
            className =
                item.target.ClassName
        end)

        lines[#lines+1] =
            "------------------------------------------------------------"

        lines[#lines+1] =
            "#"
            .. tostring(i)
            .. "  +"
            .. string.format(
                "%.4fs",
                item.time - startedAt
            )

        lines[#lines+1] =
            "TYPE: "
            .. tostring(className)

        lines[#lines+1] =
            "TARGET: "
            .. safeFullName(item.target)

        lines[#lines+1] =
            "METHOD: "
            .. tostring(item.method)

        if item.method == "InvokeServer"
            or item.method == "Invoke"
        then
            lines[#lines+1] =
                "RETURN: "
                .. returnsToLua(
                    item.returns
                )

            lines[#lines+1] =
                "RETURN_TYPE: "
                .. returnsTypeText(
                    item.returns
                )

            lines[#lines+1] =
                "REMOTE_TIME: "
                .. (
                    item.duration
                    and string.format(
                        "%.6fs",
                        item.duration
                    )
                    or "n/a"
                )
        end

        lines[#lines+1] =
            "CALLER: "
            .. (
                item.caller
                and instancePath(item.caller)
                or "unknown"
            )

        lines[#lines+1] =
            "CMD: "
            .. makeCommand(item)
    end

    lines[#lines+1] =
        "============================================================"

    return table.concat(lines, "\n"), summary
end

local function saveOutput(records, startedAt, endedAt)
    local full, summary =
        buildFullOutput(
            records,
            startedAt,
            endedAt
        )

    lastOutput = full
    lastV4Summary = summary

    if type(writefile) == "function" then
        local ok, err =
            pcall(function()
                writefile(
                    OUTPUT_FILE,
                    full
                )
            end)

        if ok then
            uiLog(
                "SAVE",
                "workspace/"
                .. OUTPUT_FILE
                .. " | calls="
                .. tostring(#records)
            )
        else
            uiLog(
                "ERROR",
                "writefile failed: "
                .. tostring(err)
            )
        end
    else
        uiLog(
            "ERROR",
            "writefile unavailable"
        )
    end

    uiLog(
        "SUMMARY",
        "Check="
        .. tostring(State.sawCheck)
        .. " | Teleport="
        .. tostring(State.sawTeleport)
    )

    -- Show only RaceV4 commands in UI for readability.
    for _,item in ipairs(records) do
        if item.target == CommF
            and item.args[1]
                == "RaceV4Progress"
        then
            uiLog(
                "V4 CMD",
                makeCommand(item)
            )
        end
    end
end

-- ============================================================
-- HOOK
-- ============================================================
local CAPTURE_METHODS = {
    InvokeServer = true,
    FireServer = true,
    Invoke = true,
    Fire = true,
}

local function restoreHook(reason)
    if State.restoring then
        return
    end

    State.restoring = true
    State.active = false

    if State.installed
        and type(hookmetamethod) == "function"
        and type(oldNamecall) == "function"
    then
        pcall(function()
            hookmetamethod(
                game,
                "__namecall",
                oldNamecall
            )
        end)
    end

    State.installed = false

    uiLog(
        "TRACE",
        "HOOK OFF"
        .. (
            reason
            and " | "
                .. tostring(reason)
            or ""
        )
    )

    State.restoring = false
end

local function installHook()
    if State.installed then
        return true
    end

    if type(hookmetamethod)
        ~= "function"
        or type(getnamecallmethod)
        ~= "function"
    then
        uiLog(
            "ERROR",
            "hookmetamethod/getnamecallmethod unavailable"
        )
        return false
    end

    local wrap =
        type(newcclosure) == "function"
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
                        -- Very fast inactive path.
                        if not State.active
                            or os.clock()
                                > State.endsAt
                        then
                            return oldNamecall(
                                self,
                                ...
                            )
                        end

                        if typeof(self)
                            ~= "Instance"
                        then
                            return oldNamecall(
                                self,
                                ...
                            )
                        end

                        local method =
                            getnamecallmethod()

                        if not CAPTURE_METHODS[
                            method
                        ] then
                            return oldNamecall(
                                self,
                                ...
                            )
                        end

                        local caller = nil

                        if type(getcallingscript)
                            == "function"
                        then
                            pcall(function()
                                caller =
                                    getcallingscript()
                            end)
                        end

                        local callArgs =
                            copyArgs(...)

                        local record = {
                            time =
                                os.clock(),
                            target = self,
                            method = method,
                            args = callArgs,
                            caller = caller,
                            returns = nil,
                            duration = nil,
                        }

                        rawCalls[
                            #rawCalls + 1
                        ] = record

                        -- For the two V4 progression calls only, preserve and
                        -- record the real InvokeServer return value.
                        --
                        -- Other network/bindable calls stay on the light
                        -- passthrough path to minimize interaction impact.
                        local isV4Invoke =
                            self == CommF
                            and method == "InvokeServer"
                            and callArgs[1]
                                == "RaceV4Progress"

                        if isV4Invoke then
                            local invokeStarted =
                                os.clock()

                            local results =
                                table.pack(
                                    oldNamecall(
                                        self,
                                        ...
                                    )
                                )

                            record.duration =
                                os.clock()
                                - invokeStarted

                            record.returns =
                                results

                            return table.unpack(
                                results,
                                1,
                                results.n
                            )
                        end

                        -- Untouched passthrough for everything else.
                        return oldNamecall(
                            self,
                            ...
                        )
                    end)
                )
        end)

    if not ok then
        uiLog(
            "ERROR",
            "hook install failed: "
            .. tostring(err)
        )
        return false
    end

    State.installed = true

    uiLog(
        "TRACE",
        "HOOK ON | full flow"
    )

    return true
end

-- ============================================================
-- CAPTURE CONTROL
-- ============================================================
local function finishCapture(reason)
    if not State.active
        and not State.installed
    then
        return
    end

    local generation =
        captureGeneration

    local startedAt =
        State.startedAt

    State.active = false

    -- Give current original remote call time to return.
    task.wait(0.06)

    restoreHook(reason)

    local endedAt =
        os.clock()

    local records =
        rawCalls

    rawCalls = {}

    uiLog(
        "CAPTURE",
        "DONE #"
        .. tostring(generation)
        .. " | calls="
        .. tostring(#records)
        .. " | "
        .. tostring(reason)
    )

    task.defer(
        saveOutput,
        records,
        startedAt,
        endedAt
    )
end

local function startFullCapture()
    if State.active then
        uiLog(
            "CAPTURE",
            "already active"
        )
        return
    end

    if State.installed then
        restoreHook(
            "cleanup before arm"
        )
        task.wait(0.05)
    end

    rawCalls = {}

    State.sawCheck = false
    State.sawTeleport = false
    State.checkAt = nil
    State.teleportAt = nil
    State.checkReturn = nil
    State.teleportReturn = nil
    State.menuOpen = false

    if not installHook() then
        return
    end

    captureGeneration += 1

    State.startedAt =
        os.clock()

    State.endsAt =
        State.startedAt
        + MAX_CAPTURE_SECONDS

    State.active = true

    uiLog(
        "ARM",
        "FULL FLOW "
        .. tostring(
            MAX_CAPTURE_SECONDS
        )
        .. "s | CLICK NPC NOW"
    )
end

-- Background classifier.
-- No expensive formatting here, only checks already captured raw records.
task.spawn(function()
    local processed = 0

    while true do
        task.wait(0.015)

        if not State.active then
            processed = 0
        else
            while processed
                < #rawCalls
            do
                processed += 1

                local item =
                    rawCalls[processed]

                if isRaceV4Call(
                    item,
                    "Check"
                )
                    and not State.sawCheck
                then
                    -- InvokeServer return may be written into the record
                    -- immediately after the original remote returns.
                    local waitDeadline =
                        os.clock() + 2

                    while item.returns == nil
                        and os.clock()
                            < waitDeadline
                    do
                        task.wait()
                    end

                    State.sawCheck = true
                    State.checkAt =
                        item.time
                    State.checkReturn =
                        item.returns

                    uiLog(
                        "FLOW",
                        "CHECK RETURN = "
                        .. returnsToLua(
                            item.returns
                        )
                        .. " | TYPE="
                        .. returnsTypeText(
                            item.returns
                        )
                        .. " | dt="
                        .. (
                            item.duration
                            and string.format(
                                "%.4fs",
                                item.duration
                            )
                            or "n/a"
                        )
                    )
                end

                if isRaceV4Call(
                    item,
                    "Teleport"
                )
                    and not State.sawTeleport
                then
                    local waitDeadline =
                        os.clock() + 2

                    while item.returns == nil
                        and os.clock()
                            < waitDeadline
                    do
                        task.wait()
                    end

                    State.sawTeleport = true
                    State.teleportAt =
                        item.time
                    State.teleportReturn =
                        item.returns

                    uiLog(
                        "FLOW",
                        "TELEPORT RETURN = "
                        .. returnsToLua(
                            item.returns
                        )
                        .. " | TYPE="
                        .. returnsTypeText(
                            item.returns
                        )
                        .. " | dt="
                        .. (
                            item.duration
                            and string.format(
                                "%.4fs",
                                item.duration
                            )
                            or "n/a"
                        )
                    )
                end
            end

            if State.sawTeleport
                and State.teleportAt
                and (
                    os.clock()
                    - State.teleportAt
                )
                    >= POST_TELEPORT_SETTLE
            then
                finishCapture(
                    "Teleport captured + settle"
                )

            elseif os.clock()
                >= State.endsAt
            then
                finishCapture(
                    "timeout"
                )
            end
        end
    end
end)

-- ============================================================
-- NPC UI WATCHER (PASSIVE)
-- ============================================================
local function readText(obj)
    local ok, value =
        pcall(function()
            return tostring(
                obj.Text or ""
            )
        end)

    return ok and value or ""
end

local function scanNpcUi()
    local open = false
    local useVisible = false

    for _,obj in ipairs(
        PlayerGui:GetDescendants()
    ) do
        if obj:IsA("TextLabel")
            or obj:IsA("TextButton")
        then
            local text =
                readText(obj):lower()

            if text:find(
                "mysterious force",
                1,
                true
            )
                or text:find(
                    "remnant of the past",
                    1,
                    true
                )
            then
                open = true
            end

            if obj:IsA("TextButton")
                and text:find(
                    "use it",
                    1,
                    true
                )
            then
                useVisible = true
            end
        end
    end

    return open, useVisible
end

local lastOpen = false
local lastUse = false

task.spawn(function()
    while true do
        task.wait(0.08)

        local open, use =
            scanNpcUi()

        if open ~= lastOpen then
            lastOpen = open
            State.menuOpen = open

            uiLog(
                "NPC UI",
                open
                    and "Mysterious Force OPEN"
                    or "Mysterious Force CLOSED"
            )
        end

        if use
            and not lastUse
        then
            uiLog(
                "NPC UI",
                '"Use it" VISIBLE'
            )
        end

        lastUse = use
    end
end)

-- ============================================================
-- GUI
-- ============================================================
local parent = CoreGui

pcall(function()
    if type(gethui) == "function" then
        parent = gethui()
    end
end)

local old =
    parent:FindFirstChild(
        "MFFullFlowDebuggerV6"
    )

if old then
    old:Destroy()
end

local Gui =
    Instance.new("ScreenGui")

Gui.Name =
    "MFFullFlowDebuggerV6"

Gui.ResetOnSpawn = false
Gui.Parent = parent

local Frame =
    Instance.new("Frame")

Frame.Size =
    UDim2.fromOffset(
        820,
        480
    )

Frame.Position =
    UDim2.new(
        0.5,
        -410,
        0.5,
        -240
    )

Frame.BackgroundColor3 =
    Color3.fromRGB(
        18,
        21,
        29
    )

Frame.BorderSizePixel = 0
Frame.Active = true
Frame.Parent = Gui

local Corner =
    Instance.new("UICorner")

Corner.CornerRadius =
    UDim.new(0,10)

Corner.Parent = Frame

local Header =
    Instance.new("TextLabel")

Header.BackgroundTransparency = 1

Header.Position =
    UDim2.fromOffset(
        12,
        7
    )

Header.Size =
    UDim2.new(
        1,
        -270,
        0,
        30
    )

Header.Font =
    Enum.Font.GothamBold

Header.TextSize = 14

Header.TextColor3 =
    Color3.new(1,1,1)

Header.TextXAlignment =
    Enum.TextXAlignment.Left

Header.Text =
    "MYSTERIOUS FORCE - FULL FLOW DEBUGGER V6"

Header.Active = true
Header.Parent = Frame

StatusLabel =
    Instance.new("TextLabel")

StatusLabel.BackgroundTransparency = 1

StatusLabel.AnchorPoint =
    Vector2.new(1,0)

StatusLabel.Position =
    UDim2.new(
        1,
        -12,
        0,
        7
    )

StatusLabel.Size =
    UDim2.fromOffset(
        250,
        30
    )

StatusLabel.Font =
    Enum.Font.Code

StatusLabel.TextSize = 11

StatusLabel.TextXAlignment =
    Enum.TextXAlignment.Right

StatusLabel.TextColor3 =
    Color3.fromRGB(
        170,
        220,
        255
    )

StatusLabel.Parent = Frame

Scroll =
    Instance.new(
        "ScrollingFrame"
    )

Scroll.Name = "LogScroll"

Scroll.Position =
    UDim2.fromOffset(
        12,
        44
    )

Scroll.Size =
    UDim2.new(
        1,
        -24,
        1,
        -126
    )

Scroll.BackgroundColor3 =
    Color3.fromRGB(
        8,
        11,
        17
    )

Scroll.BorderSizePixel = 0

Scroll.ScrollBarThickness = 12

Scroll.ScrollingDirection =
    Enum.ScrollingDirection.Y

Scroll.ElasticBehavior =
    Enum.ElasticBehavior.WhenScrollable

Scroll.AutomaticCanvasSize =
    Enum.AutomaticSize.Y

Scroll.CanvasSize =
    UDim2.new(
        0,
        0,
        0,
        0
    )

Scroll.Active = true
Scroll.Parent = Frame

local ScrollCorner =
    Instance.new("UICorner")

ScrollCorner.CornerRadius =
    UDim.new(0,7)

ScrollCorner.Parent = Scroll

LogLabel =
    Instance.new("TextLabel")

LogLabel.BackgroundTransparency = 1

LogLabel.Position =
    UDim2.fromOffset(
        8,
        6
    )

LogLabel.Size =
    UDim2.new(
        1,
        -24,
        0,
        0
    )

LogLabel.AutomaticSize =
    Enum.AutomaticSize.Y

LogLabel.Font =
    Enum.Font.Code

LogLabel.TextSize = 11

LogLabel.TextColor3 =
    Color3.fromRGB(
        215,
        225,
        240
    )

LogLabel.TextWrapped = true

LogLabel.TextXAlignment =
    Enum.TextXAlignment.Left

LogLabel.TextYAlignment =
    Enum.TextYAlignment.Top

LogLabel.Text = ""

LogLabel.Parent = Scroll

local function makeButton(
    text,
    x,
    callback
)
    local b =
        Instance.new(
            "TextButton"
        )

    b.AnchorPoint =
        Vector2.new(0,1)

    b.Position =
        UDim2.new(
            x,
            8,
            1,
            -12
        )

    b.Size =
        UDim2.new(
            0.24,
            -10,
            0,
            54
        )

    b.BackgroundColor3 =
        Color3.fromRGB(
            40,
            47,
            64
        )

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
    makeButton(
        "ARM FULL FLOW\nCLICK NPC -> USE IT",
        0,
        startFullCapture
    )

armButton.BackgroundColor3 =
    Color3.fromRGB(
        45,
        95,
        70
    )

makeButton(
    "FORCE STOP",
    0.25,
    function()
        if State.active
            or State.installed
        then
            finishCapture(
                "manual stop"
            )
        else
            restoreHook(
                "manual cleanup"
            )
        end
    end
)

local copyButton =
    makeButton(
        "COPY LAST\nFULL service.txt",
        0.5,
        function()
            if lastOutput == "" then
                uiLog(
                    "COPY",
                    "no completed capture yet"
                )
                return
            end

            if type(setclipboard)
                == "function"
            then
                local ok, err =
                    pcall(function()
                        setclipboard(
                            lastOutput
                        )
                    end)

                if ok then
                    uiLog(
                        "COPY",
                        "full last capture copied"
                    )
                else
                    uiLog(
                        "ERROR",
                        "setclipboard failed: "
                        .. tostring(err)
                    )
                end
            else
                uiLog(
                    "ERROR",
                    "setclipboard unavailable"
                )
            end
        end
    )

copyButton.BackgroundColor3 =
    Color3.fromRGB(
        55,
        75,
        110
    )

makeButton(
    "CLEAR UI LOG",
    0.75,
    function()
        uiLines = {}
        LogLabel.Text = ""
        Scroll.CanvasPosition =
            Vector2.zero

        uiLog(
            "LOG",
            "UI cleared",
            false
        )
    end
)

-- ============================================================
-- DRAG WINDOW
-- ============================================================
local dragging = false
local dragStart
local startPos

Header.InputBegan:Connect(
    function(input)
        if input.UserInputType
            == Enum.UserInputType.MouseButton1
            or input.UserInputType
            == Enum.UserInputType.Touch
        then
            dragging = true
            dragStart =
                input.Position
            startPos =
                Frame.Position
        end
    end
)

UIS.InputChanged:Connect(
    function(input)
        if dragging
            and (
                input.UserInputType
                    == Enum.UserInputType.MouseMovement
                or input.UserInputType
                    == Enum.UserInputType.Touch
            )
        then
            local delta =
                input.Position
                - dragStart

            Frame.Position =
                UDim2.new(
                    startPos.X.Scale,
                    startPos.X.Offset
                        + delta.X,
                    startPos.Y.Scale,
                    startPos.Y.Offset
                        + delta.Y
                )
        end
    end
)

UIS.InputEnded:Connect(
    function(input)
        if input.UserInputType
            == Enum.UserInputType.MouseButton1
            or input.UserInputType
            == Enum.UserInputType.Touch
        then
            dragging = false
        end
    end
)

-- ============================================================
-- STATUS
-- ============================================================
task.spawn(function()
    while Gui.Parent do
        task.wait(0.08)

        if State.active then
            local remain =
                math.max(
                    0,
                    State.endsAt
                        - os.clock()
                )

            StatusLabel.Text =
                "HOOK ON "
                .. string.format(
                    "%.1fs",
                    remain
                )
                .. " | Check:"
                .. (
                    State.sawCheck
                    and "YES"
                    or "NO"
                )
                .. " | TP:"
                .. (
                    State.sawTeleport
                    and "YES"
                    or "NO"
                )

            StatusLabel.TextColor3 =
                Color3.fromRGB(
                    80,
                    255,
                    150
                )
        else
            StatusLabel.Text =
                "HOOK OFF | READY"

            StatusLabel.TextColor3 =
                Color3.fromRGB(
                    170,
                    220,
                    255
                )
        end
    end
end)

Gui.AncestryChanged:Connect(
    function(_, p)
        if p == nil then
            restoreHook(
                "gui destroyed"
            )
        end
    end
)

-- ============================================================
-- START
-- ============================================================
uiLog(
    "READY",
    "NO HOOK at startup."
)

uiLog(
    "HOWTO",
    "ARM FULL FLOW -> click NPC -> wait menu -> click Use it."
)

uiLog(
    "OUTPUT",
    "Completed capture writes workspace/service.txt"
)

uiLog(
    "RETURN",
    "V6 records real Check/Teleport InvokeServer return values."
)

uiLog(
    "UI",
    "Use mouse wheel / scrollbar to scroll logs; drag title to move window."
)
