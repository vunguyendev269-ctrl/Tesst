-- MYSTERIOUS FORCE - ONE CLICK OPEN UI + OPTION1
-- Flow:
--   DialogueController.start(TempleTeleport, npc)
--   -> wait Mysterious Force UI
--   -> getActiveDialogue()
--   -> find Option1 / "Use it"
--   -> DialogueController.select(option)
--   -> fallback option:onSelected()
--
-- No network hook.
-- No direct InvokeServer / FireServer.

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")

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

local busy = false

local function log(...)
    print("[MF ONE CLICK]", ...)
end

local function getRootPart()
    local char = LP.Character
    return char and char:FindFirstChild("HumanoidRootPart")
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

local function waitMysteriousUI(timeout)
    local deadline = os.clock() + (timeout or 3)

    repeat
        local root = getMysteriousRoot()

        if root then
            return root
        end

        task.wait(0.03)
    until os.clock() >= deadline

    return nil
end

local function getNpcWrapper()
    local ok, list =
        pcall(
            NPCManager.getNPCsByName,
            "Mysterious Force"
        )

    if not ok or type(list) ~= "table" then
        return nil
    end

    local worldModel = nil

    pcall(function()
        local folder = workspace:FindFirstChild("NPCs")

        worldModel =
            folder
            and folder:FindFirstChild("Mysterious Force")
    end)

    local first = nil

    for _,npc in pairs(list) do
        if type(npc) == "table" then
            first = first or npc

            if type(npc.getModel) == "function" then
                local okModel, model =
                    pcall(function()
                        return npc:getModel()
                    end)

                if okModel
                    and worldModel
                    and model == worldModel
                then
                    return npc
                end
            end
        end
    end

    return first
end

local function safeClose()
    pcall(function()
        if type(DialogueController.close) == "function" then
            DialogueController.close()
        end
    end)

    task.wait(0.08)
end

local function optionText(option)
    if type(option) ~= "table" then
        return ""
    end

    local fields = {
        "_text",
        "Text",
        "text",
        "Title",
        "title",
        "_label",
        "Label",
    }

    for _,key in ipairs(fields) do
        local ok, value =
            pcall(function()
                return option[key]
            end)

        if ok and type(value) == "string" then
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

    return ok and type(fn) == "function"
end

