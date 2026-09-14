--[[
    MYSTERIOUS FORCE - EXACT COMMAND DEBUGGER
    ==========================================
    Mục tiêu:
      A) Bắt lệnh hoàn chỉnh khi bạn click NPC / mở dialogue.
      B) Bắt lệnh hoàn chỉnh khi bạn chọn "Use it".

    Cách dùng:
      1. Bấm ARM NPC CLICK.
      2. Tự click NPC.
      3. Chờ menu Mysterious Force mở.
      4. Bấm ARM USE IT.
      5. Tự bấm Use it.
      6. Xem dòng [CMD] để biết lệnh Luau hoàn chỉnh.

    Debugger KHÔNG tự click NPC.
    Debugger KHÔNG tự bấm Use it.
    Debugger KHÔNG tự gọi RaceV4Progress.
    Debugger chỉ trace khi một phase đang ARM.

    Hook chỉ:
      - copy args rất nhẹ
      - đẩy vào queue
      - return oldNamecall(...) ngay
    Việc format/print/writefile chạy ngoài __namecall.
]]

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")

local LP = Players.LocalPlayer
local PlayerGui = LP:WaitForChild("PlayerGui", 15)

local TEMPLE_POS = Vector3.new(
    28286.35546875,
    14896.5078125,
    102.62469482421875
)

local LOG_FILE =
    "MYSTERIOUS_FORCE_EXACT_COMMAND_DEBUG.txt"

-- ============================================================
-- CAPTURE STATE
-- ============================================================
local Capture = {
    mode = "OFF",       -- OFF / NPC / USE
    untilTime = 0,
}

local remoteQueue = {}
local hookInstalled = false
local oldNamecall

local logs = {}
local LogLabel
local Scroll
local ModeLabel

-- ============================================================
-- CHARACTER
-- ============================================================
local function getRoot()
    local c = LP.Character
    local h = c and c:FindFirstChildOfClass("Humanoid")
    local r = c and c:FindFirstChild("HumanoidRootPart")

    if c and h and r and h.Health > 0 then
        return r
    end
end

-- ============================================================
-- SERIALIZER TO EXECUTABLE LUA
-- ============================================================
local function quote(s)
    return string.format("%q", tostring(s))
end

