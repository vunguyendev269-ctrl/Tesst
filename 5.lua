-- MYSTERIOUS FORCE - NEAR NPC -> OPEN -> ADVANCE -> CLICK REAL OPTION1
-- Flow:
--   tween near NPC (150 studs/s)
--   open TempleTeleport dialogue
--   detect dialogue ROOT immediately (not by option presence)
--   wait text phase
--   DialogueController.advance()
--   wait real GUI option1/button
--   physically click center of button via VirtualInputManager
--   watch for server teleport
--
-- Debug panel included.

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local VIM = game:GetService("VirtualInputManager")
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
local UI_WAIT = 3
local OPTION_WAIT = 3
local JUMP_WAIT = 3

local logs = {}
local LogLabel
local Scroll
local StatusLabel
local busy = false
local cachedNPC = nil

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

    print("[MF ADVANCE]", line)

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

    StatusLabel.TextColor3 =
        running
        and Color3.fromRGB(80,255,150)
        or Color3.fromRGB(170,220,255)
end

local function getCharacter()
    local char = LP.Character

    if not char then
        char = LP.CharacterAdded:Wait()
    end

    return char
end

local function getHRP()
    local char = getCharacter()

    return char:FindFirstChild(
        "HumanoidRootPart"
    )
end

local function safeFullName(inst)
    if typeof(inst) ~= "Instance" then
        return tostring(inst)
    end

    local ok, name =
        pcall(function()
            return inst:GetFullName()
        end)

    return ok and name or tostring(inst)
end

local function stopVelocity(hrp)
    pcall(function()
        hrp.AssemblyLinearVelocity =
            Vector3.zero

        hrp.AssemblyAngularVelocity =
            Vector3.zero
    end)
end

