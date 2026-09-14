-- MYSTERIOUS FORCE - 1 BUTTON COMPACT
-- Proxy Tween 165 + Noclip + Open UI + Direct Option1

if not game:IsLoaded() then game.Loaded:Wait() end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")

local LP = Players.LocalPlayer
local PG = LP:WaitForChild("PlayerGui")

local DialogueController = require(RS:WaitForChild("DialogueController"))
local NPCManager = require(RS:WaitForChild("NPCManager"))
local DialoguesList = require(RS:WaitForChild("DialoguesList"))

local TempleTeleport = DialoguesList.TempleTeleport

local SPEED = 165
local STAND_DISTANCE = 6
local busy = false

local TEMPLE_POS = Vector3.new(
    28286.35546875,
    14896.8,
    102.625
)

local function getChar()
    return LP.Character or LP.CharacterAdded:Wait()
end

local function getHRP()
    return getChar():WaitForChild("HumanoidRootPart")
end

local function waitTemple(before, timeout)
    local deadline = os.clock() + (timeout or 4)

    while os.clock() < deadline do
        task.wait(0.05)

        local hrp = getHRP()

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

local function getNpc()
    local list = NPCManager.getNPCsByName("Mysterious Force")
    if type(list) ~= "table" then return nil end

    local worldNpc = workspace:FindFirstChild("NPCs")
    worldNpc = worldNpc and worldNpc:FindFirstChild("Mysterious Force")

    local first
    for _,npc in pairs(list) do
        if type(npc) == "table" then
            first = first or npc
            if type(npc.getModel) == "function" then
                local ok, model = pcall(function()
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
    if not npc or type(npc.getModel) ~= "function" then return nil end

    local ok, model = pcall(function()
        return npc:getModel()
    end)

    if not ok or typeof(model) ~= "Instance" then return nil end
    return model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
end

local function proxyTweenTo(cf)
    local char = getChar()
    local hrp = getHRP()

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

    local noclipConn = RunService.Heartbeat:Connect(function()
        local c = LP.Character
        if not c then return end
        for _,v in ipairs(c:GetDescendants()) do
            if v:IsA("BasePart") then
                v.CanCollide = false
            end
        end
    end)

    local syncConn = RunService.Heartbeat:Connect(function()
        local root = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if root and proxy.Parent then
            root.CFrame = proxy.CFrame
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end
    end)

    local dist = (proxy.Position - cf.Position).Magnitude
    local tween = TweenService:Create(
        proxy,
        TweenInfo.new(math.max(dist / SPEED, 0.05), Enum.EasingStyle.Linear),
        {CFrame = cf}
    )

    tween:Play()
    tween.Completed:Wait()

    if syncConn then syncConn:Disconnect() end

    hrp = getHRP()
    hrp.CFrame = cf
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero

    if proxy then proxy:Destroy() end

    -- keep noclip active until dialogue/option is completed
    return function()
        if noclipConn then noclipConn:Disconnect() end
        for part,state in pairs(oldCollide) do
            if part and part.Parent then
                part.CanCollide = state
            end
        end
    end
end

local function findGuiOption1()
    local dg = PG:FindFirstChild("DialogueGui")
    if not dg then return nil end

    for _,root in ipairs(dg:GetChildren()) do
        local options = root:FindFirstChild("optionsList")
        local scroller = options and options:FindFirstChild("scroller")

        if scroller then
            for _,container in ipairs(scroller:GetChildren()) do
                if tostring(container.Name):lower():find("option1", 1, true) then
                    local button = container:FindFirstChild("button")
                    if button and button:IsA("GuiButton") and button.Visible then
                        return button
                    end
                end
            end
        end
    end
end

local function waitGuiOption1(timeout)
    local deadline = os.clock() + (timeout or 5)
    repeat
        local b = findGuiOption1()
        if b then return b end
        task.wait(0.02)
    until os.clock() >= deadline
end

local function getActive()
    local ok, active = pcall(DialogueController.getActiveDialogue)
    if ok and type(active) == "table" then return active end
end

local function optionText(opt)
    if type(opt) ~= "table" then return "" end
    for _,k in ipairs({"_text","Text","text","Title","title"}) do
        local ok,v = pcall(function() return opt[k] end)
        if ok and type(v) == "string" then return v end
    end
    return ""
end

local function isOption(opt)
    if type(opt) ~= "table" then return false end
    local ok,fn = pcall(function() return opt.onSelected end)
    return ok and type(fn) == "function"
end

local function unwrap(v)
    if isOption(v) then return v end
    if type(v) == "table" then
        local o = rawget(v, "option")
        if isOption(o) then return o end
    end
end

local function findRealOption1(active)
    if type(active) ~= "table" then return nil end

    local best, bestScore
    local seen = {}

    local function consider(v, path, key)
        local opt = unwrap(v)
        if not opt then return end

        local p = tostring(path):lower()
        if p:find("_cancel",1,true) or p:find(".cancel",1,true) then
            return
        end

        local score = 0
        if p:find("_options",1,true) then score += 1000 end
        if p:find("option1",1,true) then score += 900 end
        if tostring(key) == "1" or tostring(key):lower() == "option1" then
            score += 800
        end
        if optionText(opt):lower():find("use it",1,true) then
            score += 2000
        end

        if not bestScore or score > bestScore then
            best = opt
            bestScore = score
        end
    end

    local function walk(tbl, depth, path)
        if type(tbl) ~= "table" or seen[tbl] or depth > 8 then return end
        seen[tbl] = true

        for k,v in pairs(tbl) do
            local childPath = path .. "." .. tostring(k)
            consider(v, childPath, k)
            if type(v) == "table" then
                walk(v, depth + 1, childPath)
            end
        end
    end

    walk(active, 0, "active")
    return best
end

local function run()
    if busy then return end
    busy = true

    task.spawn(function()
        local cleanupNoclip

        local ok, err = pcall(function()
            local npc = getNpc()
            local npcRoot = getNpcRoot(npc)
            assert(npc and npcRoot, "Mysterious Force not found")

            local target = npcRoot.CFrame * CFrame.new(0,0,-STAND_DISTANCE)
            cleanupNoclip = proxyTweenTo(target)

            pcall(DialogueController.close)
            task.wait(0.08)

            -- start() yields, so run it separately
            task.spawn(function()
                pcall(
                    DialogueController.start,
                    TempleTeleport,
                    npc
                )
            end)

            -- wait until real Option1 GUI exists
            assert(waitGuiOption1(5), "Option1 GUI not ready")

            local active = getActive()
            assert(active, "Active dialogue missing")

            local option1 = findRealOption1(active)
            assert(option1, "Real Option1 not found")

            -- runtime proved select arity = 1
            local hrp = getHRP()
            local before = hrp.Position

            local selected, selectErr = pcall(
                DialogueController.select,
                option1
            )

            assert(selected, selectErr)

            -- Wait until the server actually moves us into Temple.
            if waitTemple(before, 4) then
                -- Result dialogue:
                -- "The space tears open, and you arrive in a new place."
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
            warn("[MF]", err)
        end

        busy = false
    end)
end

-- 1 BUTTON ONLY
local parent = CoreGui
pcall(function()
    if type(gethui) == "function" then
        parent = gethui()
    end
end)

local old = parent:FindFirstChild("MF_ONE_BUTTON")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "MF_ONE_BUTTON"
gui.ResetOnSpawn = false
gui.Parent = parent

local button = Instance.new("TextButton")
button.Size = UDim2.fromOffset(260,64)
button.Position = UDim2.new(0.5,-130,0.72,0)
button.BackgroundColor3 = Color3.fromRGB(35,85,60)
button.BorderSizePixel = 0
button.Font = Enum.Font.GothamBold
button.TextSize = 14
button.TextColor3 = Color3.new(1,1,1)
button.Text = "MYSTERIOUS FORCE\nPROXY 165 + OPTION 1 + CLOSE"
button.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0,10)
corner.Parent = button

button.MouseButton1Click:Connect(run)
