local redzlib = loadstring(game:HttpGet("https://raw.githubusercontent.com/nhat0258/Redz-UI-Library/refs/heads/main/Main.lua"))()

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local LOBBY_PLACE_ID = 108533757090220
local RADIOACTIVE_RAMPAGE_PLACE_ID = 123516946198836
local isLobby = game.PlaceId == LOBBY_PLACE_ID

local function getRemote(name)
    local ok, r = pcall(function()
        local folder = game:GetService("ReplicatedStorage"):FindFirstChild("RemoteFunctions")
        if folder then
            return folder:FindFirstChild(name)
        end
        return nil
    end)
    if ok then
        return r
    end
    return nil
end

local function makeRemote(name)
    local proxy = {}
    function proxy:InvokeServer(...)
        local r = getRemote(name)
        if not r then
            error("missing remote " .. name)
        end
        return r:InvokeServer(...)
    end
    return proxy
end

local placeUnit = makeRemote("PlaceUnit")
local changeTickSpeed = makeRemote("ChangeTickSpeed")
local skipWave = makeRemote("SkipWave")
local restartGame = makeRemote("RestartGame")
local placeDifficultyVote = makeRemote("PlaceDifficultyVote")
local upgradeAll = makeRemote("UpgradeAll")
local sellAll = makeRemote("SellAll")
local activateUnitAbility = makeRemote("ActivateUnitAbility")
local autoSkipEnabled = true
local autoReplayEnabled = true
local antiAfkEnabled = true
local antiAfkConn = nil
local antiAfkDisabled = {}
local antiAfkCaptured = false

local function antiAfkPulse()
    local ok = pcall(function()
        local vu = game:GetService("VirtualUser")
        vu:CaptureController()
        vu:ClickButton2(Vector2.new(0, 0))
    end)
    if not ok then
        pcall(function()
            local vim = game:GetService("VirtualInputManager")
            vim:SendMouseMoveEvent(2, 2, game)
            task.wait(0.05)
            vim:SendMouseMoveEvent(3, 3, game)
        end)
    end
end

