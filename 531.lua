-- GREAT TREE TEST + TEMPLE UI OPTION1
-- Button 1: Set nearest Great Tree spawn + reset
-- Button 2: Proxy tween 165 + noclip + open Mysterious Force + direct Option1 + auto close result

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")

local LP = Players.LocalPlayer
local PG = LP:WaitForChild("PlayerGui")
local CommF = RS:WaitForChild("Remotes"):WaitForChild("CommF_")

local DialogueController = require(RS:WaitForChild("DialogueController"))
local NPCManager = require(RS:WaitForChild("NPCManager"))
local DialoguesList = require(RS:WaitForChild("DialoguesList"))
local TempleTeleport = DialoguesList.TempleTeleport

local SPEED = 165
local STAND_DISTANCE = 6

-- Great Tree reference from the user's island teleport mapping.
-- Only X/Z are used to choose the nearest REAL PlayerSpawn.
local GREAT_TREE_REF =
    Vector3.new(
        2681.2736816406,
        1682.8092041016,
        -7190.9853515625
    )

local TEMPLE_POS =
    Vector3.new(
        28286.35546875,
        14896.8,
        102.625
    )

local busySpawn = false
local busyTemple = false

local function notify(title, text)
    pcall(function()
        game:GetService("StarterGui"):SetCore(
            "SendNotification",
            {
                Title = title,
                Text = text,
                Duration = 4,
            }
        )
    end)
end

local function getChar(timeout)
    local deadline = os.clock() + (timeout or 8)

    repeat
        local c = LP.Character
        local h = c and c:FindFirstChildOfClass("Humanoid")
        local r = c and c:FindFirstChild("HumanoidRootPart")

        if c and h and h.Health > 0 and r then
            return c,h,r
        end

        task.wait(0.1)
    until os.clock() >= deadline
end

local function getObjectPosition(obj)
    if obj:IsA("BasePart") then
        return obj.Position
    end

    if obj:IsA("Model") then
        local ok, cf = pcall(function()
            return obj:GetPivot()
        end)

        if ok then
            return cf.Position
        end
    end
end

local function horizontalDistance(a,b)
    return (
        Vector2.new(a.X, a.Z)
        - Vector2.new(b.X, b.Z)
    ).Magnitude
end

-- Scan the game's real PlayerSpawns and pick the one nearest Great Tree.
local function findGreatTreeSpawn()
    local origin = workspace:FindFirstChild("_WorldOrigin")
    local folder = origin and origin:FindFirstChild("PlayerSpawns")

    if not folder then
        return nil, math.huge
    end

    local best = nil
    local bestDist = math.huge

    for _,group in ipairs(folder:GetChildren()) do
        if group:IsA("Folder") or group:IsA("Model") then
            for _,spawnObj in ipairs(group:GetChildren()) do
                if spawnObj:IsA("BasePart") or spawnObj:IsA("Model") then
                    local pos = getObjectPosition(spawnObj)

                    if pos then
                        local d = horizontalDistance(pos, GREAT_TREE_REF)

                        if d < bestDist then
                            bestDist = d
                            best = {
                                Name = tostring(spawnObj.Name),
                                Group = tostring(group.Name),
                                Object = spawnObj,
                                Position = pos,
                            }
                        end
                    end
                end
            end
        elseif group:IsA("BasePart") then
            local pos = group.Position
            local d = horizontalDistance(pos, GREAT_TREE_REF)

            if d < bestDist then
                bestDist = d
                best = {
                    Name = tostring(group.Name),
                    Group = "PlayerSpawns",
                    Object = group,
                    Position = pos,
                }
            end
        end
    end

    return best,bestDist
end

local function setLastSpawnScriptDisabled(char, disabled)
    local s = char and char:FindFirstChild("LastSpawnPoint")

    if s then
        pcall(function()
            s.Disabled = disabled
        end)
    end
end

local function waitSpawnValue(name, timeout)
    local deadline = os.clock() + (timeout or 2.5)

    repeat
        local data = LP:FindFirstChild("Data")
        local value = data and data:FindFirstChild("LastSpawnPoint")

        if value and tostring(value.Value) == tostring(name) then
            return true
        end

        task.wait(0.05)
    until os.clock() >= deadline

    return false
end

local function waitRespawn(oldChar, timeout)
    local deadline = os.clock() + (timeout or 12)

    repeat
        local c = LP.Character
        local h = c and c:FindFirstChildOfClass("Humanoid")
        local r = c and c:FindFirstChild("HumanoidRootPart")

        if c
            and c ~= oldChar
            and h
            and h.Health > 0
            and r
        then
            task.wait(0.3)
            return c,h,r
        end

        task.wait(0.1)
    until os.clock() >= deadline
