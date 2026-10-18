local redzlib = loadstring(game:HttpGet("https://raw.githubusercontent.com/nhat0258/Redz-UI-Library/refs/heads/main/Main.lua"))()

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local cash = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local placeUnit = game:GetService("ReplicatedStorage").RemoteFunctions.PlaceUnit
local changeTickSpeed = game:GetService("ReplicatedStorage").RemoteFunctions.ChangeTickSpeed
local skipWave = game:GetService("ReplicatedStorage").RemoteFunctions.SkipWave
local restartGame = game:GetService("ReplicatedStorage").RemoteFunctions.RestartGame
local placeDifficultyVote = game:GetService("ReplicatedStorage").RemoteFunctions.PlaceDifficultyVote
local upgradeAll = game:GetService("ReplicatedStorage").RemoteFunctions.UpgradeAll

local API_CONFIG = {
    BaseUrl = "https://api-nxswebhook.nhatbinhduong37.workers.dev",
    WebUrl = "https://api-nxswebhook.oneapp.dev/",
    UpdatePath = "/api/update",
    HeartbeatPath = "/api/heartbeat",
    Timeout = 10,
    Debounce = 1.5,
    MinInterval = 5,
    HeartbeatInterval = 0,
    MaxBackoff = 120,
}
local API_CONFIG_FILE = "NexusStella_Api.json"

local TOKEN = ""
local tokenLinked = false
local webhookEnabled = false
local CONFIG_FILE = "Nexus Stella - Graden Tower Defense.json"
local CONFIG_FILE_ALT = "NexusStella_GardenTD_Token.json"
local CONFIG_TXT = "NexusStella_Token.txt"
local FARM_URL_MEDIUM = "https://raw.githubusercontent.com/nguyennhlat2004/NexusYeuEm/refs/heads/main/Volcano-Medium.lua"
local FARM_URL_HARD = "https://raw.githubusercontent.com/nguyennhlat2004/NexusYeuEm/refs/heads/main/Volcano-Hard.lua"
local FARM_URL_ACID_L4 = "https://raw.githubusercontent.com/nguyennhlat2004/NexusYeuEm/refs/heads/main/AcidRoom-Level4.lua"
local currentFarm = "Volcano"
local selectedAcidLevel = "Level 4"
local selectedFarmMode = "Medium"
local VOLCANO_MODE_MAP = {
    ["Volcano 1"] = "Easy",
    ["Volcano 2"] = "Medium",
    ["Volcano 3"] = "Hard",
    Easy = "Easy",
    Medium = "Medium",
    Hard = "Hard",
}
local autoFarmEnabled = false
local farmThread = nil

local function fileExists(path)
    local ok, res = pcall(function()
        if isfile then
            return isfile(path)
        end
        if readfile then
            readfile(path)
            return true
        end
        return false
    end)
    return ok and res == true
end

local function readFileSafe(path)
    local ok, data = pcall(function()
        if readfile then
            return readfile(path)
        end
        return nil
    end)
    if ok and type(data) == "string" then
        return data
    end
    return nil
end

local function writeFileSafe(path, content)
    local ok = pcall(function()
        if writefile then
            writefile(path, content)
            return true
        end
        error("no writefile")
    end)
    return ok == true
end

local function cleanToken(val)
    if val == nil then return "" end
    local s = tostring(val)
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    s = s:gsub("[\r\n\t]", "")
    return s
end

local function extractTokenFromTable(data)
    if type(data) ~= "table" then return "" end
    local keys = {"Token", "token", "TOKEN", "WebhookToken", "webhookToken"}
    for _, k in ipairs(keys) do
        if data[k] ~= nil and tostring(data[k]) ~= "" then
            return cleanToken(data[k])
        end
    end
    return ""
end

local function loadConfig()
    local paths = {CONFIG_FILE, CONFIG_FILE_ALT, CONFIG_TXT}
    for _, path in ipairs(paths) do
        if fileExists(path) then
            local raw = readFileSafe(path)
            if raw and raw ~= "" then
                local trimmed = raw:match("^%s*(.-)%s*$") or raw
                if trimmed:sub(1, 1) == "{" then
                    local ok, decoded = pcall(function()
                        return HttpService:JSONDecode(trimmed)
                    end)
                    if ok and type(decoded) == "table" then
                        local tok = extractTokenFromTable(decoded)
                        if tok ~= "" then
                            return decoded, tok, path
                        end
                        return decoded, "", path
                    end
                else
                    local tok = cleanToken(trimmed)
                    if tok ~= "" then
                        return {Token = tok}, tok, path
                    end
                end
            end
        end
    end
    return {}, "", nil
end

local function saveConfig(tokenOverride)
    local tok = cleanToken(tokenOverride ~= nil and tokenOverride or TOKEN)
    TOKEN = tok
    local payload = HttpService:JSONEncode({
        Token = tok,
        token = tok,
        SavedAt = os.time()
    })
    writeFileSafe(CONFIG_FILE, payload)
    writeFileSafe(CONFIG_FILE_ALT, payload)
    if tok ~= "" then
        writeFileSafe(CONFIG_TXT, tok)
    end
    return tok
end

do
    local _, tok = loadConfig()
    if tok ~= "" then
        TOKEN = tok
    end
end

do
    if fileExists(API_CONFIG_FILE) then
        local raw = readFileSafe(API_CONFIG_FILE)
        if raw and raw ~= "" then
            local ok, decoded = pcall(function()
                return HttpService:JSONDecode(raw)
            end)
            if ok and type(decoded) == "table" then
                local base = decoded.BaseUrl or decoded.baseUrl or decoded.ApiUrl or decoded.apiUrl
                if type(base) == "string" and base:sub(1, 8) == "https://" then
                    API_CONFIG.BaseUrl = cleanToken(base)
                end
                local web = decoded.WebUrl or decoded.webUrl
                if type(web) == "string" and web:sub(1, 8) == "https://" then
                    API_CONFIG.WebUrl = cleanToken(web)
                end
            end
        end
    end
end

local function resolveFarmMode(value)
    return VOLCANO_MODE_MAP[tostring(value or "")] or "Medium"
end

local function cleanNumber(val)
    if type(val) == "number" then return val end
    if type(val) == "string" then
        local cleaned = val:gsub(",", ""):gsub("%s", "")
        return tonumber(cleaned) or 0
    end
    return 0
end

local function getCashAmount()
    return cleanNumber(cash.Value)
end

