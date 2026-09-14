--[[
    V4 NPC + CHECK->TELEPORT TEST
    ==============================
    Button 1: Tween tới vùng NPC / Mysterious Force.
    Button 2: RaceV4Progress Check -> nếu state == 2 -> Teleport.

    Không Begin / Continue / requestEntrance.
]]

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")

local LP = Players.LocalPlayer
local CommF = RS:WaitForChild("Remotes"):WaitForChild("CommF_")

-- Runtime position ngay trước cú server jump thành công.
local NPC_POS = Vector3.new(3031, 2280, -7325)

-- Runtime-confirmed Temple landing point.
local TEMPLE_POS = Vector3.new(
    28286.35546875,
    14896.5078125,
    102.62469482421875
)

local TWEEN_SPEED = 150
local NPC_TOLERANCE = 25
local TEMPLE_TOLERANCE = 120
local OBSERVE_TIMEOUT = 8

local activeTween
local activeProxy
local proxySyncConnection
local savedCollide = {}
local busy = false

local function getCharacter()
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")

    if char and hum and root and hum.Health > 0 then
        return char, hum, root
    end
end

local function waitCharacter(timeout)
    local deadline = os.clock() + (timeout or 15)

    repeat
        local c,h,r = getCharacter()
        if r then
            return c,h,r
        end
        task.wait(0.1)
    until os.clock() >= deadline
end

local function distanceTo(pos)
    local _,_,root = getCharacter()
    if not root then
        return math.huge
    end
    return (root.Position - pos).Magnitude
end

-- ============================================================
-- UI / LOG
-- ============================================================
local logs = {}
local LogLabel
local Scroll