end

local function setSpawnGreatTreeAndReset()
    if busySpawn then
        return
    end

    busySpawn = true

    task.spawn(function()
        local ok, err = pcall(function()
            local spawnData, refDist = findGreatTreeSpawn()

            assert(
                spawnData,
                "PlayerSpawns / Great Tree spawn not found"
            )

            notify(
                "Great Tree Spawn",
                string.format(
                    "Candidate: %s | group: %s | XZ ref dist: %.0f",
                    spawnData.Name,
                    spawnData.Group,
                    refDist
                )
            )

            local char, hum =
                getChar(5)

            assert(char and hum, "Character missing")

            setLastSpawnScriptDisabled(char, true)
            task.wait()

            local invoked, remoteRet =
                pcall(
                    CommF.InvokeServer,
                    CommF,
                    "SetLastSpawnPoint",
                    spawnData.Name
                )

            assert(
                invoked,
                "SetLastSpawnPoint remote failed: "
                .. tostring(remoteRet)
            )

            assert(
                waitSpawnValue(
                    spawnData.Name,
                    2.5
                ),
                "Data.LastSpawnPoint did not become "
                .. spawnData.Name
            )

            notify(
                "Great Tree Spawn",
                "Set OK: "
                .. spawnData.Name
                .. " | resetting..."
            )

            local oldChar = char

            pcall(function()
                hum.Health = 0
            end)

            local newChar, _, newRoot =
                waitRespawn(oldChar, 12)

            assert(
                newChar and newRoot,
                "Respawn timeout"
            )

            setLastSpawnScriptDisabled(
                newChar,
                false
            )

            local toSpawn =
                (newRoot.Position-spawnData.Position).Magnitude

            local toGreatTreeXZ =
                horizontalDistance(
                    newRoot.Position,
                    GREAT_TREE_REF
                )

            notify(
                "Great Tree Spawn",
                string.format(
                    "Respawned | spawn dist %.0f | GreatTree XZ %.0f",
                    toSpawn,
                    toGreatTreeXZ
                )
            )
        end)

        -- Make sure LastSpawnPoint script is re-enabled even after failure.
        local char = LP.Character
        if char then
            setLastSpawnScriptDisabled(
                char,
                false
            )
        end

        if not ok then
            warn("[GT SPAWN]", err)
            notify(
                "Great Tree Spawn ERROR",
                tostring(err)
            )
        end

        busySpawn = false
    end)
end

-- ============================================================
-- TEMPLE FLOW: proxy tween 165 + noclip + UI + direct Option1
-- ============================================================

local function getNpc()
    local list =
        NPCManager.getNPCsByName(
            "Mysterious Force"
        )

    if type(list) ~= "table" then
        return nil
    end

    local worldNpc =
        workspace:FindFirstChild("NPCs")

    worldNpc =
        worldNpc
        and worldNpc:FindFirstChild(
            "Mysterious Force"
        )

    local first

    for _,npc in pairs(list) do
        if type(npc) == "table" then
            first = first or npc

            if type(npc.getModel) == "function" then
                local ok, model =
                    pcall(function()
                        return npc:getModel()
                    end)

                if ok and model == worldNpc then
                    return npc
                end
            end
        end
    end

    return first
end

local function getNpcRoot(npc)
    if not npc
        or type(npc.getModel) ~= "function"
    then
        return nil
    end

    local ok, model =
        pcall(function()
            return npc:getModel()
        end)

    if not ok
        or typeof(model) ~= "Instance"
    then
        return nil
    end

    return model:FindFirstChild(
        "HumanoidRootPart"
    ) or model.PrimaryPart
end

