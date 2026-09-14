-- MYSTERIOUS FORCE - NEAR NPC -> OPEN UI -> OPTION1 DEBUG
-- Flow:
--   save current position
--   tween HRP to ~6 studs in front of Mysterious Force (150 studs/s)
--   open TempleTeleport dialogue
--   find Option1 / Use it
--   trigger through DialogueController.select(option)
--   fallback option:onSelected()
--   watch for the ~29k server teleport
--   restore original position only if teleport does not happen
--
-- No network hooks.
-- No direct InvokeServer / FireServer.

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")

local LP = Players.LocalPlayer
local PlayerGui = LP:WaitForChild("PlayerGui", 15)

local DialogueController =
    require(RS:WaitForChild("DialogueController"))

local NPCManager =
    require(RS:WaitForChild("NPCManager"))

local DialoguesList =
    require(RS:WaitForChild("DialoguesList"))

local TempleTeleport =
    DialoguesList.TempleTeleport

local TWEEN_SPEED = 150
local STAND_DISTANCE = 6
local ARRIVE_DISTANCE = 8
local JUMP_THRESHOLD = 1000
local JUMP_WAIT = 3

local logs = {}
local LogLabel
local Scroll
local StatusLabel
local busy = false

local cachedNPC = nil
local cachedOption = nil

