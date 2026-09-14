-- MYSTERIOUS FORCE - DIRECT REAL OPTION1 V2
-- ============================================================
-- Flow:
--   1) Tween near Mysterious Force @ 150 studs/s
--   2) Spawn DialogueController.start(...) because start() yields
--   3) Wait until GUI option1 exists (means options are ready)
--   4) Get active dialogue
--   5) Find REAL Option1 object
--   6) Call DialogueController.select(DialogueController, option1)
--   7) Wait Temple teleport
--   8) Auto-close result dialogue
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

    print("[MF DIRECT SELECT]", line)

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

local function arity(fn)
    if type(fn) ~= "function" then
        return "not-function"
    end

    if type(debug) == "table"
        and type(debug.info) == "function"
    then
        local ok,a,b =
            pcall(function()
                return debug.info(fn, "a")
            end)

        if ok then
            return tostring(a)
                .. ",vararg="
                .. tostring(b)
        end
    end

    return "unknown"
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

local function getDialogueGui()
    return PlayerGui:FindFirstChild(
        "DialogueGui"
    )
end

local function findGuiOption1()
    local dg = getDialogueGui()

    if not dg then
        return nil
    end

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
                        local ready = false

                        pcall(function()
                            ready =
                                button.Visible
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

    return nil
end

local function waitGuiOption1(timeout)
    local deadline =
        os.clock()
        + (timeout or OPTION_WAIT)

    while os.clock() < deadline do
        local b,c,r =
            findGuiOption1()

        if b then
            return b,c,r
        end

        task.wait(0.02)
    end
end

local function getActiveDialogue()
    local ok, active =
        pcall(
            DialogueController.getActiveDialogue
        )

    if ok
        and type(active) == "table"
    then
        return active, "no-self"
    end

    local ok2, active2 =
        pcall(
            DialogueController.getActiveDialogue,
            DialogueController
        )

    if ok2
        and type(active2) == "table"
    then
        return active2, "self"
    end

    return nil, "failed"
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

local function unwrapOption(v)
    if isOptionObject(v) then
        return v
    end

    if type(v) == "table" then
        local inner = rawget(v, "option")

        if isOptionObject(inner) then
            return inner
        end
    end

    return nil
end

local function candidateScore(path, opt, key)
    local p = string.lower(
        tostring(path or "")
    )

    if string.find(p, "_cancel", 1, true)
        or string.find(p, ".cancel", 1, true)
    then
        return -100000
    end

    local score = 0

    if string.find(p, "_options", 1, true) then
        score += 1000
    end

    if string.find(p, "option1", 1, true) then
        score += 900
    end

    if tostring(key) == "1"
        or string.lower(tostring(key)) == "option1"
    then
        score += 800
    end

    local txt =
        string.lower(
            optionText(opt)
        )

    if string.find(txt, "use it", 1, true) then
        score += 2000
    end

    return score
end

local function findOption1Object(active)
    if type(active) ~= "table" then
        return nil,nil
    end

    local best = nil
    local bestPath = nil
    local bestScore = -math.huge
    local seen = {}

    local function consider(value, path, key)
        local opt =
            unwrapOption(value)

        if not opt then
            return
        end

        local score =
            candidateScore(
                path,
                opt,
                key
            )

        log(
            "OPTION CANDIDATE",
            "score="..tostring(score),
            "path="..tostring(path),
            "key="..tostring(key),
            "text="..optionText(opt),
            "obj="..tostring(opt)
        )

        if score > bestScore then
            bestScore = score
            best = opt
            bestPath = path
        end
    end

    -- Strongest path seen in current runtime:
    -- active._pageStack.<page>._options.<option>
    local pageStack =
        rawget(active, "_pageStack")

    if type(pageStack) == "table" then
        for pageIndex,page in pairs(pageStack) do
            if type(page) == "table" then
                local options =
                    rawget(page, "_options")

                if type(options) == "table" then
                    for k,v in pairs(options) do
                        consider(
                            v,
                            "active._pageStack."
                            ..tostring(pageIndex)
                            .."._options."
                            ..tostring(k),
                            k
                        )
                    end
                end
            end
        end
    end

    local window =
        rawget(active, "_window")

    if type(window) == "table" then
        local options =
            rawget(window, "_options")

        if type(options) == "table" then
            for k,v in pairs(options) do
                consider(
                    v,
                    "active._window._options."
                    ..tostring(k),
                    k
                )
            end
        end
    end

    local directOptions =
        rawget(active, "_options")

    if type(directOptions) == "table" then
        for k,v in pairs(directOptions) do
            consider(
                v,
                "active._options."
                ..tostring(k),
                k
            )
        end
    end

    -- Recursive fallback.
    -- Important: cancel paths are scored out and can never win.
    local function walk(tbl, depth, path)
        if type(tbl) ~= "table"
            or seen[tbl]
            or depth > 8
        then
            return
        end

        seen[tbl] = true

        for k,v in pairs(tbl) do
            local childPath =
                path
                .."."
                ..tostring(k)

            consider(
                v,
                childPath,
                k
            )

            if type(v) == "table" then
                walk(
                    v,
                    depth+1,
                    childPath
                )
            end
        end
    end

    walk(
        active,
        0,
        "active"
    )

    if best
        and bestScore > -1000
    then
        log(
            "OPTION PICKED",
            "score="..tostring(bestScore),
            "path="..tostring(bestPath),
            "text="..optionText(best)
        )

        return best,bestPath
    end

    return nil,nil
end

local function selectOption1(option)
    if not option then
        return false, "option=nil"
    end

    log(
        "SELECT SIG",
        arity(
            DialogueController.select
        )
    )

    -- Runtime log proved selectArity=1.
    -- Correct API call: select(option), not select(self, option).
    local ok, ret =
        pcall(
            DialogueController.select,
            option
        )

    log(
        "SELECT OPTION1",
        "ok="..tostring(ok),
        "ret="..tostring(ret)
    )

    if ok then
        return true,
            "DialogueController.select(option)"
    end

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

        log(
            "OPTION onSelected",
            "ok="..tostring(okDirect),
            "ret="..tostring(retDirect)
        )

        if okDirect then
            return true,
                "option:onSelected()"
        end
    end

    return false,
        tostring(ret)
end

local function waitTeleport(before, timeout)
    local deadline =
        os.clock()
        + (timeout or TELEPORT_WAIT)

    while os.clock() < deadline do
        task.wait(0.05)

        local hrp = getHRP()

        if hrp and before then
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

local function autoCloseResult()
    task.wait(0.30)

    local ok, err =
        pcall(
            DialogueController.close,
            DialogueController
        )

    if not ok then
        ok, err =
            pcall(
                DialogueController.close
            )
    end

    log(
        "AUTO CLOSE RESULT",
        "ok="..tostring(ok),
        "err="..tostring(err)
    )
end

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

                local moved,info =
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

                pcall(
                    DialogueController.close
                )

                task.wait(0.08)

                task.spawn(function()
                    local okStart, retStart =
                        pcall(
                            DialogueController.start,
                            TempleTeleport,
                            npc
                        )

                    log(
                        "START RETURN",
                        "ok="..tostring(okStart),
                        "ret="..tostring(retStart)
                    )
                end)

                log(
                    "START SPAWNED",
                    "waiting Option1 ready"
                )

                local guiButton =
                    waitGuiOption1(
                        OPTION_WAIT
                    )

                if not guiButton then
                    error(
                        "GUI Option1 never appeared"
                    )
                end

                log(
                    "GUI OPTION1 READY",
                    safeFullName(guiButton)
                )

                local active, activeMode =
                    getActiveDialogue()

                log(
                    "ACTIVE",
                    "mode="..tostring(activeMode),
                    "type="..typeof(active)
                )

                if type(active) ~= "table" then
                    error(
                        "active dialogue missing"
                    )
                end

                local option1,path =
                    findOption1Object(active)

                log(
                    "OPTION1 OBJECT",
                    "obj="..tostring(option1),
                    "path="..tostring(path),
                    "text="..optionText(option1)
                )

                if not option1 then
                    error(
                        "real Option1 object not found"
                    )
                end

                hrp = getHRP()

                local before =
                    hrp and hrp.Position

                local selected, method =
                    selectOption1(option1)

                log(
                    "SELECT RESULT",
                    tostring(selected),
                    tostring(method)
                )

                if not selected then
                    error(
                        "Option1 direct select failed"
                    )
                end

                local teleported =
                    waitTeleport(
                        before,
                        TELEPORT_WAIT
                    )

                if not teleported then
                    error(
                        "Option1 selected but no Temple teleport"
                    )
                end

                log(
                    "SUCCESS",
                    "Temple entered"
                )

                autoCloseResult()

                log(
                    "DONE",
                    "result dialogue closed"
                )
            end)

        if not okMain then
            log(
                "ERROR",
                tostring(errMain)
            )

            log(
                "HOLD POSITION",
                "player remains near NPC"
            )
        end

        busy = false
        setStatus("READY", false)
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
        "MFDirectSelectOption1"
    )

if old then
    old:Destroy()
end

local Gui = Instance.new("ScreenGui")
Gui.Name = "MFDirectSelectOption1"
Gui.ResetOnSpawn = false
Gui.Parent = parent

local Panel = Instance.new("Frame")
Panel.Size = UDim2.fromOffset(860,510)
Panel.Position = UDim2.new(0.5,-430,0.5,-255)
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
    "MYSTERIOUS FORCE - DIRECT REAL OPTION1 V2"
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
    "1 CLICK:\nNEAR NPC -> DIRECT SELECT OPTION1",
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
            local ok,err =
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
    "INSPECT OPTION1",
    0.775,
    0.225,
    function()
        local active,mode =
            getActiveDialogue()

        local opt,path =
            findOption1Object(active)

        log(
            "INSPECT",
            "activeMode="..tostring(mode),
            "option="..tostring(opt),
            "path="..tostring(path),
            "text="..optionText(opt),
            "selectArity="
            ..arity(DialogueController.select)
        )
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
    "Direct option select",
    "cancel-filtered",
    "Tween=150"
)

log(
    "SELECT ARITY",
    arity(
        DialogueController.select
    )
)