local function proxyTweenTo(cf)
    local char,_,hrp = getChar(5)
    assert(char and hrp, "Character missing")

    local proxy = Instance.new("Part")
    proxy.Name = "_MF_PROXY"
    proxy.Size = Vector3.new(1,1,1)
    proxy.Transparency = 1
    proxy.Anchored = true
    proxy.CanCollide = false
    proxy.CFrame = hrp.CFrame
    proxy.Parent = workspace

    local oldCollide = {}

    for _,v in ipairs(char:GetDescendants()) do
        if v:IsA("BasePart") then
            oldCollide[v] = v.CanCollide
            v.CanCollide = false
        end
    end

    local noclipConn =
        RunService.Heartbeat:Connect(function()
            local c = LP.Character

            if c then
                for _,v in ipairs(c:GetDescendants()) do
                    if v:IsA("BasePart") then
                        v.CanCollide = false
                    end
                end
            end
        end)

    local syncConn =
        RunService.Heartbeat:Connect(function()
            local c = LP.Character
            local root =
                c and c:FindFirstChild(
                    "HumanoidRootPart"
                )

            if root and proxy.Parent then
                root.CFrame = proxy.CFrame
                root.AssemblyLinearVelocity =
                    Vector3.zero
                root.AssemblyAngularVelocity =
                    Vector3.zero
            end
        end)

    local dist =
        (proxy.Position-cf.Position).Magnitude

    local tween =
        TweenService:Create(
            proxy,
            TweenInfo.new(
                math.max(dist/SPEED,0.05),
                Enum.EasingStyle.Linear
            ),
            {
                CFrame=cf
            }
        )

    tween:Play()
    tween.Completed:Wait()

    syncConn:Disconnect()

    local _,_,root = getChar(3)
    if root then
        root.CFrame = cf
        root.AssemblyLinearVelocity =
            Vector3.zero
        root.AssemblyAngularVelocity =
            Vector3.zero
    end

    proxy:Destroy()

    return function()
        if noclipConn then
            noclipConn:Disconnect()
        end

        for part,state in pairs(oldCollide) do
            if part and part.Parent then
                part.CanCollide = state
            end
        end
    end
end

local function findGuiOption1()
    local dg = PG:FindFirstChild("DialogueGui")

    if not dg then
        return nil
    end

    for _,root in ipairs(dg:GetChildren()) do
        local options =
            root:FindFirstChild("optionsList")

        local scroller =
            options
            and options:FindFirstChild(
                "scroller"
            )

        if scroller then
            for _,container in ipairs(
                scroller:GetChildren()
            ) do
                local name =
                    tostring(container.Name)
                    :lower()

                if name:find(
                    "option1",
                    1,
                    true
                ) then
                    local b =
                        container:FindFirstChild(
                            "button"
                        )

                    if b
                        and b:IsA("GuiButton")
                        and b.Visible
                    then
                        return b
                    end
                end
            end
        end
    end
end

local function waitGuiOption1(timeout)
    local deadline =
        os.clock()
        + (timeout or 5)

    repeat
        local b = findGuiOption1()

        if b then
            return b
        end

        task.wait(0.02)
    until os.clock() >= deadline
end

local function getActive()
    local ok, active =
        pcall(
            DialogueController.getActiveDialogue
        )

    if ok and type(active) == "table" then
        return active
    end
end

local function optionText(opt)
    if type(opt) ~= "table" then
        return ""
    end

    for _,k in ipairs({
        "_text",
        "Text",
        "text",
        "Title",
        "title",
    }) do
        local ok,v =
            pcall(function()
                return opt[k]
            end)

        if ok and type(v) == "string" then
            return v
        end
    end

    return ""
end

local function isOption(opt)
    if type(opt) ~= "table" then
        return false
    end

    local ok,fn =
        pcall(function()
            return opt.onSelected
        end)

    return ok
        and type(fn) == "function"
end

local function unwrap(v)
    if isOption(v) then
        return v
    end

    if type(v) == "table" then
        local o = rawget(v,"option")

        if isOption(o) then
            return o
        end
    end
end

local function findRealOption1(active)
    local best,bestScore
    local seen = {}

    local function consider(v,path,key)
        local opt = unwrap(v)

        if not opt then
            return
        end

        local p = tostring(path):lower()

        if p:find("_cancel",1,true)
            or p:find(".cancel",1,true)
        then
            return
        end

        local score = 0

        if p:find("_options",1,true) then
            score += 1000
        end

        if p:find("option1",1,true) then
            score += 900
        end

        if tostring(key) == "1"
            or tostring(key):lower()
                == "option1"
        then
            score += 800
        end

        if optionText(opt)
            :lower()
            :find("use it",1,true)
        then
            score += 2000
        end

        if not bestScore
            or score > bestScore
        then
            best = opt
            bestScore = score
        end
    end

    local function walk(tbl,depth,path)
        if type(tbl) ~= "table"
            or seen[tbl]
            or depth > 8
        then
            return
        end

        seen[tbl] = true

        for k,v in pairs(tbl) do
            local child =
                path.."."..tostring(k)

            consider(v,child,k)

            if type(v) == "table" then
                walk(
                    v,
                    depth+1,
                    child
                )
            end
        end
    end

    walk(active,0,"active")
    return best
end

