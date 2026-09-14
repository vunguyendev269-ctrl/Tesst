-- MYSTERIOUS FORCE - CONCURRENT START + AUTO USE IT
-- ============================================================
-- Root-cause fix:
-- DialogueController.start(...) yields until the dialogue ends.
-- Therefore start() MUST run in a separate task, while the main
-- task watches DialogueGui and clicks Option1 / "Use it".
--
-- Flow:
--   1) Tween near Mysterious Force @ 150 studs/s
--   2) Stay there (NO restore)
--   3) task.spawn(DialogueController.start(...))
--   4) Concurrently detect real option1/button in DialogueGui
--   5) Real VIM click Use it
--   6) Detect server teleport to Temple
--   7) Auto-close "The space tears open..." result dialogue
--
-- No network hook.
-- No direct InvokeServer / FireServer.

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
local OPTION_WAIT = 5
local TELEPORT_WAIT = 4
local JUMP_THRESHOLD = 1000

local TEMPLE_POS =
    Vector3.new(
        28286.35546875,
        14896.8,
        102.625
    )

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

    if #logs > 1000 then
        table.remove(logs, 1)
    end

    print("[MF CONCURRENT]", line)

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
    return getCharacter():FindFirstChild(
        "HumanoidRootPart"
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

local function safeFullName(inst)
    if typeof(inst) ~= "Instance" then
        return tostring(inst)
    end

    local ok, result =
        pcall(function()
            return inst:GetFullName()
        end)

    return ok and result or tostring(inst)
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

-- ============================================================
-- MOVEMENT
-- ============================================================
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
            dist/TWEEN_SPEED,
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
            {
                CFrame=target
            }
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

    return false, "move timeout"
end

-- ============================================================
-- DIALOGUE / OPTION1 GUI
-- ============================================================
local function getDialogueGui()
    return PlayerGui:FindFirstChild(
        "DialogueGui"
    )
end

local function safeClose()
    pcall(function()
        DialogueController.close()
    end)

    task.wait(0.08)
end

local function findOption1Button()
    local dg = getDialogueGui()

    if not dg then
        return nil,nil,nil
    end

    -- Preferred exact structure discovered at runtime:
    -- DialogueGui
    --   dynamic root
    --     optionsList
    --       scroller
    --         dynamic "...:option1"
    --           button
    for _,root in ipairs(dg:GetChildren()) do
        local options =
            root:FindFirstChild(
                "optionsList"
            )

        local scroller =
            options
            and options:FindFirstChild(
                "scroller"
            )

        if scroller then
            for _,container in ipairs(
                scroller:GetChildren()
            ) do
                local n =
                    string.lower(
                        tostring(container.Name)
                    )

                if string.find(
                    n,
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
                        local ready = false

                        pcall(function()
                            ready =
                                button.Visible
                                and button.Active
                                and button.AbsoluteSize.X > 20
                                and button.AbsoluteSize.Y > 20
                        end)

                        if ready then
                            return button,container,root
                        end
                    end
                end
            end
        end
    end

    -- Fallback:
    -- Find a visible GuiButton with "option1" somewhere
    -- in its ancestor chain.
    for _,obj in ipairs(dg:GetDescendants()) do
        if obj:IsA("GuiButton") then
            local ready = false

            pcall(function()
                ready =
                    obj.Visible
                    and obj.Active
                    and obj.AbsoluteSize.X > 20
                    and obj.AbsoluteSize.Y > 20
            end)

            if ready then
                local cur = obj
                local signature = ""

                for _ = 1,8 do
                    if not cur then
                        break
                    end

                    signature =
                        signature
                        .. "/"
                        .. string.lower(
                            tostring(cur.Name)
                        )

                    if cur == dg then
                        break
                    end

                    cur = cur.Parent
                end

                if string.find(
                    signature,
                    "option1",
                    1,
                    true
                ) then
                    return obj,obj.Parent,nil
                end
            end
        end
    end

    return nil,nil,nil
end

local function waitOption1(timeout)
    local deadline =
        os.clock()
        + (timeout or OPTION_WAIT)

    local lastLog = 0

    while os.clock() < deadline do
        local button,container,root =
            findOption1Button()

        if button then
            return button,container,root
        end

        if os.clock()-lastLog > 0.5 then
            lastLog = os.clock()
            log(
                "WAIT OPTION1",
                string.format(
                    "%.2fs",
                    deadline-os.clock()
                )
            )
        end

        task.wait(0.02)
    end

    return nil,nil,nil
end

local function realClick(button)
    local pos = button.AbsolutePosition
    local size = button.AbsoluteSize

    local x = pos.X + size.X/2
    local y = pos.Y + size.Y/2

    log(
        "REAL CLICK",
        safeFullName(button),
        string.format(
            "center=(%.0f,%.0f) size=(%.0f,%.0f)",
            x,
            y,
            size.X,
            size.Y
        )
    )

    VIM:SendMouseMoveEvent(
        x,
        y,
        game
    )

    task.wait(0.04)

    VIM:SendMouseButtonEvent(
        x,
        y,
        0,
        true,
        game,
        0
    )

    task.wait(0.06)

    VIM:SendMouseButtonEvent(
        x,
        y,
        0,
        false,
        game,
        0
    )
end

-- ============================================================
-- TELEPORT DETECTION
-- ============================================================
local function hasTeleported(before)
    local hrp = getHRP()

    if not hrp
        or not before
    then
        return false,nil,nil
    end

    local jump =
        (hrp.Position-before).Magnitude

    local templeDist =
        (hrp.Position-TEMPLE_POS).Magnitude

    return (
        jump > JUMP_THRESHOLD
        or templeDist < 500
    ),
    jump,
    templeDist
end

local function waitTeleport(before, timeout)
    local deadline =
        os.clock()
        + (timeout or TELEPORT_WAIT)

    while os.clock() < deadline do
        task.wait(0.05)

        local yes,jump,templeDist =
            hasTeleported(before)

        if yes then
            local hrp = getHRP()

            log(
                "SERVER TELEPORT",
                string.format(
                    "jump=%.1f templeDist=%.1f pos=(%.1f,%.1f,%.1f)",
                    jump or -1,
                    templeDist or -1,
                    hrp.Position.X,
                    hrp.Position.Y,
                    hrp.Position.Z
                )
            )

            return true
        end
    end

    return false
end

local function autoCloseResultDialogue()
    -- Result dialogue:
    -- "The space tears open, and you arrive in a new place."
    task.wait(0.30)

    local ok, err =
        pcall(function()
            DialogueController.close()
        end)

    log(
        "AUTO CLOSE RESULT",
        "ok="..tostring(ok),
        "err="..tostring(err)
    )
end

-- ============================================================
-- MAIN
-- ============================================================
local function runFlow()
    if busy then
        log("BUSY")
        return
    end

    busy = true
    setStatus("RUNNING", true)

    task.spawn(function()
        local okMain, errMain =
            pcall(function()
                local npc =
                    getNpcWrapper()

                if not npc then
                    error(
                        "Mysterious Force wrapper missing"
                    )
                end

                local npcRoot =
                    getNpcRoot(npc)

                if not npcRoot then
                    error(
                        "Mysterious Force HRP missing"
                    )
                end

                log(
                    "NPC ROOT",
                    safeFullName(npcRoot)
                )

                local moved,moveInfo =
                    tweenNearNpc(npcRoot)

                log(
                    "MOVE",
                    tostring(moved),
                    tostring(moveInfo)
                )

                if not moved then
                    error(
                        "failed to reach NPC"
                    )
                end

                task.wait(0.15)

                local hrp = getHRP()

                log(
                    "NPC DIST",
                    string.format(
                        "%.2f",
                        (
                            hrp.Position
                            - npcRoot.Position
                        ).Magnitude
                    )
                )

                safeClose()

                -- ====================================================
                -- CRITICAL FIX:
                -- start() yields. Run it in a SEPARATE task.
                -- ====================================================
                local startFinished = false
                local startOk = nil
                local startRet = nil

                task.spawn(function()
                    local ok, ret =
                        pcall(
                            DialogueController.start,
                            TempleTeleport,
                            npc
                        )

                    startOk = ok
                    startRet = ret
                    startFinished = true

                    log(
                        "START RETURN",
                        "ok="..tostring(ok),
                        "ret="..tostring(ret)
                    )
                end)

                log(
                    "START SPAWNED",
                    "monitoring GUI concurrently"
                )

                -- Main task continues immediately while
                -- DialogueController.start is still yielded.
                local button,container,root =
                    waitOption1(
                        OPTION_WAIT
                    )

                if not button then
                    log(
                        "START STATE",
                        "finished="
                        ..tostring(startFinished),
                        "ok="
                        ..tostring(startOk),
                        "ret="
                        ..tostring(startRet)
                    )

                    error(
                        "Option1 did not appear while dialogue was active"
                    )
                end

                log(
                    "OPTION1 DETECTED",
                    "container="
                    ..tostring(
                        container
                        and container.Name
                    ),
                    "button="
                    ..safeFullName(button)
                )

                -- Tiny settle time after the actual button exists.
                task.wait(0.08)

                hrp = getHRP()
                local before =
                    hrp
                    and hrp.Position

                realClick(button)

                -- First teleport window.
                local teleported =
                    waitTeleport(
                        before,
                        1.25
                    )

                -- If first physical click was swallowed, retry once.
                if not teleported then
                    local retry =
                        findOption1Button()

                    if retry then
                        log(
                            "RETRY",
                            "Option1 still visible -> click again"
                        )

                        realClick(retry)

                        teleported =
                            waitTeleport(
                                before,
                                TELEPORT_WAIT
                            )
                    end
                end

                if not teleported then
                    error(
                        "Use it click sent, but no Temple teleport"
                    )
                end

                log(
                    "SUCCESS",
                    "Temple entered"
                )

                -- Stay in Temple; never restore old position.
                autoCloseResultDialogue()

                log(
                    "DONE",
                    "post-teleport result dialogue closed"
                )
            end)

        if not okMain then
            log(
                "ERROR",
                tostring(errMain)
            )

            log(
                "HOLD POSITION",
                "no restore; player remains at NPC"
            )
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
        "MFConcurrentUseItDebug"
    )

if old then
    old:Destroy()
end

local Gui = Instance.new("ScreenGui")
Gui.Name = "MFConcurrentUseItDebug"
Gui.ResetOnSpawn = false
Gui.Parent = parent

local Panel = Instance.new("Frame")
Panel.Size = UDim2.fromOffset(850,500)
Panel.Position = UDim2.new(0.5,-425,0.5,-250)
Panel.BackgroundColor3 = Color3.fromRGB(18,21,29)
Panel.BorderSizePixel = 0
Panel.Active = true
Panel.Parent = Gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0,10)
corner.Parent = Panel

local Header = Instance.new("TextLabel")
Header.BackgroundTransparency = 1
Header.Position = UDim2.fromOffset(12,8)
Header.Size = UDim2.new(1,-220,0,30)
Header.Font = Enum.Font.GothamBold
Header.TextSize = 14
Header.TextColor3 = Color3.new(1,1,1)
Header.TextXAlignment = Enum.TextXAlignment.Left
Header.Text =
    "MYSTERIOUS FORCE - CONCURRENT START + AUTO USE IT"
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

local function makeButton(
    text,
    x,
    width,
    callback
)
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
    "1 CLICK:\nNEAR NPC -> AUTO USE IT -> TEMPLE",
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
                ok and "done" or tostring(err)
            )
        end
    end
)

makeButton(
    "CHECK OPTION1",
    0.775,
    0.225,
    function()
        local b,c,r =
            findOption1Button()

        log(
            "CHECK OPTION1",
            "button="..tostring(b),
            "container="
            ..tostring(c and c.Name),
            "root="
            ..tostring(r and r.Name)
        )

        if b then
            log(
                "BUTTON PATH",
                safeFullName(b),
                string.format(
                    "pos=(%.0f,%.0f) size=(%.0f,%.0f)",
                    b.AbsolutePosition.X,
                    b.AbsolutePosition.Y,
                    b.AbsoluteSize.X,
                    b.AbsoluteSize.Y
                )
            )
        end
    end
)

-- draggable
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
    "Root fix=start() in separate task",
    "TweenSpeed=150",
    "No restore on failure"
)