local function log(...)
    local parts = {}

    for i = 1, select("#", ...) do
        parts[#parts+1] =
            tostring(select(i, ...))
    end

    local line =
        string.format(
            "[%.3f] %s",
            os.clock(),
            table.concat(parts, " ")
        )

    logs[#logs+1] = line

    if #logs > 700 then
        table.remove(logs, 1)
    end

    print("[MF NEAR NPC]", line)

    if LogLabel then
        LogLabel.Text =
            table.concat(logs, "\n")
    end

    if Scroll then
        task.defer(function()
            Scroll.CanvasPosition =
                Vector2.new(
                    0,
                    math.max(
                        0,
                        Scroll.AbsoluteCanvasSize.Y
                            - Scroll.AbsoluteWindowSize.Y
                    )
                )
        end)
    end
end

local function setStatus(text, running)
    if not StatusLabel then
        return
    end

    StatusLabel.Text = text

    if running then
        StatusLabel.TextColor3 =
            Color3.fromRGB(80,255,150)
    else
        StatusLabel.TextColor3 =
            Color3.fromRGB(170,220,255)
    end
end

local function getCharacter()
    local char = LP.Character

    if not char then
        char = LP.CharacterAdded:Wait()
    end

    return char
end

local function getRootPart()
    local char = getCharacter()

    return char:FindFirstChild(
        "HumanoidRootPart"
    )
end

local function safeFullName(inst)
    if typeof(inst) ~= "Instance" then
        return tostring(inst)
    end

    local ok, value =
        pcall(function()
            return inst:GetFullName()
        end)

    return ok and value or tostring(inst)
end

local function getNpcWrapper()
    if cachedNPC then
        return cachedNPC
    end

    local ok, list =
        pcall(
            NPCManager.getNPCsByName,
            "Mysterious Force"
        )

    log(
        "NPC LOOKUP",
        "ok=" .. tostring(ok),
        "type=" .. typeof(list)
    )

    if not ok
        or type(list) ~= "table"
    then
        return nil
    end

    local worldModel = nil

    pcall(function()
        local folder =
            workspace:FindFirstChild("NPCs")

        worldModel =
            folder
            and folder:FindFirstChild(
                "Mysterious Force"
            )
    end)

    local first = nil

    for _,npc in pairs(list) do
        if type(npc) == "table" then
            first = first or npc

            if type(npc.getModel)
                == "function"
            then
                local okModel, model =
                    pcall(function()
                        return npc:getModel()
                    end)

                if okModel then
                    log(
                        "NPC CANDIDATE",
                        safeFullName(model)
                    )

                    if worldModel
                        and model == worldModel
                    then
                        cachedNPC = npc
                        break
                    end
                end
            end
        end
    end

    cachedNPC =
        cachedNPC
        or first

    return cachedNPC
end

local function getNpcModel(npc)
    if type(npc) ~= "table"
        or type(npc.getModel)
            ~= "function"
    then
        return nil
    end

    local ok, model =
        pcall(function()
            return npc:getModel()
        end)

    if ok then
        return model
    end
end

local function getNpcRoot(npc)
    local model =
        getNpcModel(npc)

    if typeof(model) ~= "Instance" then
        return nil
    end

    local root =
        model:FindFirstChild(
            "HumanoidRootPart"
        )
        or model.PrimaryPart

    if root
        and root:IsA("BasePart")
    then
        return root
    end
end

local function getStandCFrame(npcRoot)
    -- Roblox forward is local -Z.
    -- Runtime traces showed the real player click position
    -- roughly 6 studs in front of the NPC.
    return npcRoot.CFrame
        * CFrame.new(
            0,
            0,
            -STAND_DISTANCE
        )
end

local function stopVelocity(hrp)
    pcall(function()
        hrp.AssemblyLinearVelocity =
            Vector3.zero

        hrp.AssemblyAngularVelocity =
            Vector3.zero
    end)
end

local function tweenTo(cf)
    local hrp =
        getRootPart()

    if not hrp then
        return false, "HRP missing"
    end

    local distance =
        (hrp.Position-cf.Position).Magnitude

    if distance <= ARRIVE_DISTANCE then
        hrp.CFrame = cf
        stopVelocity(hrp)
        return true, "already near"
    end

    local duration =
        math.max(
            distance / TWEEN_SPEED,
            0.05
        )

    log(
        "TWEEN",
        string.format(
            "distance=%.1f speed=%d duration=%.2fs",
            distance,
            TWEEN_SPEED,
            duration
        )
    )

    local tween =
        TweenService:Create(
            hrp,
            TweenInfo.new(
                duration,
                Enum.EasingStyle.Linear,
                Enum.EasingDirection.Out
            ),
            {
                CFrame = cf,
            }
        )

    tween:Play()

    local deadline =
        os.clock()
        + duration
        + 2

    while os.clock() < deadline do
        task.wait(0.05)

        hrp =
            getRootPart()

        if not hrp then
            tween:Cancel()
            return false, "HRP lost"
        end

        local d =
            (hrp.Position-cf.Position).Magnitude

        if d <= ARRIVE_DISTANCE then
            tween:Cancel()
            hrp.CFrame = cf
            stopVelocity(hrp)

            log(
                "ARRIVED",
                string.format(
                    "d=%.2f pos=(%.1f,%.1f,%.1f)",
                    d,
                    hrp.Position.X,
                    hrp.Position.Y,
                    hrp.Position.Z
                )
            )

            return true, d
        end
    end

    tween:Cancel()

    local finalD =
        (hrp.Position-cf.Position).Magnitude

    return finalD <= ARRIVE_DISTANCE,
        "final distance="
        .. string.format("%.2f", finalD)
end

local function getMysteriousRoot()
    local dg =
        PlayerGui:FindFirstChild(
            "DialogueGui"
        )

    if not dg then
        return nil
    end

    for _,root in ipairs(dg:GetChildren()) do
        local tf =
            root:FindFirstChild(
                "dialogueTitleFrame"
            )

        local title =
            tf
            and tf:FindFirstChild("name")

        if title
            and title:IsA("TextLabel")
            and tostring(title.Text)
                == "Mysterious Force"
        then
            return root
        end
    end
end

local function waitUi(timeout)
    local deadline =
        os.clock()
        + (timeout or 3)

    repeat
        local root =
            getMysteriousRoot()

        if root then
            return root
        end

        task.wait(0.03)
    until os.clock() >= deadline
end

local function safeClose()
    pcall(function()
        if type(DialogueController.close)
            == "function"
        then
            DialogueController.close()
        end
    end)

    task.wait(0.08)
end

local function optionText(option)
    if type(option) ~= "table" then
        return ""
    end

    local keys = {
        "_text",
        "Text",
        "text",
        "Title",
        "title",
        "_label",
        "Label",
    }

    for _,key in ipairs(keys) do
        local ok, value =
            pcall(function()
                return option[key]
            end)

        if ok
            and type(value) == "string"
        then
            return value
        end
    end

    return ""
end

local function isOptionObject(tbl)
    if type(tbl) ~= "table" then
        return false
    end

    local ok, fn =
        pcall(function()
            return tbl.onSelected
        end)

    return ok
        and type(fn) == "function"
end

local function findOption1(active)
    if type(active) ~= "table" then
        return nil
    end

    local lists = {}

    pcall(function()
        if type(active._window) == "table"
            and type(active._window._options)
                == "table"
        then
            lists[#lists+1] =
                active._window._options
        end
    end)

    pcall(function()
        if type(active._options) == "table" then
            lists[#lists+1] =
                active._options
        end
    end)

    for _,list in ipairs(lists) do
        local fallback = nil

        for k,opt in pairs(list) do
            if isOptionObject(opt) then
                fallback =
                    fallback or opt

                local txt =
                    string.lower(
                        optionText(opt)
                    )

                local key =
                    string.lower(
                        tostring(k)
                    )

                if string.find(
                    txt,
                    "use it",
                    1,
                    true
                )
                    or key == "1"
                    or key == "option1"
                then
                    return opt
                end
            end
        end

        if fallback then
            return fallback
        end
    end

    local seen = {}
    local first = nil
    local exact = nil

    local function walk(tbl, depth, path)
        if exact
            or type(tbl) ~= "table"
            or seen[tbl]
            or depth > 6
        then
            return
        end

        seen[tbl] = true

        if isOptionObject(tbl) then
            first = first or tbl

            local txt =
                string.lower(
                    optionText(tbl)
                )

            local p =
                string.lower(path)

            if string.find(
                txt,
                "use it",
                1,
                true
            )
                or string.find(
                    p,
                    "option1",
                    1,
                    true
                )
            then
                exact = tbl
                return
            end
        end

        for k,v in pairs(tbl) do
            if type(v) == "table" then
                walk(
                    v,
                    depth+1,
                    path
                    .. "."
                    .. tostring(k)
                )

                if exact then
                    return
                end
            end
        end
    end

    walk(active, 0, "active")

    return exact or first
end

local function triggerOption(option)
    local ok, ret =
        pcall(
            DialogueController.select,
            option
        )

    if ok then
        return true,
            "DialogueController.select"
    end

    log(
        "SELECT FAILED",
        tostring(ret)
    )

    local okSelf, retSelf =
        pcall(
            DialogueController.select,
            DialogueController,
            option
        )

    if okSelf then
        return true,
            "DialogueController.select(self,option)"
    end

    log(
        "SELECT SELF FAILED",
        tostring(retSelf)
    )

    local fn = nil

    pcall(function()
        fn = option.onSelected
    end)

    if type(fn) == "function" then
        local okDirect, retDirect =
            pcall(
                fn,
                option
            )

        if okDirect then
            return true,
                "option:onSelected()"
        end

        return false,
            tostring(retDirect)
    end

    return false,
        "no option callback"
end

local function waitForJump(before)
    local deadline =
        os.clock()
        + JUMP_WAIT

    while os.clock() < deadline do
        task.wait(0.05)

        local hrp =
            getRootPart()

        if hrp and before then
            local jump =
                (hrp.Position-before).Magnitude

            if jump >= JUMP_THRESHOLD then
                log(
                    "HRP JUMP",
                    string.format(
                        "%.1f studs | TO=(%.1f,%.1f,%.1f)",
                        jump,
                        hrp.Position.X,
                        hrp.Position.Y,
                        hrp.Position.Z
                    )
                )

                return true
            end
        end
    end

    return false
end

local function runFlow()
    if busy then
        log("BUSY")
        return
    end

    busy = true
    setStatus("RUNNING", true)

    task.spawn(function()
        local originalCF = nil
        local teleported = false

        local okMain, errMain =
            pcall(function()
                local hrp =
                    getRootPart()

                if not hrp then
                    error("HumanoidRootPart missing")
                end

                originalCF = hrp.CFrame

                local npc =
                    getNpcWrapper()

                if not npc then
                    error("Mysterious Force wrapper missing")
                end

                local npcRoot =
                    getNpcRoot(npc)

                if not npcRoot then
                    error("Mysterious Force HRP missing")
                end

                log(
                    "NPC ROOT",
                    safeFullName(npcRoot),
                    string.format(
                        "pos=(%.1f,%.1f,%.1f)",
                        npcRoot.Position.X,
                        npcRoot.Position.Y,
                        npcRoot.Position.Z
                    )
                )

                local targetCF =
                    getStandCFrame(
                        npcRoot
                    )

                local moved, moveInfo =
                    tweenTo(targetCF)

                log(
                    "MOVE RESULT",
                    tostring(moved),
                    tostring(moveInfo)
                )

                if not moved then
                    error(
                        "Could not reach NPC interaction position"
                    )
                end

                -- Let replicated character position settle.
                task.wait(0.18)

                hrp = getRootPart()

                local distance =
                    (hrp.Position-npcRoot.Position).Magnitude

                log(
                    "NPC DIST",
                    string.format(
                        "%.2f studs",
                        distance
                    )
                )

                safeClose()

                local okOpen, openRet =
                    pcall(
                        DialogueController.start,
                        TempleTeleport,
                        npc
                    )

                log(
                    "OPEN",
                    "ok="
                    .. tostring(okOpen),
                    "ret="
                    .. tostring(openRet)
                )

                if not okOpen then
                    error(
                        "DialogueController.start failed"
                    )
                end

                local ui =
                    waitUi(3)

                if not ui then
                    error(
                        "Mysterious Force UI did not open"
                    )
                end

                log("UI OPEN")

                task.wait(0.08)

                local okActive, active =
                    pcall(
                        DialogueController.getActiveDialogue
                    )

                log(
                    "ACTIVE",
                    "ok="
                    .. tostring(okActive),
                    "type="
                    .. typeof(active)
                )

                if not okActive
                    or type(active) ~= "table"
                then
                    error(
                        "active dialogue missing"
                    )
                end

                local option =
                    findOption1(active)

                cachedOption = option

                if not option then
                    error(
                        "Option1 / Use it not found"
                    )
                end

                log(
                    "OPTION1 FOUND",
                    'text="'
                    .. optionText(option)
                    .. '"'
                )

                -- Capture position AFTER moving close.
                hrp = getRootPart()
                local before =
                    hrp and hrp.Position

                local selected, method =
                    triggerOption(option)

                log(
                    "OPTION1 TRIGGER",
                    tostring(selected),
                    tostring(method)
                )

                if not selected then
                    error(
                        "Option1 callback failed"
                    )
                end

                teleported =
                    waitForJump(before)

                if teleported then
                    log(
                        "SUCCESS",
                        "server teleport detected"
                    )
                else
                    log(
                        "NO JUMP",
                        "Option1 executed but no server teleport"
                    )
                end
            end)

        if not okMain then
            log(
                "ERROR",
                tostring(errMain)
            )
        end

        -- Restore only on failure.
        if not teleported
            and originalCF
        then
            task.wait(0.15)

            local hrp =
                getRootPart()

            if hrp then
                pcall(function()
                    hrp.CFrame =
                        originalCF

                    stopVelocity(hrp)
                end)

                log(
                    "RESTORE",
                    "returned to original position"
                )
            end
        end

        busy = false
        setStatus("READY", false)
    end)
end

-- ============================================================
-- DEBUG PANEL
-- ============================================================
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
        "MFNearNpcOptionDebug"
    )

if old then
    old:Destroy()
end

local Gui =
    Instance.new("ScreenGui")

Gui.Name =
    "MFNearNpcOptionDebug"

Gui.ResetOnSpawn = false
Gui.Parent = parent

local Panel =
    Instance.new("Frame")

Panel.Size =
    UDim2.fromOffset(
        780,
        470
    )

Panel.Position =
    UDim2.new(
        0.5,
        -390,
        0.5,
        -235
    )

Panel.BackgroundColor3 =
    Color3.fromRGB(18,21,29)

Panel.BorderSizePixel = 0
Panel.Active = true
Panel.Parent = Gui

local pc =
    Instance.new("UICorner")

pc.CornerRadius =
    UDim.new(0,10)

pc.Parent = Panel

local Header =
    Instance.new("TextLabel")

Header.BackgroundTransparency = 1
Header.Position =
    UDim2.fromOffset(12,8)

Header.Size =
    UDim2.new(1,-220,0,30)

Header.Font =
    Enum.Font.GothamBold

Header.TextSize = 14

Header.TextColor3 =
    Color3.new(1,1,1)

Header.TextXAlignment =
    Enum.TextXAlignment.Left

Header.Text =
    "MYSTERIOUS FORCE - NEAR NPC + USE IT DEBUG"

Header.Active = true
Header.Parent = Panel

StatusLabel =
    Instance.new("TextLabel")

StatusLabel.BackgroundTransparency = 1
StatusLabel.AnchorPoint =
    Vector2.new(1,0)

StatusLabel.Position =
    UDim2.new(1,-12,0,8)

StatusLabel.Size =
    UDim2.fromOffset(190,30)

StatusLabel.Font =
    Enum.Font.Code

StatusLabel.TextSize = 11

StatusLabel.TextXAlignment =
    Enum.TextXAlignment.Right

StatusLabel.Text =
    "READY"

StatusLabel.TextColor3 =
    Color3.fromRGB(170,220,255)

StatusLabel.Parent = Panel

Scroll =
    Instance.new("ScrollingFrame")

Scroll.Position =
    UDim2.fromOffset(12,46)

Scroll.Size =
    UDim2.new(1,-24,1,-124)

Scroll.BackgroundColor3 =
    Color3.fromRGB(8,11,17)

Scroll.BorderSizePixel = 0
Scroll.ScrollBarThickness = 12

Scroll.AutomaticCanvasSize =
    Enum.AutomaticSize.Y

Scroll.CanvasSize =
    UDim2.new(0,0,0,0)

Scroll.Active = true
Scroll.Parent = Panel

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

local function makeButton(
    text,
    x,
    width,
    callback
)
    local b =
        Instance.new("TextButton")

    b.AnchorPoint =
        Vector2.new(0,1)

    b.Position =
        UDim2.new(x,8,1,-12)

    b.Size =
        UDim2.new(
            width,
            -10,
            0,
            58
        )

    b.BackgroundColor3 =
        Color3.fromRGB(40,47,64)

    b.BorderSizePixel = 0

    b.Font =
        Enum.Font.GothamBold

    b.TextSize = 10
    b.TextWrapped = true

    b.TextColor3 =
        Color3.new(1,1,1)

    b.Text = text
    b.Parent = Panel

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

local runButton =
    makeButton(
        "1 CLICK:\nNEAR NPC -> UI -> USE IT",
        0,
        0.50,
        runFlow
    )

runButton.BackgroundColor3 =
    Color3.fromRGB(42,95,69)

makeButton(
    "COPY DEBUG",
    0.50,
    0.25,
    function()
        if type(setclipboard) == "function" then
            local ok, err =
                pcall(function()
                    setclipboard(
                        table.concat(
                            logs,
                            "\n"
                        )
                    )
                end)

            log(
                "COPY",
                ok
                and "done"
                or tostring(err)
            )
        else
            log(
                "COPY",
                "setclipboard unavailable"
            )
        end
    end
)

makeButton(
    "CLEAR",
    0.75,
    0.25,
    function()
        logs = {}

        if LogLabel then
            LogLabel.Text = ""
        end

        if Scroll then
            Scroll.CanvasPosition =
                Vector2.zero
        end
    end
)

-- draggable panel
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
        startPos = Panel.Position
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
            input.Position-dragStart

        Panel.Position =
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

log(
    "READY",
    "TweenSpeed=150",
    "StandDistance=6"
)
