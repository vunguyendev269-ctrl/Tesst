--[[
    MYSTERIOUS FORCE - REMOTE DIALOGUE API TEST V2
    Fixes the V1 failure:
      TempleTeleport.Get() returns a LEGACY dialogue table.
      DialogueController.start() expects a built Dialogue object
      with methods such as _openTop.

    This version:
      1) TempleTeleport.Get()
      2) Legacy.is(raw)
      3) Legacy.convert(...) with safe candidate signatures
      4) verify converted._openTop exists
      5) DialogueController.start(converted, nil)
      6) verify Mysterious Force UI appears

    Also fixes BUSY getting stuck: every test is wrapped and busy is
    always cleared when the task exits.

    No network hook.
    No direct V4 progression remote invocation.
]]

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")

local LP = Players.LocalPlayer
local PlayerGui = LP:WaitForChild("PlayerGui", 15)

local DialogueController =
    require(RS:WaitForChild("DialogueController"))

local Legacy =
    require(
        RS:WaitForChild("DialogueController")
          :WaitForChild("Legacy")
    )

local DialoguesList =
    require(RS:WaitForChild("DialoguesList"))

local NPCManager =
    require(RS:WaitForChild("NPCManager"))

local TempleTeleport =
    DialoguesList.TempleTeleport

local logs = {}
local LogLabel
local Scroll
local busy = false

