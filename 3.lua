--[[
    MYSTERIOUS FORCE - 3S ALL NETWORK DEBUGGER
    ===========================================
    Mục tiêu:
      - KHÔNG hook khi vừa chạy.
      - Theo dõi UI "Mysterious Force" hoàn toàn thụ động.
      - Khi UI NPC vừa OPEN -> tự bật capture trong đúng 3 giây.
      - Trong 3 giây bắt toàn bộ:
          * RemoteFunction:InvokeServer(...)
          * RemoteEvent:FireServer(...)
          * UnreliableRemoteEvent:FireServer(...)
          * BindableFunction:Invoke(...)
          * BindableEvent:Fire(...)
      - Ghi luôn calling script/library nếu executor có getcallingscript().
      - Trong hook KHÔNG print, KHÔNG format, KHÔNG writefile.
      - Hết 3 giây -> OFF hook -> mới format toàn bộ.
      - Xuất workspace/service.txt

    Có thêm:
      AUTO UI CAPTURE ON/OFF
      MANUAL CAPTURE 3S
      FORCE STOP
      CLEAR

    Lưu ý:
      "ALL" ở đây là toàn bộ network/bindable command trong cửa sổ capture.
      Không hook mọi FindFirstChild/IsA/property engine call vì sẽ tạo hàng nghìn
      call mỗi giây và có thể làm nghẽn/chặn interaction NPC.
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
    warn("[SERVICE DEBUG] LocalPlayer missing")
    return
end

local PlayerGui = LP:WaitForChild("PlayerGui", 15)

local OUTPUT_FILE = "service.txt"
local CAPTURE_SECONDS = 3

-- ============================================================
-- STATE
-- ============================================================
local State = {
    autoCapture = true,
    active = false,
    trigger = "NONE",
    startedAt = 0,
    endsAt = 0,
    hookInstalled = false,
    restoring = false,
}

local oldNamecall = nil
local rawCalls = {}
local captureSequence = 0

local UiLog = {}
local LogLabel
local Scroll
local StatusLabel
local AutoButton

-- ============================================================
-- HELPERS
-- ============================================================
local function quote(s)
    return string.format("%q", tostring(s))
end

local function getRoot()
    local c = LP.Character
    local h = c and c:FindFirstChildOfClass("Humanoid")
    local r = c and c:FindFirstChild("HumanoidRootPart")

    if c and h and r and h.Health > 0 then
        return r
    end
end

local function safeFullName(inst)
    if typeof(inst) ~= "Instance" then
        return tostring(inst)
    end

    local ok, result = pcall(function()
        return inst:GetFullName()
    end)

    return ok and result or tostring(inst)
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
        .. quote(parts[1])
        .. ')'

    for i = 2, #parts do
        expr =
            expr
            .. ":WaitForChild("
            .. quote(parts[i])
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
        return quote(v)

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

            if count > 20 then
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

    return quote(tostring(v))
end

local function copyArgs(...)
    local n = select("#", ...)
    local out = {n = n}

    for i = 1, n do
        out[i] = select(i, ...)
    end

    return out
end

local function argsToLua(args)
    local out = {}

    for i = 1, args.n or 0 do
        out[#out+1] =
            valueToLua(args[i])
    end

    return table.concat(out, ", ")
end

local function uiLog(tag, msg)
    local line =
        string.format(
            "[%.3f][%s] %s",
            os.clock(),
            tostring(tag),
            tostring(msg)
        )

    UiLog[#UiLog+1] = line

    if #UiLog > 250 then
        table.remove(UiLog, 1)
    end

    print("[SERVICE DEBUG] " .. line)

    if LogLabel then
        LogLabel.Text =
            table.concat(UiLog, "\n")

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
end

-- ============================================================
-- OUTPUT FORMATTER
-- ============================================================
local function buildOutput(records, trigger, startedAt, finishedAt)
    local lines = {}

    lines[#lines+1] =
        "============================================================"

    lines[#lines+1] =
        "MYSTERIOUS FORCE - 3S ALL NETWORK CAPTURE"

    lines[#lines+1] =
        "============================================================"

    lines[#lines+1] =
        "Trigger: " .. tostring(trigger)

    lines[#lines+1] =
        "CaptureSeconds: "
        .. string.format("%.3f", finishedAt - startedAt)

    lines[#lines+1] =
        "TotalCalls: " .. tostring(#records)

    lines[#lines+1] =
        "GeneratedAtClock: "
        .. string.format("%.3f", os.clock())

    lines[#lines+1] = ""

    for index,item in ipairs(records) do
        local target = item.target
        local targetName =
            safeFullName(target)

        local className = "?"
        pcall(function()
            className = target.ClassName
        end)

        local callerText = "unknown"

        if item.caller
            and typeof(item.caller) == "Instance"
        then
            callerText =
                instancePath(item.caller)
        elseif item.caller then
            callerText =
                tostring(item.caller)
        end

        local dt =
            item.time - startedAt

        local command =
            instancePath(target)
            .. ":"
            .. item.method
            .. "("
            .. argsToLua(item.args)
            .. ")"

        lines[#lines+1] =
            "------------------------------------------------------------"

        lines[#lines+1] =
            "#"
            .. tostring(index)
            .. "  +"
            .. string.format("%.4fs", dt)

        lines[#lines+1] =
            "TYPE: "
            .. tostring(className)

        lines[#lines+1] =
            "TARGET: "
            .. targetName

        lines[#lines+1] =
            "METHOD: "
            .. tostring(item.method)

        lines[#lines+1] =
            "CALLER: "
            .. callerText

        lines[#lines+1] =
            "CMD: "
            .. command
    end

    lines[#lines+1] =
        "============================================================"

    return table.concat(lines, "\n")
end

local function saveCapture(records, trigger, startedAt, finishedAt)
    local output =
        buildOutput(
            records,
            trigger,
            startedAt,
            finishedAt
        )

    if type(writefile) == "function" then
        local ok, err =
            pcall(function()
                writefile(
                    OUTPUT_FILE,
                    output
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
            "executor has no writefile(); output printed to console"
        )

        print(output)
    end

    -- Also show important commands in UI after capture is over.
    for i,item in ipairs(records) do
        local cmd =
            instancePath(item.target)
            .. ":"
            .. item.method
            .. "("
            .. argsToLua(item.args)
            .. ")"

        uiLog(
            "CMD #" .. tostring(i),
            cmd
        )
    end
end

-- ============================================================
-- HOOK
-- ============================================================
local NETWORK_METHODS = {
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

    if State.hookInstalled
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

    State.hookInstalled = false

    uiLog(
        "TRACE",
        "HOOK OFF"
        .. (
            reason
            and (" | " .. tostring(reason))
            or ""
        )
    )

    State.restoring = false
end

local function installHook()
    if State.hookInstalled then
        return true
    end

    if type(hookmetamethod) ~= "function"
        or type(getnamecallmethod) ~= "function"
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
                        -- absolutely minimal fast path
                        if not State.active
                            or os.clock() > State.endsAt
                        then
                            return oldNamecall(
                                self,
                                ...
                            )
                        end

                        local method =
                            getnamecallmethod()

                        if not NETWORK_METHODS[method] then
                            return oldNamecall(
                                self,
                                ...
                            )
                        end

                        if typeof(self) ~= "Instance" then
                            return oldNamecall(
                                self,
                                ...
                            )
                        end

                        -- Capture caller/library only if executor provides it.
                        local caller = nil

                        if type(getcallingscript) == "function" then
                            pcall(function()
                                caller =
                                    getcallingscript()
                            end)
                        end

                        rawCalls[#rawCalls+1] = {
                            time = os.clock(),
                            target = self,
                            method = method,
                            args = copyArgs(...),
                            caller = caller,
                        }

                        -- Critical: untouched original call immediately.
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

    State.hookInstalled = true

    uiLog(
        "TRACE",
        "HOOK ON - network/bindable only"
    )

    return true
end

-- ============================================================
-- CAPTURE
-- ============================================================
local function finishCapture(reason)
    if not State.active
        and not State.hookInstalled
    then
        return
    end

    local trigger = State.trigger
    local startedAt = State.startedAt
    local finishedAt = os.clock()

    State.active = false

    -- small settle period so current original namecall can return
    task.wait(0.05)

    restoreHook(reason)

    local records = rawCalls
    rawCalls = {}

    captureSequence += 1

    uiLog(
        "CAPTURE",
        "DONE #"
        .. tostring(captureSequence)
        .. " | "
        .. tostring(trigger)
        .. " | calls="
        .. tostring(#records)
    )

    task.defer(
        saveCapture,
        records,
        trigger,
        startedAt,
        finishedAt
    )
end

local function startCapture(trigger)
    if State.active then
        uiLog(
            "CAPTURE",
            "already active"
        )
        return false
    end

    if State.hookInstalled then
        restoreHook("clean before new capture")
        task.wait(0.05)
    end

    rawCalls = {}

    if not installHook() then
        return false
    end

    State.trigger = trigger
    State.startedAt = os.clock()
    State.endsAt =
        State.startedAt
        + CAPTURE_SECONDS

    State.active = true

    uiLog(
        "CAPTURE",
        "START "
        .. tostring(trigger)
        .. " | "
        .. tostring(CAPTURE_SECONDS)
        .. "s"
    )

    task.spawn(function()
        local myStart =
            State.startedAt

        while State.active
            and State.startedAt == myStart
            and os.clock() < State.endsAt
        do
            task.wait(0.02)
        end

        if State.active
            and State.startedAt == myStart
        then
            finishCapture(
                "3s complete"
            )
        end
    end)

    return true
end

-- ============================================================
-- NPC UI WATCHER - NO HOOK WHILE IDLE
-- ============================================================
local function readText(obj)
    local ok, value =
        pcall(function()
            return tostring(obj.Text or "")
        end)

    return ok and value or ""
end

local function npcUiState()
    if not PlayerGui then
        return false, false
    end

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

local lastNpcOpen = false
local lastUseVisible = false

task.spawn(function()
    while true do
        task.wait(0.08)

        local open, useVisible =
            npcUiState()

        if open
            and not lastNpcOpen
        then
            uiLog(
                "NPC UI",
                "Mysterious Force OPEN"
            )

            if State.autoCapture then
                startCapture(
                    "NPC_UI_OPEN"
                )
            end
        elseif not open
            and lastNpcOpen
        then
            uiLog(
                "NPC UI",
                "Mysterious Force CLOSED"
            )
        end

        if useVisible
            and not lastUseVisible
        then
            uiLog(
                "NPC UI",
                '"Use it" VISIBLE'
            )
        end

        lastNpcOpen = open
        lastUseVisible = useVisible
    end
end)

-- ============================================================
-- HRP JUMP PASSIVE MONITOR
-- ============================================================
task.spawn(function()
    local lastPos = nil

    while true do
        task.wait(0.03)

        local root =
            getRoot()

        if root then
            local pos =
                root.Position

            if lastPos then
                local jump =
                    (pos - lastPos).Magnitude

                if jump >= 1000 then
                    uiLog(
                        "HRP",
                        "JUMP "
                        .. string.format("%.1f", jump)
                        .. " | "
                        .. tostring(lastPos)
                        .. " -> "
                        .. tostring(pos)
                    )
                end
            end

            lastPos = pos
        else
            lastPos = nil
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

local oldGui =
    parent:FindFirstChild(
        "MFAllNetwork3sDebugger"
    )

if oldGui then
    oldGui:Destroy()
end

local Gui = Instance.new("ScreenGui")
Gui.Name = "MFAllNetwork3sDebugger"
Gui.ResetOnSpawn = false
Gui.Parent = parent

local Frame = Instance.new("Frame")
Frame.Size = UDim2.fromOffset(
    780,
    450
)
Frame.Position = UDim2.new(
    0.5,
    -390,
    0.5,
    -225
)
Frame.BackgroundColor3 =
    Color3.fromRGB(18,21,29)
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
    UDim2.fromOffset(12,7)
Header.Size =
    UDim2.new(1,-250,0,28)
Header.Font =
    Enum.Font.GothamBold
Header.TextSize = 14
Header.TextColor3 =
    Color3.new(1,1,1)
Header.TextXAlignment =
    Enum.TextXAlignment.Left
Header.Text =
    "MYSTERIOUS FORCE - 3S ALL NETWORK DEBUGGER"
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
    UDim2.fromOffset(235,28)
StatusLabel.Font =
    Enum.Font.Code
StatusLabel.TextSize = 11
StatusLabel.TextXAlignment =
    Enum.TextXAlignment.Right
StatusLabel.TextColor3 =
    Color3.fromRGB(170,220,255)
StatusLabel.Text =
    "HOOK OFF | AUTO ON"
StatusLabel.Parent = Frame

Scroll =
    Instance.new("ScrollingFrame")
Scroll.Position =
    UDim2.fromOffset(12,42)
Scroll.Size =
    UDim2.new(1,-24,1,-122)
Scroll.BackgroundColor3 =
    Color3.fromRGB(8,11,17)
Scroll.BorderSizePixel = 0
Scroll.ScrollBarThickness = 7
Scroll.AutomaticCanvasSize =
    Enum.AutomaticSize.Y
Scroll.CanvasSize =
    UDim2.new(0,0,0,0)
Scroll.Parent = Frame

LogLabel =
    Instance.new("TextLabel")
LogLabel.BackgroundTransparency = 1
LogLabel.Position =
    UDim2.fromOffset(7,5)
LogLabel.Size =
    UDim2.new(1,-14,0,0)
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

local function makeButton(
    text,
    x,
    callback
)
    local b =
        Instance.new("TextButton")

    b.AnchorPoint =
        Vector2.new(0,1)
    b.Position =
        UDim2.new(x,8,1,-12)
    b.Size =
        UDim2.new(0.24,-10,0,52)
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

AutoButton =
    makeButton(
        "AUTO UI CAPTURE\nON",
        0,
        function()
            State.autoCapture =
                not State.autoCapture

            AutoButton.Text =
                "AUTO UI CAPTURE\n"
                .. (
                    State.autoCapture
                    and "ON"
                    or "OFF"
                )

            AutoButton.BackgroundColor3 =
                State.autoCapture
                and Color3.fromRGB(45,95,70)
                or Color3.fromRGB(65,45,55)

            uiLog(
                "AUTO",
                tostring(
                    State.autoCapture
                )
            )
        end
    )

AutoButton.BackgroundColor3 =
    Color3.fromRGB(45,95,70)

makeButton(
    "MANUAL CAPTURE\n3 sec",
    0.25,
    function()
        startCapture(
            "MANUAL_3S"
        )
    end
)

makeButton(
    "FORCE STOP",
    0.5,
    function()
        if State.active
            or State.hookInstalled
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

makeButton(
    "CLEAR UI LOG",
    0.75,
    function()
        UiLog = {}
        LogLabel.Text = ""
        uiLog(
            "LOG",
            "cleared"
        )
    end
)

-- ============================================================
-- DRAG
-- ============================================================
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
                startPos.X.Offset + d.X,
                startPos.Y.Scale,
                startPos.Y.Offset + d.Y
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

-- ============================================================
-- STATUS
-- ============================================================
task.spawn(function()
    while Gui.Parent do
        task.wait(0.1)

        local remaining = ""

        if State.active then
            remaining =
                " "
                .. string.format(
                    "%.1fs",
                    math.max(
                        0,
                        State.endsAt
                            - os.clock()
                    )
                )
        end

        StatusLabel.Text =
            "HOOK "
            .. (
                State.hookInstalled
                and "ON"
                or "OFF"
            )
            .. remaining
            .. " | AUTO "
            .. (
                State.autoCapture
                and "ON"
                or "OFF"
            )

        StatusLabel.TextColor3 =
            State.hookInstalled
            and Color3.fromRGB(
                80,255,150
            )
            or Color3.fromRGB(
                170,220,255
            )
    end
end)

Gui.AncestryChanged:Connect(function(_, p)
    if p == nil then
        restoreHook(
            "gui destroyed"
        )
    end
end)

-- ============================================================
-- START
-- ============================================================
uiLog(
    "READY",
    "Idle = NO HOOK. Auto capture starts only when Mysterious Force UI opens."
)

uiLog(
    "OUTPUT",
    "Capture will be written to workspace/service.txt"
)
