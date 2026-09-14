-- V4 NPC PROXY -> CHECK UI -> TELEPORT (2 BUTTON)
if not game:IsLoaded() then game.Loaded:Wait() end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")

local LP = Players.LocalPlayer
local PlayerGui = LP:WaitForChild("PlayerGui", 15)
local CommF = RS:WaitForChild("Remotes"):WaitForChild("CommF_")

local NPC_POS = Vector3.new(3026.8, 2281.1, -7325.4)
local TEMPLE_POS = Vector3.new(28286.35546875, 14896.8154296875, 102.625)

local TWEEN_SPEED = 150
local NPC_TOLERANCE = 25
local TEMPLE_TOLERANCE = 120
local UI_WAIT_TIMEOUT = 2.5
local TELEPORT_WAIT_TIMEOUT = 8

local busy = false
local activeTween
local activeProxy
local syncConnection
local savedCollision = {}

local logs = {}
local LogLabel
local Scroll

local function log(tag, msg)
    local line = string.format("[%.3f][%s] %s", os.clock(), tag, tostring(msg))
    logs[#logs+1] = line
    if #logs > 250 then table.remove(logs, 1) end
    print("[V4 2BTN] "..line)

    if LogLabel then
        LogLabel.Text = table.concat(logs, "\n")
        task.defer(function()
            if Scroll then
                Scroll.CanvasPosition = Vector2.new(
                    0,
                    math.max(0, Scroll.AbsoluteCanvasSize.Y - Scroll.AbsoluteWindowSize.Y)
                )
            end
        end)
    end
end

local function getCharacter()
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if char and hum and root and hum.Health > 0 then
        return char, hum, root
    end
end

local function waitCharacter(timeout)
    local deadline = os.clock() + (timeout or 10)
    repeat
        local c,h,r = getCharacter()
        if r then return c,h,r end
        task.wait(0.1)
    until os.clock() >= deadline
end

local function distanceTo(pos)
    local _,_,root = getCharacter()
    return root and (root.Position - pos).Magnitude or math.huge
end

local function restoreCollision()
    for part,old in pairs(savedCollision) do
        if part and part.Parent then
            pcall(function() part.CanCollide = old end)
        end
    end
    savedCollision = {}
end

local function cleanupProxy(reason)
    if activeTween then
        pcall(function() activeTween:Cancel() end)
        pcall(function() activeTween:Destroy() end)
        activeTween = nil
    end

    if syncConnection then
        pcall(function() syncConnection:Disconnect() end)
        syncConnection = nil
    end

    if activeProxy then
        pcall(function() activeProxy:Destroy() end)
        activeProxy = nil
    end

    restoreCollision()

    if reason then
        log("PROXY", "cleanup | "..tostring(reason))
    end
end

local function readText(obj)
    local ok, text = pcall(function()
        return tostring(obj.Text or "")
    end)
    return ok and text or ""
end

local function mysteriousUiOpen()
    for _,obj in ipairs(PlayerGui:GetDescendants()) do
        if obj:IsA("TextLabel") or obj:IsA("TextButton") then
            local s = readText(obj):lower()
            if s:find("mysterious force", 1, true)
                or s:find("remnant of the past", 1, true)
            then
                return true
            end
        end
    end
    return false
end

local function waitUi(timeout)
    local deadline = os.clock() + (timeout or UI_WAIT_TIMEOUT)
    repeat
        if mysteriousUiOpen() then return true end
        task.wait(0.05)
    until os.clock() >= deadline
    return false
end

local function valueText(v)
    if typeof(v) == "table" then
        local out = {}
        for k,val in pairs(v) do
            out[#out+1] = tostring(k).."="..tostring(val)
        end
        return "{"..table.concat(out,", ").."}"
    end
    return tostring(v)
end

-- ============================================================
-- BUTTON 1: PROXY TWEEN TO NPC
-- ============================================================
local function proxyTweenNpc()
    if busy then
        log("TWEEN", "busy=true")
        return
    end

    busy = true

    task.spawn(function()
        local char,hum,root = waitCharacter(10)
        if not root then
            log("TWEEN", "HRP missing")
            busy = false
            return
        end

        cleanupProxy()

        local dist = distanceTo(NPC_POS)
        if dist <= NPC_TOLERANCE then
            log("TWEEN", "already near NPC | dist="..string.format("%.1f",dist))
            busy = false
            return
        end

        local proxy = Instance.new("Part")
        proxy.Name = "V4_NPC_TweenProxy"
        proxy.Size = Vector3.new(1,1,1)
        proxy.Anchored = true
        proxy.CanCollide = false
        proxy.CanTouch = false
        proxy.CanQuery = false
        proxy.Transparency = 1
        proxy.CFrame = root.CFrame
        proxy.Parent = workspace
        activeProxy = proxy

        for _,obj in ipairs(char:GetDescendants()) do
            if obj:IsA("BasePart") then
                savedCollision[obj] = obj.CanCollide
                obj.CanCollide = false
            end
        end

        syncConnection = RunService.Heartbeat:Connect(function()
            if not activeProxy or activeProxy ~= proxy or not proxy.Parent or not root.Parent then
                return
            end

            root.CFrame = proxy.CFrame
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero

            for _,obj in ipairs(char:GetDescendants()) do
                if obj:IsA("BasePart") then
                    if savedCollision[obj] == nil then
                        savedCollision[obj] = obj.CanCollide
                    end
                    obj.CanCollide = false
                end
            end
        end)

        local duration = math.max(0.05, dist / TWEEN_SPEED)

        log(
            "TWEEN",
            "START | dist="..string.format("%.1f",dist)
            .." | speed="..TWEEN_SPEED
            .." | eta="..string.format("%.2fs",duration)
        )

        activeTween = TweenService:Create(
            proxy,
            TweenInfo.new(duration, Enum.EasingStyle.Linear),
            {CFrame = CFrame.new(NPC_POS)}
        )

        activeTween:Play()

        local deadline = os.clock() + duration + 5
        local arrived = false

        while os.clock() < deadline do
            local d = distanceTo(NPC_POS)
            if d <= NPC_TOLERANCE then
                arrived = true
                break
            end

            if not activeTween
                or activeTween.PlaybackState ~= Enum.PlaybackState.Playing
            then
                break
            end

            task.wait(0.05)
        end

        local finalDist = distanceTo(NPC_POS)
        cleanupProxy(arrived and "arrived_npc" or "tween_end")

        log(
            "TWEEN",
            (arrived and "ARRIVED" or "END")
            .." | NPCDist="..string.format("%.1f",finalDist)
            .." | HRP="..tostring(root.Position)
        )

        busy = false
    end)
end

-- ============================================================
-- BUTTON 2: CHECK -> OPEN UI -> TELEPORT
-- ============================================================
local function checkUiTeleport()
    if busy then
        log("FLOW", "busy=true")
        return
    end

    busy = true

    task.spawn(function()
        cleanupProxy("before_check")
        task.wait(0.08)

        local _,_,root = waitCharacter(5)
        if not root then
            log("FLOW", "HRP missing")
            busy = false
            return
        end

        local beforePos = root.Position

        local checkStart = os.clock()
        local okCheck, checkReturn = pcall(function()
            return CommF:InvokeServer("RaceV4Progress", "Check")
        end)

        log(
            "CHECK",
            "ok="..tostring(okCheck)
            .." | return="..valueText(checkReturn)
            .." | type="..typeof(checkReturn)
            .." | dt="..string.format("%.4fs",os.clock()-checkStart)
        )

        if not okCheck then
            busy = false
            return
        end

        local opened = waitUi(UI_WAIT_TIMEOUT)

        log(
            "UI",
            "Mysterious Force OPEN="..tostring(opened)
        )

        -- Do not hard-lock to state 2.
        -- Runtime tests showed Check return 4 can still Teleport successfully.
        cleanupProxy("before_teleport")
        task.wait(0.08)

        local tpStart = os.clock()
        local okTp, tpReturn = pcall(function()
            return CommF:InvokeServer("RaceV4Progress", "Teleport")
        end)

        log(
            "TELEPORT",
            "ok="..tostring(okTp)
            .." | return="..valueText(tpReturn)
            .." | type="..typeof(tpReturn)
            .." | dt="..string.format("%.4fs",os.clock()-tpStart)
        )

        if not okTp then
            busy = false
            return
        end

        local deadline = os.clock() + TELEPORT_WAIT_TIMEOUT
        local jumpLogged = false

        while os.clock() < deadline do
            task.wait(0.03)

            local _,_,liveRoot = getCharacter()
            if liveRoot then
                local pos = liveRoot.Position
                local jump = (pos - beforePos).Magnitude
                local templeDist = (pos - TEMPLE_POS).Magnitude

                if jump >= 1000 and not jumpLogged then
                    jumpLogged = true
                    log(
                        "JUMP",
                        string.format("%.1f studs",jump)
                        .." | FROM="..tostring(beforePos)
                        .." | TO="..tostring(pos)
                        .." | TempleDist="..string.format("%.3f",templeDist)
                    )
                end

                if templeDist <= TEMPLE_TOLERANCE then
                    log(
                        "SUCCESS",
                        "ARRIVED TEMPLE | TempleDist="
                        ..string.format("%.3f",templeDist)
                    )
                    busy = false
                    return
                end
            end
        end

        log(
            "FAIL",
            "Temple arrival not confirmed | dist="
            ..string.format("%.1f",distanceTo(TEMPLE_POS))
        )

        busy = false
    end)
end

-- ============================================================
-- GUI
-- ============================================================
local parent = CoreGui
pcall(function()
    if type(gethui) == "function" then parent = gethui() end
end)

local old = parent:FindFirstChild("V4NpcCheckUiTeleport2Button")
if old then old:Destroy() end

local Gui = Instance.new("ScreenGui")
Gui.Name = "V4NpcCheckUiTeleport2Button"
Gui.ResetOnSpawn = false
Gui.Parent = parent

local Frame = Instance.new("Frame")
Frame.Size = UDim2.fromOffset(650,370)
Frame.Position = UDim2.new(0.5,-325,0.5,-185)
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
Header.Size = UDim2.new(1,-24,0,28)
Header.Font = Enum.Font.GothamBold
Header.TextSize = 14
Header.TextColor3 = Color3.new(1,1,1)
Header.TextXAlignment = Enum.TextXAlignment.Left
Header.Text = "V4 NPC -> CHECK UI -> TELEPORT"
Header.Active = true
Header.Parent = Frame

Scroll = Instance.new("ScrollingFrame")
Scroll.Position = UDim2.fromOffset(12,42)
Scroll.Size = UDim2.new(1,-24,1,-118)
Scroll.BackgroundColor3 = Color3.fromRGB(8,11,17)
Scroll.BorderSizePixel = 0
Scroll.ScrollBarThickness = 10
Scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
Scroll.CanvasSize = UDim2.new(0,0,0,0)
Scroll.Parent = Frame

LogLabel = Instance.new("TextLabel")
LogLabel.BackgroundTransparency = 1
LogLabel.Position = UDim2.fromOffset(7,5)
LogLabel.Size = UDim2.new(1,-18,0,0)
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
    b.Position = UDim2.new(x,10,1,-12)
    b.Size = UDim2.new(0.48,-14,0,54)
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

makeButton(
    "1) PROXY TWEEN TO NPC\n150 studs/s",
    0,
    proxyTweenNpc
)

local flowButton = makeButton(
    "2) OPEN UI\nCHECK -> TELEPORT",
    0.5,
    checkUiTeleport
)

flowButton.BackgroundColor3 = Color3.fromRGB(45,95,70)

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

LP.CharacterRemoving:Connect(function()
    cleanupProxy("character_removing")
end)

Gui.AncestryChanged:Connect(function(_,p)
    if p == nil then
        cleanupProxy("gui_destroyed")
    end
end)

log(
    "READY",
    "Button1 Proxy Tween NPC | Button2 Check -> wait UI -> Teleport"
)