local function waitTemple(before,timeout)
    local deadline =
        os.clock()
        + (timeout or 4)

    while os.clock() < deadline do
        task.wait(0.05)

        local _,_,hrp =
            getChar(1)

        if hrp and before then
            local jump =
                (hrp.Position-before).Magnitude

            local templeDist =
                (hrp.Position-TEMPLE_POS).Magnitude

            if jump > 1000
                or templeDist < 500
            then
                return true
            end
        end
    end

    return false
end

local function runTemple()
    if busyTemple then
        return
    end

    busyTemple = true

    task.spawn(function()
        local cleanupNoclip

        local ok,err =
            pcall(function()
                local npc = getNpc()
                local npcRoot =
                    getNpcRoot(npc)

                assert(
                    npc and npcRoot,
                    "Mysterious Force not found"
                )

                local target =
                    npcRoot.CFrame
                    * CFrame.new(
                        0,
                        0,
                        -STAND_DISTANCE
                    )

                cleanupNoclip =
                    proxyTweenTo(target)

                pcall(
                    DialogueController.close
                )

                task.wait(0.08)

                -- start() yields while the dialogue is open.
                task.spawn(function()
                    pcall(
                        DialogueController.start,
                        TempleTeleport,
                        npc
                    )
                end)

                assert(
                    waitGuiOption1(5),
                    "Option1 GUI not ready"
                )

                local active = getActive()

                assert(
                    active,
                    "Active dialogue missing"
                )

                local option1 =
                    findRealOption1(active)

                assert(
                    option1,
                    "Real Option1 not found"
                )

                local _,_,hrp =
                    getChar(2)

                local before =
                    hrp and hrp.Position

                local selected,selectErr =
                    pcall(
                        DialogueController.select,
                        option1
                    )

                assert(selected,selectErr)

                if before
                    and waitTemple(before,4)
                then
                    task.wait(0.25)

                    pcall(
                        DialogueController.close
                    )
                end
            end)

        if cleanupNoclip then
            cleanupNoclip()
        end

        if not ok then
            warn("[TEMPLE]",err)

            notify(
                "Temple ERROR",
                tostring(err)
            )
        end

        busyTemple = false
    end)
end

-- ============================================================
-- 2 BUTTON TEST UI
-- ============================================================

local parent = CoreGui

pcall(function()
    if type(gethui) == "function" then
        parent = gethui()
    end
end)

local old =
    parent:FindFirstChild(
        "GT_TEMPLE_TEST"
    )

if old then
    old:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "GT_TEMPLE_TEST"
gui.ResetOnSpawn = false
gui.Parent = parent

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(560,74)
frame.Position = UDim2.new(0.5,-280,0.72,0)
frame.BackgroundColor3 = Color3.fromRGB(18,21,29)
frame.BorderSizePixel = 0
frame.Parent = gui

local fc = Instance.new("UICorner")
fc.CornerRadius = UDim.new(0,10)
fc.Parent = frame

local spawnButton = Instance.new("TextButton")
spawnButton.Size = UDim2.new(0.5,-8,1,-12)
spawnButton.Position = UDim2.fromOffset(6,6)
spawnButton.BackgroundColor3 = Color3.fromRGB(78,62,35)
spawnButton.BorderSizePixel = 0
spawnButton.Font = Enum.Font.GothamBold
spawnButton.TextSize = 12
spawnButton.TextWrapped = true
spawnButton.TextColor3 = Color3.new(1,1,1)
spawnButton.Text =
    "SET SPAWN GREAT TREE\n+ RESET"
spawnButton.Parent = frame

local sc = Instance.new("UICorner")
sc.CornerRadius = UDim.new(0,8)
sc.Parent = spawnButton

local templeButton = Instance.new("TextButton")
templeButton.Size = UDim2.new(0.5,-8,1,-12)
templeButton.Position = UDim2.new(0.5,2,0,6)
templeButton.BackgroundColor3 = Color3.fromRGB(35,85,60)
templeButton.BorderSizePixel = 0
templeButton.Font = Enum.Font.GothamBold
templeButton.TextSize = 12
templeButton.TextWrapped = true
templeButton.TextColor3 = Color3.new(1,1,1)
templeButton.Text =
    "TEMPLE\nPROXY 165 + OPTION1"
templeButton.Parent = frame

local tc = Instance.new("UICorner")
tc.CornerRadius = UDim.new(0,8)
tc.Parent = templeButton

spawnButton.MouseButton1Click:Connect(
    setSpawnGreatTreeAndReset
)

templeButton.MouseButton1Click:Connect(
    runTemple
)