local function log(tag, msg)
    local line = string.format(
        "[%.3f][%s] %s",
        os.clock(),
        tostring(tag),
        tostring(msg)
    )

    logs[#logs+1] = line
    if #logs > 250 then
        table.remove(logs, 1)
    end

    print("[V4 2BTN] "..line)

    if LogLabel then
        LogLabel.Text = table.concat(logs, "\n")

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
end

-- ============================================================
-- PROXY TWEEN MOVEMENT
-- Tween an invisible anchored proxy at 150 studs/s.
-- HRP follows proxy every Heartbeat.
-- IMPORTANT: cleanupProxyMovement() fully disconnects/destroys
-- the proxy BEFORE RaceV4Progress("Teleport") is called.
-- ============================================================
local function restoreCollision()
    for part, oldValue in pairs(savedCollide) do
        if part and part.Parent then
            pcall(function()
                part.CanCollide = oldValue
            end)
        end
    end
    savedCollide = {}
end

local function cleanupProxyMovement(reason)
    if activeTween then
        pcall(function()
            activeTween:Cancel()
        end)
        pcall(function()
            activeTween:Destroy()
        end)
        activeTween = nil
    end

    if proxySyncConnection then
        pcall(function()
            proxySyncConnection:Disconnect()
        end)
        proxySyncConnection = nil
    end

    if activeProxy then
        pcall(function()
            activeProxy:Destroy()
        end)
        activeProxy = nil
    end

    restoreCollision()

    if reason then
        log("PROXY", "cleanup | "..tostring(reason))
    end
end

local function createProxy(root)
    cleanupProxyMovement()

    local proxy = Instance.new("Part")
    proxy.Name = "V4_TweenProxy"
    proxy.Size = Vector3.new(1,1,1)
    proxy.Anchored = true
    proxy.CanCollide = false
    proxy.CanTouch = false
    proxy.CanQuery = false
    proxy.Transparency = 1
    proxy.CFrame = root.CFrame
    proxy.Parent = workspace

    activeProxy = proxy

    return proxy
end

local function startProxySync(char, root, proxy)
    savedCollide = {}

    for _,obj in ipairs(char:GetDescendants()) do
        if obj:IsA("BasePart") then
            savedCollide[obj] = obj.CanCollide
            obj.CanCollide = false
        end
    end

    proxySyncConnection = RunService.Heartbeat:Connect(function()
        if not activeProxy
            or activeProxy ~= proxy
            or not proxy.Parent
            or not root.Parent
        then
            return
        end

        -- HRP follows proxy; proxy is the only object actually tweened.
        root.CFrame = proxy.CFrame

        -- Keep old momentum from fighting the proxy path.
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero

        -- Character may gain parts while moving.
        for _,obj in ipairs(char:GetDescendants()) do
            if obj:IsA("BasePart") then
                if savedCollide[obj] == nil then
                    savedCollide[obj] = obj.CanCollide
                end
                obj.CanCollide = false
            end
        end
    end)
end

-- ============================================================
-- BUTTON 1: TWEEN NPC
-- ============================================================
local function tweenToNpc()
    if busy then
        log("TWEEN", "busy=true")
        return
    end

    busy = true

    task.spawn(function()
        local char, hum, root = waitCharacter(10)

        if not root then
            log("TWEEN", "HRP not ready")
            busy = false
            return
        end

        cleanupProxyMovement()

        local before = distanceTo(NPC_POS)

        if before <= NPC_TOLERANCE then
            log(
                "TWEEN",
                "already at NPC | dist="
                .. string.format("%.1f", before)
            )
            busy = false
            return
        end

        local proxy = createProxy(root)
        startProxySync(char, root, proxy)

        local duration = math.max(
            0.05,
            before / TWEEN_SPEED
        )

        log(
            "PROXY",
            "START | dist="
            .. string.format("%.1f", before)
            .. " | speed="
            .. tostring(TWEEN_SPEED)
            .. " | eta="
            .. string.format("%.2fs", duration)
        )

        activeTween = TweenService:Create(
            proxy,
            TweenInfo.new(
                duration,
                Enum.EasingStyle.Linear
            ),
            {
                CFrame = CFrame.new(NPC_POS)
            }
        )

        activeTween:Play()

        local deadline =
            os.clock()
            + duration
            + 5

        local arrived = false

        while os.clock() < deadline do
            local d = distanceTo(NPC_POS)

            if d <= NPC_TOLERANCE then
                arrived = true
                break
            end

            if not activeTween
                or activeTween.PlaybackState
                    ~= Enum.PlaybackState.Playing
            then
                break
            end

            task.wait(0.05)
        end

        local after = distanceTo(NPC_POS)

        -- Critical: stop Heartbeat HRP sync before the next button can
        -- call the server-side RaceV4 Teleport.
        cleanupProxyMovement(
            arrived and "arrived_npc" or "tween_finished"
        )

        log(
            "PROXY",
            (arrived and "ARRIVED" or "END")
            .. " | NPCDist="
            .. string.format("%.1f", after)
            .. " | HRP="
            .. tostring(root.Position)
        )

        busy = false
    end)
end

-- ============================================================
-- BUTTON 2: CHECK -> TELEPORT
-- ============================================================
local function checkThenTeleport()
    if busy then
        log("FLOW", "busy=true")
        return
    end

    busy = true

    task.spawn(function()
        log(
            "FLOW",
            "START RaceV4Progress Check -> Teleport"
        )

        -- Never let proxy/Heartbeat movement fight the server teleport.
        cleanupProxyMovement("before_v4_check")

        local checkStart = os.clock()

        local okCheck, state = pcall(function()
            return CommF:InvokeServer(
                "RaceV4Progress",
                "Check"
            )
        end)

        log(
            "CHECK",
            "ok="
            .. tostring(okCheck)
            .. " | state="
            .. tostring(state)
            .. " | dt="
            .. string.format(
                "%.3fs",
                os.clock() - checkStart
            )
        )

        state = tonumber(state) or state

        if not okCheck then
            log("FLOW", "STOP: Check error")
            busy = false
            return
        end

        if state ~= 2 then
            log(
                "FLOW",
                "STOP: state="
                .. tostring(state)
                .. " (need state 2)"
            )
            busy = false
            return
        end

        local _,_,root = waitCharacter(5)

        if not root then
            log("FLOW", "STOP: HRP missing")
            busy = false
            return
        end

        local beforePos = root.Position
        local beforeTemple =
            (beforePos - TEMPLE_POS).Magnitude

        -- Extra safety: proxy must be completely gone before Teleport.
        cleanupProxyMovement("before_v4_teleport")
        task.wait(0.08)

        local tpStart = os.clock()

        local okTp, result = pcall(function()
            return CommF:InvokeServer(
                "RaceV4Progress",
                "Teleport"
            )
        end)

        log(
            "TELEPORT",
            "ok="
            .. tostring(okTp)
            .. " | result="
            .. tostring(result)
            .. " | dt="
            .. string.format(
                "%.3fs",
                os.clock() - tpStart
            )
            .. " | beforeTemple="
            .. string.format("%.1f", beforeTemple)
        )

        if not okTp then
            busy = false
            return
        end

        local deadline =
            os.clock() + OBSERVE_TIMEOUT

        local jumpLogged = false

        while os.clock() < deadline do
            task.wait(0.03)

            local _,_,liveRoot = getCharacter()

            if liveRoot then
                local nowPos = liveRoot.Position
                local jump =
                    (nowPos - beforePos).Magnitude
                local td =
                    (nowPos - TEMPLE_POS).Magnitude

                if jump >= 1000
                    and not jumpLogged
                then
                    jumpLogged = true

                    log(
                        "JUMP",
                        string.format(
                            "%.1f studs",
                            jump
                        )
                        .. " | FROM="
                        .. tostring(beforePos)
                        .. " | TO="
                        .. tostring(nowPos)
                        .. " | TempleDist="
                        .. string.format("%.3f", td)
                    )
                end

                if td <= TEMPLE_TOLERANCE then
                    log(
                        "SUCCESS",
                        "ARRIVED TEMPLE | dist="
                        .. string.format("%.3f", td)
                    )
                    busy = false
                    return
                end
            end
        end

        log(
            "FAIL",
            "No Temple arrival | dist="
            .. string.format(
                "%.1f",
                distanceTo(TEMPLE_POS)
            )
        )

        busy = false
    end)
end

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
        "V4NpcCheckTeleport2Button"
    )

