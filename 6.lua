-- GREAT TREE HARD-CODED TEST
-- Banana Great Tree CFrame -> SetSpawnPoint -> reset -> verify.

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local CoreGui = game:GetService("CoreGui")

local LP = Players.LocalPlayer
local CommF =
    RS:WaitForChild("Remotes")
      :WaitForChild("CommF_")

local GREAT_TREE_CFRAME =
    CFrame.new(
        2681.2736816406,
        1682.8092041016,
        -7190.9853515625
    )

local busy = false

local function notify(title, text, duration)
    pcall(function()
        StarterGui:SetCore(
            "SendNotification",
            {
                Title = title,
                Text = tostring(text),
                Duration = duration or 5,
            }
        )
    end)

    print("[GT HARD]", title, text)
end

local function getChar(timeout)
    local deadline =
        os.clock() + (timeout or 8)

    repeat
        local char = LP.Character
        local hum =
            char and char:FindFirstChildOfClass("Humanoid")
        local root =
            char and char:FindFirstChild("HumanoidRootPart")

        if char
            and hum
            and hum.Health > 0
            and root
        then
            return char, hum, root
        end

        task.wait(0.1)
    until os.clock() >= deadline
end

local function getLastSpawn()
    local data = LP:FindFirstChild("Data")
    local value =
        data and data:FindFirstChild("LastSpawnPoint")

    return value and tostring(value.Value) or nil
end

local function waitLastSpawn(expected, timeout)
    local deadline =
        os.clock() + (timeout or 3)

    repeat
        local value = getLastSpawn()

        if value == tostring(expected) then
            return true, value
        end

        task.wait(0.05)
    until os.clock() >= deadline

    return false, getLastSpawn()
end

local function setLastSpawnScriptDisabled(char, disabled)
    local scriptObject =
        char and char:FindFirstChild("LastSpawnPoint")

    if scriptObject then
        pcall(function()
            scriptObject.Disabled = disabled
        end)
    end
end

local function waitRespawn(oldChar, timeout)
    local deadline =
        os.clock() + (timeout or 12)

    repeat
        local char = LP.Character
        local hum =
            char and char:FindFirstChildOfClass("Humanoid")
        local root =
            char and char:FindFirstChild("HumanoidRootPart")

        if char
            and char ~= oldChar
            and hum
            and hum.Health > 0
            and root
        then
            task.wait(0.35)
            return char, hum, root
        end

        task.wait(0.1)
    until os.clock() >= deadline
end

local function teleportToGreatTree(char, root)
    for _ = 1, 20 do
        if not char.Parent or not root.Parent then
            return false
        end

        pcall(function()
            char:PivotTo(GREAT_TREE_CFRAME)
            root.CFrame = GREAT_TREE_CFRAME
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end)

        task.wait(0.05)
    end

    return true
end

local function run()
    if busy then
        return
    end

    busy = true

    task.spawn(function()
        local ok, err = pcall(function()
            local char, hum, root = getChar(5)

            assert(
                char and hum and root,
                "Character missing"
            )

            notify(
                "Great Tree",
                "Teleporting to exact Banana Great Tree CFrame...",
                4
            )

            assert(
                teleportToGreatTree(char, root),
                "Great Tree teleport failed"
            )

            char, hum, root = getChar(3)

            assert(
                char and hum and root,
                "Character missing after teleport"
            )

            local currentLocation =
                LP:GetAttribute("CurrentLocation")

            notify(
                "At Great Tree",
                string.format(
                    "XYZ %.1f, %.1f, %.1f\nCurrentLocation=%s",
                    root.Position.X,
                    root.Position.Y,
                    root.Position.Z,
                    tostring(currentLocation)
                ),
                5
            )

            setLastSpawnScriptDisabled(
                char,
                true
            )

            task.wait(0.15)

            local invokeOk, ret =
                pcall(
                    CommF.InvokeServer,
                    CommF,
                    "SetSpawnPoint"
                )

            assert(
                invokeOk,
                "SetSpawnPoint failed: "
                .. tostring(ret)
            )

            local saved, value =
                waitLastSpawn(
                    "GreatTree",
                    3
                )

            assert(
                saved,
                "LastSpawnPoint="
                .. tostring(value)
                .. " instead of GreatTree"
            )

            notify(
                "Spawn Saved",
                "LastSpawnPoint = GreatTree\nResetting...",
                4
            )

            local oldChar = char

            hum.Health = 0

            local newChar, _, newRoot =
                waitRespawn(
                    oldChar,
                    12
                )

            assert(
                newChar and newRoot,
                "Respawn timeout"
            )

            setLastSpawnScriptDisabled(
                newChar,
                false
            )

            notify(
                "SUCCESS",
                string.format(
                    "Respawn XYZ %.1f, %.1f, %.1f\nLastSpawn=%s",
                    newRoot.Position.X,
                    newRoot.Position.Y,
                    newRoot.Position.Z,
                    tostring(getLastSpawn())
                ),
                8
            )
        end)

        local char = LP.Character

        if char then
            setLastSpawnScriptDisabled(
                char,
                false
            )
        end

        if not ok then
            warn("[GT HARD ERROR]", err)

            notify(
                "Great Tree ERROR",
                tostring(err),
                8
            )
        end

        busy = false
    end)
end

local parent = CoreGui

pcall(function()
    if type(gethui) == "function" then
        local h = gethui()

        if h then
            parent = h
        end
    end
end)

local old =
    parent:FindFirstChild(
        "GT_HARDCODE_TEST"
    )

if old then
    old:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "GT_HARDCODE_TEST"
gui.ResetOnSpawn = false
gui.Parent = parent

local button = Instance.new("TextButton")
button.Size = UDim2.fromOffset(320,72)
button.Position = UDim2.new(0.5,-160,0.72,0)
button.BackgroundColor3 = Color3.fromRGB(68,72,31)
button.BorderSizePixel = 0
button.Font = Enum.Font.GothamBold
button.TextSize = 13
button.TextWrapped = true
button.TextColor3 = Color3.new(1,1,1)
button.Text =
    "GREAT TREE\nHARD TP -> SET SPAWN -> RESET"
button.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0,10)
corner.Parent = button

button.MouseButton1Click:Connect(run)
