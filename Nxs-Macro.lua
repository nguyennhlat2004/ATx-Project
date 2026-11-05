local redzlib = loadstring(game:HttpGet("https://raw.githubusercontent.com/nhat0258/Redz-UI-Library/refs/heads/main/Main.lua"))()

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local G = (getgenv and getgenv()) or _G

local MACRO_FOLDER = "NxsMacro"
local HISTORY_FILE = MACRO_FOLDER .. "/history.json"
local IGNORE_WORDS = {"restart", "replay", "teleport", "chat", "ping", "analytic", "camera", "mouse", "heartbeat"}

local function clockNow()
    local ok, t = pcall(function()
        return tick()
    end)
    if ok and type(t) == "number" then
        return t
    end
    return os.clock()
end

local function isShown(path)
    local shown = false
    pcall(function()
        local cur = player.PlayerGui
        for part in path:gmatch("[^.]+") do
            cur = cur:FindFirstChild(part)
            if not cur then
                return
            end
            if cur:IsA("LayerCollector") then
                if cur.Enabled == false then
                    return
                end
            elseif cur:IsA("GuiObject") then
                if cur.Visible ~= true then
                    return
                end
            end
        end
        shown = true
    end)
    return shown
end

local PATH_GAMEEND = "GameGui.Screen.Middle.GameEnd"
local PATH_VOTE = "GameGui.Screen.Middle.DifficultyVote"
local PATH_SKIP = "GameGuiNoInset.Screen.Top.SkipWave"

local function gameEndShown()
    if not isShown(PATH_GAMEEND) then
        return false
    end
    task.wait(0.3)
    return isShown(PATH_GAMEEND)
end

local lastWaveRead = 0
local function getWave()
    local w = nil
    pcall(function()
        local t = player.PlayerGui.GameGuiNoInset.Screen.Top.GameInfo.Content.Waves.Title.Text
        local a = tostring(t):match("(%d+)%s*/%s*%d+") or tostring(t):match("[Ww]ave%s*(%d+)")
        w = tonumber(a)
    end)
    if w and w > 0 then
        lastWaveRead = w
    end
    return lastWaveRead
end

local function parseAmount(text)
    local t = tostring(text or ""):gsub("<[^>]->", ""):gsub(",", ""):gsub("%s", "")
    local num, suf = t:match("(%d+%.?%d*)([KkMmBbTt]?)")
    local n = tonumber(num)
    if not n then
        return nil
    end
    local mult = {k = 1e3, m = 1e6, b = 1e9, t = 1e12}
    if suf ~= "" then
        n = n * (mult[string.lower(suf)] or 1)
    end
    return n
end

local function getCash()
    local v = nil
    pcall(function()
        local c = player.leaderstats.Cash
        if type(c.Value) == "number" then
            v = c.Value
        else
            v = parseAmount(c.Value)
        end
    end)
    if v then
        return v
    end
    pcall(function()
        local cd = player.PlayerGui.GameGui.Screen.Bottom.CurrencyDisplay
        local row = cd:FindFirstChild("CurrencyRow") or cd
        local f = row:FindFirstChild("Cash")
        if f then
            local amt = f:FindFirstChild("Amount") or f:FindFirstChildWhichIsA("TextLabel", true)
            if amt then
                v = parseAmount(amt.Text)
            end
        end
    end)
    return v or 0
end

local function entitiesFolder()
    local f = nil
    pcall(function()
        f = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Entities")
    end)
    return f
end

local function pivotOf(obj)
    local p = nil
    pcall(function()
        if obj:IsA("Model") then
            p = obj:GetPivot().Position
        elseif obj:IsA("BasePart") then
            p = obj.Position
        end
    end)
    return p
end

local function xz(a, b)
    local dx, dz = a.X - b.X, a.Z - b.Z
    return math.sqrt(dx * dx + dz * dz)
end