if old then
    old:Destroy()
end

local Gui = Instance.new("ScreenGui")
Gui.Name = "V4NpcCheckTeleport2Button"
Gui.ResetOnSpawn = false
Gui.Parent = parent

local Frame = Instance.new("Frame")
Frame.Size = UDim2.fromOffset(620, 350)
Frame.Position = UDim2.new(0.5,-310,0.5,-175)
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
Header.Size = UDim2.new(1,-24,0,28)
Header.Font = Enum.Font.GothamBold
Header.TextSize = 14
Header.TextColor3 = Color3.new(1,1,1)
Header.TextXAlignment = Enum.TextXAlignment.Left
Header.Text = "V4 PROXY NPC + CHECK -> TELEPORT"
Header.Active = true
Header.Parent = Frame

Scroll = Instance.new("ScrollingFrame")
Scroll.Position = UDim2.fromOffset(12,42)
Scroll.Size = UDim2.new(1,-24,1,-112)
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

local function makeButton(text, xScale, cb)
    local b = Instance.new("TextButton")
    b.AnchorPoint = Vector2.new(0,1)
    b.Position = UDim2.new(xScale,10,1,-12)
    b.Size = UDim2.new(0.48,-14,0,50)
    b.BackgroundColor3 = Color3.fromRGB(40,47,64)
    b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamBold
    b.TextSize = 12
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

makeButton(
    "1) PROXY TWEEN TO NPC\n150 studs/s",
    0,
    tweenToNpc
)

local flowBtn = makeButton(
    "2) V4 CHECK -> TELEPORT",
    0.5,
    checkThenTeleport
)

flowBtn.BackgroundColor3 =
    Color3.fromRGB(45,95,70)

-- drag
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
            startPos.X.Offset + d.X,
            startPos.Y.Scale,
            startPos.Y.Offset + d.Y
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
    cleanupProxyMovement("character_removing")
end)

Gui.AncestryChanged:Connect(function(_, parentNow)
    if parentNow == nil then
        cleanupProxyMovement("gui_destroyed")
    end
end)

log(
    "READY",
    "1 Proxy Tween NPC -> cleanup proxy -> 2 Check -> Teleport"
)
