-- MYSTERIOUS FORCE - REMOTE DIALOGUE API TEST V3
-- Fix: DialogueController.start receives TempleTeleport definition table
-- (the table that owns Get), not the return value of Get().

if not game:IsLoaded() then game.Loaded:Wait() end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")

local LP = Players.LocalPlayer
local PlayerGui = LP:WaitForChild("PlayerGui", 15)

local DialogueController = require(RS:WaitForChild("DialogueController"))
local NPCManager = require(RS:WaitForChild("NPCManager"))
local DialoguesList = require(RS:WaitForChild("DialoguesList"))
local TempleTeleport = DialoguesList.TempleTeleport

local logs = {}
local LogLabel
local Scroll
local busy = false
local cachedNPC = nil

local function log(tag, msg)
    local line = string.format(
        "[%.3f][%s] %s",
        os.clock(),
        tostring(tag),
        tostring(msg)
    )

    logs[#logs+1] = line
    if #logs > 500 then
        table.remove(logs, 1)
    end

    print("[MF API V3] " .. line)

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

local function safeInstanceName(v)
    if typeof(v) ~= "Instance" then
        return nil
    end

    local ok, name = pcall(function()
        return v:GetFullName()
    end)

    if ok then
        return name
    end

    return "<Instance>"
end

local function safeValue(v)
    local t = typeof(v)

    if t == "nil"
        or t == "number"
        or t == "boolean"
    then
        return tostring(v)

    elseif t == "string" then
        return string.format("%q", v)

    elseif t == "Instance" then
        return safeInstanceName(v) or "<Instance>"

    elseif t == "function" then
        return "<function>"

    elseif t == "table" then
        return "<table>"
    end

    return "<" .. t .. ">"
end

local function summarizeTable(tbl, maxItems)
    if type(tbl) ~= "table" then
        return safeValue(tbl)
    end

    maxItems = maxItems or 20

    local out = {}
    local n = 0

    for k,v in pairs(tbl) do
        n += 1

        if n > maxItems then
            out[#out+1] = "..."
            break
        end

        out[#out+1] =
            tostring(k)
            .. ":"
            .. typeof(v)
    end

    return "{"
        .. table.concat(out, ", ")
        .. "}"
end

local function getMysteriousRoot()
    local dg = PlayerGui:FindFirstChild("DialogueGui")

    if not dg then
        return nil
    end

    for _,root in ipairs(dg:GetChildren()) do
        local tf = root:FindFirstChild("dialogueTitleFrame")
        local title = tf and tf:FindFirstChild("name")

        if title
            and title:IsA("TextLabel")
            and tostring(title.Text) == "Mysterious Force"
        then
            return root
        end
    end
end

local function waitUi(seconds)
    local deadline = os.clock() + (seconds or 3)

    while os.clock() < deadline do
        local root = getMysteriousRoot()

        if root then
            return root
        end

        task.wait(0.05)
    end

    return nil
end

local function safeClose()
    pcall(function()
        if type(DialogueController.close) == "function" then
            DialogueController.close()
        end
    end)

    task.wait(0.15)
end

local function getArity(fn)
    if type(fn) ~= "function" then
        return "not-function"
    end

    if type(debug) == "table"
        and type(debug.info) == "function"
    then
        local ok,a,b = pcall(function()
            return debug.info(fn, "a")
        end)

        if ok then
            return tostring(a)
                .. ", vararg="
                .. tostring(b)
        end
    end

    return "unavailable"
end

local function runTest(label, fn)
    if busy then
        log("BUSY", "previous test still active")
        return
    end

    busy = true

    task.spawn(function()
        local ok, err = pcall(fn)

        if not ok then
            log(label .. " ERROR", tostring(err))
        end

        busy = false
        log(label, "DONE | busy=false")
    end)
end

local function chooseNPCWrapper(result)
    if type(result) ~= "table" then
        return nil
    end

    if type(result.getModel) == "function"
        or result._npcInfo ~= nil
    then
        return result
    end

    local worldModel = nil

    pcall(function()
        local folder = workspace:FindFirstChild("NPCs")
        worldModel =
            folder
            and folder:FindFirstChild("Mysterious Force")
    end)

    local fallback = nil

    for _,v in pairs(result) do
        if type(v) == "table" then
            if not fallback then
                fallback = v
            end

            if type(v.getModel) == "function" then
                local okModel, model =
                    pcall(function()
                        return v:getModel()
                    end)

                if okModel
                    and worldModel
                    and model == worldModel
                then
                    return v
                end
            end
        end
    end

    return fallback
end

local function lookupNPC()
    local ok, result = pcall(
        NPCManager.getNPCsByName,
        "Mysterious Force"
    )

    log(
        "NPC LOOKUP",
        "ok="
        .. tostring(ok)
        .. " type="
        .. typeof(result)
    )

    if not ok then
        return nil
    end

    if type(result) == "table" then
        log(
            "NPC LOOKUP",
            "shape="
            .. summarizeTable(result, 20)
        )
    end

    local npc = chooseNPCWrapper(result)

    if npc then
        cachedNPC = npc

        log(
            "NPC SELECT",
            "wrapper found | shape="
            .. summarizeTable(npc, 25)
        )

        if type(npc.getModel) == "function" then
            local okModel, model = pcall(function()
                return npc:getModel()
            end)

            log(
                "NPC MODEL",
                "ok="
                .. tostring(okModel)
                .. " model="
                .. (
                    okModel
                    and (
                        safeInstanceName(model)
                        or safeValue(model)
                    )
                    or "<failed>"
                )
            )
        end
    else
        log("NPC SELECT", "no wrapper found")
    end

    return npc
end

local function testDefinitionNil()
    runTest(
        "DEF+NIL",
        function()
            safeClose()

            log(
                "INPUT",
                "TempleTeleport type="
                .. typeof(TempleTeleport)
                .. " Get="
                .. tostring(
                    type(
                        TempleTeleport
                        and TempleTeleport.Get
                    )
                )
            )

            local ok, ret = pcall(
                DialogueController.start,
                TempleTeleport,
                nil
            )

            log(
                "START DEF+NIL",
                "ok="
                .. tostring(ok)
                .. " ret="
                .. safeValue(ret)
            )

            if not ok then
                return
            end

            local root = waitUi(3)

            log(
                root and "SUCCESS" or "RESULT",
                root
                and "Mysterious Force UI OPEN"
                or "UI did not open"
            )
        end
    )
end

local function testLookupOnly()
    runTest(
        "LOOKUP",
        function()
            lookupNPC()
        end
    )
end

local function testDefinitionNPC()
    runTest(
        "DEF+NPC",
        function()
            safeClose()

            local npc =
                cachedNPC
                or lookupNPC()

            if not npc then
                log("FAIL", "NPC wrapper unavailable")
                return
            end

            local ok, ret = pcall(
                DialogueController.start,
                TempleTeleport,
                npc
            )

            log(
                "START DEF+NPC",
                "ok="
                .. tostring(ok)
                .. " ret="
                .. safeValue(ret)
            )

            if not ok then
                return
            end

            local root = waitUi(3)

            log(
                root and "SUCCESS" or "RESULT",
                root
                and "Mysterious Force UI OPEN"
                or "UI did not open"
            )
        end
    )
end

local function dumpInfo()
    log(
        "SIG",
        "TempleTeleport.Get="
        .. getArity(
            TempleTeleport
            and TempleTeleport.Get
        )
    )

    log(
        "SIG",
        "DialogueController.start="
        .. getArity(
            DialogueController.start
        )
    )

    log(
        "SIG",
        "NPCManager.getNPCsByName="
        .. getArity(
            NPCManager.getNPCsByName
        )
    )

    log(
        "SIG",
        "NPCManager.startDialogue="
        .. getArity(
            NPCManager.startDialogue
        )
    )

    log(
        "WHY",
        "Previous missing-Get error means start() received the wrong first object. V3 passes TempleTeleport itself, which owns Get."
    )
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
        "MFRemoteDialogueApiTestV3"
    )

if old then
    old:Destroy()
end

local Gui = Instance.new("ScreenGui")
Gui.Name = "MFRemoteDialogueApiTestV3"
Gui.ResetOnSpawn = false
Gui.Parent = parent

local Frame = Instance.new("Frame")
Frame.Size = UDim2.fromOffset(800,500)
Frame.Position = UDim2.new(0.5,-400,0.5,-250)
Frame.BackgroundColor3 = Color3.fromRGB(18,21,29)
Frame.BorderSizePixel = 0
Frame.Active = true
Frame.Parent = Gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0,10)
corner.Parent = Frame

local Header = Instance.new("TextLabel")
Header.BackgroundTransparency = 1
Header.Position = UDim2.fromOffset(12,7)
Header.Size = UDim2.new(1,-24,0,30)
Header.Font = Enum.Font.GothamBold
Header.TextSize = 14
Header.TextColor3 = Color3.new(1,1,1)
Header.TextXAlignment = Enum.TextXAlignment.Left
Header.Text = "MYSTERIOUS FORCE - REMOTE DIALOGUE API TEST V3"
Header.Active = true
Header.Parent = Frame

Scroll = Instance.new("ScrollingFrame")
Scroll.Position = UDim2.fromOffset(12,44)
Scroll.Size = UDim2.new(1,-24,1,-104)
Scroll.BackgroundColor3 = Color3.fromRGB(8,11,17)
Scroll.BorderSizePixel = 0
Scroll.ScrollBarThickness = 12
Scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
Scroll.CanvasSize = UDim2.new(0,0,0,0)
Scroll.Parent = Frame

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

local function makeButton(text,x,callback)
    local b = Instance.new("TextButton")
    b.AnchorPoint = Vector2.new(0,1)
    b.Position = UDim2.new(x,8,1,-12)
    b.Size = UDim2.new(0.24,-10,0,48)
    b.BackgroundColor3 = Color3.fromRGB(40,47,64)
    b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamBold
    b.TextSize = 10
    b.TextWrapped = true
    b.TextColor3 = Color3.new(1,1,1)
    b.Text = text
    b.Parent = Frame

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0,7)
    c.Parent = b

    b.MouseButton1Click:Connect(callback)
    return b
end

makeButton(
    "1) START\nDEFINITION + NIL",
    0,
    testDefinitionNil
).BackgroundColor3 =
    Color3.fromRGB(45,95,70)

makeButton(
    "2) LOOKUP\nNPC WRAPPER",
    0.25,
    testLookupOnly
)

makeButton(
    "3) START\nDEFINITION + NPC",
    0.5,
    testDefinitionNPC
)

makeButton(
    "RESET / INFO",
    0.75,
    function()
        busy = false
        safeClose()
        dumpInfo()
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
        startPos = Frame.Position
    end
end)

UIS.InputChanged:Connect(function(input)
    if dragging and (
        input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch
    ) then
        local d = input.Position-dragStart

        Frame.Position =
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
    "FOUND",
    "TempleTeleport.Title="
    .. tostring(
        TempleTeleport
        and TempleTeleport.Title
    )
)

dumpInfo()