local function unitModels(name)
    local out = {}
    local folder = entitiesFolder()
    if not folder then
        return out
    end
    pcall(function()
        for _, c in ipairs(folder:GetChildren()) do
            if c.Name == name then
                out[#out + 1] = c
            end
        end
    end)
    return out
end

local remoteCache = {}
local function findRemote(name)
    local c = remoteCache[name]
    if c and c.Parent then
        return c
    end
    local found = nil
    pcall(function()
        local folder = ReplicatedStorage:FindFirstChild("RemoteFunctions")
        if folder then
            found = folder:FindFirstChild(name)
        end
        if not found then
            for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
                if d.Name == name and (d:IsA("RemoteFunction") or d:IsA("RemoteEvent")) then
                    found = d
                    break
                end
            end
        end
    end)
    remoteCache[name] = found
    return found
end

local function fireRemote(name, method, args, timeout)
    local r = findRemote(name)
    if not r then
        return false, "missing remote " .. tostring(name)
    end
    local state = {done = false, ok = false, ret = nil}
    task.spawn(function()
        local ok, ret = pcall(function()
            if method == "FireServer" or r:IsA("RemoteEvent") then
                r:FireServer(table.unpack(args, 1, args.n or #args))
                return true
            end
            return table.pack(r:InvokeServer(table.unpack(args, 1, args.n or #args)))
        end)
        state.ok = ok
        state.ret = ret
        state.done = true
    end)
    local t0 = clockNow()
    while not state.done and clockNow() - t0 < (timeout or 6) do
        task.wait(0.03)
    end
    if not state.done then
        return false, "timeout"
    end
    return state.ok, state.ret
end

local function fmtNumber(n)
    if n ~= n then
        return "0"
    end
    if n == math.floor(n) and math.abs(n) < 9e15 then
        return string.format("%d", n)
    end
    local s = string.format("%.4f", n)
    s = s:gsub("0+$", ""):gsub("%.$", "")
    return s
end

local function isIdent(k)
    return type(k) == "string" and k:match("^[%a_][%w_]*$") ~= nil
end

local function writeLua(v, indent)
    indent = indent or ""
    local t = type(v)
    if t == "string" then
        return string.format("%q", v)
    elseif t == "number" then
        return fmtNumber(v)
    elseif t == "boolean" then
        return tostring(v)
    elseif t ~= "table" then
        return "nil"
    end
    local n = 0
    for k in pairs(v) do
        n = n + 1
    end
    if n == 0 then
        return "{}"
    end
    local inner = indent .. "    "
    local parts = {}
    local arrLen = #v
    local simple = true
    for i = 1, arrLen do
        if type(v[i]) == "table" then
            simple = false
        end
    end
    local keys = {}
    for k in pairs(v) do
        if not (type(k) == "number" and k >= 1 and k <= arrLen and k == math.floor(k)) then
            keys[#keys + 1] = k
            if type(v[k]) == "table" then
                simple = false
            end
        end
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)
    for i = 1, arrLen do
        parts[#parts + 1] = writeLua(v[i], inner)
    end
    for _, k in ipairs(keys) do
        local ks = isIdent(k) and k or ("[" .. (type(k) == "number" and fmtNumber(k) or string.format("%q", tostring(k))) .. "]")
        parts[#parts + 1] = ks .. " = " .. writeLua(v[k], inner)
    end
    if simple and #parts <= 8 then
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return "{\n" .. inner .. table.concat(parts, ",\n" .. inner) .. ",\n" .. indent .. "}"
end

local recorder = {
    active = false,
    actions = {},
    skips = {},
    speeds = {},
    difficulty = nil,
    units = {},
    pending = 0,
    startedAt = 0,
    waveStartAt = 0,
    lastWave = 0,
    skipSince = nil,
    voteSince = nil,
    recSpeed = true,
    recSkip = true,
    spam = {},
    status = "Idle",
}

local function idLike(key)
    local l = string.lower(tostring(key))
    return l:find("id", 1, true) ~= nil or l:find("guid", 1, true) ~= nil
end

local function unitRefFor(value)
    for _, u in ipairs(recorder.units) do
        if typeof(value) == "Instance" and u.model then
            local okD, isD = pcall(function()
                return value == u.model or value:IsDescendantOf(u.model)
            end)
            if okD and isD then
                return {__t = "unit", ref = u.ref, kind = "inst"}
            end
        end
        if type(value) == "number" or type(value) == "string" then
            if u.ret ~= nil and value == u.ret then
                return {__t = "unit", ref = u.ref, kind = "ret"}
            end
            for k, av in pairs(u.attrs or {}) do
                if av == value and idLike(k) then
                    return {__t = "unit", ref = u.ref, kind = "attr", key = k}
                end
            end
        end
    end
    return nil
end

local function serialize(v, depth, matchUnits)
    depth = depth or 0
    if depth > 6 then
        return {__t = "nil"}
    end
    if matchUnits and depth > 0 then
        local ref = unitRefFor(v)
        if ref then
            return ref
        end
    end
    local t = typeof(v)
    if t == "nil" then
        return {__t = "nil"}
    elseif t == "string" or t == "number" or t == "boolean" then
        return v
    elseif t == "Vector3" then
        return {__t = "v3", v.X, v.Y, v.Z}
    elseif t == "Vector2" then
        return {__t = "v2", v.X, v.Y}
    elseif t == "CFrame" then
        return {__t = "cf", v:GetComponents()}
    elseif t == "Color3" then
        return {__t = "c3", v.R, v.G, v.B}
    elseif t == "EnumItem" then
        return {__t = "enum", v = tostring(v)}
    elseif t == "Instance" then
        local path = "?"
        pcall(function()
            path = v:GetFullName()
        end)
        return {__t = "inst", path = path}
    elseif t == "table" then
        local out = {}
        for k, val in pairs(v) do
            if type(k) == "string" or type(k) == "number" then
                out[k] = serialize(val, depth + 1, matchUnits)
            end
        end
        return out
    end
    return {__t = "nil"}
end

local function serializeArgs(args, matchUnits)
    local out = {n = args.n or #args}
    for i = 1, out.n do
        local s = serialize(args[i], 1, matchUnits)
        if matchUnits then
            local ref = unitRefFor(args[i])
            if ref then
                s = ref
            end
        end
        out[i] = s
    end
    return out
end

local function resolvePath(path)
    local cur = game
    for part in tostring(path):gmatch("[^.]+") do
        if part ~= "Game" and part ~= game.Name then
            local nxt = nil
            pcall(function()
                nxt = cur:FindFirstChild(part)
            end)
            if not nxt then
                pcall(function()
                    nxt = game:GetService(part)
                end)
            end
            if not nxt then
                return nil
            end
            cur = nxt
        end
    end
    return cur
end

local function deserialize(v, refs, missing)
    if type(v) ~= "table" then
        return v
    end
    local tag = v.__t
    if tag == "nil" then
        return nil
    elseif tag == "v3" then
        return Vector3.new(v[1], v[2], v[3])
    elseif tag == "v2" then
        return Vector2.new(v[1], v[2])
    elseif tag == "cf" then
        return CFrame.new(table.unpack(v, 1, 12))
    elseif tag == "c3" then
        return Color3.new(v[1], v[2], v[3])
    elseif tag == "enum" then
        local e = nil
        pcall(function()
            local _, et, ei = tostring(v.v):match("^(Enum)%.([^%.]+)%.(.+)$")
            e = Enum[et][ei]
        end)
        return e
    elseif tag == "inst" then
        return resolvePath(v.path)
    elseif tag == "unit" then
        local r = refs[v.ref]
        if not r then
            missing.flag = true
            return nil
        end
        if v.kind == "inst" then
            return r.model
        elseif v.kind == "ret" then
            return r.ret
        elseif v.kind == "attr" then
            local a = nil
            pcall(function()
                a = r.model:GetAttribute(v.key)
            end)
            if a == nil then
                a = r.attrs and r.attrs[v.key]
            end
            return a
        end
        return nil
    end
    local out = {}
    for k, val in pairs(v) do
        out[k] = deserialize(val, refs, missing)
    end
    return out
end

local function deserializeArgs(sargs, refs)
    local missing = {flag = false}
    local n = sargs.n or #sargs
    local out = {n = n}
    for i = 1, n do
        out[i] = deserialize(sargs[i], refs, missing)
    end
    return out, missing.flag
end

local function modelAttrs(model)
    local attrs = {}
    pcall(function()
        for k, v in pairs(model:GetAttributes()) do
            if type(v) == "number" or type(v) == "string" then
                attrs[k] = v
            end
        end
    end)
    return attrs
end

local function firstScalar(res)
    if type(res) ~= "table" then
        return nil
    end
    for i = 1, (res.n or #res) do
        local v = res[i]
        if (type(v) == "number" and v ~= 0) or (type(v) == "string" and v ~= "") then
            return v
        end
        if type(v) == "table" then
            for _, key in ipairs({"Id", "ID", "id", "UnitId", "unitId", "UID", "uid", "Guid", "GUID"}) do
                if type(v[key]) == "number" or type(v[key]) == "string" then
                    return v[key]
                end
            end
        end
    end
    return nil
end

local function waitNewUnit(name, pos, before, timeout)
    local t0 = clockNow()
    while clockNow() - t0 < (timeout or 2) do
        for _, m in ipairs(unitModels(name)) do
            if not before[m] then
                local p = pivotOf(m)
                if p and pos and xz(p, pos) <= 4 then
                    return m
                end
            end
        end
        task.wait(0.05)
    end
    for _, m in ipairs(unitModels(name)) do
        if not before[m] then
            return m
        end
    end
    return nil
end

local function classify(name, args)
    local l = string.lower(tostring(name))
    for _, w in ipairs(IGNORE_WORDS) do
        if l:find(w, 1, true) then
            return "Ignore"
        end
    end
    if l:find("difficulty", 1, true) then
        return "Difficulty"
    end
    if l:find("skip", 1, true) and not l:find("auto", 1, true) then
        return "Skip"
    end
    if l:find("speed", 1, true) or l:find("tick", 1, true) then
        return "Speed"
    end
    if l:find("place", 1, true) and type(args[1]) == "string" and args[1]:sub(1, 5) == "unit_" then
        return "Place"
    end
    if l:find("upgradeall", 1, true) then
        return "UpgradeAll"
    end
    if l:find("sellall", 1, true) then
        return "SellAll"
    end
    if l:find("upgrade", 1, true) then
        return "Upgrade"
    end
    if l:find("sell", 1, true) or l:find("delete", 1, true) or l:find("remove", 1, true) then
        return "Sell"
    end
    if l:find("ability", 1, true) then
        return "Ability"
    end
    return "Remote"
end

local function round2(x)
    return math.floor((tonumber(x) or 0) * 100 + 0.5) / 100
end

local function processRemote(remote, method, args, res, pre)
    local name = tostring(remote.Name)
    local kind = classify(name, args)
    if kind == "Ignore" then
        return
    end
    local t = pre.t
    local sp = recorder.spam[name]
    if not sp or t - sp.t > 2 then
        sp = {t = t, n = 0}
        recorder.spam[name] = sp
    end
    sp.n = sp.n + 1
    if sp.n > 8 and kind == "Remote" then
        return
    end
    local wave = pre.wave
    if kind == "Difficulty" then
        recorder.difficulty = {
            Remote = name,
            Method = method,
            Args = serializeArgs(args, false),
            Delay = round2(pre.voteSince and (t - pre.voteSince) or 0),
        }
        recorder.status = "Recorded difficulty " .. tostring(args[1])
        return
    end
    if kind == "Skip" then
        if recorder.recSkip then
            recorder.skips[#recorder.skips + 1] = {
                Wave = wave,
                Delay = round2(pre.skipSince and (t - pre.skipSince) or 0),
                Remote = name,
                Method = method,
                Args = serializeArgs(args, false),
            }
            recorder.status = string.format("Wave %d | Skip after %.1fs", wave, pre.skipSince and (t - pre.skipSince) or 0)
        end
        return
    end
    if kind == "Speed" then
        if recorder.recSpeed then
            recorder.speeds[#recorder.speeds + 1] = {
                Wave = wave,
                Delay = round2(t - pre.waveStartAt),
                Remote = name,
                Method = method,
                Args = serializeArgs(args, false),
            }
            recorder.status = string.format("Wave %d | Speed %s", wave, tostring(args[1]))
        end
        return
    end
    local action = {
        Wave = wave,
        Type = kind,
        Remote = name,
        Method = method,
        Time = round2(t - recorder.startedAt),
    }
    local index = #recorder.actions + 1
    recorder.actions[index] = action
    recorder.pending = recorder.pending + 1
    task.spawn(function()
        pcall(function()
            if kind == "Place" then
                local unitName = args[1]
                local pos = nil
                if type(args[2]) == "table" then
                    pos = args[2].Position or (args[2].CF and args[2].CF.Position)
                end
                local model = waitNewUnit(unitName, pos, pre.before or {}, 2)
                if not model then
                    action.Failed = true
                else
                    local ref = #recorder.units + 1
                    recorder.units[ref] = {ref = ref, name = unitName, model = model, ret = firstScalar(res), attrs = modelAttrs(model)}
                    action.Ref = ref
                    action.Unit = unitName
                    if pos then
                        action.Pos = {round2(pos.X), round2(pos.Y), round2(pos.Z)}
                    end
                    action.Args = serializeArgs(args, false)
                end
            else
                action.Args = serializeArgs(args, true)
                for i = 1, (args.n or #args) do
                    local r = unitRefFor(args[i])
                    if r then
                        action.Ref = r.ref
                        break
                    end
                end
            end
            task.wait(0.5)
            local spent = (pre.cash or 0) - getCash()
            if spent > 0 and (kind == "Place" or kind == "Upgrade" or kind == "UpgradeAll" or kind == "Ability" or kind == "Remote") then
                action.Cost = math.floor(spent)
            else
                action.Cost = 0
            end
            if action.Ref and kind == "Sell" then
                local u = recorder.units[action.Ref]
                if u then
                    u.sold = true
                end
            end
        end)
        recorder.pending = recorder.pending - 1
        recorder.status = string.format("Wave %d | %s %s (%d actions)", wave, kind, action.Unit or "", #recorder.actions)
    end)
end

G.NxsMacroHandler = function(phase, self, method, args, res, pre)
    if phase == "pre" then
        local okR, isRemote = pcall(function()
            return self:IsA("RemoteFunction") or self:IsA("RemoteEvent")
        end)
        if not okR or not isRemote then
            return nil
        end
        local p = {t = clockNow(), wave = recorder.lastWave, cash = getCash(), skipSince = recorder.skipSince, voteSince = recorder.voteSince, waveStartAt = recorder.waveStartAt}
        if type(args[1]) == "string" and args[1]:sub(1, 5) == "unit_" then
            local before = {}
            for _, m in ipairs(unitModels(args[1])) do
                before[m] = true
            end
            p.before = before
        end
        return p
    end
    if phase == "post" and pre then
        task.spawn(processRemote, self, method, args, res, pre)
    end
    return nil
end

local hookReady = false
if G.NxsMacroHooked then
    hookReady = true
elseif hookmetamethod and getnamecallmethod then
    local okHook = pcall(function()
        local wrap = newcclosure or function(f)
            return f
        end
        local old
        old = hookmetamethod(game, "__namecall", wrap(function(self, ...)
            local method = getnamecallmethod()
            if (method == "InvokeServer" or method == "FireServer") and G.NxsMacroActive and not (checkcaller and checkcaller()) then
                local h = G.NxsMacroHandler
                if h then
                    local args = table.pack(...)
                    local okPre, pre = pcall(h, "pre", self, method, args)
                    if not okPre then
                        pre = nil
                    end
                    local res = table.pack(old(self, ...))
                    pcall(h, "post", self, method, args, res, pre)
                    return table.unpack(res, 1, res.n)
                end
            end
            return old(self, ...)
        end))
    end)
    if okHook then
        G.NxsMacroHooked = true
        hookReady = true
    end
end

task.spawn(function()
    local wasSkip, wasVote = false, false
    while true do
        if recorder.active then
            local now = clockNow()
            local w = getWave()
            if w ~= recorder.lastWave then
                recorder.lastWave = w
                recorder.waveStartAt = now
            end
            local s = isShown(PATH_SKIP)
            if s and not wasSkip then
                recorder.skipSince = now
            elseif not s then
                recorder.skipSince = nil
            end
            wasSkip = s
            local v = isShown(PATH_VOTE)
            if v and not wasVote then
                recorder.voteSince = now
            elseif not v then
                recorder.voteSince = nil
            end
            wasVote = v
        end
        task.wait(0.05)
    end
end)

local function ensureFolder()
    pcall(function()
        if makefolder and not (isfolder and isfolder(MACRO_FOLDER)) then
            makefolder(MACRO_FOLDER)
        end
    end)
end

local function readHistory()
    local list = {}
    pcall(function()
        if isfile and isfile(HISTORY_FILE) then
            local data = HttpService:JSONDecode(readfile(HISTORY_FILE))
            if type(data) == "table" then
                list = data
            end
        end
    end)
    return list
end

local function writeHistory(list)
    ensureFolder()
    pcall(function()
        writefile(HISTORY_FILE, HttpService:JSONEncode(list))
    end)
end

local function safeName(s)
    local n = tostring(s or ""):gsub("[^%w%-_ ]", ""):gsub("%s+", "_")
    if n == "" then
        n = "Macro"
    end
    return n:sub(1, 40)
end

local function timestamp()
    local ok, s = pcall(function()
        return os.date("%Y-%m-%d %H:%M:%S")
    end)
    if ok and type(s) == "string" then
        return s
    end
    return tostring(math.floor(os.time()))
end

local function buildConfig(name)
    local actions = {}
    for _, a in ipairs(recorder.actions) do
        if not a.Failed and a.Args then
            actions[#actions + 1] = a
        end
    end
    local refMap = {}
    for _, a in ipairs(actions) do
        if a.Type == "Place" and a.Ref then
            refMap[a.Ref] = true
        end
    end
    local waveTotal = nil
    pcall(function()
        local t = player.PlayerGui.GameGuiNoInset.Screen.Top.GameInfo.Content.Waves.Title.Text
        waveTotal = tonumber(tostring(t):match("%d+%s*/%s*(%d+)"))
    end)
    return {
        Name = name,
        Type = "NxsMacro",
        Version = 1,
        PlaceId = game.PlaceId,
        CreatedAt = timestamp(),
        WaveTotal = waveTotal,
        LastWave = recorder.lastWave,
        Units = #recorder.units,
        Difficulty = recorder.difficulty,
        Speed = recorder.speeds,
        Skips = recorder.skips,
        Actions = actions,
    }
end

local function configToText(cfg)
    return "return " .. writeLua(cfg, "") .. "\n"
end

local function loadConfigText(text)
    local ok, data = pcall(function()
        local fn = loadstring(text)
        return fn and fn()
    end)
    if ok and type(data) == "table" and data.Type == "NxsMacro" then
        return data
    end
    return nil
end

local function saveMacro(cfg)
    ensureFolder()
    local fileName = safeName(cfg.Name) .. ".lua"
    local path = MACRO_FOLDER .. "/" .. fileName
    local text = configToText(cfg)
    pcall(function()
        writefile(path, text)
    end)
    local list = readHistory()
    local kept = {}
    for _, e in ipairs(list) do
        if e.file ~= fileName then
            kept[#kept + 1] = e
        end
    end
    table.insert(kept, 1, {
        name = cfg.Name,
        file = fileName,
        created = cfg.CreatedAt,
        actions = #cfg.Actions,
        skips = #cfg.Skips,
        speeds = #cfg.Speed,
        lastWave = cfg.LastWave,
        place = cfg.PlaceId,
    })
    writeHistory(kept)
    return text, path
end

local function loadMacroFile(fileName)
    local text = nil
    pcall(function()
        text = readfile(MACRO_FOLDER .. "/" .. fileName)
    end)
    if not text then
        return nil, nil
    end
    return loadConfigText(text), text
end

local function historyNames()
    local names = {}
    for _, e in ipairs(readHistory()) do
        names[#names + 1] = tostring(e.file)
    end
    pcall(function()
        if listfiles then
            local seen = {}
            for _, n in ipairs(names) do
                seen[n] = true
            end
            for _, f in ipairs(listfiles(MACRO_FOLDER)) do
                local base = tostring(f):match("([^/\\]+%.lua)$")
                if base and not seen[base] then
                    names[#names + 1] = base
                end
            end
        end
    end)
    return names
end

local panelGui = nil
local function guiParent()
    local p = nil
    pcall(function()
        if gethui then
            p = gethui()
        end
    end)
    if not p then
        pcall(function()
            p = game:GetService("CoreGui")
        end)
    end
    return p or player.PlayerGui
end

local function showConfigPanel(title, text)
    pcall(function()
        if panelGui then
            panelGui:Destroy()
        end
    end)
    local sg = Instance.new("ScreenGui")
    sg.Name = "NxsMacroConfig"
    sg.ResetOnSpawn = false
    sg.DisplayOrder = 10001
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    sg.Parent = guiParent()
    panelGui = sg

    local frame = Instance.new("Frame")
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.Position = UDim2.new(0.5, 0, 0.5, 0)
    frame.Size = UDim2.new(0.72, 0, 0.78, 0)
    frame.BackgroundColor3 = Color3.fromRGB(18, 10, 36)
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Draggable = true
    frame.Parent = sg
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = frame
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(255, 255, 255)
    stroke.Transparency = 0.5
    stroke.Parent = frame
    local limit = Instance.new("UISizeConstraint")
    limit.MaxSize = Vector2.new(760, 520)
    limit.Parent = frame

    local head = Instance.new("TextLabel")
    head.BackgroundTransparency = 1
    head.Position = UDim2.new(0, 12, 0, 6)
    head.Size = UDim2.new(1, -24, 0, 26)
    head.Font = Enum.Font.GothamBold
    head.TextSize = 15
    head.TextColor3 = Color3.fromRGB(240, 232, 255)
    head.TextXAlignment = Enum.TextXAlignment.Left
    head.TextTruncate = Enum.TextTruncate.AtEnd
    head.Text = title
    head.Parent = frame

    local scroll = Instance.new("ScrollingFrame")
    scroll.Position = UDim2.new(0, 10, 0, 36)
    scroll.Size = UDim2.new(1, -20, 1, -86)
    scroll.BackgroundColor3 = Color3.fromRGB(8, 4, 18)
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 5
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.XY
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.Parent = frame
    local sc = Instance.new("UICorner")
    sc.CornerRadius = UDim.new(0, 8)
    sc.Parent = scroll

    local box = Instance.new("TextBox")
    box.BackgroundTransparency = 1
    box.Position = UDim2.new(0, 6, 0, 6)
    box.Size = UDim2.new(1, -12, 0, 0)
    box.AutomaticSize = Enum.AutomaticSize.XY
    box.ClearTextOnFocus = false
    box.MultiLine = true
    box.TextEditable = true
    box.Font = Enum.Font.Code
    box.TextSize = 13
    box.TextColor3 = Color3.fromRGB(225, 215, 255)
    box.TextXAlignment = Enum.TextXAlignment.Left
    box.TextYAlignment = Enum.TextYAlignment.Top
    box.Text = text
    box.Parent = scroll

    local function makeBtn(label, xScale, color, fn)
        local b = Instance.new("TextButton")
        b.AnchorPoint = Vector2.new(0, 1)
        b.Position = UDim2.new(xScale, 10, 1, -8)
        b.Size = UDim2.new(0.5, -15, 0, 36)
        b.BackgroundColor3 = color
        b.BorderSizePixel = 0
        b.Font = Enum.Font.GothamBold
        b.TextSize = 15
        b.TextColor3 = Color3.fromRGB(255, 255, 255)
        b.Text = label
        b.Parent = frame
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 8)
        c.Parent = b
        b.Activated:Connect(fn)
        return b
    end
    local copyBtn
    copyBtn = makeBtn("Copy", 0, Color3.fromRGB(124, 58, 237), function()
        local ok = pcall(function()
            if setclipboard then
                setclipboard(text)
            elseif toclipboard then
                toclipboard(text)
            else
                error("no clipboard")
            end
        end)
        copyBtn.Text = ok and "Copied!" or "Copy failed - select text manually"
        task.delay(1.5, function()
            pcall(function()
                copyBtn.Text = "Copy"
            end)
        end)
    end)
    makeBtn("Close", 0.5, Color3.fromRGB(70, 40, 110), function()
        pcall(function()
            sg:Destroy()
        end)
    end)
end

local function startRecording()
    if not hookReady then
        recorder.status = "Executor does not support hookmetamethod"
        return false
    end
    recorder.actions = {}
    recorder.skips = {}
    recorder.speeds = {}
    recorder.difficulty = nil
    recorder.units = {}
    recorder.pending = 0
    recorder.spam = {}
    recorder.startedAt = clockNow()
    recorder.lastWave = getWave()
    recorder.waveStartAt = clockNow()
    recorder.skipSince = isShown(PATH_SKIP) and clockNow() or nil
    recorder.voteSince = isShown(PATH_VOTE) and clockNow() or nil
    recorder.active = true
    G.NxsMacroActive = true
    recorder.status = "Recording..."
    return true
end

local macroNameInput = ""

local function stopRecording()
    if not recorder.active then
        return
    end
    recorder.active = false
    G.NxsMacroActive = false
    local t0 = clockNow()
    while recorder.pending > 0 and clockNow() - t0 < 3 do
        task.wait(0.1)
    end
    local name = macroNameInput ~= "" and macroNameInput or ("Macro " .. timestamp())
    local cfg = buildConfig(name)
    local text, path = saveMacro(cfg)
    recorder.status = string.format("Saved %s (%d actions, %d skips, %d speed)", path, #cfg.Actions, #cfg.Skips, #cfg.Speed)
    showConfigPanel(name .. "  |  " .. path, text)
end

local playback = {
    playing = false,
    autoReplay = true,
    skipAll = false,
    status = "Idle",
    file = nil,
    runId = 0,
}

local lastRestart = 0
local function restartGame()
    if clockNow() - lastRestart < 8 then
        return
    end
    lastRestart = clockNow()
    fireRemote("RestartGame", "InvokeServer", {n = 0}, 5)
end

local function playOnce(cfg, runId)
    local function alive()
        return playback.playing and playback.runId == runId
    end
    local refs = {}
    local gameOver = false
    playback.status = "Waiting game start"

    local t0 = clockNow()
    local voteSince = nil
    while alive() and clockNow() - t0 < 15 do
        if gameEndShown() then
            return "ended"
        end
        if isShown(PATH_VOTE) then
            voteSince = voteSince or clockNow()
            local d = cfg.Difficulty
            if d then
                if clockNow() - voteSince >= (tonumber(d.Delay) or 0) then
                    playback.status = "Vote difficulty"
                    local args = deserializeArgs(d.Args or {n = 0}, refs)
                    fireRemote(d.Remote, d.Method, args, 5)
                    task.wait(0.5)
                end
            end
        elseif voteSince or getWave() >= 1 then
            break
        end
        task.wait(0.1)
    end
    if not alive() then
        return "stopped"
    end

    local waveStart = {}
    local curWave = getWave()
    waveStart[curWave] = clockNow()

    task.spawn(function()
        while alive() and not gameOver do
            local w = getWave()
            if w ~= curWave then
                curWave = w
                waveStart[w] = clockNow()
            end
            if gameEndShown() then
                gameOver = true
            end
            task.wait(0.1)
        end
    end)

    task.spawn(function()
        for _, sp in ipairs(cfg.Speed or {}) do
            while alive() and not gameOver and curWave < (tonumber(sp.Wave) or 0) do
                task.wait(0.2)
            end
            if not alive() or gameOver then
                return
            end
            local base = waveStart[curWave] or clockNow()
            while alive() and not gameOver and clockNow() - base < (tonumber(sp.Delay) or 0) do
                task.wait(0.1)
            end
            if alive() and not gameOver then
                fireRemote(sp.Remote, sp.Method, deserializeArgs(sp.Args or {n = 0}, refs), 5)
            end
        end
    end)

    task.spawn(function()
        local byWave = {}
        for _, sk in ipairs(cfg.Skips or {}) do
            local w = tonumber(sk.Wave) or 0
            byWave[w] = byWave[w] or {}
            table.insert(byWave[w], sk)
        end
        local defaultSkip = (cfg.Skips or {})[1]
        local doneWave = {}
        local was = false
        local since = nil
        while alive() and not gameOver do
            local s = isShown(PATH_SKIP)
            if s and not was then
                since = clockNow()
            end
            was = s
            if s and since and not doneWave[curWave] then
                local list = byWave[curWave]
                if playback.skipAll and not list then
                    list = {{Delay = 0, Remote = defaultSkip and defaultSkip.Remote or "SkipWave", Method = defaultSkip and defaultSkip.Method or "InvokeServer", Args = defaultSkip and defaultSkip.Args or {"y", n = 1}}}
                end
                if list then
                    doneWave[curWave] = true
                    local w = curWave
                    task.spawn(function()
                        for _, sk in ipairs(list) do
                            while alive() and not gameOver and clockNow() - since < (tonumber(sk.Delay) or 0) do
                                task.wait(0.05)
                            end
                            if alive() and not gameOver and isShown(PATH_SKIP) and curWave == w then
                                fireRemote(sk.Remote, sk.Method, deserializeArgs(sk.Args or {n = 0}, refs), 5)
                            end
                        end
                    end)
                end
            end
            task.wait(0.05)
        end
    end)

    local total = #(cfg.Actions or {})
    for i, a in ipairs(cfg.Actions or {}) do
        if not alive() or gameOver then
            break
        end
        local needWave = tonumber(a.Wave) or 0
        while alive() and not gameOver and curWave < needWave do
            playback.status = string.format("Wave %d | Waiting wave %d for %s %s (%d/%d)", curWave, needWave, a.Type, a.Unit or "", i, total)
            task.wait(0.2)
        end
        local cost = tonumber(a.Cost) or 0
        while alive() and not gameOver and cost > 0 and getCash() < cost do
            playback.status = string.format("Wave %d | Waiting cash %d/%d for %s %s (%d/%d)", curWave, math.floor(getCash()), cost, a.Type, a.Unit or "", i, total)
            task.wait(0.2)
        end
        if not alive() or gameOver then
            break
        end
        playback.status = string.format("Wave %d | %s %s (%d/%d)", curWave, a.Type, a.Unit or "", i, total)
        if a.Type == "Place" then
            local pos = a.Pos and Vector3.new(a.Pos[1], a.Pos[2], a.Pos[3]) or nil
            for attempt = 1, 30 do
                if not alive() or gameOver then
                    break
                end
                local args = deserializeArgs(a.Args or {n = 0}, refs)
                local before = {}
                for _, m in ipairs(unitModels(a.Unit)) do
                    before[m] = true
                end
                local ok, res = fireRemote(a.Remote, a.Method, args, 6)
                local model = waitNewUnit(a.Unit, pos, before, 1.5)
                if model then
                    refs[a.Ref or (#refs + 1)] = {model = model, ret = firstScalar(ok and res or nil), attrs = modelAttrs(model)}
                    break
                end
                playback.status = string.format("Wave %d | Retry %s %d (%d/%d)", curWave, a.Unit or "", attempt, i, total)
                task.wait(0.5)
                while alive() and not gameOver and cost > 0 and getCash() < cost do
                    task.wait(0.2)
                end
            end
        else
            local args, missing = deserializeArgs(a.Args or {n = 0}, refs)
            if not missing then
                fireRemote(a.Remote, a.Method, args, 6)
            end
        end
        task.wait(0.15)
    end

    while alive() and not gameOver do
        playback.status = string.format("Wave %d | Macro done, waiting game end", curWave)
        task.wait(0.5)
    end
    if gameOver then
        return "ended"
    end
    return "stopped"
end

local function startPlayback()
    if playback.playing then
        return
    end
    if not playback.file then
        playback.status = "Select a macro first"
        return
    end
    local cfg = loadMacroFile(playback.file)
    if not cfg then
        playback.status = "Cannot load " .. tostring(playback.file)
        return
    end
    playback.playing = true
    playback.runId = playback.runId + 1
    local runId = playback.runId
    task.spawn(function()
        while playback.playing and playback.runId == runId do
            local okRun, result = pcall(playOnce, cfg, runId)
            if not okRun then
                playback.status = "Error: " .. tostring(result)
                task.wait(1)
            end
            if not (playback.playing and playback.runId == runId) then
                break
            end
            if result == "ended" then
                if playback.autoReplay then
                    playback.status = "Game end | Restart"
                    restartGame()
                    local w = 0
                    while gameEndShown() and w < 15 do
                        task.wait(0.2)
                        w = w + 0.5
                    end
                else
                    playback.playing = false
                    playback.status = "Game ended"
                    break
                end
            end
            task.wait(0.3)
        end
    end)
end

local function stopPlayback()
    playback.playing = false
    playback.runId = playback.runId + 1
    playback.status = "Stopped"
end

local Window = redzlib:MakeWindow({
    Title = "Nexus Stella Macro",
    SubTitle = "By nhat0258",
    SaveFolder = "NxsMacro_UI.json"
})

local TabMacro = Window:MakeTab({"Macro", "play"})
local TabHistory = Window:MakeTab({"History", "list"})

TabMacro:AddSection({"Record"})

TabMacro:AddTextBox({
    Name = "Macro Name",
    Description = "File name when saving",
    PlaceholderText = "Enchanted L5",
    Callback = function(Value)
        macroNameInput = tostring(Value or "")
    end
})

TabMacro:AddToggle({
    Name = "Record Speed (x2/x3)",
    Default = true,
    Flag = "NxsRecSpeed",
    Callback = function(Value)
        recorder.recSpeed = Value == true
    end
})

TabMacro:AddToggle({
    Name = "Record Skip Wave",
    Description = "Saves the delay after the Skip button appears",
    Default = true,
    Flag = "NxsRecSkip",
    Callback = function(Value)
        recorder.recSkip = Value == true
    end
})

local recordToggle = nil
recordToggle = TabMacro:AddToggle({
    Name = "Record Macro",
    Description = "Turn off to stop and save",
    Default = false,
    Callback = function(Value)
        if Value then
            if not startRecording() then
                task.defer(function()
                    pcall(function()
                        recordToggle:Set(false)
                    end)
                end)
            end
        else
            task.spawn(stopRecording)
        end
    end
})

local recordParagraph = TabMacro:AddParagraph({"Record Status", hookReady and "Idle" or "Executor does not support hookmetamethod"})

TabMacro:AddSection({"Play"})

local playDropdown = TabMacro:AddDropdown({
    Name = "Macro File",
    Options = historyNames(),
    Default = "",
    Callback = function(Value)
        if type(Value) == "string" and Value ~= "" then
            playback.file = Value
        end
    end
})

TabMacro:AddToggle({
    Name = "Auto Replay",
    Default = true,
    Flag = "NxsAutoReplay",
    Callback = function(Value)
        playback.autoReplay = Value == true
    end
})

TabMacro:AddToggle({
    Name = "Skip Every Wave",
    Description = "Also skip waves that were not recorded",
    Default = false,
    Flag = "NxsSkipAll",
    Callback = function(Value)
        playback.skipAll = Value == true
    end
})

TabMacro:AddToggle({
    Name = "Play Macro",
    Default = false,
    Callback = function(Value)
        if Value then
            startPlayback()
        else
            stopPlayback()
        end
    end
})

local playParagraph = TabMacro:AddParagraph({"Play Status", "Idle"})

local historySelected = nil
local historyParagraph = nil

local function historySummary(fileName)
    for _, e in ipairs(readHistory()) do
        if e.file == fileName then
            return string.format("%s\nCreated: %s\nActions: %s | Skips: %s | Speed: %s\nLast wave: %s | Place: %s", tostring(e.name), tostring(e.created), tostring(e.actions), tostring(e.skips), tostring(e.speeds), tostring(e.lastWave), tostring(e.place))
        end
    end
    local cfg = loadMacroFile(fileName)
    if cfg then
        return string.format("%s\nCreated: %s\nActions: %d | Skips: %d | Speed: %d", tostring(cfg.Name), tostring(cfg.CreatedAt), #(cfg.Actions or {}), #(cfg.Skips or {}), #(cfg.Speed or {}))
    end
    return "N/A"
end

local historyDropdown = TabHistory:AddDropdown({
    Name = "Saved Macros",
    Options = historyNames(),
    Default = "",
    Callback = function(Value)
        if type(Value) == "string" and Value ~= "" then
            historySelected = Value
            if historyParagraph then
                pcall(function()
                    historyParagraph:SetDesc(historySummary(Value))
                end)
            end
        end
    end
})

historyParagraph = TabHistory:AddParagraph({"Macro Info", "Select a macro"})

TabHistory:AddButton({
    Name = "View Config",
    Callback = function()
        if not historySelected then
            return
        end
        local _, text = loadMacroFile(historySelected)
        if text then
            showConfigPanel(historySelected, text)
        end
    end
})

TabHistory:AddButton({
    Name = "Use For Play",
    Callback = function()
        if historySelected then
            playback.file = historySelected
            playback.status = "Selected " .. historySelected
        end
    end
})

local function refreshLists()
    local names = historyNames()
    pcall(function()
        playDropdown:Set(names)
    end)
    pcall(function()
        historyDropdown:Set(names)
    end)
end

TabHistory:AddButton({
    Name = "Delete Macro",
    Callback = function()
        if not historySelected then
            return
        end
        pcall(function()
            if delfile then
                delfile(MACRO_FOLDER .. "/" .. historySelected)
            end
        end)
        local kept = {}
        for _, e in ipairs(readHistory()) do
            if e.file ~= historySelected then
                kept[#kept + 1] = e
            end
        end
        writeHistory(kept)
        historySelected = nil
        pcall(function()
            historyParagraph:SetDesc("Deleted")
        end)
        refreshLists()
    end
})

TabHistory:AddButton({
    Name = "Refresh",
    Callback = refreshLists
})

local lastCount = #historyNames()
task.spawn(function()
    while true do
        pcall(function()
            recordParagraph:SetDesc(recorder.active and string.format("%s\nWave %d | Actions %d | Skips %d | Speed %d", recorder.status, recorder.lastWave, #recorder.actions, #recorder.skips, #recorder.speeds) or recorder.status)
            playParagraph:SetDesc(playback.status)
        end)
        local n = #historyNames()
        if n ~= lastCount then
            lastCount = n
            refreshLists()
        end
        task.wait(0.5)
    end
end)
