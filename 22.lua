-- MYSTERIOUS FORCE INTERACT SAFE DEBUGGER V3
-- Fix: no hook at startup; temporary CommF_-only hook on ARM; auto-unhook after capture/timeout.

if not game:IsLoaded() then game.Loaded:Wait() end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")

local LP = Players.LocalPlayer
local PlayerGui = LP:WaitForChild("PlayerGui", 15)
local CommF = RS:WaitForChild("Remotes"):WaitForChild("CommF_")

local TEMPLE_POS = Vector3.new(28286.35546875,14896.5078125,102.62469482421875)
local LOG_FILE = "MYSTERIOUS_FORCE_INTERACT_SAFE_V3.txt"

local Capture = {mode="OFF", untilTime=0, stopRequested=false}
local hookInstalled = false
local oldNamecall
local queue = {}

local logs = {}
local LogLabel
local Scroll
local StatusLabel
local dirty = false

local function getRoot()
    local c = LP.Character
    local h = c and c:FindFirstChildOfClass("Humanoid")
    local r = c and c:FindFirstChild("HumanoidRootPart")
    if c and h and r and h.Health > 0 then return r end
end

local function q(s)
    return string.format("%q", tostring(s))
end

local function instancePath(inst)
    local parts = {}
    local cur = inst

    while cur and cur ~= game do
        table.insert(parts,1,cur.Name)
        cur = cur.Parent
    end

    if not cur or #parts == 0 then return "nil" end

    local expr = 'game:GetService('..q(parts[1])..')'
    for i=2,#parts do
        expr = expr..":WaitForChild("..q(parts[i])..")"
    end
    return expr
end

local function toLua(v)
    local t = typeof(v)

    if t == "nil" then
        return "nil"
    elseif t == "string" then
        return q(v)
    elseif t == "number" or t == "boolean" then
        return tostring(v)
    elseif t == "Vector3" then
        return string.format("Vector3.new(%.6f, %.6f, %.6f)",v.X,v.Y,v.Z)
    elseif t == "CFrame" then
        local p = v.Position
        return string.format("CFrame.new(%.6f, %.6f, %.6f)",p.X,p.Y,p.Z)
    elseif t == "Instance" then
        return instancePath(v)
    end

    return q(tostring(v))
end

local function copyArgs(...)
    local n = select("#",...)
    local t = {n=n}
    for i=1,n do t[i] = select(i,...) end
    return t
end