local function findOption1(active)
    if type(active) ~= "table" then
        return nil
    end

    -- Fast path: active._window._options
    local fastLists = {}

    pcall(function()
        if type(active._window) == "table"
            and type(active._window._options) == "table"
        then
            fastLists[#fastLists+1] = active._window._options
        end
    end)

    pcall(function()
        if type(active._options) == "table" then
            fastLists[#fastLists+1] = active._options
        end
    end)

    for _,list in ipairs(fastLists) do
        local fallback = nil

        for k,opt in pairs(list) do
            if isOptionObject(opt) then
                fallback = fallback or opt

                local txt = string.lower(optionText(opt))

                if string.find(txt, "use it", 1, true)
                    or tostring(k) == "1"
                    or tostring(k):lower() == "option1"
                then
                    return opt
                end
            end
        end

        if fallback then
            return fallback
        end
    end

    -- Recursive fallback.
    local seen = {}
    local firstOption = nil
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
            firstOption = firstOption or tbl

            local txt = string.lower(optionText(tbl))
            local p = string.lower(path)

            if string.find(txt, "use it", 1, true)
                or string.find(p, "option1", 1, true)
            then
                exact = tbl
                return
            end
        end

        for k,v in pairs(tbl) do
            if type(v) == "table" then
                walk(
                    v,
                    depth + 1,
                    path .. "." .. tostring(k)
                )

                if exact then
                    return
                end
            end
        end
    end

    walk(active, 0, "active")

    return exact or firstOption
end

local function triggerOption(option)
    if not option then
        return false, "option=nil"
    end

    -- First try the controller, matching normal game flow.
    local ok, ret =
        pcall(
            DialogueController.select,
            option
        )

    if ok then
        return true, "DialogueController.select"
    end

    log(
        "select(option) failed:",
        tostring(ret)
    )

    -- Some module methods may expect self explicitly.
    local okSelf, retSelf =
        pcall(
            DialogueController.select,
            DialogueController,
            option
        )

    if okSelf then
        return true, "DialogueController.select(self, option)"
    end

    log(
        "select(self,option) failed:",
        tostring(retSelf)
    )

    -- Last fallback: call Option:onSelected().
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
            return true, "option:onSelected()"
        end

        return false,
            "onSelected error: "
            .. tostring(retDirect)
    end

    return false, "no usable select/onSelected"
end

local function runOneClick()
    if busy then
        log("BUSY")
        return
    end

    busy = true

    task.spawn(function()
        local okMain, errMain =
            pcall(function()
                safeClose()

                local npc = getNpcWrapper()

                local okOpen, openRet

                if npc then
                    okOpen, openRet =
                        pcall(
                            DialogueController.start,
                            TempleTeleport,
                            npc
                        )
                else
                    okOpen, openRet =
                        pcall(
                            DialogueController.start,
                            TempleTeleport,
                            nil
                        )
                end

                log(
                    "OPEN",
                    okOpen,
                    openRet
                )

                if not okOpen then
                    return
                end

                local ui =
                    waitMysteriousUI(3)

                if not ui then
                    log("Mysterious Force UI NOT FOUND")
                    return
                end

                log("UI OPEN")

                -- Give the dialogue object/options one short frame to finish building.
                task.wait(0.08)

                local okActive, active =
                    pcall(
                        DialogueController.getActiveDialogue
                    )

                if not okActive
                    or type(active) ~= "table"
                then
                    log(
                        "ACTIVE DIALOGUE FAILED",
                        okActive,
                        active
                    )
                    return
                end

                local option =
                    findOption1(active)

                if not option then
                    log("OPTION1 NOT FOUND")
                    return
                end

                log(
                    "OPTION1 FOUND",
                    optionText(option)
                )

                local hrp = getRootPart()
                local before =
                    hrp and hrp.Position

                local selected, method =
                    triggerOption(option)

                log(
                    "OPTION1 TRIGGER",
                    selected,
                    method
                )

                -- Observe the known ~29k server teleport.
                if selected and before then
                    local deadline =
                        os.clock() + 2.5

                    while os.clock() < deadline do
                        task.wait(0.05)

                        hrp = getRootPart()

                        if hrp then
                            local jump =
                                (hrp.Position-before).Magnitude

                            if jump > 1000 then
                                log(
                                    "HRP JUMP",
                                    string.format(
                                        "%.1f studs -> %.1f, %.1f, %.1f",
                                        jump,
                                        hrp.Position.X,
                                        hrp.Position.Y,
                                        hrp.Position.Z
                                    )
                                )

                                return
                            end
                        end
                    end

                    log(
                        "OPTION1 ran but no >1000 stud jump."
                    )
                end
            end)

        if not okMain then
            log(
                "ERROR",
                tostring(errMain)
            )
        end

        busy = false
    end)
end

-- ============================================================
-- ONE-BUTTON GUI
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
        "MFOneClickOpenOption1"
    )

if old then
    old:Destroy()
end

local Gui =
    Instance.new("ScreenGui")

Gui.Name =
    "MFOneClickOpenOption1"

Gui.ResetOnSpawn = false
Gui.Parent = parent

local Button =
    Instance.new("TextButton")

Button.Size =
    UDim2.fromOffset(
        280,
        72
    )

Button.Position =
    UDim2.new(
        0.5,
        -140,
        0.65,
        0
    )

Button.BackgroundColor3 =
    Color3.fromRGB(42,95,69)

Button.BorderSizePixel = 0
Button.Font =
    Enum.Font.GothamBold
Button.TextSize = 15
Button.TextWrapped = true
Button.TextColor3 =
    Color3.new(1,1,1)

Button.Text =
    "OPEN MYSTERIOUS FORCE\n+ OPTION 1 (USE IT)"

Button.Parent = Gui

local corner =
    Instance.new("UICorner")

corner.CornerRadius =
    UDim.new(0,10)

corner.Parent = Button

Button.MouseButton1Click:Connect(
    runOneClick
)

log(
    "READY",
    "Click the single button."
)