local function getSeedsAmount()
    local ls = player:FindFirstChild("leaderstats")
    if not ls then
        return nil
    end
    local seedsStat = ls:FindFirstChild("Seeds")
    if not seedsStat then
        return nil
    end
    local ok, value = pcall(function()
        return seedsStat.Value
    end)
    if not ok or value == nil then
        return nil
    end
    if type(value) == "number" then
        if value ~= value or value < 0 then
            return nil
        end
        return value
    end
    if type(value) == "string" then
        local cleaned = value:gsub(",", ""):gsub("%s", "")
        local n = tonumber(cleaned)
        if n and n >= 0 then
            return n
        end
    end
    return nil
end

local function getWaveNumber()
    local paths = {
        function()
            return player.PlayerGui.GameGuiNoInset.Screen.Top.GameInfo.Content.Waves.Title
        end,
        function()
            return player.PlayerGui.GameGui.Screen.Top.GameInfo.Content.Waves.Title
        end,
    }
    for _, getter in ipairs(paths) do
        local ok, title = pcall(getter)
        if ok and title and title:IsA("TextLabel") then
            local text = title.Text or ""
            local wave = text:match("[Ww]ave%s*(%d+)")
            if wave then
                return tonumber(wave) or 0
            end
            local a = text:match("(%d+)%s*/%s*%d+")
            if a then
                return tonumber(a) or 0
            end
        end
    end
    return 0
end

local function getEntitiesFolder()
    local ok, folder = pcall(function()
        return workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Entities")
    end)
    if ok and folder then
        return folder
    end
    local ok2, folder2 = pcall(function()
        return workspace:FindFirstChild("Entities")
    end)
    if ok2 then
        return folder2
    end
    return nil
end

local function getOwnedUnitCount()
    local folder = getEntitiesFolder()
    if not folder then
        return 0
    end
    local count = 0
    local ok, children = pcall(function()
        return folder:GetChildren()
    end)
    if not ok or type(children) ~= "table" then
        return 0
    end
    for _, child in ipairs(children) do
        local n = string.lower(tostring(child.Name or ""))
        if n:sub(1, 5) == "unit_" then
            count = count + 1
        end
    end
    return count
end

local function isVisible(path)
    local ok, gui = pcall(function()
        local cur = player.PlayerGui
        for part in path:gmatch("[^.]+") do
            cur = cur[part]
        end
        return cur
    end)
    return ok and gui and gui.Visible == true
end

local function waitUntilHidden(path)
    while autoFarmEnabled and isVisible(path) do task.wait(0.5) end
end

local function waitForGameStart(difficulty)
    difficulty = difficulty or "dif_normal"
    while autoFarmEnabled do
        if isVisible("GameGui.Screen.Middle.GameEnd") then
            pcall(function() restartGame:InvokeServer() end)
            waitUntilHidden("GameGui.Screen.Middle.GameEnd")
        elseif isVisible("GameGui.Screen.Middle.DifficultyVote") then
            pcall(function() placeDifficultyVote:InvokeServer(difficulty) end)
            waitUntilHidden("GameGui.Screen.Middle.DifficultyVote")
        else
            break
        end
        task.wait(0.5)
    end
end

local function clockNow()
    local ok, t = pcall(function()
        return tick()
    end)
    if ok and type(t) == "number" then
        return t
    end
    return os.time()
end

local syncState = {
    observedSeed = nil,
    observedAt = 0,
    lastSentSeed = nil,
    lastOkAt = 0,
    nextAllowedAt = 0,
    failCount = 0,
    inflight = false,
    authFailed = false,
    forceSend = false,
    needUpdate = true,
    lastStatus = "idle",
}

local function getRequestFunction()
    local fn = nil
    pcall(function()
        if syn and syn.request then
            fn = syn.request
        elseif http and http.request then
            fn = http.request
        elseif request then
            fn = request
        elseif http_request then
            fn = http_request
        elseif fluxus and fluxus.request then
            fn = fluxus.request
        end
    end)
    return fn
end

local function apiReady()
    local base = tostring(API_CONFIG.BaseUrl or "")
    if base == "" or base:find("YOUR-SUBDOMAIN", 1, true) then
        return false
    end
    return base:sub(1, 8) == "https://"
end

local function apiUrl(path)
    local base = tostring(API_CONFIG.BaseUrl or ""):gsub("/+$", "")
    return base .. tostring(path or "")
end

local function httpJson(method, url, payload, timeout)
    local fn = getRequestFunction()
    if not fn then
        return nil, 0, "no_request_function", nil
    end
    local body = nil
    if payload ~= nil then
        local okEnc, enc = pcall(function()
            return HttpService:JSONEncode(payload)
        end)
        if not okEnc or type(enc) ~= "string" then
            return nil, 0, "encode_failed", nil
        end
        body = enc
    end
    local headers = {
        ["Content-Type"] = "application/json",
        ["Accept"] = "application/json",
    }
    if TOKEN ~= "" then
        headers["Authorization"] = "Bearer " .. TOKEN
    end
    local box = {done = false, ok = false, res = nil}
    task.spawn(function()
        local ok, res = pcall(fn, {
            Url = url,
            Method = method,
            Headers = headers,
            Body = body,
        })
        box.ok = ok
        box.res = res
        box.done = true
    end)
    local started = clockNow()
    local limit = tonumber(timeout) or 10
    while not box.done do
        if clockNow() - started >= limit then
            return nil, 0, "timeout", nil
        end
        task.wait(0.1)
    end
    if not box.ok or type(box.res) ~= "table" then
        return nil, 0, "network_error", nil
    end
    local res = box.res
    local status = tonumber(res.StatusCode or res.Status or res.status_code or res.statusCode) or 0
    local raw = res.Body or res.body
    local data = nil
    if type(raw) == "string" and raw ~= "" then
        local okDec, dec = pcall(function()
            return HttpService:JSONDecode(raw)
        end)
        if okDec and type(dec) == "table" then
            data = dec
        end
    end
    local retryAfter = nil
    local h = res.Headers or res.headers
    if type(h) == "table" then
        retryAfter = tonumber(h["Retry-After"] or h["retry-after"] or h["RETRY-AFTER"])
    end
    return data, status, nil, retryAfter
end

local function scheduleRetry(retryAfter)
    syncState.failCount = syncState.failCount + 1
    local delay = API_CONFIG.MinInterval * (2 ^ math.min(syncState.failCount, 6))
    if delay > API_CONFIG.MaxBackoff then
        delay = API_CONFIG.MaxBackoff
    end
    if retryAfter and retryAfter > delay then
        delay = math.min(retryAfter, 600)
    end
    syncState.nextAllowedAt = clockNow() + delay
end