local function argsLua(args)
    local out = {}
    for i=1,args.n or 0 do
        out[#out+1] = toLua(args[i])
    end
    return table.concat(out,", ")
end

local function refresh()
    if not LogLabel then return end

    local first = math.max(1,#logs-140)
    local view = {}

    for i=first,#logs do
        view[#view+1] = logs[i]
    end

    LogLabel.Text = table.concat(view,"\n")

    task.defer(function()
        if Scroll then
            Scroll.CanvasPosition = Vector2.new(
                0,
                math.max(0,Scroll.AbsoluteCanvasSize.Y-Scroll.AbsoluteWindowSize.Y)
            )
        end
    end)
end

local function log(tag,msg,mode)
    local line = string.format(
        "[%.3f][%s][%s] %s",
        os.clock(),
        mode or Capture.mode,
        tag,
        tostring(msg)
    )

    logs[#logs+1] = line
    if #logs > 900 then table.remove(logs,1) end

    print("[MF SAFE V3] "..line)
    dirty = true
    refresh()
end

task.spawn(function()
    while true do
        task.wait(0.75)
        if dirty and type(writefile) == "function" then
            dirty = false
            pcall(function()
                writefile(LOG_FILE,table.concat(logs,"\n"))
            end)
        end
    end
end)

-- UI observer: never hooks anything.
local lastOpen = false
local lastUse = false

local function scanMenu()
    local open = false
    local use = false

    for _,obj in ipairs(PlayerGui:GetDescendants()) do
        if obj:IsA("TextLabel") or obj:IsA("TextButton") then
            local ok,text = pcall(function() return tostring(obj.Text or "") end)
            local s = ok and text:lower() or ""

            if s:find("mysterious force",1,true)
                or s:find("remnant of the past",1,true)
            then
                open = true
            end

            if obj:IsA("TextButton") and s:find("use it",1,true) then
                use = true
            end
        end
    end

    return open,use
end

task.spawn(function()
    while true do
        task.wait(0.15)

        local open,use = scanMenu()

        if open ~= lastOpen then
            lastOpen = open
            log("UI",open and "Mysterious Force menu OPEN" or "Mysterious Force menu CLOSED","OBSERVE")
        end

        if use ~= lastUse then
            lastUse = use
            if use then
                log("UI",'"Use it" VISIBLE',"OBSERVE")
            end
        end
    end
end)

local function restoreHook(reason)
    Capture.mode = "OFF"
    Capture.untilTime = 0
    Capture.stopRequested = false

    if not hookInstalled then return true end

    local ok = false

    if type(hookmetamethod) == "function" and type(oldNamecall) == "function" then
        ok = pcall(function()
            hookmetamethod(game,"__namecall",oldNamecall)
        end)
    end

    hookInstalled = false
    log("TRACE","hook OFF | "..tostring(reason or ""),"OFF")
    return ok
end

local function installHook()
    if hookInstalled then return true end

    if type(hookmetamethod) ~= "function"
        or type(getnamecallmethod) ~= "function"
    then
        log("ERROR","hookmetamethod/getnamecallmethod unavailable","OFF")
        return false
    end

    local wrap = type(newcclosure) == "function" and newcclosure or function(f) return f end

    local ok,err = pcall(function()
        oldNamecall = hookmetamethod(
            game,
            "__namecall",
            wrap(function(self,...)
                -- fastest exit: only active short capture window
                if Capture.mode == "OFF" or os.clock() > Capture.untilTime then
                    return oldNamecall(self,...)
                end

                -- important: ignore every remote except CommF_
                if self ~= CommF then
                    return oldNamecall(self,...)
                end

                local method = getnamecallmethod()
                if method ~= "InvokeServer" and method ~= "FireServer" then
                    return oldNamecall(self,...)
                end

                queue[#queue+1] = {
                    mode=Capture.mode,
                    method=method,
                    args=copyArgs(...)
                }

                Capture.stopRequested = true

                -- game call passes through untouched
                return oldNamecall(self,...)
            end)
        )
    end)

    if not ok then
        log("ERROR","hook install failed: "..tostring(err),"OFF")
        return false
    end

    hookInstalled = true
    log("TRACE","temporary CommF_-only hook ON")
    return true
end

local function arm(mode)
    if hookInstalled then
        restoreHook("re-arm")
        task.wait(0.05)
    end

    if not installHook() then return end

    Capture.mode = mode
    Capture.untilTime = os.clock()+5
    Capture.stopRequested = false

    log("ARM",mode.." for 5s")
end

-- Process captured commands outside hook, then immediately remove hook.
task.spawn(function()
    while true do
        task.wait(0.015)

        if #queue > 0 then
            local batch = queue
            queue = {}

            for _,item in ipairs(batch) do
                local cmd =
                    instancePath(CommF)
                    ..":"..item.method
                    .."("..argsLua(item.args)..")"

                log("REMOTE",item.method.." "..CommF:GetFullName(),item.mode)
                log("CMD",cmd,item.mode)
            end
        end

        if hookInstalled then
            if Capture.stopRequested then
                Capture.stopRequested = false
                task.wait(0.03)
                restoreHook("captured CommF_")

            elseif Capture.mode ~= "OFF"
                and os.clock() > Capture.untilTime
            then
                restoreHook("timeout")
            end
        end
    end
end)

-- Passive HRP jump monitor.
task.spawn(function()
    local lastPos

    while true do
        task.wait(0.03)
        local r = getRoot()

        if r then
            local p = r.Position

            if lastPos then
                local jump = (p-lastPos).Magnitude

                if jump >= 1000 then
                    log(
                        "HRP",
                        "JUMP "..string.format("%.1f",jump)
                        .." FROM="..tostring(lastPos)
                        .." TO="..tostring(p)
                        .." TempleDist="..string.format("%.3f",(p-TEMPLE_POS).Magnitude),
                        "OBSERVE"
                    )
                end
            end

            lastPos = p
        else
            lastPos = nil
        end
    end
end)

-- GUI
local parent = CoreGui
pcall(function()
    if type(gethui) == "function" then parent = gethui() end
end)

local old = parent:FindFirstChild("MFInteractSafeDebuggerV3")
if old then old:Destroy() end

local Gui = Instance.new("ScreenGui")
Gui.Name = "MFInteractSafeDebuggerV3"
Gui.ResetOnSpawn = false
Gui.Parent = parent

local Frame = Instance.new("Frame")
Frame.Size = UDim2.fromOffset(760,430)
Frame.Position = UDim2.new(0.5,-380,0.5,-215)
Frame.BackgroundColor3 = Color3.fromRGB(18,21,29)
Frame.BorderSizePixel = 0
Frame.Active = true
Frame.Parent = Gui

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(0,10)
Corner.Parent = Frame

local Header = Instance.new("TextLabel")
Header.BackgroundTransparency = 1
Header.Position = UDim2.fromOffset(12,7)
Header.Size = UDim2.new(1,-230,0,28)
Header.Font = Enum.Font.GothamBold
Header.TextSize = 14
Header.TextColor3 = Color3.new(1,1,1)
Header.TextXAlignment = Enum.TextXAlignment.Left
Header.Text = "MYSTERIOUS FORCE INTERACT SAFE DEBUGGER V3"
Header.Active = true
Header.Parent = Frame

StatusLabel = Instance.new("TextLabel")
StatusLabel.BackgroundTransparency = 1
StatusLabel.AnchorPoint = Vector2.new(1,0)
StatusLabel.Position = UDim2.new(1,-12,0,7)
StatusLabel.Size = UDim2.fromOffset(220,28)
StatusLabel.Font = Enum.Font.Code
StatusLabel.TextSize = 11
StatusLabel.TextXAlignment = Enum.TextXAlignment.Right
StatusLabel.TextColor3 = Color3.fromRGB(170,220,255)
StatusLabel.Parent = Frame

Scroll = Instance.new("ScrollingFrame")
Scroll.Position = UDim2.fromOffset(12,42)
Scroll.Size = UDim2.new(1,-24,1,-120)
Scroll.BackgroundColor3 = Color3.fromRGB(8,11,17)
Scroll.BorderSizePixel = 0
Scroll.ScrollBarThickness = 7
Scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
Scroll.CanvasSize = UDim2.new(0,0,0,0)
Scroll.Parent = Frame

LogLabel = Instance.new("TextLabel")
LogLabel.BackgroundTransparency = 1
LogLabel.Position = UDim2.fromOffset(7,5)
LogLabel.Size = UDim2.new(1,-14,0,0)
LogLabel.AutomaticSize = Enum.AutomaticSize.Y
LogLabel.Font = Enum.Font.Code
LogLabel.TextSize = 11
LogLabel.TextColor3 = Color3.fromRGB(215,225,240)
LogLabel.TextWrapped = true
LogLabel.TextXAlignment = Enum.TextXAlignment.Left
LogLabel.TextYAlignment = Enum.TextYAlignment.Top
LogLabel.Parent = Scroll

local function makeButton(text,x,cb)
    local b = Instance.new("TextButton")
    b.AnchorPoint = Vector2.new(0,1)
    b.Position = UDim2.new(x,8,1,-12)
    b.Size = UDim2.new(0.24,-10,0,50)
    b.BackgroundColor3 = Color3.fromRGB(40,47,64)
    b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamBold
    b.TextSize = 11
    b.TextWrapped = true
    b.TextColor3 = Color3.new(1,1,1)
    b.Text = text
    b.Parent = Frame

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0,7)
    c.Parent = b

    b.MouseButton1Click:Connect(cb)
    return b
end

local npc = makeButton("ARM NPC CLICK\n5 sec",0,function() arm("NPC") end)
npc.BackgroundColor3 = Color3.fromRGB(65,65,105)

local use = makeButton("ARM USE IT\n5 sec",0.25,function() arm("USE") end)
use.BackgroundColor3 = Color3.fromRGB(45,95,70)

makeButton("FORCE HOOK OFF",0.5,function()
    restoreHook("manual")
end)

makeButton("CLEAR LOG",0.75,function()
    logs = {}
    dirty = true
    refresh()
    log("LOG","cleared","OFF")
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
            startPos.X.Scale,startPos.X.Offset+d.X,
            startPos.Y.Scale,startPos.Y.Offset+d.Y
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

task.spawn(function()
    while Gui.Parent do
        task.wait(0.1)

        local remain = ""
        if Capture.mode ~= "OFF" and os.clock() <= Capture.untilTime then
            remain = " "..string.format("%.1fs",Capture.untilTime-os.clock())
        end

        StatusLabel.Text =
            "HOOK: "..(hookInstalled and "ON" or "OFF")
            .." | CAPTURE: "..Capture.mode..remain

        StatusLabel.TextColor3 =
            hookInstalled
            and Color3.fromRGB(80,255,150)
            or Color3.fromRGB(170,220,255)
    end
end)

Gui.AncestryChanged:Connect(function(_,p)
    if p == nil then restoreHook("gui destroyed") end
end)

log("READY","NO hook at startup; NPC interaction remains normal.","OFF")
log("HOWTO","ARM NPC CLICK -> click NPC immediately.","OFF")
log("HOWTO","Menu open -> ARM USE IT -> click Use it.","OFF")
