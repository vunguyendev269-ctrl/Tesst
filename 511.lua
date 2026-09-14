-- MYSTERIOUS FORCE REMOTE UI OPENER FINDER V3 NOHOOK

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")

local LP = Players.LocalPlayer
if not LP then
    warn("[MF OPENER V3] LocalPlayer missing")
    return
end

local PlayerGui = LP:WaitForChild("PlayerGui", 15)
if not PlayerGui then
    warn("[MF OPENER V3] PlayerGui missing")
    return
end

local OUTPUT_FILE = "remote_ui_opener.txt"
local WATCH_SECONDS = 10

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
}

local State = {
    watching = false,
    watchEndsAt = 0,
    foundRoot = nil,
    foundOption1 = nil,
}

local report = {}
local lastOutput = ""
local LogLabel
local Scroll
local StatusLabel

local function q(v)
    return string.format("%q", tostring(v))
end

local function lower(v)
    return string.lower(tostring(v or ""))
end

local function keywordMatch(v)
    local s = lower(v)

    for _,kw in ipairs(KEYWORDS) do
        if string.find(s, kw, 1, true) then
            return true, kw
        end
    end

    return false, nil
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

local function simpleValue(v)
    local t = typeof(v)

    if t == "nil" then
        return "nil"
    elseif t == "string" then
        return q(v)
    elseif t == "number" or t == "boolean" then
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
        local out = {}
        local count = 0

        for k,val in pairs(v) do
            count = count + 1

            if count > 12 then
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

