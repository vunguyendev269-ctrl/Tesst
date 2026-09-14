-- GREAT TREE SPAWN RESET - CLEAN TEST
-- One button:
-- scan real PlayerSpawns nearest Great Tree reference
-- -> SetLastSpawnPoint
-- -> verify Data.LastSpawnPoint
-- -> kill character
-- -> verify respawn position

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

local GREAT_TREE_REF =
    Vector3.new(
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

    print("[GT SPAWN]", title, text)
end

local function getChar(timeout)
    local deadline =
        os.clock()
        + (timeout or 8)

    repeat
        local char = LP.Character
        local hum =
            char
            and char:FindFirstChildOfClass("Humanoid")

        local root =
            char
            and char:FindFirstChild("HumanoidRootPart")

        if char
            and hum
            and hum.Health > 0
            and root
        then
            return char,hum,root
        end

        task.wait(0.1)
    until os.clock() >= deadline
end

local function objectPosition(obj)
    if obj:IsA("BasePart") then
        return obj.Position
    end

    if obj:IsA("Model") then
        local ok,cf =
            pcall(function()
                return obj:GetPivot()
            end)

        if ok then
            return cf.Position
        end
    end
end

local function xzDistance(a,b)
    local dx = a.X - b.X
    local dz = a.Z - b.Z

    return math.sqrt(
        dx*dx + dz*dz
    )
end

local function findGreatTreeSpawn()
    local origin =
        workspace:FindFirstChild("_WorldOrigin")

    local folder =
        origin
        and origin:FindFirstChild("PlayerSpawns")

    if not folder then
        return nil,
            "workspace._WorldOrigin.PlayerSpawns missing"
    end

    local best = nil
    local bestDist = math.huge
    local count = 0

    for _,group in ipairs(folder:GetChildren()) do
        if group:IsA("Folder")
            or group:IsA("Model")
        then
            for _,obj in ipairs(group:GetChildren()) do
                if obj:IsA("BasePart")
                    or obj:IsA("Model")
                then
                    local pos = objectPosition(obj)

                    if pos then
                        count += 1

                        local d =
                            xzDistance(
                                pos,
                                GREAT_TREE_REF
                            )

                        if d < bestDist then
                            bestDist = d
                            best = {
                                Name = tostring(obj.Name),
                                Group = tostring(group.Name),
                                Position = pos,
                                Object = obj,
                            }
                        end
                    end
                end
            end

        elseif group:IsA("BasePart") then
            count += 1

            local pos = group.Position
            local d =
                xzDistance(
                    pos,
                    GREAT_TREE_REF
                )

            if d < bestDist then
                bestDist = d
                best = {
                    Name = tostring(group.Name),
                    Group = "PlayerSpawns",
                    Position = pos,
                    Object = group,
                }
            end
        end
    end

    if not best then
        return nil,
            "no valid spawn found; scanned "
            .. tostring(count)
    end

    best.RefDistance = bestDist
    best.TotalScanned = count

    return best
end

local function setLastSpawnScript(char, disabled)
    local s =
        char
        and char:FindFirstChild("LastSpawnPoint")

    if s then
        pcall(function()
            s.Disabled = disabled
        end)
    end
end

local function getLastSpawnValue()
    local data = LP:FindFirstChild("Data")
    local value =
        data
        and data:FindFirstChild("LastSpawnPoint")

    return value,
        value
        and tostring(value.Value)
        or nil
end

local function waitLastSpawn(expected, timeout)
    local deadline =
        os.clock()
        + (timeout or 3)

    repeat
        local _,value = getLastSpawnValue()

        if value == tostring(expected) then
            return true,value
        end

        task.wait(0.05)
    until os.clock() >= deadline

    local _,value = getLastSpawnValue()

    return false,value
end

local function waitRespawn(oldChar, timeout)
    local deadline =
        os.clock()
        + (timeout or 12)

    repeat
        local char = LP.Character

        local hum =
            char
            and char:FindFirstChildOfClass("Humanoid")

        local root =
            char
            and char:FindFirstChild("HumanoidRootPart")

        if char
            and char ~= oldChar
            and hum
            and hum.Health > 0
            and root
        then
            task.wait(0.35)
            return char,hum,root
        end

        task.wait(0.1)
    until os.clock() >= deadline
end

local function run()
    if busy then
        return
    end

    busy = true

    task.spawn(function()
        local ok,err =
            pcall(function()
                local spawnData,findErr =
                    findGreatTreeSpawn()

                assert(spawnData, findErr)

                notify(
                    "Great Tree Candidate",
                    string.format(
                        "%s / %s\nXYZ %.0f, %.0f, %.0f\nGT XZ dist %.0f | scanned %d",
                        spawnData.Group,
                        spawnData.Name,
                        spawnData.Position.X,
                        spawnData.Position.Y,
                        spawnData.Position.Z,
                        spawnData.RefDistance,
                        spawnData.TotalScanned
                    ),
                    7
                )

                local char,hum,root =
                    getChar(5)

                assert(
                    char and hum and root,
                    "Character missing"
                )

                local before = root.Position
                local _,oldSpawn =
                    getLastSpawnValue()

                notify(
                    "Before",
                    string.format(
                        "LastSpawn=%s\nXYZ %.0f, %.0f, %.0f",
                        tostring(oldSpawn),
                        before.X,
                        before.Y,
                        before.Z
                    ),
                    5
                )

                setLastSpawnScript(char, true)
                task.wait()

                local invoked,remoteResult =
                    pcall(
                        CommF.InvokeServer,
                        CommF,
                        "SetLastSpawnPoint",
                        spawnData.Name
                    )

                assert(
                    invoked,
                    "SetLastSpawnPoint InvokeServer failed: "
                    .. tostring(remoteResult)
                )

                local confirmed,currentValue =
                    waitLastSpawn(
                        spawnData.Name,
                        3
                    )

                assert(
                    confirmed,
                    "server call returned but LastSpawnPoint is "
                    .. tostring(currentValue)
                    .. " instead of "
                    .. tostring(spawnData.Name)
                )

                notify(
                    "Set Spawn OK",
                    "LastSpawnPoint = "
                    .. tostring(spawnData.Name)
                    .. "\nResetting character...",
                    5
                )

                local oldChar = char
                hum.Health = 0

                local newChar,_,newRoot =
                    waitRespawn(
                        oldChar,
                        12
                    )

                assert(
                    newChar and newRoot,
                    "respawn timeout"
                )

                setLastSpawnScript(
                    newChar,
                    false
                )

                local respawnPos =
                    newRoot.Position

                local spawnDist =
                    (
                        respawnPos
                        - spawnData.Position
                    ).Magnitude

                local gtXZ =
                    xzDistance(
                        respawnPos,
                        GREAT_TREE_REF
                    )

                notify(
                    "Respawn Result",
                    string.format(
                        "XYZ %.0f, %.0f, %.0f\nspawn dist %.0f | GT XZ %.0f",
                        respawnPos.X,
                        respawnPos.Y,
                        respawnPos.Z,
                        spawnDist,
                        gtXZ
                    ),
                    8
                )
            end)

        local char = LP.Character

        if char then
            setLastSpawnScript(
                char,
                false
            )
        end

        if not ok then
            warn("[GT SPAWN ERROR]", err)

            notify(
                "Great Tree Spawn ERROR",
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
        "GT_SPAWN_CLEAN_TEST"
    )

if old then
    old:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "GT_SPAWN_CLEAN_TEST"
gui.ResetOnSpawn = false
gui.Parent = parent

local button = Instance.new("TextButton")
button.Size = UDim2.fromOffset(300,68)
button.Position = UDim2.new(0.5,-150,0.72,0)
button.BackgroundColor3 = Color3.fromRGB(80,62,32)
button.BorderSizePixel = 0
button.Font = Enum.Font.GothamBold
button.TextSize = 13
button.TextColor3 = Color3.new(1,1,1)
button.Text =
    "TEST SET SPAWN GREAT TREE\n+ RESET"
button.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0,10)
corner.Parent = button

button.MouseButton1Click:Connect(run)
