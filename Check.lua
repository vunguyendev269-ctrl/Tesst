--[[
    V4 TITLE CHECKER - STANDALONE
    Flow:
      1) Choose Team (Pirates)
      2) Check owned V4 titles via CommF_:InvokeServer("getTitles")
      3) Require 3 consecutive successful scans with the exact same owned-title set
      4) Write <PlayerName>.txt => Completed-<count>r<race1><race2>...

    Example:
      Angel only          -> Completed-1rangel
      Angel + Human       -> Completed-2rangelhuman
      Angel+Human+Rabbit  -> Completed-3rangelhumanrabbit

    Deterministic output order:
      Angel, Human, Rabbit, Shark, Ghoul, Cyborg, Draco
]]

repeat task.wait(0.25) until game:IsLoaded()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CommF_ = Remotes:WaitForChild("CommF_")

-- ============================================================
-- 1) CHOOSE TEAM - same style as Kaitun V3
-- ============================================================
local function chooseTeam()
    if LocalPlayer.Team then
        return true
    end

    local playerGui = LocalPlayer:WaitForChild("PlayerGui")
    while playerGui:FindFirstChild("LoadingScreen") do
        task.wait(0.5)
    end

    while not LocalPlayer.Team do
        local ok = pcall(function()
            CommF_:InvokeServer("SetTeam", "Pirates")
        end)

        if not ok or not LocalPlayer.Team then
            pcall(function()
                local minimal = playerGui:FindFirstChild("Main (minimal)")
                local choose = minimal and minimal:FindFirstChild("ChooseTeam")
                local container = choose and choose:FindFirstChild("Container")
                local pirates = container and container:FindFirstChild("Pirates")
                if pirates and firesignal then
                    firesignal(pirates)
                end
            end)
        end

        task.wait(1)
    end

    return true
end

chooseTeam()

-- ============================================================
-- 2) EXACT V4 TITLE CHECKER - based on Kaitun V3 getTitles scan
-- ============================================================
local TITLE_FIELDS = {
    title = true,
    name = true,
    titlename = true,
    displayname = true,
}

-- Output order is fixed only so the file content is deterministic.
-- Ownership is determined ONLY by title possession.
local V4_TITLE_TARGETS = {
    { title = "His Majesty",          race = "angel"  }, -- Angel V4
    { title = "Berserker",            race = "human"  }, -- Human V4
    { title = "Thunderbolt",          race = "rabbit" }, -- Rabbit V4
    { title = "Leviathan",            race = "shark"  }, -- Shark V4
    { title = "Nightwalker",          race = "ghoul"  }, -- Ghoul V4
    { title = "Genesis",              race = "cyborg" }, -- Cyborg V4
    { title = "Primordial Guardian",  race = "draco"  }, -- Draco V4
}

local function normalizeText(value)
    return tostring(value or ""):lower():gsub("[^%w]", "")
end

local function exactTitleMatch(targetTitle, value)
    return normalizeText(targetTitle) == normalizeText(value)
end

local function walkTables(value, depth, visited, callback)
    if type(value) ~= "table" or depth > 10 then
        return
    end
    if visited[value] then
        return
    end

    visited[value] = true
    callback(value)

    for _, child in pairs(value) do
        if type(child) == "table" then
            walkTables(child, depth + 1, visited, callback)
        end
    end
end

local function nodeHasExactTitle(node, targetTitle)
    for key, value in pairs(node) do
        local normalizedKey = normalizeText(key)

        if type(value) ~= "table"
            and TITLE_FIELDS[normalizedKey]
            and exactTitleMatch(targetTitle, value)
        then
            return true
        end

        if type(key) == "string" and exactTitleMatch(targetTitle, key) then
            return true
        end
    end

    return false
end

local function invokeGetTitles(timeoutSeconds)
    local completed = false
    local okResult = false
    local dataResult = nil

    task.spawn(function()
        local ok, data = pcall(function()
            return CommF_:InvokeServer("getTitles")
        end)
        okResult = ok
        dataResult = ok and data or nil
        completed = true
    end)

    local deadline = tick() + (tonumber(timeoutSeconds) or 3)
    repeat
        task.wait(0.05)
    until completed or tick() >= deadline

    if not completed then
        return false, nil, "timeout"
    end

    if not okResult or type(dataResult) ~= "table" then
        return false, nil, "remote_failed"
    end

    return true, dataResult, nil
end

local function scanOwnedV4Titles()
    local ok, remoteData, err = invokeGetTitles(3)
    if not ok then
        return false, nil, err
    end

    local owned = {}

    for _, target in ipairs(V4_TITLE_TARGETS) do
        local found = false

        walkTables(remoteData, 0, {}, function(node)
            if not found and nodeHasExactTitle(node, target.title) then
                found = true
            end
        end)

        if found then
            table.insert(owned, target.race)
        end
    end

    return true, owned, nil
end

local function signatureOf(races)
    return table.concat(races or {}, "|")
end

local function buildCompletedText(races)
    return "Completed-" .. tostring(#races) .. "r" .. table.concat(races, "")
end

-- ============================================================
-- 3) CONFIRM EXACT SAME RESULT 3 CONSECUTIVE FRESH SCANS
-- ============================================================
local REQUIRED_CONFIRMATIONS = 3
local CONFIRM_GAP = 1.0

local lastSignature = nil
local confirmCount = 0
local confirmedRaces = nil

while true do
    local ok, races, err = scanOwnedV4Titles()

    if not ok then
        confirmCount = 0
        lastSignature = nil
        warn("[V4-TITLE] getTitles failed: " .. tostring(err) .. " -> reset confirm")
        task.wait(CONFIRM_GAP)
        continue
    end

    if #races == 0 then
        confirmCount = 0
        lastSignature = nil
        warn("[V4-TITLE] No owned V4 title detected -> waiting...")
        task.wait(CONFIRM_GAP)
        continue
    end

    local sig = signatureOf(races)

    if sig == lastSignature then
        confirmCount += 1
    else
        lastSignature = sig
        confirmCount = 1
    end

    print(string.format(
        "[V4-TITLE] Confirm %d/%d | races=%s",
        confirmCount,
        REQUIRED_CONFIRMATIONS,
        table.concat(races, ",")
    ))

    if confirmCount >= REQUIRED_CONFIRMATIONS then
        confirmedRaces = races
        break
    end

    task.wait(CONFIRM_GAP)
end

-- ============================================================
-- 4) WRITE PlayerName.txt
-- ============================================================
local fileName = LocalPlayer.Name .. ".txt"
local content = buildCompletedText(confirmedRaces)

if type(writefile) ~= "function" then
    error("[V4-TITLE] writefile is not available in this executor")
end

local okWrite, writeErr = pcall(function()
    writefile(fileName, content)
end)

if not okWrite then
    error("[V4-TITLE] Failed to write " .. fileName .. ": " .. tostring(writeErr))
end

-- Optional verification when executor supports readfile/isfile.
local verified = true
if type(isfile) == "function" then
    local ok, exists = pcall(isfile, fileName)
    if ok and exists == false then
        verified = false
    end
end

if verified and type(readfile) == "function" then
    local ok, readBack = pcall(readfile, fileName)
    if ok and tostring(readBack or "") ~= content then
        verified = false
    end
end

if not verified then
    error("[V4-TITLE] writefile returned but verification failed: " .. fileName)
end

print("[V4-TITLE] DONE -> " .. fileName .. " = " .. content)