local function performSync(kind, seed)
    syncState.inflight = true
    pcall(function()
        local payload = {username = tostring(player.Name)}
        local path = API_CONFIG.HeartbeatPath
        if kind == "update" then
            payload.seed = seed
            path = API_CONFIG.UpdatePath
        end
        local data, status, _, retryAfter = httpJson("POST", apiUrl(path), payload, API_CONFIG.Timeout)
        local t = clockNow()
        if status >= 200 and status < 300 and type(data) == "table" and data.ok == true then
            syncState.failCount = 0
            syncState.lastOkAt = t
            syncState.nextAllowedAt = t + API_CONFIG.MinInterval
            tokenLinked = true
            if kind == "update" then
                syncState.lastSentSeed = seed
                syncState.needUpdate = false
            end
            syncState.lastStatus = "ok"
        elseif status == 401 or status == 403 then
            tokenLinked = false
            syncState.authFailed = true
            syncState.lastStatus = "auth_" .. tostring(status)
        elseif status == 404 and kind == "heartbeat" then
            syncState.needUpdate = true
            syncState.nextAllowedAt = t + API_CONFIG.HeartbeatInterval
            syncState.lastStatus = "not_registered"
        elseif status == 400 or status == 413 or status == 415 or status == 422 then
            syncState.nextAllowedAt = t + API_CONFIG.MaxBackoff
            syncState.lastStatus = "bad_request_" .. tostring(status)
        else
            scheduleRetry(retryAfter)
            syncState.lastStatus = "retry_" .. tostring(status)
        end
    end)
    syncState.inflight = false
end

local function syncTick()
    if not webhookEnabled or TOKEN == "" or syncState.authFailed or syncState.inflight or not apiReady() then
        return
    end
    local t = clockNow()
    local seed = getSeedsAmount()
    if seed ~= nil and seed ~= syncState.observedSeed then
        syncState.observedSeed = seed
        syncState.observedAt = t
    end
    if t < syncState.nextAllowedAt then
        return
    end
    if seed ~= nil and (syncState.needUpdate or syncState.forceSend or seed ~= syncState.lastSentSeed) then
        if syncState.forceSend or t - syncState.observedAt >= API_CONFIG.Debounce then
            syncState.forceSend = false
            performSync("update", seed)
        end
        return
    end
    if API_CONFIG.HeartbeatInterval > 0 and t - syncState.lastOkAt >= API_CONFIG.HeartbeatInterval then
        performSync("heartbeat", nil)
    end
end

local function resetSync()
    tokenLinked = false
    syncState.authFailed = false
    syncState.failCount = 0
    syncState.nextAllowedAt = 0
    syncState.lastOkAt = 0
    syncState.lastSentSeed = nil
    syncState.needUpdate = true
    syncState.forceSend = true
end

local function parsePos(pos)
    if typeof(pos) == "Vector3" then
        return pos
    end
    if type(pos) == "table" then
        local x = tonumber(pos[1] or pos.x or pos.X) or 0
        local y = tonumber(pos[2] or pos.y or pos.Y) or 0
        local z = tonumber(pos[3] or pos.z or pos.Z) or 0
        return Vector3.new(x, y, z)
    end
    if type(pos) == "string" then
        local a, b, c = pos:match("([%-%.%d]+)%s*,%s*([%-%.%d]+)%s*,%s*([%-%.%d]+)")
        if a then
            return Vector3.new(tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0)
        end
    end
    return Vector3.new(0, 0, 0)
end

local function normalizeUnit(entry, priceMap)
    if type(entry) ~= "table" then return nil end
    local name = entry.name or entry.unit or entry.Unit or entry[1]
    if type(name) ~= "string" then return nil end
    local pos = parsePos(entry.pos or entry.position or entry.Position or entry[2])
    local price = priceMap[name]
    if not price and entry.price then
        price = cleanNumber(entry.price)
    end
    local chance = entry.chance or entry.Chance or entry.rate or entry.Rate
    if chance ~= nil then
        chance = tonumber(chance)
        if chance and chance > 1 then
            chance = chance / 100
        end
    end
    return {
        name = name,
        pos = pos,
        price = price,
        chance = chance,
    }
end

local function httpGet(url)
    local ok, body = pcall(function()
        if game and game.HttpGet then
            return game:HttpGet(url)
        end
        if syn and syn.request then
            local res = syn.request({Url = url, Method = "GET"})
            return res.Body or res.body
        end
        if http and http.request then
            local res = http.request({Url = url, Method = "GET"})
            return res.Body or res.body
        end
        if request then
            local res = request({Url = url, Method = "GET"})
            return res.Body or res.body
        end
        if http_request then
            local res = http_request({Url = url, Method = "GET"})
            return res.Body or res.body
        end
        return nil
    end)
    if ok and type(body) == "string" and body ~= "" and not body:find("404: Not Found", 1, true) then
        return body
    end
    return nil
end

local function decodeFarmLua(raw)
    if type(raw) ~= "string" or raw == "" then
        return nil
    end
    local ok, data = pcall(function()
        local fn, err = loadstring(raw)
        if not fn then
            error(err or "loadstring fail")
        end
        local result = fn()
        if type(result) ~= "table" then
            error("farm profile must return table")
        end
        return result
    end)
    if ok and type(data) == "table" then
        return data
    end
    return nil
end

local function deepCopy(tbl)
    if type(tbl) ~= "table" then return tbl end
    local out = {}
    for k, v in pairs(tbl) do
        out[k] = deepCopy(v)
    end
    return out
end