local function refresh()
    if not LogLabel then
        return
    end

    local first = math.max(1, #report - 230)
    local view = {}

    for i = first, #report do
        view[#view+1] = report[i]
    end

    LogLabel.Text = table.concat(view, "\n")
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

local function add(tag, msg, autoScroll)
    local line =
        "["
        .. string.format("%.3f", os.clock())
        .. "]["
        .. tostring(tag)
        .. "] "
        .. tostring(msg)

    report[#report+1] = line

    if #report > 3000 then
        table.remove(report, 1)
    end

    print("[MF OPENER V3] " .. line)
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
            add("SAVE", "workspace/" .. OUTPUT_FILE)
        else
            add("SAVE ERROR", tostring(err))
        end
    else
        add("SAVE", "writefile unavailable")
    end
end

-- ============================================================
-- DIALOGUE DISCOVERY
-- ============================================================
local function getDialogueGui()
    return PlayerGui:FindFirstChild("DialogueGui")
end

local function getMysteriousRoot()
    local dialogueGui = getDialogueGui()

    if not dialogueGui then
        return nil
    end

    for _,root in ipairs(dialogueGui:GetChildren()) do
        local titleFrame =
            root:FindFirstChild("dialogueTitleFrame")

        local title =
            titleFrame
            and titleFrame:FindFirstChild("name")

        if title
            and title:IsA("TextLabel")
            and lower(safeText(title))
                == "mysterious force"
        then
            return root
        end
    end

    return nil
end

local function getOption1Button(root)
    root = root or getMysteriousRoot()

    if not root then
        return nil
    end

    local options = root:FindFirstChild("optionsList")
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

    return nil
end

local function describeDialogue(root)
    State.foundRoot = root

    add("UI ROOT", instancePath(root))
    add(
        "UI ROOT",
        "Name="
        .. q(root.Name)
        .. " Class="
        .. tostring(root.ClassName)
    )

    local button = getOption1Button(root)
    State.foundOption1 = button

    if button then
        add("OPTION1", instancePath(button))

        local ok, info = pcall(function()
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

        if ok then
            add("OPTION1", info)
        end
    else
        add("OPTION1", "not found")
    end
end

-- ============================================================
-- OPTIONAL EXECUTOR APIS
-- ============================================================
local function getApi(name)
    local ok, fn = pcall(function()
        return _G[name]
    end)

    if ok and type(fn) == "function" then
        return fn
    end

    return nil
end

local apiGetConnections = getApi("getconnections")
local apiGetGc = getApi("getgc")
local apiGetConstants = getApi("getconstants")
local apiGetUpvalues = getApi("getupvalues")
local apiGetFenv = getApi("getfenv")

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
end

local function functionScript(fn)
    if not apiGetFenv then
        return nil
    end

    local ok, env = pcall(apiGetFenv, fn)

    if not ok or type(env) ~= "table" then
        return nil
    end

    local scriptObj = env.script

    if typeof(scriptObj) == "Instance" then
        return scriptObj
    end

    return nil
end

local function functionDescriptor(fn)
    local scriptObj = functionScript(fn)

    if scriptObj then
        return tostring(fn)
            .. " | SCRIPT="
            .. safeFullName(scriptObj)
    end

    return tostring(fn)
end

local function scanFunction(fn, prefix)
    if type(fn) ~= "function" then
        return
    end

    add(prefix, functionDescriptor(fn))

    if apiGetConstants then
        local ok, constants =
            pcall(apiGetConstants, fn)

        if ok and type(constants) == "table" then
            for i,v in ipairs(constants) do
                if type(v) == "string" then
                    local hit, kw = keywordMatch(v)

                    if hit then
                        add(
                            prefix .. " CONST",
                            "#"
                            .. tostring(i)
                            .. "="
                            .. q(v)
                            .. " ["
                            .. tostring(kw)
                            .. "]"
                        )
                    end
                end
            end
        end
    end

    if apiGetUpvalues then
        local ok, values =
            pcall(apiGetUpvalues, fn)

        if ok and type(values) == "table" then
            local shown = 0

            for k,v in pairs(values) do
                if shown >= 12 then
                    break
                end

                local matched = false

                if type(v) == "string" then
                    matched = keywordMatch(v)
                elseif type(v) == "table" then
                    local tested = 0

                    for tk,tv in pairs(v) do
                        tested = tested + 1

                        if tested > 30 then
                            break
                        end

                        local mk = keywordMatch(tk)
                        local mv = keywordMatch(tv)

                        if mk or mv then
                            matched = true
                            break
                        end
                    end
                end

                if matched then
                    shown = shown + 1

                    add(
                        prefix .. " UPVALUE",
                        tostring(k)
                        .. "="
                        .. simpleValue(v)
                    )
                end
            end
        end
    end
end

-- ============================================================
-- OPTION1 CALLBACK SCAN
-- ============================================================
local function scanOption1Callbacks()
    local button =
        State.foundOption1
        or getOption1Button()

    if not button then
        add("CALLBACK", "option1 button not found")
        return
    end

    add(
        "CALLBACK",
        "button=" .. instancePath(button)
    )

    if not apiGetConnections then
        add("CALLBACK", "getconnections unavailable")
        return
    end

    local names = {
        "Activated",
        "MouseButton1Click",
        "MouseButton1Down",
    }

    for _,signalName in ipairs(names) do
        local signal = nil

        local okSignal = pcall(function()
            signal = button[signalName]
        end)

        if okSignal and signal then
            local ok, connections =
                pcall(
                    apiGetConnections,
                    signal
                )

            if ok
                and type(connections) == "table"
            then
                add(
                    "CALLBACK",
                    signalName
                    .. " connections="
                    .. tostring(#connections)
                )

                for i,conn in ipairs(connections) do
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
                        scanFunction(
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
                            .. " function hidden"
                        )
                    end
                end
            end
        end
    end
end

-- ============================================================
-- SAFE GC SCAN
-- ============================================================
local function scanGcSafe()
    if not apiGetGc then
        add("GC", "getgc unavailable")
        return
    end

    if not apiGetConstants then
        add("GC", "getconstants unavailable")
        return
    end

    add("GC", "scan start")

    local ok, objects =
        pcall(apiGetGc, true)

    if not ok or type(objects) ~= "table" then
        add(
            "GC",
            "getgc failed: "
            .. tostring(objects)
        )
        return
    end

    local hitCount = 0
    local checked = 0

    for _,obj in ipairs(objects) do
        if type(obj) == "function" then
            checked = checked + 1

            local okConst, constants =
                pcall(
                    apiGetConstants,
                    obj
                )

            if okConst
                and type(constants) == "table"
            then
                local matches = {}

                for i,v in ipairs(constants) do
                    if type(v) == "string" then
                        local hit, kw = keywordMatch(v)

                        if hit then
                            matches[#matches+1] =
                                "#"
                                .. tostring(i)
                                .. "="
                                .. q(v)
                                .. "["
                                .. tostring(kw)
                                .. "]"
                        end
                    end
                end

                if #matches > 0 then
                    hitCount = hitCount + 1

                    add(
                        "GC HIT #"
                        .. tostring(hitCount),
                        functionDescriptor(obj)
                    )

                    add(
                        "GC CONST",
                        table.concat(
                            matches,
                            " | "
                        )
                    )

                    scanFunction(
                        obj,
                        "GC FUNC #"
                        .. tostring(hitCount)
                    )

                    if hitCount >= 60 then
                        break
                    end
                end
            end
        end
    end

    add(
        "GC",
        "done | functionsChecked="
        .. tostring(checked)
        .. " hits="
        .. tostring(hitCount)
    )
end

-- ============================================================
-- UI WATCH
-- ============================================================
local function startWatch()
    if State.watching then
        add("WATCH", "already active")
        return
    end

    State.watching = true
    State.watchEndsAt =
        os.clock() + WATCH_SECONDS

    State.foundRoot = nil
    State.foundOption1 = nil

    add(
        "WATCH",
        "ARMED "
        .. tostring(WATCH_SECONDS)
        .. "s | CLICK NPC NOW"
    )
end

task.spawn(function()
    local lastRoot = nil

    while true do
        task.wait(0.05)

        local root = getMysteriousRoot()

        if root and root ~= lastRoot then
            lastRoot = root

            add(
                "WATCH",
                "Mysterious Force UI OPEN"
            )

            describeDialogue(root)

            if State.watching then
                State.watching = false

                task.spawn(function()
                    task.wait(0.15)

                    local ok, err =
                        pcall(
                            scanOption1Callbacks
                        )

                    if not ok then
                        add(
                            "CALLBACK ERROR",
                            tostring(err)
                        )
                    end

                    saveReport()
                end)
            end
        elseif not root then
            lastRoot = nil
        end

        if State.watching
            and os.clock() >= State.watchEndsAt
        then
            State.watching = false
            add("WATCH", "timeout")
            saveReport()
        end
    end
end)

-- ============================================================
-- GUI
-- ============================================================
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
        "MFRemoteUiOpenerFinderV3"
    )

if old then
    old:Destroy()
end

local Gui = Instance.new("ScreenGui")
Gui.Name = "MFRemoteUiOpenerFinderV3"
Gui.ResetOnSpawn = false
Gui.Parent = parent

local Frame = Instance.new("Frame")
Frame.Size = UDim2.fromOffset(860,510)
Frame.Position = UDim2.new(0.5,-430,0.5,-255)
Frame.BackgroundColor3 = Color3.fromRGB(18,21,29)
Frame.BorderSizePixel = 0
Frame.Active = true
Frame.Parent = Gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0,10)
corner.Parent = Frame

local Header = Instance.new("TextLabel")
Header.BackgroundTransparency = 1
Header.Position = UDim2.fromOffset(12,7)
Header.Size = UDim2.new(1,-280,0,30)
Header.Font = Enum.Font.GothamBold
Header.TextSize = 14
Header.TextColor3 = Color3.new(1,1,1)
Header.TextXAlignment = Enum.TextXAlignment.Left
Header.Text = "MYSTERIOUS FORCE - REMOTE UI OPENER FINDER V3 NOHOOK"
Header.Active = true
Header.Parent = Frame

StatusLabel = Instance.new("TextLabel")
StatusLabel.BackgroundTransparency = 1
StatusLabel.AnchorPoint = Vector2.new(1,0)
StatusLabel.Position = UDim2.new(1,-12,0,7)
StatusLabel.Size = UDim2.fromOffset(265,30)
StatusLabel.Font = Enum.Font.Code
StatusLabel.TextSize = 11
StatusLabel.TextXAlignment = Enum.TextXAlignment.Right
StatusLabel.TextColor3 = Color3.fromRGB(170,220,255)
StatusLabel.Parent = Frame

Scroll = Instance.new("ScrollingFrame")
Scroll.Position = UDim2.fromOffset(12,44)
Scroll.Size = UDim2.new(1,-24,1,-128)
Scroll.BackgroundColor3 = Color3.fromRGB(8,11,17)
Scroll.BorderSizePixel = 0
Scroll.ScrollBarThickness = 12
Scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
Scroll.CanvasSize = UDim2.new(0,0,0,0)
Scroll.Active = true
Scroll.Parent = Frame

LogLabel = Instance.new("TextLabel")
LogLabel.BackgroundTransparency = 1
LogLabel.Position = UDim2.fromOffset(8,6)
LogLabel.Size = UDim2.new(1,-24,0,0)
LogLabel.AutomaticSize = Enum.AutomaticSize.Y
LogLabel.Font = Enum.Font.Code
LogLabel.TextSize = 11
LogLabel.TextColor3 = Color3.fromRGB(215,225,240)
LogLabel.TextWrapped = true
LogLabel.TextXAlignment = Enum.TextXAlignment.Left
LogLabel.TextYAlignment = Enum.TextYAlignment.Top
LogLabel.Text = ""
LogLabel.Parent = Scroll

local function makeButton(text,x,callback)
    local b = Instance.new("TextButton")
    b.AnchorPoint = Vector2.new(0,1)
    b.Position = UDim2.new(x,8,1,-12)
    b.Size = UDim2.new(0.24,-10,0,56)
    b.BackgroundColor3 = Color3.fromRGB(40,47,64)
    b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamBold
    b.TextSize = 11
    b.TextWrapped = true
    b.TextColor3 = Color3.new(1,1,1)
    b.Text = text
    b.Parent = Frame

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0,7)
    c.Parent = b

    b.MouseButton1Click:Connect(callback)
    return b
end

local watchButton =
    makeButton(
        "ARM UI WATCH\n10 sec",
        0,
        startWatch
    )

watchButton.BackgroundColor3 =
    Color3.fromRGB(45,95,70)

makeButton(
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
                    "CALLBACK ERROR",
                    tostring(err)
                )
            end

            saveReport()
        end)
    end
)

makeButton(
    "SCAN GC\nSAFE",
    0.5,
    function()
        task.spawn(function()
            local ok, err =
                pcall(scanGcSafe)

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

local copyButton =
    makeButton(
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

copyButton.BackgroundColor3 =
    Color3.fromRGB(55,75,110)

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

        if State.watching then
            StatusLabel.Text =
                "WATCH "
                .. string.format(
                    "%.1fs",
                    math.max(
                        0,
                        State.watchEndsAt
                            - os.clock()
                    )
                )
                .. " | NOHOOK"

            StatusLabel.TextColor3 =
                Color3.fromRGB(80,255,150)
        else
            StatusLabel.Text =
                "READY | NOHOOK"

            StatusLabel.TextColor3 =
                Color3.fromRGB(170,220,255)
        end
    end
end)

add(
    "READY",
    "V3 loaded. No network interception."
)

add(
    "HOWTO",
    "ARM UI WATCH -> click Mysterious Force normally."
)

add(
    "CAP",
    "getconnections="
    .. tostring(apiGetConnections ~= nil)
    .. " getgc="
    .. tostring(apiGetGc ~= nil)
    .. " getconstants="
    .. tostring(apiGetConstants ~= nil)
    .. " getupvalues="
    .. tostring(apiGetUpvalues ~= nil)
)

add(
    "KNOWN",
    'NPC click -> Check return 4; Use it -> Teleport.'
)

add(
    "OUTPUT",
    "workspace/remote_ui_opener.txt"
)