local function toLua(v, depth, seen)
    depth = depth or 0
    seen = seen or {}

    if depth > 3 then
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
            "Vector3.new(%.9f, %.9f, %.9f)",
            v.X, v.Y, v.Z
        )

    elseif t == "Vector2" then
        return string.format(
            "Vector2.new(%.9f, %.9f)",
            v.X, v.Y
        )

    elseif t == "CFrame" then
        local comps = {v:GetComponents()}
        local out = {}

        for i,n in ipairs(comps) do
            out[i] = string.format("%.9f", n)
        end

        return "CFrame.new("
            .. table.concat(out, ", ")
            .. ")"

    elseif t == "Color3" then
        return string.format(
            "Color3.new(%.9f, %.9f, %.9f)",
            v.R, v.G, v.B
        )

    elseif t == "EnumItem" then
        return tostring(v)

    elseif t == "Instance" then
        local parts = {}
        local cur = v

        while cur and cur ~= game do
            table.insert(
                parts,
                1,
                cur.Name
            )
            cur = cur.Parent
        end

        if not cur then
            return "nil --[[Instance:"
                .. quote(v:GetFullName())
                .. "]]"
        end

        local service = parts[1]
        local expr =
            'game:GetService('
            .. quote(service)
            .. ')'

        for i = 2, #parts do
            expr =
                expr
                .. ":WaitForChild("
                .. quote(parts[i])
                .. ")"
        end

        return expr

    elseif t == "table" then
        if seen[v] then
            return "{} --[[recursive]]"
        end

        seen[v] = true

        local out = {}
        local count = 0

        for k,val in pairs(v) do
            count += 1

            if count > 15 then
                out[#out+1] = "--[[...]]"
                break
            end

            out[#out+1] =
                "["
                .. toLua(k, depth+1, seen)
                .. "]="
                .. toLua(val, depth+1, seen)
        end

        seen[v] = nil

        return "{"
            .. table.concat(out, ", ")
            .. "}"
    end

    return quote(tostring(v))
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

local function argsToLua(args)
    local out = {}

    for i = 1, args.n or 0 do
        out[#out+1] =
            toLua(args[i])
    end

    return table.concat(out, ", ")
end

local function copyArgs(...)
    local n = select("#", ...)
    local t = {n=n}

    for i = 1,n do
        t[i] = select(i,...)
    end

    return t
end

-- ============================================================
-- LOG
-- ============================================================
local function flush()
    if type(writefile) == "function" then
        pcall(function()
            writefile(
                LOG_FILE,
                table.concat(logs, "\n")
            )
        end)
    end
end

local function refresh()
    if not LogLabel then
        return
    end

    local first =
        math.max(1, #logs - 160)

    local view = {}

    for i=first,#logs do
        view[#view+1] = logs[i]
    end

    LogLabel.Text =
        table.concat(view, "\n")

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

local function log(tag, msg)
    local line =
        string.format(
            "[%.3f][%s][%s] %s",
            os.clock(),
            Capture.mode,
            tostring(tag),
            tostring(msg)
        )

    logs[#logs+1] = line

    if #logs > 1200 then
        table.remove(logs,1)
    end

    print("[MF EXACT DBG] "..line)
    refresh()
    flush()
end

local function arm(mode, seconds)
    Capture.mode = mode
    Capture.untilTime =
        os.clock() + (seconds or 12)

    log(
        "ARM",
        mode
        .. " for "
        .. tostring(seconds or 12)
        .. "s"
    )
end

local function active()
    return Capture.mode ~= "OFF"
        and os.clock() <= Capture.untilTime
end

-- ============================================================
-- UI DETECTION
-- ============================================================
local lastMenuOpen = false
local lastUseVisible = false

local function textOf(obj)
    local ok, value =
        pcall(function()
            return tostring(obj.Text or "")
        end)

    return ok and value or ""
end

local function scanDialogue()
    if not PlayerGui then
        return false, false
    end

    local menuOpen = false
    local useVisible = false

    for _,obj in ipairs(PlayerGui:GetDescendants()) do
        if obj:IsA("TextLabel")
            or obj:IsA("TextButton")
        then
            local s = textOf(obj):lower()

            if s:find(
                "mysterious force",
                1,
                true
            )
            or s:find(
                "remnant of the past",
                1,
                true
            )
            then
                menuOpen = true
            end

            if obj:IsA("TextButton")
                and s:find(
                    "use it",
                    1,
                    true
                )
            then
                useVisible = true
            end
        end
    end

    return menuOpen, useVisible
end

task.spawn(function()
    while true do
        task.wait(0.1)

        local open, use =
            scanDialogue()

        if open ~= lastMenuOpen then
            lastMenuOpen = open

            log(
                "UI",
                open
                and "Mysterious Force menu OPEN"
                or "Mysterious Force menu CLOSED"
            )
        end

        if use ~= lastUseVisible then
            lastUseVisible = use

            if use then
                log(
                    "UI",
                    '"Use it" button VISIBLE'
                )
            end
        end

        if Capture.mode ~= "OFF"
            and os.clock() > Capture.untilTime
        then
            log(
                "ARM",
                "capture timeout -> OFF"
            )
            Capture.mode = "OFF"
        end
    end
end)

-- ============================================================
-- HOOK
-- ============================================================
local function installHook()
    if hookInstalled then
        return true
    end

    if type(hookmetamethod) ~= "function"
        or type(getnamecallmethod) ~= "function"
    then
        log(
            "ERROR",
            "executor missing hookmetamethod/getnamecallmethod"
        )
        return false
    end

    local wrap =
        type(newcclosure) == "function"
        and newcclosure
        or function(f) return f end

    local ok, err =
        pcall(function()
            oldNamecall =
                hookmetamethod(
                    game,
                    "__namecall",
                    wrap(function(self, ...)
                        if not active() then
                            return oldNamecall(self, ...)
                        end

                        local method =
                            getnamecallmethod()

                        if (
                            method ~= "InvokeServer"
                            and method ~= "FireServer"
                        )
                            or typeof(self) ~= "Instance"
                            or not (
                                self:IsA("RemoteFunction")
                                or self:IsA("RemoteEvent")
                            )
                        then
                            return oldNamecall(self, ...)
                        end

                        local args =
                            copyArgs(...)

                        -- queue only; no print/UI/writefile inside hook
                        remoteQueue[#remoteQueue+1] = {
                            mode = Capture.mode,
                            method = method,
                            remote = self,
                            args = args,
                            when = os.clock(),
                        }

                        return oldNamecall(self, ...)
                    end)
                )
        end)

    if not ok then
        log(
            "ERROR",
            "hook install failed: "
            .. tostring(err)
        )
        return false
    end

    hookInstalled = true
    log(
        "TRACE",
        "hook installed; passive until ARM"
    )

    return true
end

-- drain remote queue OUTSIDE hook
task.spawn(function()
    while true do
        task.wait(0.02)

        if #remoteQueue > 0 then
            local q = remoteQueue
            remoteQueue = {}

            for _,item in ipairs(q) do
                local cmd =
                    instancePath(item.remote)
                    .. ":"
                    .. item.method
                    .. "("
                    .. argsToLua(item.args)
                    .. ")"

                log(
                    "REMOTE",
                    item.method
                    .. " "
                    .. item.remote:GetFullName()
                )

                log(
                    "CMD",
                    cmd
                )
            end
        end
    end
end)

-- ============================================================
-- HRP JUMP MONITOR
-- ============================================================
task.spawn(function()
    local lastPos

    while true do
        task.wait(0.03)

        local r = getRoot()

        if r then
            local p = r.Position

            if lastPos then
                local jump =
                    (p-lastPos).Magnitude

                if jump >= 1000 then
                    local td =
                        (p-TEMPLE_POS).Magnitude

                    log(
                        "HRP",
                        "JUMP "
                        .. string.format("%.1f", jump)
                        .. " studs FROM="
                        .. tostring(lastPos)
                        .. " TO="
                        .. tostring(p)
                        .. " TempleDist="
                        .. string.format("%.3f", td)
                    )
                end
            end

            lastPos = p
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

local old =
    parent:FindFirstChild(
        "MFExactCommandDebugger"
    )

if old then
    old:Destroy()
end

local Gui = Instance.new("ScreenGui")
Gui.Name = "MFExactCommandDebugger"
Gui.ResetOnSpawn = false
Gui.Parent = parent

local Frame = Instance.new("Frame")
Frame.Size = UDim2.fromOffset(760,430)
Frame.Position = UDim2.new(0.5,-380,0.5,-215)
Frame.BackgroundColor3 = Color3.fromRGB(18,21,29)
Frame.BorderSizePixel = 0
Frame.Active = true
Frame.Parent = Gui

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(0,10)
Corner.Parent = Frame

local Header = Instance.new("TextLabel")
Header.BackgroundTransparency = 1
Header.Position = UDim2.fromOffset(12,7)
Header.Size = UDim2.new(1,-190,0,28)
Header.Font = Enum.Font.GothamBold
Header.TextSize = 14
Header.TextColor3 = Color3.new(1,1,1)
Header.TextXAlignment = Enum.TextXAlignment.Left
Header.Text = "MYSTERIOUS FORCE - EXACT COMMAND DEBUGGER"
Header.Active = true
Header.Parent = Frame

ModeLabel = Instance.new("TextLabel")
ModeLabel.BackgroundTransparency = 1
ModeLabel.AnchorPoint = Vector2.new(1,0)
ModeLabel.Position = UDim2.new(1,-12,0,7)
ModeLabel.Size = UDim2.fromOffset(170,28)
ModeLabel.Font = Enum.Font.Code
ModeLabel.TextSize = 11
ModeLabel.TextXAlignment = Enum.TextXAlignment.Right
ModeLabel.TextColor3 = Color3.fromRGB(170,220,255)
ModeLabel.Text = "CAPTURE: OFF"
ModeLabel.Parent = Frame

Scroll = Instance.new("ScrollingFrame")
Scroll.Position = UDim2.fromOffset(12,42)
Scroll.Size = UDim2.new(1,-24,1,-120)
Scroll.BackgroundColor3 = Color3.fromRGB(8,11,17)
Scroll.BorderSizePixel = 0
Scroll.ScrollBarThickness = 7
Scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
Scroll.CanvasSize = UDim2.new(0,0,0,0)
Scroll.Parent = Frame

LogLabel = Instance.new("TextLabel")
LogLabel.BackgroundTransparency = 1
LogLabel.Position = UDim2.fromOffset(7,5)
LogLabel.Size = UDim2.new(1,-14,0,0)
LogLabel.AutomaticSize = Enum.AutomaticSize.Y
LogLabel.Font = Enum.Font.Code
LogLabel.TextSize = 11
LogLabel.TextColor3 = Color3.fromRGB(215,225,240)
LogLabel.TextWrapped = true
LogLabel.TextXAlignment = Enum.TextXAlignment.Left
LogLabel.TextYAlignment = Enum.TextYAlignment.Top
LogLabel.Text = ""
LogLabel.Parent = Scroll

local function makeButton(text, x, cb)
    local b = Instance.new("TextButton")
    b.AnchorPoint = Vector2.new(0,1)
    b.Position = UDim2.new(x,8,1,-12)
    b.Size = UDim2.new(0.24,-10,0,50)
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

    b.MouseButton1Click:Connect(cb)
    return b
end

local npcBtn =
    makeButton(
        "ARM NPC CLICK\n12 sec",
        0,
        function()
            if installHook() then
                arm("NPC",12)
            end
        end
    )

npcBtn.BackgroundColor3 =
    Color3.fromRGB(70,70,110)

local useBtn =
    makeButton(
        "ARM USE IT\n12 sec",
        0.25,
        function()
            if installHook() then
                arm("USE",12)
            end
        end
    )

useBtn.BackgroundColor3 =
    Color3.fromRGB(45,95,70)

makeButton(
    "CAPTURE OFF",
    0.5,
    function()
        Capture.mode = "OFF"
        Capture.untilTime = 0
        log("ARM","manual OFF")
    end
)

makeButton(
    "CLEAR LOG",
    0.75,
    function()
        logs = {}
        refresh()
        flush()
        log("LOG","cleared")
    end
)

-- Drag
local dragging = false
local dragStart
local startPos

Header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
    then
        dragging = true
        dragStart = input.Position
        startPos = Frame.Position
    end
end)

UIS.InputChanged:Connect(function(input)
    if dragging and (
        input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch
    ) then
        local d = input.Position - dragStart

        Frame.Position = UDim2.new(
            startPos.X.Scale,
            startPos.X.Offset+d.X,
            startPos.Y.Scale,
            startPos.Y.Offset+d.Y
        )
    end
end)

UIS.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
    then
        dragging = false
    end
end)

task.spawn(function()
    while Gui.Parent do
        task.wait(0.1)

        if active() then
            ModeLabel.Text =
                "CAPTURE: "
                .. Capture.mode
                .. " "
                .. string.format(
                    "%.1fs",
                    Capture.untilTime-os.clock()
                )

            ModeLabel.TextColor3 =
                Color3.fromRGB(80,255,150)
        else
            ModeLabel.Text =
                "CAPTURE: OFF"

            ModeLabel.TextColor3 =
                Color3.fromRGB(170,220,255)
        end
    end
end)

installHook()

log(
    "READY",
    "ARM NPC CLICK -> click NPC; then ARM USE IT -> click Use it."
)

log(
    "INFO",
    "Exact commands appear as [CMD] lines."
)