local HARD_PROFILE_FALLBACK = {
    Name = "Volcano ( Hard )",
    Difficulty = "dif_hard",
    MaxPlace = 20,
    UfoReserve = 0,
    DefaultAngle = {-math.pi, 0, -math.pi},
    DefaultRotation = 180,
    Price = {
        unit_cactus = 150,
        unit_palm_tree = 500,
        unit_scent_flower = 1250,
        unit_ufo = 1200,
    },
    Events = {
        {
            Type = "StartUpgradeAll",
            Name = "Upgrade_After5",
            RequireMinPlaced = 5,
            StopAtWave = 5,
        },
        {
            Type = "StartPlace",
            Name = "Place1_Fast_1to7",
            HardCap = 7,
            MaxCount = 7,
            SoftFail = false,
            MaxAttempts = 40,
            MaxCashWait = 180,
            Shuffle = false,
            ReserveSlots = 0,
            Units = {
                {name = "unit_cactus", pos = {103.56, -31.57, -62.66}},
                {name = "unit_cactus", pos = {106.36, -31.57, -65.83}},
                {name = "unit_cactus", pos = {104.14, -31.57, -59.03}},
                {name = "unit_palm_tree", pos = {122.24, -31.57, -62.39}},
                {name = "unit_cactus", pos = {106.53, -31.57, -62.49}},
                {name = "unit_cactus", pos = {103.92, -31.57, -56.04}},
                {name = "unit_cactus", pos = {106.19, -31.57, -58.65}, chance = 0.5},
            },
        },
        {
            Type = "WaitWave",
            Wave = 5,
        },
        {
            Type = "StartPlace",
            Name = "Place2_Palm_8to11",
            HardCap = 11,
            MaxCount = 4,
            SoftFail = false,
            MaxAttempts = 40,
            MaxCashWait = 180,
            Shuffle = false,
            ReserveSlots = 0,
            PauseUpgrade = true,
            Units = {
                {name = "unit_palm_tree", pos = {122.31, -31.57, -60.83}},
                {name = "unit_palm_tree", pos = {123.20, -31.57, -59.47}},
                {name = "unit_palm_tree", pos = {123.81, -31.57, -62.27}},
                {name = "unit_palm_tree", pos = {124.92, -31.57, -60.13}},
            },
        },
        {
            Type = "StartUpgradeAll",
            Name = "Upgrade_To15",
            RequireMinPlaced = 1,
            StopAtWave = 15,
        },
        {
            Type = "WaitWave",
            Wave = 15,
        },
        {
            Type = "StartPlace",
            Name = "Place3_Flower_12to15",
            HardCap = 15,
            MaxCount = 4,
            SoftFail = false,
            MaxAttempts = 25,
            MaxCashWait = 120,
            Shuffle = false,
            ReserveSlots = 0,
            PauseUpgrade = true,
            Units = {
                {name = "unit_scent_flower", pos = {131.84, -31.57, -57.48}},
                {name = "unit_scent_flower", pos = {134.01, -31.57, -60.08}},
                {name = "unit_scent_flower", pos = {134.40, -31.57, -55.74}},
                {name = "unit_scent_flower", pos = {136.38, -31.57, -58.37}},
            },
        },
        {
            Type = "StartUpgradeAll",
            Name = "Upgrade_To21",
            RequireMinPlaced = 1,
            StopAtWave = 21,
        },
        {
            Type = "WaitWave",
            Wave = 21,
        },
        {
            Type = "StartPlace",
            Name = "Place4_UFO_16to20",
            HardCap = 20,
            MaxCount = 5,
            SoftFail = false,
            MaxAttempts = 30,
            MaxCashWait = 120,
            Shuffle = false,
            ReserveSlots = 0,
            PauseUpgrade = true,
            Units = {
                {name = "unit_ufo", pos = {153.75, -26.75, -13.95}},
                {name = "unit_ufo", pos = {153.06, -26.75, -11.10}},
                {name = "unit_ufo", pos = {156.23, -26.75, -6.12}},
                {name = "unit_ufo", pos = {158.12, -26.75, -8.06}},
                {name = "unit_ufo", pos = {159.61, -26.75, -9.20}},
            },
        },
        {
            Type = "StartUpgradeAll",
            Name = "Upgrade_End",
            RequireMinPlaced = 0,
            UntilGameEnd = true,
        },
    },
}

local ACID_L4_PROFILE_FALLBACK = {
    Name = "Acid Room ( Level 4 )",
    Difficulty = "dif_insane",
    MaxPlace = 20,
    UfoReserve = 0,
    DefaultAngle = {-math.pi, 0, -math.pi},
    DefaultRotation = 180,
    Price = {
        unit_razor_rainbow = 200,
        unit_life_flower = 1300,
        unit_black_hole = 4500,
        unit_mechanical_flower = 1800,
        unit_banana = 1500,
    },
    Events = {
        {
            Type = "StartPlace",
            Name = "Place1_Rainbow_1to5",
            HardCap = 5,
            MaxCount = 5,
            SoftFail = false,
            MaxAttempts = 80,
            MaxCashWait = 900,
            Shuffle = true,
            ReserveSlots = 0,
            Units = {
                {name = "unit_razor_rainbow", pos = {-4.14, 2.00, 329.10}},
                {name = "unit_razor_rainbow", pos = {-6.66, 2.00, 325.66}},
                {name = "unit_razor_rainbow", pos = {-3.47, 2.00, 326.34}},
                {name = "unit_razor_rainbow", pos = {-7.03, 2.00, 322.20}},
                {name = "unit_razor_rainbow", pos = {-3.31, 2.00, 322.17}},
            },
        },
        {
            Type = "StartUpgradeAll",
            Name = "Upgrade_To9",
            RequireMinPlaced = 5,
            StopAtWave = 9,
        },
        {
            Type = "WaitWave",
            Wave = 9,
        },
        {
            Type = "StartPlace",
            Name = "Place2_Ember_6",
            HardCap = 6,
            MaxCount = 1,
            SoftFail = false,
            MaxAttempts = 80,
            MaxCashWait = 900,
            Shuffle = true,
            ReserveSlots = 0,
            PauseUpgrade = true,
            Units = {
                {name = "unit_life_flower", pos = {-1.23, 2.00, 292.98}},
            },
        },
        {
            Type = "StartUpgradeAll",
            Name = "Upgrade_To18",
            RequireMinPlaced = 1,
            StopAtWave = 18,
        },
        {
            Type = "WaitWave",
            Wave = 18,
        },
        {
            Type = "StartPlace",
            Name = "Place3_BlackHole_7to9",
            HardCap = 9,
            MaxCount = 3,
            SoftFail = false,
            MaxAttempts = 80,
            MaxCashWait = 900,
            Shuffle = true,
            ReserveSlots = 0,
            PauseUpgrade = true,
            Units = {
                {name = "unit_black_hole", pos = {-8.71, 2.00, 304.53}},
                {name = "unit_black_hole", pos = {-6.39, 2.00, 304.74}},
                {name = "unit_black_hole", pos = {-3.59, 2.00, 304.29}},
            },
        },
        {
            Type = "StartUpgradeAll",
            Name = "Upgrade_To25",
            RequireMinPlaced = 1,
            StopAtWave = 25,
        },
        {
            Type = "WaitWave",
            Wave = 25,
        },
        {
            Type = "StartPlace",
            Name = "Place4_Mechanical_10to15",
            HardCap = 15,
            MaxCount = 6,
            SoftFail = false,
            MaxAttempts = 80,
            MaxCashWait = 900,
            Shuffle = true,
            ReserveSlots = 0,
            PauseUpgrade = true,
            Units = {
                {name = "unit_mechanical_flower", pos = {-22.86, 2.00, 314.46}},
                {name = "unit_mechanical_flower", pos = {-26.10, 2.00, 315.01}},
                {name = "unit_mechanical_flower", pos = {-22.05, 2.00, 311.19}},
                {name = "unit_mechanical_flower", pos = {-25.93, 2.00, 312.16}},
                {name = "unit_mechanical_flower", pos = {-22.76, 2.00, 307.86}},
                {name = "unit_mechanical_flower", pos = {-26.27, 2.00, 307.71}},
            },
        },
        {
            Type = "StartUpgradeAll",
            Name = "Upgrade_To29",
            RequireMinPlaced = 1,
            StopAtWave = 29,
        },
        {
            Type = "WaitWave",
            Wave = 29,
        },
        {
            Type = "StartPlace",
            Name = "Place5_Banana_16to20",
            HardCap = 20,
            MaxCount = 5,
            SoftFail = false,
            MaxAttempts = 80,
            MaxCashWait = 900,
            Shuffle = true,
            ReserveSlots = 0,
            PauseUpgrade = true,
            Units = {
                {name = "unit_banana", pos = {-22.12, 2.00, 295.89}},
                {name = "unit_banana", pos = {-26.23, 2.00, 296.44}},
                {name = "unit_banana", pos = {-22.13, 2.00, 292.62}},
                {name = "unit_banana", pos = {-25.84, 2.00, 293.02}},
                {name = "unit_banana", pos = {-21.47, 2.00, 289.18}},
            },
        },
        {
            Type = "StartUpgradeAll",
            Name = "Upgrade_End",
            RequireMinPlaced = 0,
            UntilGameEnd = true,
        },
    },
}