local function log(tag, msg)
    local line =
        string.format(
            "[%.3f][%s] %s",
            os.clock(),
            tostring(tag),
            tostring(msg)
        )

    logs[#logs+1] = line

    if #logs > 500 then
        table.remove(logs, 1)
    end

    print("[MF API V2] " .. line)

    if LogLabel then
        LogLabel.Text =
            table.concat(logs, "\n")

        task.defer(function()
            if Scroll then
                Scroll.CanvasPosition =
                    Vector2.new(
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

local function valueText(v)
    local t = typeof(v)

    if t == "table" then
        local out = {}
        local n = 0

        for k,val in pairs(v) do
            n += 1
            if n > 18 then
                out[#out+1] = "..."
                break
            end

            out[#out+1] =
                tostring(k)
                .. "="
                .. tostring(val)
        end

        return "{"
            .. table.concat(out, ", ")
            .. "}"
    end

    return tostring(v)
end

local function getArity(fn)
    if type(fn) ~= "function" then
        return nil, nil
    end

    if type(debug) == "table"
        and type(debug.info) == "function"
    then
        local ok,a,b =
            pcall(function()
                return debug.info(fn, "a")
            end)

        if ok then
            return a,b
        end
    end

    return nil,nil
end

local function arityText(fn)
    local a,b = getArity(fn)

    if a == nil then
        return "unavailable"
    end

    return tostring(a)
        .. ", vararg="
        .. tostring(b)
end

local function getMysteriousRoot()
    local dg =
        PlayerGui:FindFirstChild("DialogueGui")

    if not dg then
        return nil
    end

    for _,root in ipairs(dg:GetChildren()) do
        local tf =
            root:FindFirstChild("dialogueTitleFrame")

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

    while os.clock() < deadline do
        local root =
            getMysteriousRoot()

        if root then
            return root
        end

        task.wait(0.05)
    end

    return nil
end

local function safeClose()
    pcall(function()
        DialogueController.close()
    end)

    task.wait(0.12)
end

local function isBuiltDialogue(v)
    return type(v) == "table"
        and type(v._openTop) == "function"
        and type(v.build) == "function"
end

local function reportShape(label, obj)
    log(
        label,
        "type="
        .. typeof(obj)
        .. " _openTop="
        .. tostring(
            type(obj) == "table"
            and type(obj._openTop)
            or "n/a"
        )
        .. " build="
        .. tostring(
            type(obj) == "table"
            and type(obj.build)
            or "n/a"
        )
        .. " value="
        .. valueText(obj)
    )
end

local function getRaw()
    local ok, raw =
        pcall(function()
            return TempleTeleport.Get()
        end)

    log(
        "GET",
        "ok="
        .. tostring(ok)
        .. " type="
        .. typeof(raw)
        .. " value="
        .. valueText(raw)
    )

    if not ok then
        return nil
    end

    return raw
end

local function convertLegacy(raw)
    local legacyIs = nil

    if type(Legacy.is) == "function" then
        local okIs, retIs =
            pcall(
                Legacy.is,
                raw
            )

        log(
            "LEGACY.IS",
            "ok="
            .. tostring(okIs)
            .. " return="
            .. tostring(retIs)
        )

        if okIs then
            legacyIs = retIs
        end
    end

    log(
        "SIG",
        "Legacy.convert args="
        .. arityText(Legacy.convert)
    )

    -- Candidate A: convert(raw)
    do
        local ok, converted =
            pcall(
                Legacy.convert,
                raw
            )

        log(
            "CONVERT A",
            "Legacy.convert(raw) ok="
            .. tostring(ok)
            .. " ret="
            .. valueText(converted)
        )

        if isBuiltDialogue(converted) then
            return converted, "A:return"
        end

        if isBuiltDialogue(raw) then
            return raw, "A:mutated-raw"
        end
    end

    -- Candidate B: convert(raw, title)
    do
        local ok, converted =
            pcall(
                Legacy.convert,
                raw,
                TempleTeleport.Title
            )

        log(
            "CONVERT B",
            "Legacy.convert(raw,title) ok="
            .. tostring(ok)
            .. " ret="
            .. valueText(converted)
        )

        if isBuiltDialogue(converted) then
            return converted, "B:return"
        end

        if isBuiltDialogue(raw) then
            return raw, "B:mutated-raw"
        end
    end

    -- Candidate C: convert(title, raw)
    do
        local ok, converted =
            pcall(
                Legacy.convert,
                TempleTeleport.Title,
                raw
            )

        log(
            "CONVERT C",
            "Legacy.convert(title,raw) ok="
            .. tostring(ok)
            .. " ret="
            .. valueText(converted)
        )

        if isBuiltDialogue(converted) then
            return converted, "C:return"
        end

        if isBuiltDialogue(raw) then
            return raw, "C:mutated-raw"
        end
    end

    log(
        "CONVERT",
        "No candidate produced a Dialogue object"
        .. " | Legacy.is="
        .. tostring(legacyIs)
    )

    return nil,nil
end

local function runSafely(name, fn)
    if busy then
        log(
            "BUSY",
            "previous test still active"
        )
        return
    end

    busy = true

    task.spawn(function()
        local ok, err =
            xpcall(
                fn,
                function(e)
                    return tostring(e)
                end
            )

        if not ok then
            log(
                name .. " ERROR",
                tostring(err)
            )
        end

        busy = false

        log(
            name,
            "DONE | busy=false"
        )
    end)
end

local function testConvertAndStart()
    runSafely(
        "TEST1",
        function()
            safeClose()

            local raw = getRaw()

            if not raw then
                return
            end

            reportShape(
                "RAW SHAPE",
                raw
            )

            local dialogue, mode =
                convertLegacy(raw)

            if not dialogue then
                log(
                    "FAIL",
                    "Legacy conversion failed"
                )
                return
            end

            log(
                "CONVERT",
                "SUCCESS via "
                .. tostring(mode)
            )

            reportShape(
                "DIALOGUE SHAPE",
                dialogue
            )

            local okStart, ret =
                pcall(
                    DialogueController.start,
                    dialogue,
                    nil
                )

            log(
                "START",
                "DialogueController.start(dialogue,nil) ok="
                .. tostring(okStart)
                .. " ret="
                .. valueText(ret)
            )

            local root =
                waitUi(3)

            if root then
                log(
                    "SUCCESS",
                    "Mysterious Force UI OPEN"
                )
            else
                log(
                    "RESULT",
                    "UI did not open"
                )
            end
        end
    )
end

local function testNpcLookup()
    runSafely(
        "TEST2",
        function()
            local ok, result =
                pcall(
                    NPCManager.getNPCsByName,
                    "Mysterious Force"
                )

            log(
                "NPC LOOKUP",
                "ok="
                .. tostring(ok)
                .. " type="
                .. typeof(result)
                .. " value="
                .. valueText(result)
            )

            if type(result) == "table" then
                local i = 0

                for k,v in pairs(result) do
                    i += 1

                    if i > 10 then
                        break
                    end

                    log(
                        "NPC ITEM",
                        tostring(k)
                        .. " => "
                        .. valueText(v)
                    )
                end
            end
        end
    )
end

local function dumpSignatures()
    log(
        "SIG",
        "TempleTeleport.Get="
        .. arityText(
            TempleTeleport.Get
        )
    )

    log(
        "SIG",
        "Legacy.is="
        .. arityText(
            Legacy.is
        )
    )

    log(
        "SIG",
        "Legacy.convert="
        .. arityText(
            Legacy.convert
        )
    )

    log(
        "SIG",
        "DialogueController.start="
        .. arityText(
            DialogueController.start
        )
    )

    log(
        "SIG",
        "NPCManager.startDialogue="
        .. arityText(
            NPCManager.startDialogue
        )
    )

    log(
        "SIG",
        "NPCManager.getNPCsByName="
        .. arityText(
            NPCManager.getNPCsByName
        )
    )
end

-- ============================================================
-- GUI
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
        "MFRemoteDialogueApiTestV2"
    )

if old then
    old:Destroy()
end

local Gui =
    Instance.new("ScreenGui")

Gui.Name =
    "MFRemoteDialogueApiTestV2"

Gui.ResetOnSpawn = false
Gui.Parent = parent

local Frame =
    Instance.new("Frame")

Frame.Size =
    UDim2.fromOffset(
        780,
        500
    )

Frame.Position =
    UDim2.new(
        0.5,
        -390,
        0.5,
        -250
    )

Frame.BackgroundColor3 =
    Color3.fromRGB(18,21,29)

Frame.BorderSizePixel = 0
Frame.Active = true
Frame.Parent = Gui

local corner =
    Instance.new("UICorner")

corner.CornerRadius =
    UDim.new(0,10)

corner.Parent = Frame

local Header =
    Instance.new("TextLabel")

Header.BackgroundTransparency = 1
Header.Position =
    UDim2.fromOffset(12,7)

Header.Size =
    UDim2.new(1,-24,0,30)

Header.Font =
    Enum.Font.GothamBold

Header.TextSize = 14

Header.TextColor3 =
    Color3.new(1,1,1)

Header.TextXAlignment =
    Enum.TextXAlignment.Left

Header.Text =
    "MYSTERIOUS FORCE - REMOTE DIALOGUE API TEST V2"

Header.Active = true
Header.Parent = Frame

Scroll =
    Instance.new("ScrollingFrame")

Scroll.Position =
    UDim2.fromOffset(12,44)

Scroll.Size =
    UDim2.new(1,-24,1,-104)

Scroll.BackgroundColor3 =
    Color3.fromRGB(8,11,17)

Scroll.BorderSizePixel = 0
Scroll.ScrollBarThickness = 12
Scroll.AutomaticCanvasSize =
    Enum.AutomaticSize.Y
Scroll.CanvasSize =
    UDim2.new(0,0,0,0)
Scroll.Parent = Frame

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

local function button(
    text,
    x,
    callback
)
    local b =
        Instance.new("TextButton")

    b.AnchorPoint =
        Vector2.new(0,1)

    b.Position =
        UDim2.new(
            x,
            8,
            1,
            -12
        )

    b.Size =
        UDim2.new(
            0.24,
            -10,
            0,
            48
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
    b.Parent = Frame

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

button(
    "1) GET -> LEGACY.CONVERT -> START",
    0,
    testConvertAndStart
).BackgroundColor3 =
    Color3.fromRGB(45,95,70)

button(
    "2) NPC LOOKUP\nMysterious Force",
    0.25,
    testNpcLookup
)

button(
    "DUMP\nSIGNATURES",
    0.5,
    dumpSignatures
)

button(
    "RESET BUSY\n+ CLOSE",
    0.75,
    function()
        busy = false
        safeClose()
        log(
            "RESET",
            "busy=false"
        )
    end
)

-- Drag
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
        startPos = Frame.Position
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
            input.Position
            - dragStart

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
    if input.UserInputType
        == Enum.UserInputType.MouseButton1
        or input.UserInputType
        == Enum.UserInputType.Touch
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

log(
    "WHY V1 FAILED",
    "TempleTeleport.Get() returned raw legacy table;"
    .. " DialogueController.start expected Dialogue with _openTop."
)

dumpSignatures()
