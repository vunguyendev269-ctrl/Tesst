-- MYSTERIOUS FORCE - REMOTE DIALOGUE API TEST
-- No network hook. No direct InvokeServer/FireServer calls.

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
local TempleTeleportBack = DialoguesList.TempleTeleportBack

local logs = {}
local LogLabel
local Scroll
local busy = false

local function log(tag, msg)
    local line = string.format("[%.3f][%s] %s", os.clock(), tostring(tag), tostring(msg))
    logs[#logs+1] = line
    if #logs > 400 then table.remove(logs,1) end
    print("[MF API TEST] "..line)

    if LogLabel then
        LogLabel.Text = table.concat(logs,"\n")
        task.defer(function()
            if Scroll then
                Scroll.CanvasPosition = Vector2.new(
                    0,
                    math.max(0, Scroll.AbsoluteCanvasSize.Y - Scroll.AbsoluteWindowSize.Y)
                )
            end
        end)
    end
end

local function valueText(v)
    if typeof(v) == "table" then
        local out = {}
        local n = 0
        for k,val in pairs(v) do
            n += 1
            if n > 15 then
                out[#out+1] = "..."
                break
            end
            out[#out+1] = tostring(k).."="..tostring(val)
        end
        return "{"..table.concat(out,", ").."}"
    end
    return tostring(v)
end

local function getMysteriousRoot()
    local dg = PlayerGui:FindFirstChild("DialogueGui")
    if not dg then return nil end

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

local function waitUi(timeout)
    local deadline = os.clock() + (timeout or 3)
    repeat
        local root = getMysteriousRoot()
        if root then return root end
        task.wait(0.05)
    until os.clock() >= deadline
end

local function closeActive()
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

    if type(debug) == "table" and type(debug.info) == "function" then
        local ok,a,b = pcall(function()
            return debug.info(fn,"a")
        end)

        if ok then
            return tostring(a)..", vararg="..tostring(b)
        end
    end

    return "unavailable"
end

local function dumpSignatures()
    log("SIG","TempleTeleport.Get args="..getArity(TempleTeleport and TempleTeleport.Get))
    log("SIG","TempleTeleportBack.Get args="..getArity(TempleTeleportBack and TempleTeleportBack.Get))
    log("SIG","DialogueController.start args="..getArity(DialogueController.start))
    log("SIG","NPCManager.startDialogue args="..getArity(NPCManager.startDialogue))
    log("SIG","NPCManager.getNPCsByName args="..getArity(NPCManager.getNPCsByName))
end

local function runIsolated(label, fn)
    if busy then
        log("BUSY","wait")
        return
    end

    busy = true

    task.spawn(function()
        closeActive()

        local ok,ret = pcall(fn)

        log(
            label,
            "ok="..tostring(ok)
            .." type="..typeof(ret)
            .." return="..valueText(ret)
        )

        local root = waitUi(3)

        log(
            root and "SUCCESS" or "RESULT",
            root and "Mysterious Force UI OPEN" or "UI did not open"
        )

        busy = false
    end)
end

local function testGetOnly()
    runIsolated("GET ONLY", function()
        return TempleTeleport.Get()
    end)
end

local function testGetThenStart()
    if busy then
        log("BUSY","wait")
        return
    end

    busy = true

    task.spawn(function()
        closeActive()

        local okGet,dialogue = pcall(function()
            return TempleTeleport.Get()
        end)

        log(
            "GET",
            "ok="..tostring(okGet)
            .." type="..typeof(dialogue)
            .." value="..valueText(dialogue)
        )

        if not okGet then
            local okSelf,dialogueSelf = pcall(function()
                return TempleTeleport.Get(TempleTeleport)
            end)

            log(
                "GET SELF",
                "ok="..tostring(okSelf)
                .." type="..typeof(dialogueSelf)
                .." value="..valueText(dialogueSelf)
            )

            if not okSelf then
                busy = false
                return
            end

            dialogue = dialogueSelf
        end

        local okStart,startRet = pcall(function()
            return DialogueController.start(dialogue)
        end)

        log(
            "DIALOGUE START",
            "ok="..tostring(okStart)
            .." return="..valueText(startRet)
        )

        local root = waitUi(3)

        log(
            root and "SUCCESS" or "RESULT",
            root and "Mysterious Force UI OPEN" or "UI did not open"
        )

        busy = false
    end)
end

local function testNpcStartId()
    runIsolated("NPC START ID", function()
        return NPCManager.startDialogue("TempleTeleport")
    end)
end

local function testNpcStartTable()
    runIsolated("NPC START TABLE", function()
        return NPCManager.startDialogue(TempleTeleport)
    end)
end

local parent = CoreGui
pcall(function()
    if type(gethui) == "function" then
        local h = gethui()
        if h then parent = h end
    end
end)

local old = parent:FindFirstChild("MFRemoteDialogueApiTest")
if old then old:Destroy() end

local Gui = Instance.new("ScreenGui")
Gui.Name = "MFRemoteDialogueApiTest"
Gui.ResetOnSpawn = false
Gui.Parent = parent

local Frame = Instance.new("Frame")
Frame.Size = UDim2.fromOffset(760,500)
Frame.Position = UDim2.new(0.5,-380,0.5,-250)
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
Header.Text = "MYSTERIOUS FORCE - REMOTE DIALOGUE API TEST"
Header.Active = true
Header.Parent = Frame

Scroll = Instance.new("ScrollingFrame")
Scroll.Position = UDim2.fromOffset(12,44)
Scroll.Size = UDim2.new(1,-24,1,-162)
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

local function makeButton(text,x,y,callback)
    local b = Instance.new("TextButton")
    b.AnchorPoint = Vector2.new(0,1)
    b.Position = UDim2.new(x,8,1,y)
    b.Size = UDim2.new(0.24,-10,0,54)
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

makeButton("1) GET ->\nDIALOGUE START",0,-76,testGetThenStart).BackgroundColor3 =
    Color3.fromRGB(45,95,70)

makeButton('2) NPC START\n"TempleTeleport"',0.25,-76,testNpcStartId)
makeButton("3) NPC START\nTempleTeleport table",0.5,-76,testNpcStartTable)
makeButton("4) GET ONLY\nDiagnostic",0.75,-76,testGetOnly)

makeButton("DUMP\nSIGNATURES",0,-12,dumpSignatures)

makeButton("CLOSE\nDIALOGUE",0.25,-12,function()
    closeActive()
    log("CLOSE","called")
end)

makeButton("COPY LOG",0.5,-12,function()
    if type(setclipboard) == "function" then
        pcall(function()
            setclipboard(table.concat(logs,"\n"))
        end)
        log("COPY","done")
    end
end)

makeButton("CLEAR LOG",0.75,-12,function()
    logs = {}
    LogLabel.Text = ""
end)

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

        Frame.Position = UDim2.new(
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

log("FOUND","TempleTeleport.Title="..tostring(TempleTeleport and TempleTeleport.Title))
log("FOUND","TempleTeleport.Get="..tostring(TempleTeleport and TempleTeleport.Get))
log("FOUND","NPCManager.startDialogue="..tostring(NPCManager.startDialogue))
dumpSignatures()