local ACID_LEVELS = {
    ["Level 4"] = {url = FARM_URL_ACID_L4, fallback = ACID_L4_PROFILE_FALLBACK},
}

local function loadAcidProfile(level)
    local entry = ACID_LEVELS[tostring(level or selectedAcidLevel or "Level 4")] or ACID_LEVELS["Level 4"]
    local url = entry.url
    local data = decodeFarmLua(httpGet(url))
    if not data then
        data = deepCopy(entry.fallback)
        url = "embedded:AcidRoom"
    end
    if not data then
        return nil, nil
    end
    data.Difficulty = data.Difficulty or "dif_insane"
    return data, url
end

local function loadFarmProfile(mode)
    mode = resolveFarmMode(mode or selectedFarmMode)
    local url = FARM_URL_MEDIUM
    if mode == "Hard" then
        url = FARM_URL_HARD
    end

    local data = decodeFarmLua(httpGet(url))
    if not data and mode == "Hard" then
        data = deepCopy(HARD_PROFILE_FALLBACK)
        url = "embedded:Hard"
    end
    if not data then
        return nil, nil
    end

    if mode == "Easy" then
        data = deepCopy(data)
        data.Name = "Volcano 1"
        data.Difficulty = "dif_easy"
    elseif mode == "Medium" then
        data.Name = data.Name or "Volcano ( Medium )"
        data.Difficulty = data.Difficulty or "dif_normal"
    elseif mode == "Hard" then
        data.Name = data.Name or "Volcano ( Hard )"
        data.Difficulty = data.Difficulty or "dif_hard"
    end

    return data, url
end

local function loadActiveProfile()
    if currentFarm == "AcidRoom" then
        return loadAcidProfile(selectedAcidLevel)
    end
    return loadFarmProfile(selectedFarmMode)
end

local farmProfile = nil
do
    local data = loadActiveProfile()
    if data then
        farmProfile = data
    end
end

local function getPriceMap(profile)
    local src = profile.Price or profile.Prices or profile.price or {}
    local map = {}
    for k, v in pairs(src) do
        map[tostring(k)] = cleanNumber(v)
    end
    return map
end

local function getDefaultAngle(profile)
    local a = profile.DefaultAngle
    if type(a) == "table" then
        return CFrame.Angles(
            tonumber(a[1]) or -math.pi,
            tonumber(a[2]) or 0,
            tonumber(a[3]) or -math.pi
        )
    end
    return CFrame.Angles(-math.pi, 0, -math.pi)
end

local JITTER_MAX = 2
local JITTER_MIN = 0.2

local function getUnitJitterRange(unitName)
    local n = string.lower(tostring(unitName or ""))
    if n:find("palm", 1, true) then
        return 0, 0
    end
    if n:find("ufo", 1, true) then
        return 1, 2
    end
    if n:find("cactus", 1, true) or n:find("catus", 1, true) then
        return 0.1, 0.3
    end
    if n:find("flower", 1, true) or n:find("scent", 1, true) then
        return 0.1, 0.3
    end
    return 0.1, 0.3
end

local function jitterPos(pos, minMag, maxMag)
    local minV = tonumber(minMag) or 0
    local maxV = tonumber(maxMag) or 0
    if maxV <= 0 then
        return Vector3.new(pos.X, pos.Y, pos.Z)
    end
    if minV < 0 then minV = 0 end
    if maxV < minV then maxV = minV end

    local function axisOffset()
        local amount
        if minV == maxV then
            amount = minV
        else
            amount = minV + (math.random() * (maxV - minV))
        end
        if amount <= 0 then
            return 0
        end
        if math.random(1, 2) == 1 then
            return -amount
        end
        return amount
    end
    return Vector3.new(pos.X + axisOffset(), pos.Y, pos.Z + axisOffset())
end

local function nextJitter(minMag, maxMag)
    local minV = tonumber(minMag) or 0
    local maxV = tonumber(maxMag) or 0
    if maxV <= 0 then
        return minV, maxV
    end
    maxV = maxV * 0.5
    if maxV < minV then
        maxV = minV
    end
    return minV, maxV
end

local function jitterWait(base)
    task.wait(base + (math.random() * 0.35))
end

