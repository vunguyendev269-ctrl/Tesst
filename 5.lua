--[[
    MYSTERIOUS FORCE - REMOTE UI OPENER FINDER V1
    ==============================================
    Goal:
      Find the CLIENT-SIDE function/module/table that opens the
      Mysterious Force DialogueGui so it can later be reproduced
      without relying on a physical NPC click.

    Workflow:
      1) Run this script. It installs NO hook at startup.
      2) Press ARM CLICK TRACE.
      3) Click Mysterious Force normally.
      4) Wait until dialogue appears.
      5) Finder records:
         - RaceV4Progress Check/Teleport calls + real returns
         - DialogueGui root creation
         - option1 button path
         - option1 event callback(s), when getconnections is available
         - getgc() functions/tables whose constants/values mention:
             Mysterious Force
             DialogueGui
             dialogueTitleFrame
             optionsList
             Use it
             RaceV4Progress
      6) Output:
         workspace/remote_ui_opener.txt

    Safety:
      - CommF_ hook exists only during ARM.
      - Hook observes only RaceV4Progress InvokeServer.
      - Original return values are preserved exactly.
      - Heavy scans run AFTER the UI opens, outside __namecall.
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
    warn("[REMOTE UI FINDER] LocalPlayer missing")
    return
end

local PlayerGui = LP:WaitForChild("PlayerGui", 15)
local DialogueGui = PlayerGui:WaitForChild("DialogueGui", 15)
local CommF = RS:WaitForChild("Remotes"):WaitForChild("CommF_")

local OUTPUT_FILE = "remote_ui_opener.txt"
local ARM_SECONDS = 8

local KEYWORDS = {
    "mysterious force",
    "dialoguegui",
    "dialoguetitleframe",
    "optionslist",
    "use it",
    "remnant of the past",
    "racev4progress",
}

-- ============================================================
-- STATE
-- ============================================================
local State = {
    armed = false,
    hookInstalled = false,
    armEndsAt = 0,
    uiOpenedAt = nil,
    sawCheck = false,
    sawTeleport = false,
}

local oldNamecall
local rawRemoteRecords = {}
local lastOutput = ""

local report = {}
local LogLabel
local Scroll
local StatusLabel

-- ============================================================
-- GENERIC HELPERS
-- ============================================================
local function q(v)
    return string.format("%q", tostring(v))
end

local function lower(v)
    return string.lower(tostring(v or ""))
end

local function containsKeyword(value)
    local s = lower(value)

    for _,keyword in ipairs(KEYWORDS) do
        if string.find(s, keyword, 1, true) then
            return true, keyword
        end
    end

    return false, nil
end

local function safeFullName(inst)
    if typeof(inst) ~= "Instance" then
        return tostring(inst)
    end

    local ok, value = pcall(function()
        return inst:GetFullName()
    end)

    return ok and value or tostring(inst)
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

    local expr = 'game:GetService(' .. q(chain[1]) .. ')'

    for i = 2, #chain do
        expr =
            expr
            .. ":WaitForChild("
            .. q(chain[i])
            .. ")"
    end

    return expr
end

