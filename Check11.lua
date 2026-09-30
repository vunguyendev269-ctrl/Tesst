-- ============================================================
-- CẤU HÌNH DANH SÁCH BỎ QUA (Điền dạng bảng bên dưới)
-- Hỗ trợ cả Username và DisplayName, không phân biệt hoa thường
-- ============================================================
getgenv().IgnoreNames = {
    "BaconPulseSpark2006",
    "BeastBearAlpha51"
}

repeat task.wait(0.25) until game:IsLoaded()

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- ============================================================
-- HÀM KIỂM TRA CHẶN (CHECK NGAY LẬP TỨC ĐẦU SCRIPT)
-- ============================================================
local function cleanStr(str)
    return tostring(str or ""):lower():gsub("%s+", "")
end

local function checkShouldIgnore()
    local rawList = getgenv().IgnoreNames or getgenv().names or getgenv().name or {}
    
    -- Nếu người dùng vô tình truyền vào 1 chuỗi string đơn lẻ thay vì table
    local list = {}
    if type(rawList) == "string" then
        for name in string.gmatch(rawList, "[^,%s]+") do
            table.insert(list, name)
        end
    elseif type(rawList) == "table" then
        list = rawList
    end

    if #list == 0 then
        return false
    end

    -- 1. Kiểm tra tài khoản đang chạy (LocalPlayer)
    local myName = cleanStr(LocalPlayer.Name)
    local myDisplay = cleanStr(LocalPlayer.DisplayName)

    for _, target in ipairs(list) do
        local targetClean = cleanStr(target)
        if targetClean ~= "" and (targetClean == myName or targetClean == myDisplay) then
            warn(string.format("[V4-TITLE] LocalPlayer (%s) nằm trong danh sách bỏ qua -> DỪNG SCRIPT!", LocalPlayer.Name))
            return true
        end
    end

    -- 2. Kiểm tra nếu có bất kỳ ai trong server trùng tên trong danh sách
    for _, player in ipairs(Players:GetPlayers()) do
        local pName = cleanStr(player.Name)
        local pDisplay = cleanStr(player.DisplayName)

        for _, target in ipairs(list) do
            local targetClean = cleanStr(target)
            if targetClean ~= "" and (targetClean == pName or targetClean == pDisplay) then
                warn(string.format("[V4-TITLE] Phát hiện player trong server (%s / %s) khớp danh sách bỏ qua -> DỪNG SCRIPT!", player.Name, player.DisplayName))
                return true
            end
        end
    end

    return false
end

-- Thực hiện kiểm tra ngay lập tức
if checkShouldIgnore() then
    return
end

-- ============================================================
-- 1) CHOOSE TEAM
-- ============================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CommF_ = Remotes:WaitForChild("CommF_")

local function chooseTeam()
    if LocalPlayer.Team then return true end

    local playerGui = LocalPlayer:WaitForChild("PlayerGui")
    while playerGui:FindFirstChild("LoadingScreen") do
        task.wait(0.5)
    end

    while not LocalPlayer.Team do
        pcall(function()
            CommF_:InvokeServer("SetTeam", "Pirates")
        end)

        if not LocalPlayer.Team then
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
-- 2) SCAN V4 TITLES
-- ============================================================
local TITLE_FIELDS = { title = true, name = true, titlename = true, displayname = true }
local V4_TITLE_TARGETS = {
    { title = "His Majesty",          race = "angel"  },
    { title = "Berserker",            race = "human"  },
    { title = "Thunderbolt",          race = "rabbit" },
    { title = "Leviathan",            race = "shark"  },
    { title = "Nightwalker",          race = "ghoul"  },
    { title = "Genesis",              race = "cyborg" },
    { title = "Primordial Guardian",  race = "draco"  },
}

local function normalizeText(value)
    return tostring(value or ""):lower():gsub("[^%w]", "")
end

local function exactTitleMatch(targetTitle, value)
    return normalizeText(targetTitle) == normalizeText(value)
end

local function walkTables(value, depth, visited, callback)
    if type(value) ~= "table" or depth > 10 or visited[value] then return end
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
        if type(value) ~= "table" and TITLE_FIELDS[normalizedKey] and exactTitleMatch(targetTitle, value) then
            return true
        end
        if type(key) == "string" and exactTitleMatch(targetTitle, key) then
            return true
        end
    end
    return false
end

local function invokeGetTitles(timeoutSeconds)
    local completed, okResult, dataResult = false, false, nil
    task.spawn(function()
        local ok, data = pcall(function() return CommF_:InvokeServer("getTitles") end)
        okResult, dataResult, completed = ok, (ok and data or nil), true
    end)

    local deadline = tick() + (tonumber(timeoutSeconds) or 3)
    repeat task.wait(0.05) until completed or tick() >= deadline

    if not completed then return false, nil, "timeout" end
    if not okResult or type(dataResult) ~= "table" then return false, nil, "remote_failed" end
    return true, dataResult, nil
end

local function scanOwnedV4Titles()
    local ok, remoteData, err = invokeGetTitles(3)
    if not ok then return false, nil, err end

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
-- 3) 3 CONSECUTIVE CONFIRMATIONS
-- ============================================================
local REQUIRED_CONFIRMATIONS = 3
local CONFIRM_GAP = 1.0
local lastSignature, confirmCount, confirmedRaces = nil, 0, nil

while true do
    local ok, races, err = scanOwnedV4Titles()

    if not ok then
        confirmCount, lastSignature = 0, nil
        warn("[V4-TITLE] getTitles failed: " .. tostring(err))
        task.wait(CONFIRM_GAP)
        continue
    end

    if #races == 0 then
        confirmCount, lastSignature = 0, nil
        warn("[V4-TITLE] No owned V4 title detected...")
        task.wait(CONFIRM_GAP)
        continue
    end

    local sig = signatureOf(races)
    if sig == lastSignature then
        confirmCount += 1
    else
        lastSignature, confirmCount = sig, 1
    end

    print(string.format("[V4-TITLE] Confirm %d/%d | races=%s", confirmCount, REQUIRED_CONFIRMATIONS, table.concat(races, ",")))

    if confirmCount >= REQUIRED_CONFIRMATIONS then
        confirmedRaces = races
        break
    end
    task.wait(CONFIRM_GAP)
end

-- Kiểm tra lại lần 2 trước khi ghi file đề phòng người chơi vào sau
if checkShouldIgnore() then
    return
end

-- ============================================================
-- 4) WRITE FILE
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

print("[V4-TITLE] DONE -> " .. fileName .. " = " .. content)