-- ============================================================
-- NPC
-- ============================================================
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
        "ok="..tostring(ok),
        "type="..typeof(list)
    )

    if not ok
        or type(list) ~= "table"
    then
        return nil
    end

    local worldModel = nil

    pcall(function()
        local f = workspace:FindFirstChild("NPCs")

        worldModel =
            f
            and f:FindFirstChild(
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

                if okModel
                    and worldModel
                    and model == worldModel
                then
                    cachedNPC = npc
                    break
                end
            end
        end
    end

    cachedNPC =
        cachedNPC
        or first

    return cachedNPC
end

local function getNpcRoot(npc)
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

    if not ok
        or typeof(model) ~= "Instance"
    then
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

local function tweenNearNpc(npcRoot)
    local hrp = getHRP()

    if not hrp then
        return false, "HRP missing"
    end

    local target =
        npcRoot.CFrame
        * CFrame.new(
            0,
            0,
            -STAND_DISTANCE
        )

    local dist =
        (hrp.Position-target.Position).Magnitude

    if dist <= ARRIVE_DISTANCE then
        hrp.CFrame = target
        stopVelocity(hrp)

        return true, dist
    end

    local duration =
        math.max(
            dist / TWEEN_SPEED,
            0.05
        )

    log(
        "TWEEN",
        string.format(
            "dist=%.1f duration=%.2f speed=%d",
            dist,
            duration,
            TWEEN_SPEED
        )
    )

    local tween =
        TweenService:Create(
            hrp,
            TweenInfo.new(
                duration,
                Enum.EasingStyle.Linear
            ),
            {CFrame=target}
        )

    tween:Play()

    local deadline =
        os.clock()
        + duration
        + 2

    while os.clock() < deadline do
        task.wait(0.05)

        hrp = getHRP()

        if not hrp then
            tween:Cancel()
            return false, "HRP lost"
        end

        local d =
            (hrp.Position-target.Position).Magnitude

        if d <= ARRIVE_DISTANCE then
            tween:Cancel()

            hrp.CFrame = target
            stopVelocity(hrp)

            return true, d
        end
    end

    tween:Cancel()

    return false,
        "timeout"
end

-- ============================================================
-- DIALOGUE ROOT DETECTION
-- Detect root before Option1 exists.
-- ============================================================
local function getDialogueGui()
    return PlayerGui:FindFirstChild(
        "DialogueGui"
    )
end

local function getMysteriousRoot()
    local dg = getDialogueGui()

    if not dg then
        return nil
    end

    for _,root in ipairs(dg:GetChildren()) do
        local titleFrame =
            root:FindFirstChild(
                "dialogueTitleFrame"
            )

        local title =
            titleFrame
            and titleFrame:FindFirstChild("name")

        if title
            and title:IsA("TextLabel")
            and tostring(title.Text)
                == "Mysterious Force"
        then
            return root
        end
    end
end

local function waitRoot()
    local deadline =
        os.clock() + UI_WAIT

    repeat
        local root =
            getMysteriousRoot()

        if root then
            return root
        end

        task.wait(0.03)
    until os.clock() >= deadline
end

local function getDialogueBodyText(root)
    if not root then
        return ""
    end

    local found = {}

    for _,obj in ipairs(root:GetDescendants()) do
        if obj:IsA("TextLabel") then
            local ok, text =
                pcall(function()
                    return tostring(obj.Text or "")
                end)

            if ok
                and text ~= ""
                and text ~= "Mysterious Force"
            then
                found[#found+1] = text
            end
        end
    end

    return table.concat(
        found,
        " | "
    )
end

-- ============================================================
-- REAL GUI OPTION1 DETECTION
-- ============================================================
local function findOption1Gui(root)
    if not root then
        return nil
    end

    local options =
        root:FindFirstChild("optionsList")

    local scroller =
        options
        and options:FindFirstChild("scroller")

    if not scroller then
        return nil
    end

    for _,container in ipairs(
        scroller:GetChildren()
    ) do
        local name =
            string.lower(
                tostring(container.Name)
            )

        if string.find(
            name,
            "option1",
            1,
            true
        ) then
            local button =
                container:FindFirstChild(
                    "button"
                )

            if button
                and button:IsA("GuiButton")
            then
                return button, container
            end
        end
    end
end

local function waitOption1(root)
    local deadline =
        os.clock()
        + OPTION_WAIT

    while os.clock() < deadline do
        local button, container =
            findOption1Gui(root)

        if button then
            local okVisible, ready =
                pcall(function()
                    return button.Visible
                        and button.AbsoluteSize.X > 0
                        and button.AbsoluteSize.Y > 0
                end)

            if okVisible and ready then
                return button, container
            end
        end

        task.wait(0.03)
    end
end

local function clickGuiButton(button)
    local p = button.AbsolutePosition
    local s = button.AbsoluteSize

    local x = p.X + s.X/2
    local y = p.Y + s.Y/2

    log(
        "CLICK OPTION1",
        string.format(
            "x=%.0f y=%.0f size=(%.0f,%.0f)",
            x,
            y,
            s.X,
            s.Y
        )
    )

    pcall(function()
        VIM:SendMouseMoveEvent(
            x,
            y,
            game
        )
    end)

    task.wait(0.03)

    VIM:SendMouseButtonEvent(
        x,
        y,
        0,
        true,
        game,
        0
    )

    task.wait(0.05)

    VIM:SendMouseButtonEvent(
        x,
        y,
        0,
        false,
        game,
        0
    )
end

local function waitJump(before)
    local deadline =
        os.clock()
        + JUMP_WAIT

    while os.clock() < deadline do
        task.wait(0.05)

        local hrp = getHRP()

        if hrp and before then
            local jump =
                (hrp.Position-before).Magnitude

            if jump > 1000 then
                log(
                    "HRP JUMP",
                    string.format(
                        "%.1f studs -> (%.1f,%.1f,%.1f)",
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

local function safeClose()
    pcall(function()
        DialogueController.close()
    end)

    task.wait(0.08)
end

-- ============================================================
-- MAIN FLOW
-- ============================================================
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
                local hrp = getHRP()

                if not hrp then
                    error("HRP missing")
                end

                originalCF = hrp.CFrame

                local npc =
                    getNpcWrapper()

                if not npc then
                    error(
                        "Mysterious Force NPC wrapper missing"
                    )
                end

                local npcRoot =
                    getNpcRoot(npc)

                if not npcRoot then
                    error(
                        "Mysterious Force root missing"
                    )
                end

                log(
                    "NPC ROOT",
                    safeFullName(npcRoot)
                )

                local moved, moveInfo =
                    tweenNearNpc(npcRoot)

                log(
                    "MOVE",
                    tostring(moved),
                    tostring(moveInfo)
                )

                if not moved then
                    error(
                        "could not reach NPC"
                    )
                end

                task.wait(0.18)

                safeClose()

                local okOpen, openRet =
                    pcall(
                        DialogueController.start,
                        TempleTeleport,
                        npc
                    )

                log(
                    "OPEN",
                    "ok="..tostring(okOpen),
                    "ret="..tostring(openRet)
                )

                if not okOpen then
                    error(
                        "DialogueController.start failed"
                    )
                end

                local root = waitRoot()

                if not root then
                    error(
                        "Mysterious Force root not detected"
                    )
                end

                log(
                    "UI ROOT DETECTED",
                    root.Name
                )

                local body =
                    getDialogueBodyText(root)

                log(
                    "BODY",
                    body
                )

                -- IMPORTANT:
                -- Option1 does not exist yet during the initial text phase.
                local button =
                    findOption1Gui(root)

                if not button then
                    log(
                        "OPTION1",
                        "not present yet -> ADVANCE dialogue"
                    )

                    -- First try normal controller advance.
                    local okAdvance, advRet =
                        pcall(
                            DialogueController.advance
                        )

                    log(
                        "ADVANCE",
                        "ok="..tostring(okAdvance),
                        "ret="..tostring(advRet)
                    )

                    -- Some versions may expect self.
                    if not okAdvance then
                        local okAdvanceSelf,
                              advSelfRet =
                            pcall(
                                DialogueController.advance,
                                DialogueController
                            )

                        log(
                            "ADVANCE SELF",
                            "ok="
                            .. tostring(okAdvanceSelf),
                            "ret="
                            .. tostring(advSelfRet)
                        )
                    end
                else
                    log(
                        "OPTION1",
                        "already present"
                    )
                end

                local realButton =
                    waitOption1(root)

                if not realButton then
                    error(
                        "Option1 GUI did not appear after advance"
                    )
                end

                log(
                    "OPTION1 GUI DETECTED",
                    realButton:GetFullName()
                )

                hrp = getHRP()
                local before =
                    hrp and hrp.Position

                clickGuiButton(
                    realButton
                )

                teleported =
                    waitJump(before)

                if teleported then
                    log(
                        "SUCCESS",
                        "server teleport detected"
                    )
                else
                    log(
                        "NO JUMP",
                        "real Option1 clicked but no teleport"
                    )
                end
            end)

        if not okMain then
            log(
                "ERROR",
                tostring(errMain)
            )
        end

        if not teleported
            and originalCF
        then
            task.wait(0.12)

            local hrp = getHRP()

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
-- DEBUG UI
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
        "MFAdvanceOptionDebug"
    )

if old then
    old:Destroy()
end

local Gui = Instance.new("ScreenGui")
Gui.Name = "MFAdvanceOptionDebug"
Gui.ResetOnSpawn = false
Gui.Parent = parent

local Panel = Instance.new("Frame")
Panel.Size = UDim2.fromOffset(800,480)
Panel.Position = UDim2.new(0.5,-400,0.5,-240)
Panel.BackgroundColor3 = Color3.fromRGB(18,21,29)
Panel.BorderSizePixel = 0
Panel.Active = true
Panel.Parent = Gui

local pc = Instance.new("UICorner")
pc.CornerRadius = UDim.new(0,10)
pc.Parent = Panel

local Header = Instance.new("TextLabel")
Header.BackgroundTransparency = 1
Header.Position = UDim2.fromOffset(12,8)
Header.Size = UDim2.new(1,-220,0,30)
Header.Font = Enum.Font.GothamBold
Header.TextSize = 14
Header.TextColor3 = Color3.new(1,1,1)
Header.TextXAlignment = Enum.TextXAlignment.Left
Header.Text = "MYSTERIOUS FORCE - OPEN -> ADVANCE -> REAL OPTION1"
Header.Active = true
Header.Parent = Panel

StatusLabel = Instance.new("TextLabel")
StatusLabel.BackgroundTransparency = 1
StatusLabel.AnchorPoint = Vector2.new(1,0)
StatusLabel.Position = UDim2.new(1,-12,0,8)
StatusLabel.Size = UDim2.fromOffset(190,30)
StatusLabel.Font = Enum.Font.Code
StatusLabel.TextSize = 11
StatusLabel.TextXAlignment = Enum.TextXAlignment.Right
StatusLabel.Text = "READY"
StatusLabel.TextColor3 = Color3.fromRGB(170,220,255)
StatusLabel.Parent = Panel

Scroll = Instance.new("ScrollingFrame")
Scroll.Position = UDim2.fromOffset(12,46)
Scroll.Size = UDim2.new(1,-24,1,-124)
Scroll.BackgroundColor3 = Color3.fromRGB(8,11,17)
Scroll.BorderSizePixel = 0
Scroll.ScrollBarThickness = 12
Scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
Scroll.CanvasSize = UDim2.new(0,0,0,0)
Scroll.Active = true
Scroll.Parent = Panel

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

local function makeButton(text,x,width,callback)
    local b = Instance.new("TextButton")
    b.AnchorPoint = Vector2.new(0,1)
    b.Position = UDim2.new(x,8,1,-12)
    b.Size = UDim2.new(width,-10,0,58)
    b.BackgroundColor3 = Color3.fromRGB(40,47,64)
    b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamBold
    b.TextSize = 10
    b.TextWrapped = true
    b.TextColor3 = Color3.new(1,1,1)
    b.Text = text
    b.Parent = Panel

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0,7)
    c.Parent = b

    b.MouseButton1Click:Connect(callback)
    return b
end

makeButton(
    "1 CLICK:\nNEAR -> OPEN -> ADVANCE -> USE IT",
    0,
    0.55,
    runFlow
).BackgroundColor3 =
    Color3.fromRGB(42,95,69)

makeButton(
    "COPY DEBUG",
    0.55,
    0.225,
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
    0.775,
    0.225,
    function()
        logs = {}
        LogLabel.Text = ""
        Scroll.CanvasPosition =
            Vector2.zero
    end
)

local dragging = false
local dragStart
local startPos

Header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
    then
        dragging = true
        dragStart = input.Position
        startPos = Panel.Position
    end
end)

UIS.InputChanged:Connect(function(input)
    if dragging and (
        input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch
    ) then
        local d = input.Position-dragStart

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
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
    then
        dragging = false
    end
end)

log(
    "READY",
    "Tween=150",
    "Flow=OPEN -> ADVANCE -> GUI option1"
)