local function valueText(v, depth, seen)
    depth = depth or 0
    seen = seen or {}

    if depth > 2 then
        return "<depth-limit>"
    end

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
        return "<function:" .. tostring(v) .. ">"

    elseif t == "table" then
        if seen[v] then
            return "<recursive-table>"
        end

        seen[v] = true

        local out = {}
        local n = 0

        for k,val in pairs(v) do
            n += 1
            if n > 12 then
                out[#out+1] = "..."
                break
            end

            out[#out+1] =
                "["
                .. valueText(k, depth+1, seen)
                .. "]="
                .. valueText(val, depth+1, seen)
        end

        seen[v] = nil

        return "{"
            .. table.concat(out, ", ")
            .. "}"
    end

    return tostring(v)
end

local function copyArgs(...)
    local n = select("#", ...)
    local out = {n = n}

    for i = 1, n do
        out[i] = select(i, ...)
    end

    return out
end

local function packedText(p)
    if not p then
        return "<not captured>"
    end

    local out = {}

    for i = 1, p.n or 0 do
        out[#out+1] = valueText(p[i])
    end

    if #out == 0 then
        return "<no return values>"
    end

    return table.concat(out, ", ")
end

-- ============================================================
-- REPORT / UI LOG
-- ============================================================
local function refresh()
    if not LogLabel then
        return
    end

    local first = math.max(1, #report - 220)
    local view = {}

    for i = first, #report do
        view[#view+1] = report[i]
    end

    LogLabel.Text = table.concat(view, "\n")
end

local function scrollBottom()
    task.defer(function()
        if Scroll then
            Scroll.CanvasPosition = Vector2.new(
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

local function add(tag, msg, autoScroll)
    local line =
        string.format(
            "[%.3f][%s] %s",
            os.clock(),
            tostring(tag),
            tostring(msg)
        )

    report[#report+1] = line

    if #report > 4000 then
        table.remove(report, 1)
    end

    print("[REMOTE UI FINDER] " .. line)

    refresh()

    if autoScroll ~= false then
        scrollBottom()
    end
end

local function saveReport()
    local text = table.concat(report, "\n")
    lastOutput = text

    if type(writefile) == "function" then
        local ok, err = pcall(function()
            writefile(OUTPUT_FILE, text)
        end)

        if ok then
            add(
                "SAVE",
                "workspace/"
                .. OUTPUT_FILE
            )
        else
            add(
                "ERROR",
                "writefile: "
                .. tostring(err)
            )
        end
    end
end

-- ============================================================
-- DEBUG API HELPERS
-- ============================================================
local dbg = debug or {}

local getConstants =
    dbg.getconstants
    or rawget(getgenv and getgenv() or _G, "getconstants")

local getUpvalues =
    dbg.getupvalues
    or rawget(getgenv and getgenv() or _G, "getupvalues")

local getInfo =
    dbg.getinfo

local function functionScript(fn)
    if type(getfenv) == "function" then
        local ok, env = pcall(getfenv, fn)

        if ok and type(env) == "table" then
            local s = rawget(env, "script")

            if typeof(s) == "Instance" then
                return s
            end
        end
    end
end

local function functionInfo(fn)
    local out = {}

    local scriptInst =
        functionScript(fn)

    if scriptInst then
        out[#out+1] =
            "SCRIPT="
            .. safeFullName(scriptInst)
    end

    if type(getInfo) == "function" then
        local ok, info =
            pcall(getInfo, fn)

        if ok and type(info) == "table" then
            if info.name then
                out[#out+1] =
                    "NAME="
                    .. tostring(info.name)
            end

            if info.source then
                out[#out+1] =
                    "SOURCE="
                    .. tostring(info.source)
            end

            if info.short_src then
                out[#out+1] =
                    "SHORT_SRC="
                    .. tostring(info.short_src)
            end

            if info.linedefined then
                out[#out+1] =
                    "LINE="
                    .. tostring(info.linedefined)
            end
        end
    end

    return table.concat(out, " | ")
end

local function getFunctionConstants(fn)
    if type(getConstants) ~= "function" then
        return nil
    end

    local ok, constants =
        pcall(getConstants, fn)

    if ok
        and type(constants) == "table"
    then
        return constants
    end
end

local function getFunctionUpvalues(fn)
    if type(getUpvalues) ~= "function" then
        return nil
    end

    local ok, values =
        pcall(getUpvalues, fn)

    if ok
        and type(values) == "table"
    then
        return values
    end
end

-- ============================================================
-- MYSTERIOUS FORCE DIALOGUE ROOT / OPTION1
-- ============================================================
local function readText(obj)
    local ok, text = pcall(function()
        return tostring(obj.Text or "")
    end)

    return ok and text or ""
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

-- ============================================================
-- BUTTON CONNECTION INSPECTION
-- ============================================================
local function inspectConnectionFunction(fn, label)
    if type(fn) ~= "function" then
        return
    end

    add(
        "CALLBACK",
        label
        .. " | "
        .. functionInfo(fn)
    )

    local constants =
        getFunctionConstants(fn)

    if constants then
        local hits = {}

        for i,v in ipairs(constants) do
            local match, keyword =
                containsKeyword(v)

            if match then
                hits[#hits+1] =
                    "#"
                    .. tostring(i)
                    .. "="
                    .. valueText(v)
                    .. " ["
                    .. keyword
                    .. "]"
            end
        end

        if #hits > 0 then
            add(
                "CALLBACK CONSTANTS",
                table.concat(
                    hits,
                    " | "
                )
            )
        end
    end

    local upvalues =
        getFunctionUpvalues(fn)

    if upvalues then
        for k,v in pairs(upvalues) do
            local matched = false

            if type(v) == "string" then
                matched =
                    containsKeyword(v)

            elseif type(v) == "table" then
                for tk,tv in pairs(v) do
                    local mk =
                        containsKeyword(tk)

                    local mv =
                        containsKeyword(tv)

                    if mk or mv then
                        matched = true
                        break
                    end
                end
            end

            if matched then
                add(
                    "CALLBACK UPVALUE",
                    tostring(k)
                    .. "="
                    .. valueText(v)
                )
            end
        end
    end
end

local function inspectOption1Connections()
    local button =
        getOption1Button()

    if not button then
        add(
            "OPTION1",
            "button not found"
        )
        return
    end

    add(
        "OPTION1",
        "BUTTON="
        .. instancePath(button)
    )

    add(
        "OPTION1",
        string.format(
            "VISIBLE=%s ACTIVE=%s POS=(%.0f,%.0f) SIZE=(%.0f,%.0f)",
            tostring(button.Visible),
            tostring(button.Active),
            button.AbsolutePosition.X,
            button.AbsolutePosition.Y,
            button.AbsoluteSize.X,
            button.AbsoluteSize.Y
        )
    )

    if type(getconnections) ~= "function" then
        add(
            "OPTION1",
            "getconnections unavailable"
        )
        return
    end

    local signals = {
        {"Activated", button.Activated},
        {"MouseButton1Click", button.MouseButton1Click},
        {"MouseButton1Down", button.MouseButton1Down},
    }

    for _,pair in ipairs(signals) do
        local signalName = pair[1]
        local signal = pair[2]

        local ok, conns =
            pcall(
                getconnections,
                signal
            )

        if ok
            and type(conns) == "table"
        then
            add(
                "CONNECTIONS",
                signalName
                .. "="
                .. tostring(#conns)
            )

            for i,conn in ipairs(conns) do
                local fn = nil

                pcall(function()
                    fn = conn.Function
                end)

                if type(fn) ~= "function" then
                    pcall(function()
                        fn = conn.function
                    end)
                end

                if type(fn) == "function" then
                    inspectConnectionFunction(
                        fn,
                        signalName
                        .. "#"
                        .. tostring(i)
                    )
                else
                    add(
                        "CALLBACK",
                        signalName
                        .. "#"
                        .. tostring(i)
                        .. " function unavailable"
                    )
                end
            end
        end
    end
end

-- ============================================================
-- GETGC SCAN
-- ============================================================
local function scanGcForDialogueCandidates()
    if type(getgc) ~= "function" then
        add(
            "GC",
            "getgc unavailable"
        )
        return
    end

    add(
        "GC",
        "scan start"
    )

    local ok, objects =
        pcall(getgc, true)

    if not ok
        or type(objects) ~= "table"
    then
        add(
            "GC",
            "getgc failed"
        )
        return
    end

    local functionHits = 0
    local tableHits = 0
    local maxFunctionHits = 80
    local maxTableHits = 80

    for _,obj in ipairs(objects) do
        if type(obj) == "function"
            and functionHits < maxFunctionHits
        then
            local constants =
                getFunctionConstants(obj)

            if constants then
                local hits = {}

                for i,v in ipairs(constants) do
                    if type(v) == "string" then
                        local match, keyword =
                            containsKeyword(v)

                        if match then
                            hits[#hits+1] =
                                "#"
                                .. tostring(i)
                                .. "="
                                .. valueText(v)
                                .. "["
                                .. keyword
                                .. "]"
                        end
                    end
                end

                if #hits > 0 then
                    functionHits += 1

                    add(
                        "GC FUNCTION",
                        "#"
                        .. tostring(functionHits)
                        .. " "
                        .. functionInfo(obj)
                    )

                    add(
                        "GC CONSTANTS",
                        table.concat(
                            hits,
                            " | "
                        )
                    )

                    local ups =
                        getFunctionUpvalues(obj)

                    if ups then
                        local shown = 0

                        for k,v in pairs(ups) do
                            local matched = false

                            if type(v) == "string" then
                                matched =
                                    containsKeyword(v)

                            elseif type(v) == "table" then
                                local n = 0

                                for tk,tv in pairs(v) do
                                    n += 1

                                    if n > 20 then
                                        break
                                    end

                                    local mk =
                                        containsKeyword(tk)

                                    local mv =
                                        containsKeyword(tv)

                                    if mk or mv then
                                        matched = true
                                        break
                                    end
                                end
                            end

                            if matched
                                and shown < 8
                            then
                                shown += 1

                                add(
                                    "GC UPVALUE",
                                    tostring(k)
                                    .. "="
                                    .. valueText(v)
                                )
                            end
                        end
                    end
                end
            end

        elseif type(obj) == "table"
            and tableHits < maxTableHits
        then
            local hits = {}
            local count = 0

            for k,v in pairs(obj) do
                count += 1

                if count > 80 then
                    break
                end

                local mk, keyKeyword =
                    containsKeyword(k)

                local mv, valKeyword =
                    containsKeyword(v)

                if mk then
                    hits[#hits+1] =
                        "KEY "
                        .. valueText(k)
                        .. " ["
                        .. tostring(keyKeyword)
                        .. "]"
                end

                if mv then
                    hits[#hits+1] =
                        "VALUE "
                        .. valueText(v)
                        .. " ["
                        .. tostring(valKeyword)
                        .. "]"
                end
            end

            if #hits > 0 then
                tableHits += 1

                add(
                    "GC TABLE",
                    "#"
                    .. tostring(tableHits)
                    .. " "
                    .. tostring(obj)
                )

                add(
                    "GC TABLE HITS",
                    table.concat(
                        hits,
                        " | "
                    )
                )

                -- Show function-valued fields in promising tables.
                local shownFunctions = 0

                for k,v in pairs(obj) do
                    if type(v) == "function"
                        and shownFunctions < 10
                    then
                        shownFunctions += 1

                        add(
                            "GC TABLE FN",
                            "key="
                            .. valueText(k)
                            .. " | "
                            .. functionInfo(v)
                        )
                    end
                end
            end
        end
    end

    add(
        "GC",
        "scan done | functions="
        .. tostring(functionHits)
        .. " tables="
        .. tostring(tableHits)
    )
end

-- ============================================================
-- RACE V4 REMOTE TRACE
-- ============================================================
local function restoreHook(reason)
    State.armed = false
    State.armEndsAt = 0

    if not State.hookInstalled then
        return
    end

    if type(hookmetamethod) == "function"
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

    State.hookInstalled = false

    add(
        "TRACE",
        "HOOK OFF | "
        .. tostring(reason or "")
    )
end

local function installHook()
    if State.hookInstalled then
        return true
    end

    if type(hookmetamethod) ~= "function"
        or type(getnamecallmethod) ~= "function"
    then
        add(
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
                        if not State.armed
                            or os.clock() > State.armEndsAt
                        then
                            return oldNamecall(self, ...)
                        end

                        if self ~= CommF then
                            return oldNamecall(self, ...)
                        end

                        local method =
                            getnamecallmethod()

                        if method ~= "InvokeServer" then
                            return oldNamecall(self, ...)
                        end

                        local args =
                            copyArgs(...)

                        if args[1] ~= "RaceV4Progress" then
                            return oldNamecall(self, ...)
                        end

                        local caller = nil

                        if type(getcallingscript) == "function" then
                            pcall(function()
                                caller = getcallingscript()
                            end)
                        end

                        local start =
                            os.clock()

                        local returns =
                            table.pack(
                                oldNamecall(
                                    self,
                                    ...
                                )
                            )

                        rawRemoteRecords[
                            #rawRemoteRecords+1
                        ] = {
                            time = start,
                            args = args,
                            returns = returns,
                            duration =
                                os.clock() - start,
                            caller = caller,
                        }

                        return table.unpack(
                            returns,
                            1,
                            returns.n
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

    State.hookInstalled = true

    add(
        "TRACE",
        "RaceV4Progress hook ON"
    )

    return true
end

local function armTrace()
    if State.hookInstalled then
        restoreHook("re-arm")
        task.wait(0.05)
    end

    rawRemoteRecords = {}
    State.sawCheck = false
    State.sawTeleport = false
    State.uiOpenedAt = nil

    if not installHook() then
        return
    end

    State.armed = true
    State.armEndsAt =
        os.clock()
        + ARM_SECONDS

    add(
        "ARM",
        "CLICK Mysterious Force NOW | "
        .. tostring(ARM_SECONDS)
        .. "s"
    )
end

-- Drain captured remote records outside hook.
task.spawn(function()
    local processed = 0

    while true do
        task.wait(0.02)

        while processed
            < #rawRemoteRecords
        do
            processed += 1

            local item =
                rawRemoteRecords[processed]

            local action =
                item.args[2]

            add(
                "REMOTE",
                'RaceV4Progress("'
                .. tostring(action)
                .. '") RETURN='
                .. packedText(item.returns)
                .. " dt="
                .. string.format(
                    "%.4fs",
                    item.duration
                )
                .. " CALLER="
                .. (
                    item.caller
                    and safeFullName(item.caller)
                    or "unknown"
                )
            )

            if action == "Check" then
                State.sawCheck = true
            elseif action == "Teleport" then
                State.sawTeleport = true
            end
        end

        if State.armed
            and os.clock()
                > State.armEndsAt
        then
            restoreHook("timeout")
            saveReport()
            processed = 0
        end
    end
end)

-- ============================================================
-- WATCH DIALOGUE UI OPEN
-- ============================================================
local lastRoot = nil
local scanning = false

task.spawn(function()
    while true do
        task.wait(0.05)

        local root =
            getMysteriousRoot()

        if root
            and root ~= lastRoot
        then
            lastRoot = root
            State.uiOpenedAt =
                os.clock()

            add(
                "UI OPEN",
                "ROOT="
                .. instancePath(root)
            )

            add(
                "UI OPEN",
                "rootName="
                .. q(root.Name)
                .. " CheckSeen="
                .. tostring(State.sawCheck)
            )

            if not scanning then
                scanning = true

                task.spawn(function()
                    task.wait(0.2)

                    inspectOption1Connections()

                    task.wait(0.05)

                    scanGcForDialogueCandidates()

                    saveReport()

                    scanning = false
                end)
            end
        elseif not root then
            lastRoot = nil
        end
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
        "MFRemoteUiOpenerFinder"
    )

if old then
    old:Destroy()
end

local Gui =
    Instance.new("ScreenGui")

Gui.Name =
    "MFRemoteUiOpenerFinder"

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
    "MYSTERIOUS FORCE - REMOTE UI OPENER FINDER"

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
    Instance.new("ScrollingFrame")

Scroll.Position =
    UDim2.fromOffset(12,44)

Scroll.Size =
    UDim2.new(1,-24,1,-126)

Scroll.BackgroundColor3 =
    Color3.fromRGB(8,11,17)

Scroll.BorderSizePixel = 0
Scroll.ScrollBarThickness = 12
Scroll.ScrollingDirection =
    Enum.ScrollingDirection.Y
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

local function makeButton(text,x,callback)
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

local arm =
    makeButton(
        "ARM CLICK TRACE\n8 sec",
        0,
        armTrace
    )

arm.BackgroundColor3 =
    Color3.fromRGB(45,95,70)

makeButton(
    "SCAN GC NOW",
    0.25,
    function()
        task.spawn(function()
            scanGcForDialogueCandidates()
            saveReport()
        end)
    end
)

local copy =
    makeButton(
        "COPY REPORT",
        0.5,
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

copy.BackgroundColor3 =
    Color3.fromRGB(55,75,110)

makeButton(
    "CLEAR",
    0.75,
    function()
        report = {}
        lastOutput = ""
        LogLabel.Text = ""
        Scroll.CanvasPosition =
            Vector2.zero

        add(
            "LOG",
            "cleared",
            false
        )
    end
)

-- Drag window
local dragging = false
local dragStart
local startPos

Header.InputBegan:Connect(function(input)
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

        if State.armed then
            local remain =
                math.max(
                    0,
                    State.armEndsAt
                    - os.clock()
                )

            StatusLabel.Text =
                "ARM "
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
        restoreHook("gui destroyed")
    end
end)

-- ============================================================
-- START
-- ============================================================
add(
    "READY",
    "No hook at startup."
)

add(
    "HOWTO",
    "ARM CLICK TRACE -> click Mysterious Force normally -> wait for UI."
)

add(
    "OUTPUT",
    "workspace/remote_ui_opener.txt"
)

add(
    "CAPS",
    "getgc="
    .. tostring(type(getgc) == "function")
    .. " getconnections="
    .. tostring(type(getconnections) == "function")
    .. " getconstants="
    .. tostring(type(getConstants) == "function")
    .. " getupvalues="
    .. tostring(type(getUpvalues) == "function")
)