local function setAntiAfk(on)
    antiAfkEnabled = on == true
    if antiAfkEnabled then
        pcall(function()
            if getconnections then
                if not antiAfkCaptured then
                    antiAfkCaptured = true
                    for _, c in ipairs(getconnections(player.Idled)) do
                        antiAfkDisabled[#antiAfkDisabled + 1] = c
                    end
                end
                for _, c in ipairs(antiAfkDisabled) do
                    pcall(function()
                        if c.Disable then
                            c:Disable()
                        end
                    end)
                end
            end
        end)
        if not antiAfkConn then
            pcall(function()
                antiAfkConn = player.Idled:Connect(function()
                    if antiAfkEnabled then
                        antiAfkPulse()
                    end
                end)
            end)
        end
    else
        for _, c in ipairs(antiAfkDisabled) do
            pcall(function()
                if c.Enable then
                    c:Enable()
                end
            end)
        end
    end
end

setAntiAfk(true)

task.spawn(function()
    while true do
        task.wait(240)
        if antiAfkEnabled then
            antiAfkPulse()
        end
    end
end)

local API_CONFIG = {
    BaseUrl = "https://api-nxswebhook.nhatbinhduong37.workers.dev",
    Token = "TDShYgpvyfa19gjSI15-OcHCV_TtJH-5nk7T2A_kU14",
    UpdatePath = "/api/update",
    HeartbeatPath = "/api/heartbeat",
    Timeout = 10,
    Debounce = 1.5,
    MinInterval = 5,
    HeartbeatInterval = 0,
    MaxBackoff = 120,
}
local API_CONFIG_FILE = "NexusStella_Api.json"

local TOKEN = API_CONFIG.Token
local tokenLinked = false
local webhookEnabled = false
local FARM_URL_MEDIUM = "https://raw.githubusercontent.com/nguyennhlat2004/NexusYeuEm/refs/heads/main/Volcano-Medium.lua"
local FARM_URL_HARD = "https://raw.githubusercontent.com/nguyennhlat2004/NexusYeuEm/refs/heads/main/Volcano-Hard.lua"
local FARM_URL_RADIOACTIVE_RAMPAGE_L4 = "https://raw.githubusercontent.com/nguyennhlat2004/NexusYeuEm/refs/heads/main/RadioactiveRampage-Level4.lua"
local FARM_URL_ENCHANTED_ENCOUNTER_L5 = "https://raw.githubusercontent.com/nguyennhlat2004/NexusYeuEm/refs/heads/main/EnchantedEncounter-Level5.lua"
local selectedEnchantedEncounterLevel = "Level 5"
local currentFarm = "Volcano"
local selectedRadioactiveRampageLevel = "Level 4"
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
                local tok = decoded.Token or decoded.token
                if type(tok) == "string" and cleanToken(tok) ~= "" then
                    API_CONFIG.Token = cleanToken(tok)
                    TOKEN = API_CONFIG.Token
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
    local ls = player:FindFirstChild("leaderstats")
    local c = ls and ls:FindFirstChild("Cash")
    if not c then
        return 0
    end
    return cleanNumber(c.Value)
end

local function stripRichText(text)
    local t = tostring(text or "")
    t = t:gsub("<[^>]->", "")
    return t
end

local function parseAmountText(text)
    local t = stripRichText(text):gsub(",", ""):gsub("%s", "")
    local num, suf = t:match("(%d+%.?%d*)([KkMmBbTt]?)")
    if not num then
        return nil, false
    end
    local n = tonumber(num)
    if not n then
        return nil, false
    end
    local mult = {k = 1e3, m = 1e6, b = 1e9, t = 1e12}
    if suf ~= "" then
        n = n * (mult[string.lower(suf)] or 1)
        return n, true
    end
    return n, false
end

local function getCurrencyFrame(name)
    local ok, frame = pcall(function()
        return player.PlayerGui.GameGui.Screen.Bottom.CurrencyDisplay:FindFirstChild(name)
    end)
    if ok then
        return frame
    end
    return nil
end

local displayFrameCache = {}
local displaySearchAt = {}

local function readLabelNumber(obj)
    local best, bestText = nil, nil
    pcall(function()
        if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
            for _, prop in ipairs({"Text", "ContentText"}) do
                local raw = obj[prop]
                if type(raw) == "string" and raw ~= "" then
                    local clean = stripRichText(raw)
                    local n = parseAmountText(clean)
                    if n then
                        best, bestText = n, clean
                        return
                    end
                end
            end
        end
    end)
    return best, bestText
end

local function readFrameAmount(frame)
    if not frame then
        return nil, nil
    end
    local okTitle, title = pcall(function()
        return frame:FindFirstChild("Title")
    end)
    if okTitle and title then
        local n, txt = readLabelNumber(title)
        if n then
            return n, txt
        end
    end
    local best, bestText, bestLen = nil, nil, -1
    local ok, list = pcall(function()
        local out = {frame}
        for _, d in ipairs(frame:GetDescendants()) do
            out[#out + 1] = d
        end
        return out
    end)
    if not ok or type(list) ~= "table" then
        return nil, nil
    end
    for _, obj in ipairs(list) do
        local n, clean = readLabelNumber(obj)
        if n then
            local digits = #(clean:gsub("%D", ""))
            if digits > bestLen then
                best, bestText, bestLen = n, clean, digits
            end
        end
    end
    return best, bestText
end

local function findDisplayFrames(name)
    local list = {}
    local primary = getCurrencyFrame(name)
    if primary then
        list[#list + 1] = primary
    end
    local cached = displayFrameCache[name]
    if cached then
        for _, f in ipairs(cached) do
            local okP, parent = pcall(function()
                return f.Parent
            end)
            if okP and parent and f ~= primary then
                list[#list + 1] = f
            end
        end
    end
    return list
end

local function searchDisplayFrames(name)
    local now = 0
    pcall(function()
        now = tick()
    end)
    if displaySearchAt[name] and now - displaySearchAt[name] < 5 then
        return
    end
    displaySearchAt[name] = now
    local found = {}
    pcall(function()
        for _, d in ipairs(player.PlayerGui:GetDescendants()) do
            if d.Name == name then
                found[#found + 1] = d
            end
        end
    end)
    displayFrameCache[name] = found
end

local function readDisplayAmount(name)
    for _, frame in ipairs(findDisplayFrames(name)) do
        local n, txt = readFrameAmount(frame)
        if n then
            if txt then
                txt = txt:gsub("^%s+", ""):gsub("%s+$", "")
            end
            return n, txt
        end
    end
    searchDisplayFrames(name)
    for _, frame in ipairs(displayFrameCache[name] or {}) do
        local n, txt = readFrameAmount(frame)
        if n then
            if txt then
                txt = txt:gsub("^%s+", ""):gsub("%s+$", "")
            end
            return n, txt
        end
    end
    return nil, nil
end

local function statNow()
    local ok, t = pcall(function()
        return tick()
    end)
    if ok and type(t) == "number" then
        return t
    end
    return os.time()
end

local function exactNumber(value)
    if type(value) == "number" then
        if value ~= value or value < 0 then
            return nil
        end
        return value
    end
    if type(value) == "string" then
        local n, abbr = parseAmountText(value)
        if n and n >= 0 and not abbr then
            return n
        end
    end
    return nil
end

local function normName(name)
    local n = string.lower(tostring(name or ""))
    n = n:gsub("[%s_%-]", "")
    return n
end

local function nameIn(name, names)
    local n = normName(name)
    for _, want in ipairs(names) do
        if n == want then
            return true
        end
    end
    return false
end

local statSourceCache = {}

local function readCachedSource(src)
    local ok, v = pcall(function()
        if src.kind == "value" then
            if not src.obj or not src.obj.Parent then
                return nil
            end
            return src.obj.Value
        elseif src.kind == "attr" then
            return src.obj:GetAttribute(src.attr)
        end
        return nil
    end)
    if ok then
        return exactNumber(v)
    end
    return nil
end

local function scanValueObjects(root, names, skip)
    local found = nil
    pcall(function()
        for _, child in ipairs(root:GetChildren()) do
            if not (skip and skip[child.Name]) then
                if child:IsA("ValueBase") and nameIn(child.Name, names) and exactNumber(child.Value) then
                    found = child
                    return
                end
                for _, d in ipairs(child:GetDescendants()) do
                    if d:IsA("ValueBase") and nameIn(d.Name, names) and exactNumber(d.Value) then
                        found = d
                        return
                    end
                end
            end
        end
    end)
    return found
end

local function findExactStat(cacheKey, names)
    local cached = statSourceCache[cacheKey]
    if cached and cached.kind then
        local n = readCachedSource(cached)
        if n then
            return n, cached.label
        end
        statSourceCache[cacheKey] = nil
        cached = nil
    end
    if cached and cached.miss and statNow() - cached.miss < 15 then
        return nil, nil
    end

    local ls = player:FindFirstChild("leaderstats")
    if ls then
        for _, child in ipairs(ls:GetChildren()) do
            if child:IsA("ValueBase") and nameIn(child.Name, names) and exactNumber(child.Value) then
                statSourceCache[cacheKey] = {kind = "value", obj = child, label = "leaderstats"}
                return exactNumber(child.Value), "leaderstats"
            end
        end
    end

    local okAttr, attrs = pcall(function()
        return player:GetAttributes()
    end)
    if okAttr and type(attrs) == "table" then
        for k, v in pairs(attrs) do
            if nameIn(k, names) and exactNumber(v) then
                statSourceCache[cacheKey] = {kind = "attr", obj = player, attr = k, label = "attribute"}
                return exactNumber(v), "attribute"
            end
        end
    end

    local obj = scanValueObjects(player, names, {PlayerGui = true, PlayerScripts = true, Backpack = true, StarterGear = true, leaderstats = true})
    if obj then
        statSourceCache[cacheKey] = {kind = "value", obj = obj, label = "data"}
        return exactNumber(obj.Value), "data"
    end

    pcall(function()
        local rs = game:GetService("ReplicatedStorage")
        local roots = {}
        for _, n in ipairs({player.Name, tostring(player.UserId)}) do
            local direct = rs:FindFirstChild(n)
            if direct then roots[#roots + 1] = direct end
        end
        for _, folderName in ipairs({"PlayerData", "Players", "Data", "PlayerStats", "Profiles", "Profile", "Stats"}) do
            local f = rs:FindFirstChild(folderName)
            if f then
                for _, n in ipairs({player.Name, tostring(player.UserId)}) do
                    local sub = f:FindFirstChild(n)
                    if sub then roots[#roots + 1] = sub end
                end
            end
        end
        for _, root in ipairs(roots) do
            local o = scanValueObjects(root, names, nil)
            if o then
                obj = o
                return
            end
        end
    end)
    if obj then
        statSourceCache[cacheKey] = {kind = "value", obj = obj, label = "data"}
        return exactNumber(obj.Value), "data"
    end

    statSourceCache[cacheKey] = {miss = statNow()}
    return nil, nil
end

local SEED_NAMES = {"seeds", "seed"}
local TRAIT_NAMES = {"traittokens", "traittoken"}

local lastKnownStat = {}

local function rememberStat(key, v, src)
    if v ~= nil then
        lastKnownStat[key] = {value = v, src = src}
    end
    return v, src
end

local function cachedStat(key)
    local c = lastKnownStat[key]
    if c then
        return c.value, "cached"
    end
    return nil, nil
end

local function getSeedsAmount()
    local v, src = findExactStat("Seeds", SEED_NAMES)
    if v ~= nil then
        return rememberStat("Seeds", v, src)
    end
    local n, raw = readDisplayAmount("SeedsDisplay")
    if n and n >= 0 then
        local _, abbr = parseAmountText(raw or "")
        return rememberStat("Seeds", n, abbr and "GUI rounded" or "GUI")
    end
    return cachedStat("Seeds")
end

local function getTraitTokensAmount()
    local v, src = findExactStat("Trait Token", TRAIT_NAMES)
    if v ~= nil then
        return rememberStat("Trait Token", v, src)
    end
    local n, raw = readDisplayAmount("TraitTokensDisplay")
    if n and n >= 0 then
        local _, abbr = parseAmountText(raw or "")
        return rememberStat("Trait Token", n, abbr and "GUI rounded" or "GUI")
    end
    return cachedStat("Trait Token")
end

local iconCache = {}

local function readDisplayIconId(name)
    if iconCache[name] then
        return iconCache[name]
    end
    local frame = getCurrencyFrame(name)
    if not frame then
        return nil
    end
    local found = nil
    pcall(function()
        local list = {frame}
        for _, d in ipairs(frame:GetDescendants()) do
            list[#list + 1] = d
        end
        for _, obj in ipairs(list) do
            if obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
                local img = tostring(obj.Image or "")
                local id = img:match("rbxassetid://(%d+)") or img:match("[?&]id=(%d+)") or img:match("^(%d+)$")
                if id then
                    found = tonumber(id)
                    return
                end
            end
        end
    end)
    if found then
        iconCache[name] = found
    end
    return found
end

local function getStatIcons()
    local icons = {}
    local any = false
    local s = readDisplayIconId("SeedsDisplay")
    if s then
        icons["Seeds"] = s
        any = true
    end
    local t = readDisplayIconId("TraitTokensDisplay")
    if t then
        icons["Trait Token"] = t
        any = true
    end
    if any then
        return icons
    end
    return nil
end

local function collectStats()
    local stats = {}
    local keys = {}
    local seeds = getSeedsAmount()
    if seeds ~= nil then
        stats["Seeds"] = seeds
        keys[#keys + 1] = "Seeds"
    end
    local trait = getTraitTokensAmount()
    if trait ~= nil then
        stats["Trait Token"] = trait
        keys[#keys + 1] = "Trait Token"
    end
    if #keys == 0 then
        return nil, nil
    end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do
        parts[#parts + 1] = k .. "=" .. tostring(stats[k])
    end
    return stats, table.concat(parts, "|")
end

local gameMetaCache = nil

local function getGameMeta()
    if gameMetaCache and gameMetaCache.placeId == game.PlaceId then
        return gameMetaCache
    end
    local meta = {placeId = game.PlaceId, universeId = nil, gameName = nil}
    pcall(function()
        local gid = game.GameId
        if type(gid) == "number" and gid > 0 then
            meta.universeId = gid
        end
    end)
    pcall(function()
        local info = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId)
        if type(info) == "table" and type(info.Name) == "string" and info.Name ~= "" then
            meta.gameName = info.Name
        end
    end)
    gameMetaCache = meta
    return meta
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

local function clickGuiButton(btn)
    if not btn then
        return false
    end
    local target = btn
    local okIs, isBtn = pcall(function()
        return target:IsA("GuiButton")
    end)
    if not okIs or not isBtn then
        local okFind, sub = pcall(function()
            return btn:FindFirstChildWhichIsA("GuiButton", true)
        end)
        if not okFind or not sub then
            return false
        end
        target = sub
    end
    local fired = false
    pcall(function()
        if getconnections then
            for _, sig in ipairs({target.MouseButton1Click, target.Activated}) do
                for _, c in ipairs(getconnections(sig)) do
                    pcall(function()
                        if c.Fire then
                            c:Fire()
                        elseif c.Function then
                            c.Function()
                        end
                    end)
                    fired = true
                end
            end
        end
    end)
    if fired then
        return true
    end
    pcall(function()
        if firesignal then
            firesignal(target.MouseButton1Click)
            fired = true
        end
    end)
    if fired then
        return true
    end
    pcall(function()
        local vim = game:GetService("VirtualInputManager")
        local pos = target.AbsolutePosition + (target.AbsoluteSize / 2)
        local x, y = pos.X, pos.Y
        local sg = target:FindFirstAncestorWhichIsA("ScreenGui")
        if sg and not sg.IgnoreGuiInset then
            local inset = game:GetService("GuiService"):GetGuiInset()
            y = y + inset.Y
        end
        vim:SendMouseButtonEvent(x, y, 0, true, game, 0)
        task.wait(0.05)
        vim:SendMouseButtonEvent(x, y, 0, false, game, 0)
        fired = true
    end)
    return fired
end

local function waitUntilHidden(path)
    while autoFarmEnabled and isVisible(path) do task.wait(0.5) end
end

local function waitForGameStart(difficulty)
    difficulty = difficulty or "dif_normal"
    while autoFarmEnabled do
        if isVisible("GameGui.Screen.Middle.GameEnd") then
            if autoReplayEnabled then
                pcall(function() restartGame:InvokeServer() end)
                waitUntilHidden("GameGui.Screen.Middle.GameEnd")
            end
        elseif isVisible("GameGui.Screen.Middle.DifficultyVote") then
            pcall(function() placeDifficultyVote:InvokeServer(difficulty) end)
            waitUntilHidden("GameGui.Screen.Middle.DifficultyVote")
        else
            break
        end
        task.wait(0.5)
    end
end

local function getSpeedButton(n)
    local ok, b = pcall(function()
        return player.PlayerGui.GameGuiNoInset.Screen.Top.WaveControls.WaveControls.GameSpeed.Speeds:FindFirstChild(tostring(n))
    end)
    if ok then
        return b
    end
    return nil
end

local function isSpeedLocked(n)
    local b = getSpeedButton(n)
    if not b then
        return false
    end
    local lock = b:FindFirstChild("Lock")
    if not lock then
        return false
    end
    local ok, vis = pcall(function()
        return lock.Visible
    end)
    if ok and vis == false then
        return false
    end
    return true
end

local function isSpeedSelected(n)
    local b = getSpeedButton(n)
    if not b then
        return nil
    end
    local grad = b:FindFirstChild("UIGradient")
    if not grad then
        return nil
    end
    local ok, c = pcall(function()
        return grad.Color.Keypoints[1].Value
    end)
    if not ok or not c then
        return nil
    end
    if c.G > 0.8 and c.R < 0.6 and c.B < 0.25 then
        return true
    end
    return false
end

local function getCurrentSpeed()
    for n = 1, 3 do
        if isSpeedSelected(n) == true then
            return n
        end
    end
    return nil
end

local function getDesiredSpeed()
    if isSpeedLocked(3) then
        return 2
    end
    return 3
end

local function runSpeedMonitor(isActive, nowFn)
    local lastVote = -1000
    local votedOnce = false
    while isActive() do
        local want = getDesiredSpeed()
        local cur = getCurrentSpeed()
        if (cur ~= nil and cur ~= want) or (cur == nil and not votedOnce) then
            local t = nowFn()
            if t - lastVote >= 2 then
                pcall(function()
                    changeTickSpeed:InvokeServer(want)
                end)
                lastVote = t
                votedOnce = true
            end
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
    observedSig = nil,
    observedAt = 0,
    lastSentSig = nil,
    lastSentStats = nil,
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

local function performSync(kind, stats, sig)
    syncState.inflight = true
    pcall(function()
        local payload = {username = tostring(player.Name)}
        local path = API_CONFIG.HeartbeatPath
        if kind == "update" then
            path = API_CONFIG.UpdatePath
            payload.stats = stats
            if stats["Seeds"] ~= nil then
                payload.seed = stats["Seeds"]
            end
            if stats["Trait Token"] ~= nil then
                payload.traitTokens = stats["Trait Token"]
            end
            local icons = getStatIcons()
            if icons then
                payload.icons = icons
            end
            pcall(function()
                payload.userId = player.UserId
                payload.displayName = tostring(player.DisplayName)
            end)
            local meta = getGameMeta()
            payload.placeId = meta.placeId
            payload.universeId = meta.universeId
            payload.gameName = meta.gameName
        end
        local data, status, _, retryAfter = httpJson("POST", apiUrl(path), payload, API_CONFIG.Timeout)
        local t = clockNow()
        if status >= 200 and status < 300 and type(data) == "table" and data.ok == true then
            syncState.failCount = 0
            syncState.lastOkAt = t
            syncState.nextAllowedAt = t + API_CONFIG.MinInterval
            tokenLinked = true
            if kind == "update" then
                syncState.lastSentSig = sig
                syncState.lastSentStats = stats
                syncState.needUpdate = false
            end
            syncState.lastStatus = "ok"
        elseif status == 401 or status == 403 then
            tokenLinked = false
            syncState.authFailed = true
            syncState.lastStatus = "auth_" .. tostring(status)
        elseif status == 404 and kind == "heartbeat" then
            syncState.needUpdate = true
            syncState.nextAllowedAt = t + math.max(API_CONFIG.HeartbeatInterval, API_CONFIG.MinInterval)
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
    local stats, sig = collectStats()
    if sig ~= nil and sig ~= syncState.observedSig then
        syncState.observedSig = sig
        syncState.observedAt = t
    end
    if t < syncState.nextAllowedAt then
        return
    end
    if stats ~= nil and (syncState.needUpdate or syncState.forceSend or sig ~= syncState.lastSentSig) then
        if syncState.forceSend or t - syncState.observedAt >= API_CONFIG.Debounce then
            syncState.forceSend = false
            performSync("update", stats, sig)
        end
        return
    end
    if API_CONFIG.HeartbeatInterval > 0 and t - syncState.lastOkAt >= API_CONFIG.HeartbeatInterval then
        performSync("heartbeat", nil, nil)
    end
end

local function resetSync()
    tokenLinked = false
    syncState.authFailed = false
    syncState.failCount = 0
    syncState.nextAllowedAt = 0
    syncState.lastOkAt = 0
    syncState.lastSentSig = nil
    syncState.lastSentStats = nil
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

local RADIOACTIVE_RAMPAGE_L4_PROFILE_FALLBACK = {
    Name = "Radioactive Rampage ( Level 4 )",
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

local ENCHANTED_ENCOUNTER_L5_PROFILE_FALLBACK = {
    Name = "Enchanted Encounter ( Level 5 )",
    Difficulty = "dif_impossible",
    MaxPlace = 20,
    UfoReserve = 0,
    DefaultAngle = {-math.pi, 0, -math.pi},
    DefaultRotation = 180,
    Price = {
        unit_razor_rainbow = 200,
        unit_life_flower = 1300,
        unit_black_hole = 4500,
        unit_bloodvine = 2000,
        unit_lava_shroom = 3250,
    },
    Abilities = {
        {Unit = "unit_lava_shroom", Interval = 2},
    },
    Events = {
        {
            Type = "StartPlace",
            Name = "Stage1_Rainbow_1to6",
            HardCap = 6,
            MaxCount = 6,
            SoftFail = false,
            MaxAttempts = 80,
            MaxCashWait = 900,
            Shuffle = true,
            ReserveSlots = 0,
            Units = {
                {name = "unit_razor_rainbow", pos = {-339.91, 61.68, -69.11}},
                {name = "unit_razor_rainbow", pos = {-339.55, 61.68, -72.08}},
                {name = "unit_razor_rainbow", pos = {-339.76, 61.68, -74.75}},
                {name = "unit_razor_rainbow", pos = {-331.43, 61.68, -69.14}},
                {name = "unit_razor_rainbow", pos = {-331.92, 61.68, -72.04}},
                {name = "unit_razor_rainbow", pos = {-331.19, 61.68, -74.66}},
            },
        },
        {
            Type = "StartUpgradeAll",
            Name = "Upgrade_To9",
            RequireMinPlaced = 6,
            StopAtWave = 9,
        },
        {
            Type = "WaitWave",
            Wave = 9,
        },
        {
            Type = "StartPlace",
            Name = "Stage1_Ember_7",
            HardCap = 7,
            MaxCount = 1,
            SoftFail = false,
            MaxAttempts = 80,
            MaxCashWait = 900,
            Shuffle = true,
            ReserveSlots = 0,
            PauseUpgrade = true,
            Units = {
                {name = "unit_life_flower", pos = {-335.72, 61.68, -122.21}},
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
            Name = "Stage1_BlackHole_8to10",
            HardCap = 10,
            MaxCount = 3,
            SoftFail = false,
            MaxAttempts = 80,
            MaxCashWait = 900,
            Shuffle = true,
            ReserveSlots = 0,
            PauseUpgrade = true,
            Units = {
                {name = "unit_black_hole", pos = {-338.76, 61.68, -124.50}},
                {name = "unit_black_hole", pos = {-335.42, 61.68, -125.40}},
                {name = "unit_black_hole", pos = {-331.14, 61.68, -124.77}},
            },
        },
        {
            Type = "StartUpgradeAll",
            Name = "Upgrade_To27",
            RequireMinPlaced = 1,
            StopAtWave = 27,
        },
        {
            Type = "WaitWave",
            Wave = 27,
        },
        {
            Type = "StartPlace",
            Name = "Stage1_Bloodvine_11to15",
            HardCap = 15,
            MaxCount = 5,
            SoftFail = false,
            MaxAttempts = 80,
            MaxCashWait = 900,
            Shuffle = true,
            ReserveSlots = 0,
            PauseUpgrade = true,
            Units = {
                {name = "unit_bloodvine", pos = {-342.08, 61.68, -129.99}},
                {name = "unit_bloodvine", pos = {-337.48, 61.68, -130.16}},
                {name = "unit_bloodvine", pos = {-333.00, 61.68, -130.15}},
                {name = "unit_bloodvine", pos = {-328.43, 61.68, -129.57}},
                {name = "unit_bloodvine", pos = {-330.30, 61.68, -134.85}},
            },
        },
        {
            Type = "StartUpgradeAll",
            Name = "Upgrade_To30",
            RequireMinPlaced = 1,
            StopAtWave = 30,
        },
        {
            Type = "WaitWave",
            Wave = 30,
        },
        {
            Type = "StartPlace",
            Name = "Stage1_Ashroom_16to18",
            HardCap = 18,
            MaxCount = 3,
            SoftFail = false,
            MaxAttempts = 80,
            MaxCashWait = 900,
            Shuffle = true,
            ReserveSlots = 0,
            PauseUpgrade = true,
            Units = {
                {name = "unit_lava_shroom", pos = {-340.10, 61.68, -114.17}},
                {name = "unit_lava_shroom", pos = {-330.93, 61.68, -114.18}},
                {name = "unit_lava_shroom", pos = {-344.12, 61.68, -116.54}},
            },
        },
        {
            Type = "StartUpgradeAll",
            Name = "Upgrade_Stage1_End",
            RequireMinPlaced = 0,
            UntilGameEnd = true,
        },
    },
    Stage2 = {
        TriggerZ = -147.468,
        Compare = "less",
        EnemyMatch = "enemy",
        ConfirmChecks = 2,
        SellAll = true,
        Events = {
            {
                Type = "StartPlace",
                Name = "Stage2_All_1to12",
                HardCap = 12,
                MaxCount = 12,
                SoftFail = false,
                MaxAttempts = 80,
                MaxCashWait = 900,
                Shuffle = false,
                ReserveSlots = 0,
                PauseUpgrade = true,
                Units = {
                    {name = "unit_bloodvine", pos = {-340.29, 61.68, -212.21}},
                    {name = "unit_bloodvine", pos = {-339.80, 61.68, -216.59}},
                    {name = "unit_bloodvine", pos = {-328.89, 61.68, -218.62}},
                    {name = "unit_bloodvine", pos = {-340.55, 61.68, -221.37}},
                    {name = "unit_bloodvine", pos = {-329.25, 61.68, -224.26}},
                    {name = "unit_life_flower", pos = {-330.50, 61.68, -212.67}},
                    {name = "unit_lava_shroom", pos = {-339.63, 61.68, -225.98}},
                    {name = "unit_lava_shroom", pos = {-329.74, 61.68, -228.97}},
                    {name = "unit_lava_shroom", pos = {-329.01, 61.68, -235.23}},
                    {name = "unit_black_hole", pos = {-338.53, 61.68, -228.87}},
                    {name = "unit_black_hole", pos = {-331.44, 61.68, -232.74}},
                    {name = "unit_black_hole", pos = {-339.77, 61.68, -233.83}},
                },
            },
            {
                Type = "StartUpgradeAll",
                Name = "Upgrade_Stage2_End",
                RequireMinPlaced = 0,
                UntilGameEnd = true,
            },
        },
    },
}

local ENCHANTED_ENCOUNTER_LEVELS = {
    ["Level 5"] = {url = FARM_URL_ENCHANTED_ENCOUNTER_L5, fallback = ENCHANTED_ENCOUNTER_L5_PROFILE_FALLBACK},
}

local function loadEnchantedEncounterProfile(level)
    local entry = ENCHANTED_ENCOUNTER_LEVELS[tostring(level or selectedEnchantedEncounterLevel or "Level 5")] or ENCHANTED_ENCOUNTER_LEVELS["Level 5"]
    local url = entry.url
    local data = decodeFarmLua(httpGet(url))
    if not data then
        data = deepCopy(entry.fallback)
        url = "embedded:EnchantedEncounter"
    end
    if not data then
        return nil, nil
    end
    data.Difficulty = data.Difficulty or "dif_impossible"
    return data, url
end

local RADIOACTIVE_RAMPAGE_LEVELS = {
    ["Level 4"] = {url = FARM_URL_RADIOACTIVE_RAMPAGE_L4, fallback = RADIOACTIVE_RAMPAGE_L4_PROFILE_FALLBACK},
}

local function loadRadioactiveRampageProfile(level)
    local entry = RADIOACTIVE_RAMPAGE_LEVELS[tostring(level or selectedRadioactiveRampageLevel or "Level 4")] or RADIOACTIVE_RAMPAGE_LEVELS["Level 4"]
    local url = entry.url
    local data = decodeFarmLua(httpGet(url))
    if not data then
        data = deepCopy(entry.fallback)
        url = "embedded:RadioactiveRampage"
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
    if currentFarm == "RadioactiveRampage" then
        return loadRadioactiveRampageProfile(selectedRadioactiveRampageLevel)
    end
    if currentFarm == "EnchantedEncounter" then
        return loadEnchantedEncounterProfile(selectedEnchantedEncounterLevel)
    end
    return loadFarmProfile(selectedFarmMode)
end

local farmProfile = nil
if not isLobby then
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

local placedUnitIds = {}
local abilityDebugText = "N/A"

local function extractUnitId(v, depth)
    depth = depth or 0
    if depth > 2 then
        return nil
    end
    local tv = type(v)
    if tv == "number" then
        if v > 0 and v == math.floor(v) then
            return v
        end
        return nil
    end
    if tv == "string" then
        local n = tonumber(v)
        if n and n > 0 and n == math.floor(n) then
            return n
        end
        return nil
    end
    if tv == "table" then
        for _, k in ipairs({"Id", "ID", "id", "UnitId", "unitId", "UnitID", "Uid", "UID", "uid"}) do
            local n = extractUnitId(v[k], depth + 1)
            if n then
                return n
            end
        end
        return extractUnitId(v[1], depth + 1)
    end
    local found = nil
    pcall(function()
        if typeof(v) == "Instance" then
            for k, val in pairs(v:GetAttributes()) do
                if type(val) == "number" and string.lower(k):find("id") then
                    found = val
                    return
                end
            end
        end
    end)
    return found
end

local function rememberPlacedId(unitName, ret)
    local id = extractUnitId(ret)
    if not id then
        return
    end
    local list = placedUnitIds[unitName] or {}
    for _, x in ipairs(list) do
        if x == id then
            return
        end
    end
    list[#list + 1] = id
    placedUnitIds[unitName] = list
end

local function scanEntityIds(unitName)
    local out = {}
    local core = string.lower(tostring(unitName)):gsub("^unit_", "")
    local folder = getEntitiesFolder()
    if not folder then
        return out, 0
    end
    local count = 0
    pcall(function()
        for _, m in ipairs(folder:GetChildren()) do
            local n = string.lower(tostring(m.Name))
            if n:sub(1, 5) == "unit_" and n:find(core, 1, true) then
                count = count + 1
                local id = nil
                pcall(function()
                    for k, v in pairs(m:GetAttributes()) do
                        if type(v) == "number" and string.lower(k):find("id") then
                            id = v
                            return
                        end
                    end
                end)
                if not id then
                    pcall(function()
                        for _, c in ipairs(m:GetChildren()) do
                            if c:IsA("ValueBase") and string.lower(c.Name):find("id") then
                                local nn = tonumber(c.Value)
                                if nn then
                                    id = nn
                                    return
                                end
                            end
                        end
                    end)
                end
                if not id then
                    id = tonumber(n:match("(%d+)$"))
                end
                if id then
                    out[#out + 1] = id
                end
            end
        end
    end)
    return out, count
end

local function getAbilityIds(unitName)
    local ids, seen = {}, {}
    local scanned, count = scanEntityIds(unitName)
    for _, id in ipairs(scanned) do
        if not seen[id] then
            seen[id] = true
            ids[#ids + 1] = id
        end
    end
    for _, id in ipairs(placedUnitIds[unitName] or {}) do
        if not seen[id] then
            seen[id] = true
            ids[#ids + 1] = id
        end
    end
    return ids, count
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

    local okInvoke, placeRet = pcall(function()
        return placeUnit:InvokeServer(unpack(args))
    end)
    if okInvoke then
        rememberPlacedId(unit.name, placeRet)
    end

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

    local stage2Cfg = type(profile.Stage2) == "table" and profile.Stage2 or nil
    local stageState = {stage = 1, triggered = false}

    local function stillInGame()
        if not inGame then
            return false
        end
        if stageState.stage == 1 and stageState.triggered then
            return false
        end
        return true
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
        runSpeedMonitor(function()
            return autoFarmEnabled and inGame
        end, clockNow)
    end)

    task.spawn(function()
        while autoFarmEnabled and inGame do
            if autoSkipEnabled and isVisible("GameGuiNoInset.Screen.Top.SkipWave") then
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
                task.wait(0.4)
                local tries = 0
                while autoFarmEnabled and inGame and isVisible("GameGui.Screen.Bottom.UnitViewer") and tries < 8 do
                    local closeBtn = nil
                    pcall(function()
                        closeBtn = player.PlayerGui.GameGui.Screen.Bottom.UnitViewer.Close
                    end)
                    clickGuiButton(closeBtn)
                    tries = tries + 1
                    task.wait(0.35)
                end
                if autoFarmEnabled and inGame and isVisible("GameGui.Screen.Bottom.UnitViewer") then
                    pcall(function()
                        player.PlayerGui.GameGui.Screen.Bottom.UnitViewer.Visible = false
                    end)
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
        while autoFarmEnabled and stillInGame() and getWaveNumber() < target do
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
        if not autoFarmEnabled or not stillInGame() then return end
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

    local function runEvents(events)
        for _, ev in ipairs(events or {}) do
            if not autoFarmEnabled or not stillInGame() then break end
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
    end

    local function enemyPassed(cfg)
        local folder = getEntitiesFolder()
        if not folder then
            return false
        end
        local limit = tonumber(cfg.TriggerZ) or -147.468
        local cmp = string.lower(tostring(cfg.Compare or "less"))
        local match = string.lower(tostring(cfg.EnemyMatch or "enemy"))
        local hit = false
        pcall(function()
            for _, m in ipairs(folder:GetChildren()) do
                local n = string.lower(tostring(m.Name))
                if n:sub(1, 5) ~= "unit_" and n:find(match, 1, true) then
                    local okPos, pos = pcall(function()
                        if m.GetPivot then
                            return m:GetPivot().Position
                        end
                        return m.Position
                    end)
                    if okPos and pos then
                        local z = pos.Z
                        if (cmp == "greater" and z > limit) or (cmp ~= "greater" and z < limit) then
                            hit = true
                            return
                        end
                    end
                end
            end
        end)
        return hit
    end

    if stage2Cfg then
        task.spawn(function()
            local need = tonumber(stage2Cfg.ConfirmChecks) or 2
            local streak = 0
            while autoFarmEnabled and inGame and not stageState.triggered do
                if enemyPassed(stage2Cfg) then
                    streak = streak + 1
                    if streak >= need then
                        stageState.triggered = true
                        break
                    end
                else
                    streak = 0
                end
                task.wait(0.3)
            end
        end)
    end

    if type(profile.Abilities) == "table" and #profile.Abilities > 0 then
        task.spawn(function()
            local lastFire = {}
            while autoFarmEnabled and inGame do
                local parts = {}
                for _, ab in ipairs(profile.Abilities) do
                    local unitName = tostring(ab.Unit or ab.unit or "")
                    if unitName ~= "" then
                        local ids, count = getAbilityIds(unitName)
                        local interval = tonumber(ab.Interval or ab.interval) or 2
                        local now = clockNow()
                        if #ids > 0 and (not lastFire[unitName] or now - lastFire[unitName] >= interval) then
                            lastFire[unitName] = now
                            for _, id in ipairs(ids) do
                                pcall(function()
                                    activateUnitAbility:InvokeServer(id)
                                end)
                            end
                        end
                        local idText = {}
                        for _, id in ipairs(ids) do
                            idText[#idText + 1] = tostring(id)
                        end
                        parts[#parts + 1] = unitName:gsub("^unit_", "") .. " x" .. tostring(count) .. ": " .. (#idText > 0 and table.concat(idText, ", ") or "no ID")
                    end
                end
                abilityDebugText = table.concat(parts, " | ")
                task.wait(0.5)
            end
        end)
    end

    local function runStage2()
        stageState.stage = 2
        setUpgrade(nil, false)
        upgradeState.pause = true
        if stage2Cfg.SellAll ~= false then
            pcall(function()
                sellAll:InvokeServer()
            end)
            local waited = 0
            while autoFarmEnabled and inGame and getOwnedUnitCount() > 0 and waited < 8 do
                task.wait(0.25)
                waited = waited + 0.25
            end
            for k in pairs(placedUnitIds) do
                placedUnitIds[k] = nil
            end
        end
        placedCounter.value = getOwnedUnitCount()
        upgradeState.pause = false
        task.wait(0.4)
        runEvents(stage2Cfg.Events)
    end

    runEvents(profile.Events)

    while autoFarmEnabled and inGame and not isVisible("GameGui.Screen.Middle.GameEnd") do
        if stage2Cfg and stageState.triggered and stageState.stage == 1 then
            runStage2()
        end
        task.wait(0.5)
    end
    inGame = false
    isPlacing.value = false
end

local function startAutoFarm()
    if farmThread then return end
    farmThread = task.spawn(function()
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

local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local UI_STATE_FILE = "NexusStella_UIState.json"
local Settings = {UIHidden = false}

do
    if fileExists(UI_STATE_FILE) then
        local raw = readFileSafe(UI_STATE_FILE)
        if raw and raw ~= "" then
            local ok, decoded = pcall(function()
                return HttpService:JSONDecode(raw)
            end)
            if ok and type(decoded) == "table" and type(decoded.UIHidden) == "boolean" then
                Settings.UIHidden = decoded.UIHidden
            end
        end
    end
end

local function SaveState()
    pcall(function()
        writeFileSafe(UI_STATE_FILE, HttpService:JSONEncode({UIHidden = Settings.UIHidden}))
    end)
end

local function getMainGui()
    local gui = nil
    pcall(function()
        gui = CoreGui:FindFirstChild("redz Library V5")
    end)
    if not gui then
        pcall(function()
            if gethui then
                gui = gethui():FindFirstChild("redz Library V5")
            end
        end)
    end
    return gui
end

local function CreateLogo()
    if CoreGui:FindFirstChild("NexusLogoGui") then
        CoreGui:FindFirstChild("NexusLogoGui"):Destroy()
    end
    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "NexusLogoGui"
    ScreenGui.ResetOnSpawn = false
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    ScreenGui.DisplayOrder = 10000
    ScreenGui.Parent = CoreGui

    local LogoButton = Instance.new("ImageButton")
    LogoButton.Name = "Logo"
    LogoButton.Parent = ScreenGui
    LogoButton.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    LogoButton.BackgroundTransparency = 0.5
    LogoButton.Position = UDim2.new(0.1, 0, 0.1, 0)
    LogoButton.Size = UDim2.new(0, 50, 0, 50)
    LogoButton.AutoButtonColor = false
    LogoButton.Active = true

    local UICorner = Instance.new("UICorner")
    UICorner.CornerRadius = UDim.new(0, 12)
    UICorner.Parent = LogoButton

    local UIStroke = Instance.new("UIStroke")
    UIStroke.Parent = LogoButton
    UIStroke.Color = Color3.fromRGB(255, 255, 255)
    UIStroke.Thickness = 1
    UIStroke.Transparency = 0.5

    task.spawn(function()
        local ok, imgAsset = pcall(function()
            local fileName = "NexusLogo_ATx.png"
            local url = "https://raw.githubusercontent.com/nguyennhlat2004/Roblox-Api/main/ATx.png"
            if not isfile(fileName) then
                writefile(fileName, game:HttpGet(url))
            end
            return getcustomasset(fileName)
        end)
        if ok and imgAsset then
            LogoButton.Image = imgAsset
        else
            LogoButton.Image = "rbxassetid://13347535978"
        end
    end)

    local dragging = false
    local moved = false
    local dragStart = nil
    local startPos = nil
    local dragInput = nil

    LogoButton.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            moved = false
            dragStart = input.Position
            startPos = LogoButton.Position
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if not dragging or not dragStart then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement or input == dragInput or input.UserInputType == Enum.UserInputType.Touch then
            local delta = input.Position - dragStart
            if math.abs(delta.X) > 6 or math.abs(delta.Y) > 6 then
                moved = true
            end
            if moved then
                LogoButton.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
            if not moved then
                local MainGui = getMainGui()
                if MainGui then
                    MainGui.Enabled = not MainGui.Enabled
                    Settings.UIHidden = not MainGui.Enabled
                    SaveState()
                end
            end
        end
    end)
end

CreateLogo()

task.spawn(function()
    if Settings.UIHidden then
        task.wait(0.5)
        local MainGui = getMainGui()
        if MainGui then
            MainGui.Enabled = false
        end
    end
end)

local TabMain = nil
if not isLobby then
    TabMain = Window:MakeTab({"Main", "home"})
end
local TabSetting = Window:MakeTab({"Setting", "settings"})

local volcanoToggle = nil
local radioactiveRampageToggle = nil
local enchantedEncounterToggle = nil

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
        elseif other == "RadioactiveRampage" then
            setToggleSilent(radioactiveRampageToggle, false)
        elseif other == "EnchantedEncounter" then
            setToggleSilent(enchantedEncounterToggle, false)
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

if TabMain then
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
        Name = "Radioactive Rampage Level",
        Options = {"Level 4"},
        Default = "Level 4",
        Flag = "RadioactiveRampageLevel",
        Callback = function(Value)
            local v = tostring(Value or "Level 4")
            if RADIOACTIVE_RAMPAGE_LEVELS[v] then
                selectedRadioactiveRampageLevel = v
            else
                selectedRadioactiveRampageLevel = "Level 4"
            end
            if currentFarm == "RadioactiveRampage" then
                local data = loadActiveProfile()
                if data then
                    farmProfile = data
                end
            end
        end
    })

    radioactiveRampageToggle = TabMain:AddToggle({
        Name = "Auto Farm Radioactive Rampage",
        Default = false,
        Flag = "AutoFarmRadioactiveRampage",
        Callback = function(Value)
            if Value then
                startFarmFor("RadioactiveRampage")
            else
                stopFarmFor("RadioactiveRampage")
            end
        end
    })

    TabMain:AddDropdown({
        Name = "Enchanted Encounter Level",
        Options = {"Level 5"},
        Default = "Level 5",
        Flag = "EnchantedEncounterLevel",
        Callback = function(Value)
            local v = tostring(Value or "Level 5")
            if ENCHANTED_ENCOUNTER_LEVELS[v] then
                selectedEnchantedEncounterLevel = v
            else
                selectedEnchantedEncounterLevel = "Level 5"
            end
            if currentFarm == "EnchantedEncounter" then
                local data = loadActiveProfile()
                if data then
                    farmProfile = data
                end
            end
        end
    })

    enchantedEncounterToggle = TabMain:AddToggle({
        Name = "Auto Farm Enchanted Encounter",
        Default = false,
        Flag = "AutoFarmEnchantedEncounter",
        Callback = function(Value)
            if Value then
                startFarmFor("EnchantedEncounter")
            else
                stopFarmFor("EnchantedEncounter")
            end
        end
    })
end

local function formatAmount(n)
    if n == nil then
        return "N/A"
    end
    local whole = math.floor(n + 0.5)
    local str = tostring(whole)
    local out = str:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    out = out:gsub("^,", "")
    return out
end

if not isLobby then
    TabSetting:AddToggle({
        Name = "Auto Skip",
        Default = true,
        Flag = "AutoSkipWave",
        Callback = function(Value)
            autoSkipEnabled = Value == true
        end
    })

    TabSetting:AddToggle({
        Name = "Auto Replay",
        Default = true,
        Flag = "AutoReplay",
        Callback = function(Value)
            autoReplayEnabled = Value == true
        end
    })
end

TabSetting:AddToggle({
    Name = "Anti AFK",
    Default = true,
    Flag = "AntiAfkEnabled",
    Callback = function(Value)
        setAntiAfk(Value == true)
    end
})

TabSetting:AddToggle({
    Name = "WebHook",
    Default = false,
    Flag = "WebHookEnabled",
    Callback = function(Value)
        if Value then
            resetSync()
            webhookEnabled = true
        else
            webhookEnabled = false
        end
    end
})

local seedParagraph = TabSetting:AddParagraph({"Seed", "N/A"})
local traitParagraph = TabSetting:AddParagraph({"Trait Token", "N/A"})
local webhookParagraph = TabSetting:AddParagraph({"WebHook Status", "Off"})
local abilityParagraph = nil
if not isLobby then
    abilityParagraph = TabSetting:AddParagraph({"Ashroom Ability", "N/A"})
end

local showCurrencyRunning = false
local currencyState = {root = nil, original = {}, touched = {}}

local function getCurrencyDisplay()
    local ok, cd = pcall(function()
        return player.PlayerGui.GameGui.Screen.Bottom.CurrencyDisplay
    end)
    if ok then
        return cd
    end
    return nil
end

local function isGuiObject(obj)
    local ok, res = pcall(function()
        return obj:IsA("GuiObject")
    end)
    return ok and res == true
end

local function rememberOriginal(obj)
    if obj and currencyState.original[obj] == nil and isGuiObject(obj) then
        currencyState.original[obj] = obj.Visible == true
    end
end

local function snapshotCurrency(cd)
    currencyState.root = cd
    currencyState.original = {}
    currencyState.touched = {}
    rememberOriginal(cd)
    pcall(function()
        for _, child in ipairs(cd:GetChildren()) do
            rememberOriginal(child)
        end
    end)
end

local function currencyStep()
    local cd = getCurrencyDisplay()
    if not cd then
        return
    end
    if currencyState.root ~= cd then
        snapshotCurrency(cd)
    end
    pcall(function()
        for _, child in ipairs(cd:GetChildren()) do
            if not currencyState.touched[child] then
                rememberOriginal(child)
            end
        end
    end)
    if showCurrencyRunning then
        local targets = {cd, cd:FindFirstChild("SeedsDisplay"), cd:FindFirstChild("TraitTokensDisplay")}
        for _, obj in ipairs(targets) do
            if obj and isGuiObject(obj) then
                rememberOriginal(obj)
                if obj.Visible ~= true then
                    obj.Visible = true
                end
                currencyState.touched[obj] = true
            end
        end
    else
        for obj in pairs(currencyState.touched) do
            local okParent, parent = pcall(function()
                return obj.Parent
            end)
            if okParent and parent then
                local orig = currencyState.original[obj]
                if orig ~= nil and obj.Visible ~= orig then
                    obj.Visible = orig
                end
            else
                currencyState.touched[obj] = nil
            end
        end
    end
end

TabSetting:AddToggle({
    Name = "Show Seed And TraitToken",
    Default = false,
    Flag = "ShowSeedTraitToken",
    Callback = function(Value)
        showCurrencyRunning = Value == true
        pcall(currencyStep)
    end
})

task.spawn(function()
    while true do
        pcall(currencyStep)
        task.wait(0.25)
    end
end)

local function webhookStatusText()
    if not webhookEnabled then
        return "Off"
    end
    if not apiReady() or TOKEN == "" then
        return "API not configured"
    end
    if syncState.authFailed then
        return "Token rejected (" .. tostring(syncState.lastStatus) .. ")"
    end
    if collectStats() == nil then
        return "Cannot read Seed / Trait Token"
    end
    local st = tostring(syncState.lastStatus or "")
    if st == "ok" and syncState.lastSentStats ~= nil then
        local parts = {}
        for _, k in ipairs({"Seeds", "Trait Token"}) do
            if syncState.lastSentStats[k] ~= nil then
                parts[#parts + 1] = k .. ": " .. formatAmount(syncState.lastSentStats[k])
            end
        end
        return "Sent " .. table.concat(parts, " | ") .. " (" .. tostring(player.Name) .. ")"
    end
    if st:sub(1, 6) == "retry_" then
        return "Network error, retrying (" .. st:sub(7) .. ")"
    end
    if st:sub(1, 12) == "bad_request_" then
        return "Bad request (" .. st:sub(13) .. ")"
    end
    return "Sending..."
end

task.spawn(function()
    while true do
        pcall(function()
            local seed, seedSrc = getSeedsAmount()
            if seed ~= nil then
                seedParagraph:SetDesc(formatAmount(seed) .. "  (" .. tostring(seedSrc) .. ")")
            else
                seedParagraph:SetDesc("N/A")
            end
            local tn, tSrc = getTraitTokensAmount()
            if tn ~= nil then
                traitParagraph:SetDesc(formatAmount(tn) .. "  (" .. tostring(tSrc) .. ")")
            else
                traitParagraph:SetDesc("N/A")
            end
            webhookParagraph:SetDesc(webhookStatusText())
            if abilityParagraph then
                abilityParagraph:SetDesc(abilityDebugText)
            end
        end)
        task.wait(0.5)
    end
end)

if not isLobby then
    TabSetting:AddButton({
        Name = "Reload Farm Profile",
        Callback = function()
            local data = loadActiveProfile()
            if data then
                farmProfile = data
            end
        end
    })
end

task.spawn(function()
    while true do
        pcall(syncTick)
        task.wait(0.5)
    end
end)
d)