local function shuffleCopy(list)
    local t = {}
    for i, v in ipairs(list) do
        t[i] = v
    end
    for i = #t, 2, -1 do
        local j = math.random(1, i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

local function tryPlaceOne(unit, defaultAngle, defaultRotation, minMag, maxMag)
    local price = unit.price
    if not price then return false end
    local beforeCash = getCashAmount()
    if beforeCash < price then return false end
    local beforeUnits = getOwnedUnitCount()

    local placePos = jitterPos(unit.pos, minMag, maxMag)
    local rotSpread = 0
    if (tonumber(maxMag) or 0) > 0 then
        rotSpread = math.max(1, math.floor((tonumber(maxMag) or 0) * 2))
    end
    local rot = (defaultRotation or 180)
    if rotSpread > 0 then
        rot = rot + math.random(-rotSpread, rotSpread)
    end
    local args = {
        [1] = unit.name,
        [2] = {
            CF = CFrame.new(placePos) * defaultAngle,
            Position = placePos,
            Valid = true,
            Rotation = rot,
        }
    }

    pcall(function()
        placeUnit:InvokeServer(unpack(args))
    end)

    for _ = 1, 15 do
        task.wait(0.08)
        local afterUnits = getOwnedUnitCount()
        if afterUnits > beforeUnits then
            return true
        end
        local spent = beforeCash - getCashAmount()
        if spent >= (price * 0.85) then
            return true
        end
    end
    return false
end

local function placeUnitList(list, inGameRef, maxCount, placedCounter, isPlacingFlag, opts, defaultAngle, defaultRotation)
    opts = opts or {}
    local limit = maxCount or #list
    local placed = 0
    local maxAttempts = opts.maxAttempts or 12
    local softFail = opts.softFail == true
    local maxCashWait = opts.maxCashWait or 90
    local hardCap = opts.hardCap or 999
    local order = opts.shuffle and shuffleCopy(list) or list

    if isPlacingFlag then
        isPlacingFlag.value = true
    end

    local function syncPlacedCounter()
        local real = getOwnedUnitCount()
        if placedCounter then
            if real > placedCounter.value then
                placedCounter.value = real
            end
            return placedCounter.value
        end
        if real > placed then
            placed = real
        end
        return placed
    end

    local function totalPlaced()
        return syncPlacedCounter()
    end

    local function atCap()
        return totalPlaced() >= hardCap
    end

    local function roomLeft()
        local cur = totalPlaced()
        local byCap = hardCap - cur
        local byLimit = limit - placed
        if byCap < byLimit then return byCap end
        return byLimit
    end

    for _, unit in ipairs(order) do
        if roomLeft() <= 0 or atCap() then break end
        if not autoFarmEnabled or not inGameRef() or isVisible("GameGui.Screen.Middle.GameEnd") then break end

        local skipUnit = false
        if unit.chance ~= nil then
            if math.random() > unit.chance then
                skipUnit = true
            end
        end

        if not skipUnit and unit.price then
            local success = false
            local attempts = 0
            local jMin, jMax = getUnitJitterRange(unit.name)
            while autoFarmEnabled and inGameRef() and not success and attempts < maxAttempts do
                if isVisible("GameGui.Screen.Middle.GameEnd") or atCap() or roomLeft() <= 0 then
                    if isPlacingFlag then isPlacingFlag.value = false end
                    return placed
                end

                local cashWait = 0
                while autoFarmEnabled and inGameRef() and getCashAmount() < unit.price do
                    if isVisible("GameGui.Screen.Middle.GameEnd") or atCap() then
                        if isPlacingFlag then isPlacingFlag.value = false end
                        return placed
                    end
                    if softFail and cashWait >= maxCashWait then break end
                    task.wait(0.5)
                    cashWait = cashWait + 0.5
                    if not softFail and cashWait > maxCashWait then break end
                end

                if not autoFarmEnabled or not inGameRef() or atCap() or roomLeft() <= 0 then break end
                if getCashAmount() < unit.price then
                    if softFail then break end
                    attempts = attempts + 1
                    task.wait(0.5)
                else
                    local beforeCount = totalPlaced()
                    local beforeCash = getCashAmount()
                    attempts = attempts + 1
                    success = tryPlaceOne(unit, defaultAngle, defaultRotation, jMin, jMax)

                    local afterUnits = getOwnedUnitCount()
                    local afterCash = getCashAmount()
                    local unitOk = afterUnits > beforeCount
                    local spentOk = (beforeCash - afterCash) >= (unit.price * 0.85)
                    if success or unitOk or spentOk then
                        success = true
                        local newTotal = math.max(afterUnits, beforeCount + 1)
                        if placedCounter then
                            if newTotal > placedCounter.value then
                                placedCounter.value = newTotal
                            else
                                placedCounter.value = beforeCount + 1
                            end
                        end
                        placed = placed + 1
                        if atCap() or roomLeft() <= 0 then break end
                        jitterWait(0.12)
                    else
                        success = false
                        jMin, jMax = nextJitter(jMin, jMax)
                        if softFail and attempts >= 6 then break end
                        jitterWait(0.15)
                    end
                end
            end
        end
    end

    if isPlacingFlag then
        isPlacingFlag.value = false
    end
    return placed
end

local function buildUnitList(rawList, priceMap)
    local out = {}
    if type(rawList) ~= "table" then return out end
    for _, entry in ipairs(rawList) do
        local u = normalizeUnit(entry, priceMap)
        if u and u.price then
            table.insert(out, u)
        end
    end
    return out
end

local function runFarmProfile(profile)
    if type(profile) ~= "table" or type(profile.Events) ~= "table" then
        return
    end

    local priceMap = getPriceMap(profile)
    local defaultAngle = getDefaultAngle(profile)
    local defaultRotation = tonumber(profile.DefaultRotation) or 180
    local maxPlace = tonumber(profile.MaxPlace) or 20
    local ufoReserve = tonumber(profile.UfoReserve or profile.ufoReserve) or 1
    local difficulty = profile.Difficulty or "dif_normal"

    waitForGameStart(difficulty)
    if not autoFarmEnabled then return end

    local inGame = true
    local placedCounter = {value = 0}
    local isPlacing = {value = false}
    local upgradeState = {
        enabled = false,
        minPlaced = 0,
        minWave = 0,
        maxWave = nil,
        pause = false,
    }

    local function stillInGame()
        return inGame
    end

    local function refreshPlacedFromWorld()
        local real = getOwnedUnitCount()
        if real > placedCounter.value then
            placedCounter.value = real
        end
        return placedCounter.value
    end

    refreshPlacedFromWorld()

    local function setUpgrade(ev, enabled)
        if not enabled then
            upgradeState.enabled = false
            upgradeState.minPlaced = 0
            upgradeState.minWave = 0
            upgradeState.maxWave = nil
            upgradeState.pause = false
            return
        end
        upgradeState.enabled = true
        upgradeState.pause = false
        upgradeState.minPlaced = tonumber(ev.RequireMinPlaced or ev.requireMinPlaced or ev.MinPlaced) or 0
        upgradeState.minWave = tonumber(ev.StartFromWave or ev.startFromWave or ev.MinWave or ev.ForceFromWave or ev.forceFromWave) or 0
        if ev.UntilGameEnd == true or ev.untilGameEnd == true then
            upgradeState.maxWave = nil
        else
            local stopAt = ev.StopAtWave or ev.stopAtWave or ev.MaxWave or ev.maxWave
            if stopAt == nil then
                upgradeState.maxWave = nil
            else
                upgradeState.maxWave = tonumber(stopAt)
            end
        end
    end

    local function canUpgrade()
        if not autoFarmEnabled or not inGame then return false end
        if not upgradeState.enabled then return false end
        if upgradeState.pause then return false end

        local wave = getWaveNumber()
        local owned = refreshPlacedFromWorld()
        if upgradeState.minPlaced > 0 and owned < upgradeState.minPlaced then
            return false
        end
        if wave < upgradeState.minWave then
            return false
        end
        if upgradeState.maxWave ~= nil and wave >= upgradeState.maxWave then
            return false
        end
        return true
    end

    task.spawn(function()
        while autoFarmEnabled and inGame do
            if isVisible("GameGuiNoInset.Screen.Top.SkipWave") then
                pcall(function()
                    skipWave:InvokeServer("y")
                end)
                task.wait(0.1)
            else
                task.wait(0.25)
            end
        end
    end)

    task.spawn(function()
        while autoFarmEnabled and inGame do
            if isVisible("GameGui.Screen.Bottom.UnitViewer") then
                task.wait(0.75)
                local vim = game:GetService("VirtualInputManager")
                while autoFarmEnabled and inGame and isVisible("GameGui.Screen.Bottom.UnitViewer") do
                    vim:SendKeyEvent(true, "Q", false, nil)
                    task.wait(0.05)
                    vim:SendKeyEvent(false, "Q", false, nil)
                    task.wait(0.2)
                end
            end
            task.wait(0.3)
        end
    end)

    task.spawn(function()
        while autoFarmEnabled and inGame do
            if canUpgrade() then
                pcall(function()
                    upgradeAll:InvokeServer()
                end)
                task.wait(0.1 + (math.random() * 0.2))
            else
                task.wait(0.15)
            end
        end
    end)

    task.spawn(function()
        while autoFarmEnabled and inGame do
            if isVisible("GameGui.Screen.Middle.GameEnd") then
                inGame = false
                break
            end
            task.wait(0.5)
        end
    end)

    local function waitWaveAtLeast(target)
        local t = 0
        while autoFarmEnabled and inGame and getWaveNumber() < target do
            if isVisible("GameGui.Screen.Middle.GameEnd") then
                inGame = false
                break
            end
            task.wait(0.35)
            t = t + 0.35
            if t > 1800 then break end
        end
    end

    local function runPlaceEvent(ev)
        if not autoFarmEnabled or not inGame then return end
        local units = buildUnitList(ev.Units or ev.units or {}, priceMap)
        if #units == 0 then return end

        local reserve = tonumber(ev.ReserveSlots or ev.reserveSlots) or 0
        if ev.ReserveForUfo or ev.ReserveUfo then
            reserve = math.max(reserve, ufoReserve)
        end

        local hardCap = tonumber(ev.HardCap or ev.hardCap)
        if not hardCap then
            hardCap = maxPlace - reserve
        end
        if hardCap > (maxPlace - reserve) then
            hardCap = maxPlace - reserve
        end
        if hardCap < 0 then hardCap = 0 end

        local maxCount = tonumber(ev.MaxCount or ev.maxCount)
        if not maxCount then
            maxCount = #units
        end
        if maxCount > #units then
            maxCount = #units
        end

        local room = hardCap - placedCounter.value
        if room < 0 then room = 0 end
        if maxCount > room then
            maxCount = room
        end
        if maxCount <= 0 then return end

        local pauseUpgrade = ev.PauseUpgrade == true
        if pauseUpgrade then
            upgradeState.pause = true
        end
        isPlacing.value = true

        local okPlace, got = pcall(function()
            task.wait(0.2)
            return placeUnitList(units, stillInGame, maxCount, placedCounter, isPlacing, {
                maxAttempts = tonumber(ev.MaxAttempts) or 12,
                softFail = ev.SoftFail == true,
                maxCashWait = tonumber(ev.MaxCashWait) or 90,
                shuffle = ev.Shuffle == true,
                hardCap = hardCap,
            }, defaultAngle, defaultRotation)
        end)
        if not okPlace then
            got = 0
        end
        got = tonumber(got) or 0

        local fillRemain = ev.FillRemainWith or ev.fillRemainWith
        local onlyAfterMain = ev.FillRemainOnlyIfPlaced ~= false
        if fillRemain and autoFarmEnabled and inGame then
            local allowFill = true
            if onlyAfterMain and got < 1 and #units > 0 then
                allowFill = false
            end
            if allowFill then
                local remainCap = tonumber(ev.FillRemainHardCap) or maxPlace
                if remainCap > maxPlace then remainCap = maxPlace end
                local remain = remainCap - placedCounter.value
                if remain > 0 then
                    local fillUnits = buildUnitList(fillRemain, priceMap)
                    if #fillUnits > 0 then
                        if remain > #fillUnits then
                            remain = #fillUnits
                        end
                        pcall(function()
                            placeUnitList(fillUnits, stillInGame, remain, placedCounter, isPlacing, {
                                maxAttempts = 4,
                                softFail = true,
                                maxCashWait = 10,
                                shuffle = true,
                                hardCap = remainCap,
                            }, defaultAngle, defaultRotation)
                        end)
                    end
                end
            end
        end

        isPlacing.value = false
        if pauseUpgrade then
            upgradeState.pause = false
        end
        if placedCounter.value > hardCap and not fillRemain then
            placedCounter.value = hardCap
        end
        if isVisible("GameGui.Screen.Middle.GameEnd") then inGame = false end
    end

    for _, ev in ipairs(profile.Events) do
        if not autoFarmEnabled or not inGame then break end
        local t = tostring(ev.Type or ev.type or "")

        if t == "StartPlace" or t == "Place" then
            runPlaceEvent(ev)
        elseif t == "StartUpgradeAll" or t == "UpgradeAll" then
            setUpgrade(ev, true)
        elseif t == "StopUpgradeAll" then
            setUpgrade(ev, false)
        elseif t == "WaitWave" then
            local wave = tonumber(ev.Wave or ev.wave) or 0
            if wave > 0 then
                waitWaveAtLeast(wave)
            end
        elseif t == "Wait" then
            local sec = tonumber(ev.Seconds or ev.seconds) or 1
            task.wait(sec)
        end
    end

    while autoFarmEnabled and inGame and not isVisible("GameGui.Screen.Middle.GameEnd") do
        task.wait(0.5)
    end
    inGame = false
    isPlacing.value = false
end

local function startAutoFarm()
    if farmThread then return end
    farmThread = task.spawn(function()
        pcall(function() changeTickSpeed:InvokeServer(2) end)
        while autoFarmEnabled do
            local data = loadActiveProfile()
            if data then
                farmProfile = data
            end
            if farmProfile then
                runFarmProfile(farmProfile)
            else
                task.wait(2)
            end
            task.wait(1)
        end
        farmThread = nil
    end)
end

local function stopAutoFarm()
    autoFarmEnabled = false
end

local Window = redzlib:MakeWindow({
    Title = "Nexus Stella⭐",
    SubTitle = "By nhat0258 | v2.0.8",
    SaveFolder = "NexusStella_v2.json"
})

local TabMain = Window:MakeTab({"Main", "home"})
local TabSetting = Window:MakeTab({"Setting", "settings"})

local volcanoToggle = nil
local acidToggle = nil

local function setToggleSilent(toggle, value)
    pcall(function()
        if toggle and type(toggle.Set) == "function" then
            toggle:Set(value)
        end
    end)
end

local function startFarmFor(name)
    if autoFarmEnabled and currentFarm ~= name then
        local other = currentFarm
        currentFarm = name
        if other == "Volcano" then
            setToggleSilent(volcanoToggle, false)
        elseif other == "AcidRoom" then
            setToggleSilent(acidToggle, false)
        end
    end
    currentFarm = name
    autoFarmEnabled = true
    local data = loadActiveProfile()
    if data then
        farmProfile = data
    end
    startAutoFarm()
end

local function stopFarmFor(name)
    if currentFarm == name then
        stopAutoFarm()
    end
end

TabMain:AddDropdown({
    Name = "Volcano Mode",
    Options = {"Volcano 1", "Volcano 2", "Volcano 3"},
    Default = "Volcano 2",
    Flag = "VolcanoModeV3",
    Callback = function(Value)
        selectedFarmMode = resolveFarmMode(Value)
        if currentFarm == "Volcano" then
            local data = loadActiveProfile()
            if data then
                farmProfile = data
            end
        end
    end
})

volcanoToggle = TabMain:AddToggle({
    Name = "Auto Farm Volcano",
    Default = false,
    Flag = "AutoFarmVolcano",
    Callback = function(Value)
        if Value then
            startFarmFor("Volcano")
        else
            stopFarmFor("Volcano")
        end
    end
})

TabMain:AddDropdown({
    Name = "Acid Room Level",
    Options = {"Level 4"},
    Default = "Level 4",
    Flag = "AcidRoomLevel",
    Callback = function(Value)
        local v = tostring(Value or "Level 4")
        if ACID_LEVELS[v] then
            selectedAcidLevel = v
        else
            selectedAcidLevel = "Level 4"
        end
        if currentFarm == "AcidRoom" then
            local data = loadActiveProfile()
            if data then
                farmProfile = data
            end
        end
    end
})

acidToggle = TabMain:AddToggle({
    Name = "Auto Farm Acid Room",
    Default = false,
    Flag = "AutoFarmAcidRoom",
    Callback = function(Value)
        if Value then
            startFarmFor("AcidRoom")
        else
            stopFarmFor("AcidRoom")
        end
    end
})

local tokenBox = TabSetting:AddTextBox({
    Name = "Enter Your Token",
    Default = TOKEN,
    PlaceholderText = "Enter Your Token",
    ClearText = false,
    Callback = function(Value)
        local tok = cleanToken(Value)
        if tok == "" then return end
        TOKEN = tok
        saveConfig(tok)
        resetSync()
    end
})

pcall(function()
    if tokenBox and tokenBox.OnChanging then
        tokenBox.OnChanging = function(text)
            return cleanToken(text)
        end
    end
end)

task.spawn(function()
    task.wait(0.35)
    pcall(function()
        local gui = game:GetService("CoreGui"):FindFirstChild("redz Library V5")
        if not gui then return end
        for _, obj in ipairs(gui:GetDescendants()) do
            if obj:IsA("TextBox") and (obj.PlaceholderText == "Enter Your Token" or obj.PlaceholderText == "Input") then
                if TOKEN ~= "" and (obj.Text == "" or obj.Text == nil) then
                    obj.Text = TOKEN
                end
            end
        end
    end)
end)

local function readGuiToken()
    local guiToken = TOKEN
    pcall(function()
        local gui = game:GetService("CoreGui"):FindFirstChild("redz Library V5")
        if not gui then return end
        for _, obj in ipairs(gui:GetDescendants()) do
            if obj:IsA("TextBox") and obj.PlaceholderText == "Enter Your Token" then
                local t = cleanToken(obj.Text)
                if t ~= "" then
                    guiToken = t
                end
            end
        end
    end)
    return cleanToken(guiToken)
end

local function copyText(text)
    local ok = false
    pcall(function()
        if setclipboard then
            setclipboard(text)
            ok = true
        elseif toclipboard then
            toclipboard(text)
            ok = true
        elseif Clipboard and Clipboard.set then
            Clipboard.set(text)
            ok = true
        end
    end)
    return ok
end

TabSetting:AddButton({
    Name = "Linked Token",
    Callback = function()
        local guiToken = readGuiToken()
        if guiToken == "" then return end
        TOKEN = guiToken
        saveConfig(guiToken)
        resetSync()
    end
})

TabSetting:AddToggle({
    Name = "WebHook",
    Default = false,
    Flag = "WebHookEnabled",
    Callback = function(Value)
        if Value then
            local guiToken = readGuiToken()
            if guiToken ~= "" and guiToken ~= TOKEN then
                TOKEN = guiToken
                saveConfig(guiToken)
            end
            resetSync()
            webhookEnabled = true
        else
            webhookEnabled = false
        end
    end
})

TabSetting:AddButton({
    Name = "WebHook Link",
    Callback = function()
        copyText(API_CONFIG.WebUrl)
    end
})

TabSetting:AddButton({
    Name = "Reload Farm Profile",
    Callback = function()
        local data = loadActiveProfile()
        if data then
            farmProfile = data
        end
    end
})

task.spawn(function()
    local _, tok = loadConfig()
    if tok ~= "" then
        TOKEN = tok
    end
    if TOKEN ~= "" then
        resetSync()
    end
end)

task.spawn(function()
    while true do
        pcall(syncTick)
        task.wait(0.5)
    end
end)
