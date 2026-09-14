-- MYSTERIOUS FORCE - ROBUST REAL OPTION1 + AUTO CLOSE RESULT
-- ============================================================
-- Flow:
--   1) save current position
--   2) tween near real Mysterious Force at 150 studs/s
--   3) open TempleTeleport dialogue with NPC wrapper
--   4) scan ALL visible GuiButtons inside PlayerGui.DialogueGui
--      - prefer ancestor/name containing option1
--      - else prefer reconstructed text containing "use it"
--      - else prefer option-like large button in options/scroller
--   5) real mouse click via VirtualInputManager
--   6) detect server teleport
--   7) auto-close the post-teleport
--      "The space tears open..." dialogue
--   8) restore original position only if teleport failed
--
-- No network hooks.
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
local BUTTON_WAIT = 4.0
local JUMP_WAIT = 3.5
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
    local p = {}

    for i = 1, select("#", ...) do
        p[#p+1] =
            tostring(select(i, ...))
    end

    local line =
        string.format(
            "[%.3f] %s",
            os.clock(),
            table.concat(p, " ")
        )

    logs[#logs+1] = line

    if #logs > 1000 then
        table.remove(logs, 1)
    end

    print("[MF ROBUST]", line)

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
    local c = LP.Character

    if not c then
        c = LP.CharacterAdded:Wait()
    end

    return c
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

    local ok, n =
        pcall(function()
            return inst:GetFullName()
        end)

    return ok and n or tostring(inst)
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
        local f =
            workspace:FindFirstChild("NPCs")

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

    return false, "timeout"
end

-- ============================================================
-- DIALOGUE HELPERS
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

local function lower(s)
    return string.lower(
        tostring(s or "")
    )
end

local function getAncestorSignature(obj)
    local parts = {}
    local cur = obj
    local dg = getDialogueGui()

    for _ = 1,10 do
        if not cur then
            break
        end

        parts[#parts+1] =
            tostring(cur.Name)

        if cur == dg then
            break
        end

        cur = cur.Parent
    end

    return lower(
        table.concat(
            parts,
            "/"
        )
    )
end

local function collectVisibleText(root)
    if typeof(root) ~= "Instance" then
        return ""
    end

    local items = {}

    for _,d in ipairs(root:GetDescendants()) do
        if d:IsA("TextLabel")
            or d:IsA("TextButton")
        then
            local ok, visible =
                pcall(function()
                    return d.Visible
                end)

            local okText, text =
                pcall(function()
                    return tostring(
                        d.Text or ""
                    )
                end)

            if ok
                and visible
                and okText
                and text ~= ""
            then
                local pos =
                    Vector2.new(0,0)

                pcall(function()
                    pos =
                        d.AbsolutePosition
                end)

                items[#items+1] = {
                    text=text,
                    x=pos.X,
                    y=pos.Y,
                }
            end
        end
    end

    table.sort(
        items,
        function(a,b)
            if math.abs(a.y-b.y) < 8 then
                return a.x < b.x
            end

            return a.y < b.y
        end
    )

    local out = {}

    for _,it in ipairs(items) do
        out[#out+1] = it.text
    end

    return lower(
        table.concat(
            out,
            ""
        )
    )
end

local function isVisibleButton(btn)
    if not btn:IsA("GuiButton") then
        return false
    end

    local ok, good =
        pcall(function()
            return btn.Visible
                and btn.Active
                and btn.AbsoluteSize.X > 20
                and btn.AbsoluteSize.Y > 15
        end)

    return ok and good
end

local function scoreButton(btn)
    local score = 0

    local sig =
        getAncestorSignature(btn)

    local text =
        collectVisibleText(btn)

    local size =
        btn.AbsoluteSize

    if string.find(
        sig,
        "option1",
        1,
        true
    ) then
        score += 1000
    end

    if string.find(
        text,
        "useit",
        1,
        true
    )
        or string.find(
            text,
            "use it",
            1,
            true
        )
    then
        score += 900
    end

    if string.find(
        sig,
        "optionslist",
        1,
        true
    ) then
        score += 300
    end

    if string.find(
        sig,
        "scroller",
        1,
        true
    ) then
        score += 200
    end

    if size.X > 250
        and size.Y > 40
    then
        score += 100
    end

    if lower(btn.Name) == "button" then
        score += 50
    end

    return score, sig, text
end

local function scanDialogueButtons(verbose)
    local dg = getDialogueGui()

    if not dg then
        return nil
    end

    local best = nil
    local bestScore = -math.huge

    for _,obj in ipairs(dg:GetDescendants()) do
        if obj:IsA("GuiButton")
            and isVisibleButton(obj)
        then
            local score,sig,text =
                scoreButton(obj)

            if verbose then
                log(
                    "BUTTON",
                    "score="..tostring(score),
                    "name="..tostring(obj.Name),
                    "size="
                    ..string.format(
                        "%.0fx%.0f",
                        obj.AbsoluteSize.X,
                        obj.AbsoluteSize.Y
                    ),
                    "path="..sig,
                    "text="..text
                )
            end

            if score > bestScore then
                best = obj
                bestScore = score
            end
        end
    end

    if best
        and bestScore >= 100
    then
        return best,bestScore
    end

    return nil,bestScore
end

local function waitUseItButton(timeout)
    local deadline =
        os.clock()
        + (timeout or BUTTON_WAIT)

    local lastVerbose = 0

    while os.clock() < deadline do
        local btn, score =
            scanDialogueButtons(false)

        if btn then
            return btn,score
        end

        if os.clock()-lastVerbose > 0.8 then
            lastVerbose = os.clock()
            scanDialogueButtons(true)
        end

        task.wait(0.03)
    end

    scanDialogueButtons(true)

    return nil
end

local function realClick(btn)
    local pos =
        btn.AbsolutePosition

    local size =
        btn.AbsoluteSize

    local x =
        pos.X
        + size.X/2

    local y =
        pos.Y
        + size.Y/2

    log(
        "REAL CLICK",
        "button="
        ..safeFullName(btn),
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
-- TELEPORT / POST-DIALOGUE
-- ============================================================
local function waitJump(before)
    local deadline =
        os.clock()
        + JUMP_WAIT

    while os.clock() < deadline do
        task.wait(0.05)

        local hrp = getHRP()

        if hrp
            and before
        then
            local jump =
                (hrp.Position-before).Magnitude

            local templeDist =
                (hrp.Position-TEMPLE_POS).Magnitude

            if jump > JUMP_THRESHOLD
                or templeDist < 500
            then
                log(
                    "SERVER TELEPORT",
                    string.format(
                        "jump=%.1f templeDist=%.1f pos=(%.1f,%.1f,%.1f)",
                        jump,
                        templeDist,
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

local function autoClosePostTeleport()
    -- Let the game render:
    -- "The space tears open, and you arrive in a new place."
    task.wait(0.25)

    local active = nil

    pcall(function()
        active =
            DialogueController.getActiveDialogue()
    end)

    log(
        "POST DIALOGUE",
        "active="
        ..tostring(
            active ~= nil
        )
    )

    local okClose, errClose =
        pcall(function()
            DialogueController.close()
        end)

    log(
        "AUTO CLOSE RESULT",
        "ok="
        ..tostring(okClose),
        "err="
        ..tostring(errClose)
    )

    task.wait(0.15)
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

                local moved, info =
                    tweenNearNpc(npcRoot)

                log(
                    "MOVE",
                    tostring(moved),
                    tostring(info)
                )

                if not moved then
                    error(
                        "failed to reach NPC"
                    )
                end

                task.wait(0.18)

                hrp = getHRP()

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

                local okOpen, openRet =
                    pcall(
                        DialogueController.start,
                        TempleTeleport,
                        npc
                    )

                log(
                    "OPEN",
                    "ok="
                    ..tostring(okOpen),
                    "ret="
                    ..tostring(openRet)
                )

                if not okOpen then
                    error(
                        "DialogueController.start failed"
                    )
                end

                -- Do NOT call advance.
                -- Do NOT require exact option hierarchy.
                -- Wait until a real visible response button exists.
                local useButton,score =
                    waitUseItButton(
                        BUTTON_WAIT
                    )

                if not useButton then
                    error(
                        "could not identify real Use it button"
                    )
                end

                log(
                    "USE IT BUTTON",
                    "score="
                    ..tostring(score),
                    safeFullName(useButton)
                )

                hrp = getHRP()

                local before =
                    hrp and hrp.Position

                realClick(
                    useButton
                )

                teleported =
                    waitJump(before)

                if not teleported then
                    log(
                        "NO TELEPORT",
                        "dumping buttons after click"
                    )

                    scanDialogueButtons(
                        true
                    )

                    error(
                        "Use it clicked but server teleport not detected"
                    )
                end

                log(
                    "SUCCESS",
                    "entered Temple"
                )

                -- Close the extra result dialogue automatically.
                autoClosePostTeleport()

                log(
                    "FLOW",
                    "post-teleport dialogue closed"
                )
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
        "MFRobustUseItDebug"
    )

if old then
    old:Destroy()
end

local Gui =
    Instance.new("ScreenGui")

Gui.Name =
    "MFRobustUseItDebug"

Gui.ResetOnSpawn = false
Gui.Parent = parent

local Panel =
    Instance.new("Frame")

Panel.Size =
    UDim2.fromOffset(
        850,
        500
    )

Panel.Position =
    UDim2.new(
        0.5,
        -425,
        0.5,
        -250
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
    "MYSTERIOUS FORCE - ROBUST USE IT + AUTO CLOSE"

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

makeButton(
    "1 CLICK:\nNEAR NPC -> REAL USE IT -> AUTO CLOSE",
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
        end
    end
)

makeButton(
    "DUMP BUTTONS",
    0.775,
    0.225,
    function()
        scanDialogueButtons(
            true
        )
    end
)

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
    "Tween=150",
    "No advance()",
    "Button scan=ALL DialogueGui",
    "PostTeleport=auto close"
)
