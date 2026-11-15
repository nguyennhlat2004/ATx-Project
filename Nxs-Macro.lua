local redzlib = loadstring(game:HttpGet("https://raw.githubusercontent.com/nhat0258/Redz-UI-Library/refs/heads/main/Main.lua"))()

local HttpService = game:GetService("HttpService")
pcall(function()
    math.randomseed(math.floor((tick() % 1000000) * 1000) + math.floor(os.clock() * 1000))
end)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local G = (getgenv and getgenv()) or _G

G.NxsMacroActive = false
local MACRO_FOLDER = "NxsMacro"
local HISTORY_FILE = MACRO_FOLDER .. "/history.json"

local function clockNow()
    local ok, t = pcall(function()
        return tick()
    end)
    if ok and type(t) == "number" then
        return t
    end
    return os.clock()
end

local ctxState = {last = nil, hooked = false, gui = {}, scanAt = {}}

local function currentContext()
    local best = nil
    pcall(function()
        local ctx = workspace:FindFirstChild("Contexts")
        if not ctx then
            return
        end
        if not ctxState.hooked then
            ctxState.hooked = true
            pcall(function()
                ctx.ChildAdded:Connect(function(c)
                    ctxState.last = c
                end)
            end)
        end
        local lc = ctxState.last
        if lc and lc.Parent == ctx then
            best = lc
            return
        end
        local kids = ctx:GetChildren()
        for i = #kids, 1, -1 do
            if kids[i]:FindFirstChild("Entities") then
                best = kids[i]
                return
            end
        end
        best = kids[#kids]
    end)
    return best
end

local function contextMode()
    local yes = false
    pcall(function()
        local cur = currentContext()
        yes = cur ~= nil and cur:FindFirstChild("Entities") ~= nil
    end)
    return yes
end

local function hasObjects(folder)
    local found = false
    pcall(function()
        for _, k in ipairs(folder:GetChildren()) do
            local nm = tostring(k.Name)
            if nm:sub(1, 5) == "unit_" or nm:sub(1, 6) == "enemy_" then
                found = true
                return
            end
        end
    end)
    return found
end

local function isShown(path)
    local shown = false
    local exists = true
    pcall(function()
        local cur = player.PlayerGui
        for part in path:gmatch("[^.]+") do
            cur = cur:FindFirstChild(part)
            if not cur then
                exists = false
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
    if exists or not contextMode() then
        return shown
    end
    local name = path:match("([^.]+)$") or path
    pcall(function()
        local pg = player.PlayerGui
        local obj = ctxState.gui[name]
        if obj and not obj:IsDescendantOf(pg) then
            obj = nil
            ctxState.gui[name] = nil
        end
        if not obj and os.clock() - (ctxState.scanAt[name] or -100) >= 1 then
            ctxState.scanAt[name] = os.clock()
            for _, d in ipairs(pg:GetDescendants()) do
                if d.Name == name and (d:IsA("GuiObject") or d:IsA("LayerCollector")) then
                    obj = d
                    break
                end
            end
            ctxState.gui[name] = obj
        end
        if not obj then
            return
        end
        local cur = obj
        while cur and cur ~= pg do
            if cur:IsA("LayerCollector") then
                if cur.Enabled == false then
                    return
                end
            elseif cur:IsA("GuiObject") then
                if cur.Visible ~= true then
                    return
                end
            end
            cur = cur.Parent
        end
        shown = cur == pg
    end)
    return shown
end

local PATH_GAMEEND = "GameGui.Screen.Middle.GameEnd"
local PATH_VOTE = "GameGui.Screen.Middle.DifficultyVote"
local PATH_SKIP = "GameGuiNoInset.Screen.Top.SkipWave"

local lastWaveRead = 0
local function autoSkipColorState()
    local state = nil
    pcall(function()
        local c = player.PlayerGui.GameGuiNoInset.Screen.Top.WaveControls.WaveControls.AutoSkip.UIGradient.Color.Keypoints[1].Value
        if c.G > 0.8 and c.R < 0.6 then
            state = true
        elseif c.R > 0.9 and c.G > 0.5 and c.G < 0.8 and c.B < 0.25 then
            state = false
        end
    end)
    return state
end

local lastMaxRead = 0
local function getWaveInfo()
    local w, mx = nil, nil
    for _, getter in ipairs({
        function()
            return player.PlayerGui.GameGuiNoInset.Screen.Top.GameInfo.Content.Waves.Title.Text
        end,
        function()
            return player.PlayerGui.GameGui.Screen.Top.GameInfo.Content.Waves.Title.Text
        end,
    }) do
        local ok, t = pcall(getter)
        if ok and t then
            local a, b = tostring(t):match("(%d+)%s*/%s*(%d+)")
            if a then
                w, mx = tonumber(a), tonumber(b)
                break
            end
            local c = tostring(t):match("[Ww]ave%s*(%d+)")
            if c then
                w = tonumber(c)
                break
            end
        end
    end
    if w and w > 0 then
        lastWaveRead = w
    end
    if mx and mx > 0 then
        lastMaxRead = mx
    end
    return lastWaveRead, lastMaxRead
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
    local mapE = nil
    pcall(function()
        mapE = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Entities")
    end)
    if mapE and hasObjects(mapE) then
        return mapE
    end
    local ce = nil
    pcall(function()
        local cur = currentContext()
        ce = cur and cur:FindFirstChild("Entities")
    end)
    if ce and (not mapE or hasObjects(ce)) then
        return ce
    end
    if mapE then
        return mapE
    end
    local f = nil
    pcall(function()
        f = workspace:FindFirstChild("Entities")
    end)
    return f
end

local function enemyCount()
    local n = 0
    local folder = entitiesFolder()
    if not folder then
        return 0
    end
    pcall(function()
        for _, c in ipairs(folder:GetChildren()) do
            if tostring(c.Name):sub(1, 6) == "enemy_" then
                n = n + 1
            end
        end
    end)
    return n
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
        return string.format("%.0f", n)
    end
    local s = string.format("%.3f", n)
    s = s:gsub("0+$", ""):gsub("%.$", "")
    return s
end

local function isIdent(k)
    return type(k) == "string" and k:match("^[%a_][%w_]*$") ~= nil
end

local function writeLuaInline(v)
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
    local parts = {}
    local arrLen = #v
    for i = 1, arrLen do
        parts[#parts + 1] = writeLuaInline(v[i])
    end
    local keys = {}
    for k in pairs(v) do
        if not (type(k) == "number" and k >= 1 and k <= arrLen and k == math.floor(k)) then
            keys[#keys + 1] = k
        end
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)
    for _, k in ipairs(keys) do
        local ks = isIdent(k) and k or ("[" .. (type(k) == "number" and fmtNumber(k) or string.format("%q", tostring(k))) .. "]")
        parts[#parts + 1] = ks .. " = " .. writeLuaInline(v[k])
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

local function writeLua(v, indent)
    indent = indent or ""
    if type(v) ~= "table" then
        return writeLuaInline(v)
    end
    local inline = writeLuaInline(v)
    if #inline <= 200 then
        return inline
    end
    local inner = indent .. "    "
    local parts = {}
    local arrLen = #v
    for i = 1, arrLen do
        parts[#parts + 1] = writeLua(v[i], inner)
    end
    local keys = {}
    for k in pairs(v) do
        if not (type(k) == "number" and k >= 1 and k <= arrLen and k == math.floor(k)) then
            keys[#keys + 1] = k
        end
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)
    for _, k in ipairs(keys) do
        local ks = isIdent(k) and k or ("[" .. (type(k) == "number" and fmtNumber(k) or string.format("%q", tostring(k))) .. "]")
        parts[#parts + 1] = ks .. " = " .. writeLua(v[k], inner)
    end
    return "{\n" .. inner .. table.concat(parts, ",\n" .. inner) .. ",\n" .. indent .. "}"
end

local recorder = {
    active = false,
    events = {},
    skips = {},
    skipRemote = nil,
    difficulty = nil,
    place = nil,
    remotes = {},
    units = {},
    pending = 0,
    startedAt = 0,
    waveStartAt = 0,
    lastWave = 0,
    maxWave = 0,
    skipSince = nil,
    voteSince = nil,
    claimed = {},
    finalSeen = false,
    zeroSince = nil,
    status = "Chưa ghi",
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
        local isCtx = false
        pcall(function()
            isCtx = v.Parent ~= nil and v.Parent.Name == "Contexts" and v.Parent.Parent == workspace
        end)
        if isCtx then
            return {__t = "ctx"}
        end
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
    elseif tag == "ctx" then
        return currentContext()
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

local function waitNewUnit(name, pos, before, timeout, claimed)
    claimed = claimed or {}
    local t0 = clockNow()
    while clockNow() - t0 < (timeout or 1.2) do
        local best, bestD = nil, math.huge
        for _, m in ipairs(unitModels(name)) do
            if not before[m] and not claimed[m] then
                local p = pivotOf(m)
                if p and pos then
                    local d = xz(p, pos)
                    if d <= 2 and d < bestD then
                        best, bestD = m, d
                    end
                elseif not pos then
                    best = m
                end
            end
        end
        if best then
            claimed[best] = true
            return best
        end
        task.wait(0.05)
    end
    return nil
end

local function remoteRejected(res)
    return type(res) == "table" and (res.n or #res) >= 1 and res[1] == false
end

local function classify(name, args)
    local l = string.lower(tostring(name))
    if l:find("difficulty", 1, true) then
        return "Difficulty"
    end
    if l:find("skip", 1, true) then
        if l:find("auto", 1, true) then
            return nil
        end
        return "Skip"
    end
    if l:find("upgradeall", 1, true) then
        return "UpgradeAll"
    end
    if l:find("place", 1, true) then
        for i = 1, (args.n or #args) do
            if type(args[i]) == "string" and args[i]:sub(1, 5) == "unit_" then
                return "Place"
            end
        end
        return nil
    end
    if l:find("ability", 1, true) then
        return "Ability"
    end
    return nil
end

local TYPE_VI = {Place = "Đặt", UpgradeAll = "Nâng cấp tất cả", Ability = "Kỹ năng"}

local function round2(x)
    return math.floor((tonumber(x) or 0) * 100 + 0.5) / 100
end

local function placeArgInfo(args)
    local uIdx, dIdx = nil, nil
    for i = 1, (args.n or #args) do
        if not uIdx and type(args[i]) == "string" and args[i]:sub(1, 5) == "unit_" then
            uIdx = i
        elseif not dIdx and type(args[i]) == "table" then
            dIdx = i
        end
    end
    return uIdx, dIdx
end

local function processRemote(remote, method, args, res, pre)
    local name = tostring(remote.Name)
    local kind = classify(name, args)
    if not kind then
        return
    end
    local t = pre.t
    local wave = pre.wave
    if kind == "Difficulty" then
        if remoteRejected(res) then
            return
        end
        recorder.difficulty = {
            Remote = name,
            Method = method,
            Args = serializeArgs(args, false),
            Delay = round2(pre.voteSince and (t - pre.voteSince) or 0),
        }
        recorder.status = "Đã ghi vote độ khó"
        return
    end
    if kind == "Skip" then
        if recorder.skips[wave] == nil then
            recorder.skips[wave] = round2(pre.skipSince and (t - pre.skipSince) or 0)
            recorder.skipRemote = recorder.skipRemote or {Remote = name, Method = method, Args = serializeArgs(args, false)}
            recorder.status = string.format("Wave %d | Skip sau %.1f giây", wave, recorder.skips[wave])
        end
        return
    end
    local ev = {Wave = wave, Delay = round2(t - (pre.waveStartAt or t)), Type = kind}
    recorder.events[#recorder.events + 1] = ev
    recorder.pending = recorder.pending + 1
    task.spawn(function()
        pcall(function()
            if kind == "Place" then
                local uIdx, dIdx = placeArgInfo(args)
                local unitName = uIdx and args[uIdx] or nil
                local data = dIdx and args[dIdx] or nil
                local pos = nil
                if type(data) == "table" then
                    pos = data.Position or (data.CF and data.CF.Position)
                end
                local model = nil
                if unitName and not remoteRejected(res) then
                    model = waitNewUnit(unitName, pos, pre.before or {}, 1.5, recorder.claimed)
                end
                if not model then
                    ev.Failed = true
                else
                    local ref = #recorder.units + 1
                    recorder.units[ref] = {ref = ref, name = unitName, model = model, ret = firstScalar(res), attrs = modelAttrs(model)}
                    ev.Ref = ref
                    ev.Unit = unitName
                    local mp = pos or pivotOf(model)
                    if mp then
                        ev.Pos = {round2(mp.X), round2(mp.Y), round2(mp.Z)}
                    end
                    if not recorder.place and type(data) == "table" then
                        local tpl = {}
                        for k, v in pairs(data) do
                            if k ~= "Position" and k ~= "CF" and k ~= "Attempt" and type(v) ~= "table" and typeof(v) ~= "Vector3" and typeof(v) ~= "CFrame" then
                                tpl[k] = v
                            end
                        end
                        local rot = nil
                        if typeof(data.CF) == "CFrame" then
                            local c = {data.CF:GetComponents()}
                            rot = {}
                            for i = 4, 12 do
                                rot[#rot + 1] = math.floor((tonumber(c[i]) or 0) * 10000 + 0.5) / 10000
                            end
                        end
                        local sargs = serializeArgs(args, false)
                        sargs[uIdx] = "unit"
                        sargs[dIdx] = {__t = "nil"}
                        recorder.place = {Remote = name, Method = method, Args = sargs, UnitIndex = uIdx, DataIndex = dIdx, Template = tpl, Rot = rot}
                    end
                end
            elseif kind == "UpgradeAll" then
                if remoteRejected(res) then
                    ev.Failed = true
                end
                recorder.remotes.UpgradeAll = recorder.remotes.UpgradeAll or {Remote = name, Method = method, Args = serializeArgs(args, false)}
            elseif kind == "Ability" then
                if remoteRejected(res) then
                    ev.Failed = true
                end
                ev.Remote = name
                ev.Method = method
                ev.Args = serializeArgs(args, true)
                for i = 1, (args.n or #args) do
                    local r = unitRefFor(args[i])
                    if r then
                        ev.Ref = r.ref
                        break
                    end
                end
            end
            local spent = (pre.cash or 0) - (pre.cashAfter or pre.cash or 0)
            if spent <= 0 and kind ~= "Ability" then
                local minCash = getCash()
                local tc = clockNow()
                while clockNow() - tc < 0.4 do
                    local c = getCash()
                    if c < minCash then
                        minCash = c
                    end
                    task.wait(0.05)
                end
                spent = (pre.cash or 0) - minCash
            end
            ev.Cost = spent > 0 and math.floor(spent) or 0
        end)
        recorder.pending = recorder.pending - 1
        recorder.status = string.format("Wave %d | %s %s", wave, TYPE_VI[kind] or kind, ev.Unit or "")
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

G.NxsNC = G.NxsNC or setmetatable({}, {__mode = "k"})
local hookWrap = newcclosure or function(f)
    return f
end

local function recordCall(old, self, method, ...)
    local h = G.NxsMacroHandler
    if not h then
        return old(self, ...)
    end
    local args = table.pack(...)
    local okPre, pre = pcall(h, "pre", self, method, args)
    if not okPre then
        pre = nil
    end
    local res = table.pack(old(self, ...))
    if type(pre) == "table" then
        pcall(function()
            pre.cashAfter = getCash()
        end)
    end
    pcall(h, "post", self, method, args, res, pre)
    return table.unpack(res, 1, res.n)
end

if not G.NxsMacroHooked and hookmetamethod and getnamecallmethod then
    local okHook = pcall(function()
        local old
        old = hookmetamethod(game, "__namecall", hookWrap(function(self, ...)
            local method = getnamecallmethod()
            if (method == "InvokeServer" or method == "FireServer") and G.NxsMacroActive and not (checkcaller and checkcaller()) then
                local th = coroutine.running()
                G.NxsNC[th] = (G.NxsNC[th] or 0) + 1
                local res = table.pack(pcall(recordCall, old, self, method, ...))
                G.NxsNC[th] = (G.NxsNC[th] or 1) - 1
                if res[1] then
                    return table.unpack(res, 2, res.n)
                end
                error(res[2], 0)
            end
            return old(self, ...)
        end))
    end)
    if okHook then
        G.NxsMacroHooked = true
    end
end

if not G.NxsMacroFnHooked and hookfunction then
    local okFn = pcall(function()
        local rf = Instance.new("RemoteFunction")
        local re = Instance.new("RemoteEvent")
        local function install(fn, method)
            local old
            old = hookfunction(fn, hookWrap(function(self, ...)
                if G.NxsMacroActive and not (checkcaller and checkcaller()) and (G.NxsNC[coroutine.running()] or 0) <= 0 then
                    return recordCall(old, self, method, ...)
                end
                return old(self, ...)
            end))
        end
        install(rf.InvokeServer, "InvokeServer")
        install(re.FireServer, "FireServer")
        pcall(function()
            rf:Destroy()
            re:Destroy()
        end)
    end)
    if okFn then
        G.NxsMacroFnHooked = true
    end
end

local hookReady = G.NxsMacroHooked == true or G.NxsMacroFnHooked == true
local hookInfo = (G.NxsMacroHooked and "namecall" or "") .. ((G.NxsMacroHooked and G.NxsMacroFnHooked) and " + " or "") .. (G.NxsMacroFnHooked and "function" or "")

local autoStop = {fn = nil}

task.spawn(function()
    local wasSkip, wasVote = false, false
    while true do
        if recorder.active then
            local now = clockNow()
            local w, mx = getWaveInfo()
            if mx and mx > 0 then
                recorder.maxWave = mx
            end
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
            local stopNow = false
            if mx and mx > 0 and w >= mx then
                if enemyCount() > 0 then
                    recorder.finalSeen = true
                    recorder.zeroSince = nil
                elseif recorder.finalSeen then
                    recorder.zeroSince = recorder.zeroSince or now
                    if now - recorder.zeroSince >= 3 then
                        stopNow = true
                    end
                end
            end
            if isShown(PATH_GAMEEND) and now - recorder.startedAt > 5 then
                stopNow = true
            end
            if stopNow and autoStop.fn then
                pcall(autoStop.fn)
            end
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

local function median(list)
    if not list or #list == 0 then
        return nil
    end
    table.sort(list)
    return list[math.ceil(#list / 2)]
end

local function compileConfig(name)
    local events, priceList = {}, {}
    local unitCount = 0
    for _, ev in ipairs(recorder.events) do
        if not ev.Failed then
            if ev.Type == "Place" and ev.Ref and ev.Pos then
                events[#events + 1] = {Wave = ev.Wave, Delay = ev.Delay, Type = "Place", Ref = ev.Ref, Unit = ev.Unit, Pos = ev.Pos, Cost = ev.Cost}
                unitCount = unitCount + 1
                if (ev.Cost or 0) > 0 then
                    priceList[ev.Unit] = priceList[ev.Unit] or {}
                    table.insert(priceList[ev.Unit], ev.Cost)
                end
            elseif ev.Type == "UpgradeAll" then
                events[#events + 1] = {Wave = ev.Wave, Delay = ev.Delay, Type = "UpgradeAll", Cost = ev.Cost}
            elseif ev.Type == "Ability" and ev.Args then
                events[#events + 1] = {Wave = ev.Wave, Delay = ev.Delay, Type = "Ability", Ref = ev.Ref, Remote = ev.Remote, Method = ev.Method, Args = ev.Args}
            end
        end
    end
    local price = {}
    for n, list in pairs(priceList) do
        price[n] = median(list)
    end
    local skips = {}
    for w, d in pairs(recorder.skips) do
        skips[#skips + 1] = {Wave = w, Delay = d}
    end
    table.sort(skips, function(a, b)
        return a.Wave < b.Wave
    end)
    return {
        Name = name,
        Type = "NxsMacro",
        Version = 3,
        PlaceId = game.PlaceId,
        CreatedAt = timestamp(),
        LastWave = recorder.lastWave,
        MaxWave = recorder.maxWave,
        UnitCount = unitCount,
        Difficulty = recorder.difficulty,
        SkipRemote = recorder.skipRemote,
        Skips = skips,
        Place = recorder.place,
        Remotes = recorder.remotes,
        Price = price,
        Events = events,
    }
end

local function configToText(cfg)
    local out = {"return {"}
    local function line(indent, text)
        out[#out + 1] = string.rep("    ", indent) .. text
    end
    for _, k in ipairs({"Name", "Type", "Version", "PlaceId", "CreatedAt", "LastWave", "MaxWave", "UnitCount", "Difficulty", "SkipRemote", "Place", "Remotes", "Price"}) do
        if cfg[k] ~= nil then
            line(1, k .. " = " .. writeLuaInline(cfg[k]) .. ",")
        end
    end
    line(1, "Skips = {")
    for _, sk in ipairs(cfg.Skips or {}) do
        line(2, writeLuaInline(sk) .. ",")
    end
    line(1, "},")
    line(1, "Events = {")
    for _, ev in ipairs(cfg.Events or {}) do
        line(2, writeLuaInline(ev) .. ",")
    end
    line(1, "},")
    out[#out + 1] = "}"
    return table.concat(out, "\n") .. "\n"
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
        units = cfg.UnitCount,
        events = #(cfg.Events or {}),
        skips = #(cfg.Skips or {}),
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

local function copyText(text)
    local ok = pcall(function()
        if setclipboard then
            setclipboard(text)
        elseif toclipboard then
            toclipboard(text)
        elseif Clipboard and Clipboard.set then
            Clipboard.set(text)
        else
            error("no clipboard")
        end
    end)
    return ok
end

local function splitChunks(text, maxLines, maxChars)
    local chunks = {}
    local cur, lines, chars = {}, 0, 0
    for line in (tostring(text) .. "\n"):gmatch("(.-)\n") do
        if #line > maxChars then
            line = line:sub(1, maxChars) .. " ..."
        end
        if lines >= maxLines or chars + #line > maxChars then
            chunks[#chunks + 1] = table.concat(cur, "\n")
            cur, lines, chars = {}, 0, 0
        end
        cur[#cur + 1] = line
        lines = lines + 1
        chars = chars + #line + 1
    end
    if #cur > 0 then
        chunks[#chunks + 1] = table.concat(cur, "\n")
    end
    return chunks
end

local function showConfigPanel(title, text, summary)
    pcall(function()
        if panelGui then
            panelGui:Destroy()
        end
    end)
    local sg = Instance.new("ScreenGui")
    sg.Name = "NxsMacroConfig"
    sg.ResetOnSpawn = false
    sg.DisplayOrder = 10001
    sg.IgnoreGuiInset = true
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    sg.Parent = guiParent()
    panelGui = sg

    local frame = Instance.new("Frame")
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.Position = UDim2.new(0.5, 0, 0.5, 0)
    frame.Size = UDim2.new(0.8, 0, 0.8, 0)
    frame.BackgroundColor3 = Color3.fromRGB(18, 10, 36)
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Parent = sg
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = frame
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(255, 255, 255)
    stroke.Transparency = 0.5
    stroke.Parent = frame
    local limit = Instance.new("UISizeConstraint")
    limit.MaxSize = Vector2.new(820, 560)
    limit.Parent = frame

    local function makeBtn(label, xScale, color)
        local b = Instance.new("TextButton")
        b.AnchorPoint = Vector2.new(0, 1)
        b.Position = UDim2.new(xScale, 10, 1, -8)
        b.Size = UDim2.new(0.5, -15, 0, 38)
        b.BackgroundColor3 = color
        b.BorderSizePixel = 0
        b.Font = Enum.Font.GothamBold
        b.TextSize = 16
        b.TextColor3 = Color3.fromRGB(255, 255, 255)
        b.Text = label
        b.ZIndex = 5
        b.Parent = frame
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 8)
        c.Parent = b
        return b
    end
    local copyBtn = makeBtn("Sao chép", 0, Color3.fromRGB(124, 58, 237))
    local closeBtn = makeBtn("Đóng", 0.5, Color3.fromRGB(70, 40, 110))
    copyBtn.Activated:Connect(function()
        local ok = copyText(text)
        copyBtn.Text = ok and "Đã sao chép!" or "Executor không hỗ trợ sao chép"
        task.delay(1.8, function()
            pcall(function()
                copyBtn.Text = "Sao chép"
            end)
        end)
    end)
    closeBtn.Activated:Connect(function()
        pcall(function()
            sg:Destroy()
        end)
    end)

    local head = Instance.new("TextLabel")
    head.BackgroundTransparency = 1
    head.Position = UDim2.new(0, 12, 0, 6)
    head.Size = UDim2.new(1, -24, 0, 22)
    head.Font = Enum.Font.GothamBold
    head.TextSize = 15
    head.TextColor3 = Color3.fromRGB(240, 232, 255)
    head.TextXAlignment = Enum.TextXAlignment.Left
    head.TextTruncate = Enum.TextTruncate.AtEnd
    head.Text = title
    head.Parent = frame

    local sub = Instance.new("TextLabel")
    sub.BackgroundTransparency = 1
    sub.Position = UDim2.new(0, 12, 0, 28)
    sub.Size = UDim2.new(1, -24, 0, 18)
    sub.Font = Enum.Font.Gotham
    sub.TextSize = 13
    sub.TextColor3 = Color3.fromRGB(200, 185, 255)
    sub.TextXAlignment = Enum.TextXAlignment.Left
    sub.TextTruncate = Enum.TextTruncate.AtEnd
    sub.Text = summary or ""
    sub.Parent = frame

    local scroll = Instance.new("ScrollingFrame")
    scroll.Position = UDim2.new(0, 10, 0, 50)
    scroll.Size = UDim2.new(1, -20, 1, -106)
    scroll.BackgroundColor3 = Color3.fromRGB(8, 4, 18)
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 6
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.Parent = frame
    local sc = Instance.new("UICorner")
    sc.CornerRadius = UDim.new(0, 8)
    sc.Parent = scroll
    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = scroll
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 6)
    pad.PaddingRight = UDim.new(0, 6)
    pad.PaddingTop = UDim.new(0, 6)
    pad.PaddingBottom = UDim.new(0, 6)
    pad.Parent = scroll

    task.spawn(function()
        local chunks = splitChunks(text, 60, 5000)
        local maxChunks = 60
        for idx, chunk in ipairs(chunks) do
            if idx > maxChunks then
                local more = Instance.new("TextLabel")
                more.BackgroundTransparency = 1
                more.Size = UDim2.new(1, 0, 0, 24)
                more.Font = Enum.Font.GothamBold
                more.TextSize = 13
                more.TextColor3 = Color3.fromRGB(255, 200, 120)
                more.TextXAlignment = Enum.TextXAlignment.Left
                more.Text = "... Config dài, chỉ hiện một phần. Nút Sao chép vẫn copy đủ."
                more.LayoutOrder = idx
                more.Parent = scroll
                break
            end
            pcall(function()
                local lbl = Instance.new("TextLabel")
                lbl.BackgroundTransparency = 1
                lbl.Size = UDim2.new(1, 0, 0, 0)
                lbl.AutomaticSize = Enum.AutomaticSize.Y
                lbl.Font = Enum.Font.Code
                lbl.TextSize = 12
                lbl.TextWrapped = true
                lbl.TextColor3 = Color3.fromRGB(225, 215, 255)
                lbl.TextXAlignment = Enum.TextXAlignment.Left
                lbl.TextYAlignment = Enum.TextYAlignment.Top
                lbl.LayoutOrder = idx
                lbl.Text = chunk
                lbl.Parent = scroll
            end)
            if idx % 10 == 0 then
                task.wait()
            end
        end
    end)
end

local function configSummary(cfg)
    if type(cfg) ~= "table" then
        return ""
    end
    if cfg.Version ~= 3 then
        return "Macro bản cũ, hãy ghi lại bằng bản mới"
    end
    local up, ab = 0, 0
    for _, ev in ipairs(cfg.Events or {}) do
        if ev.Type == "UpgradeAll" then
            up = up + 1
        elseif ev.Type == "Ability" then
            ab = ab + 1
        end
    end
    local dif = "chưa có"
    pcall(function()
        for _, a in ipairs(cfg.Difficulty.Args) do
            if type(a) == "string" and a:sub(1, 4) == "dif_" then
                dif = a
            end
        end
    end)
    return string.format("Độ khó: %s | %d unit | %d Upgrade All | %d kỹ năng | skip %d wave | tới wave %s/%s", dif, tonumber(cfg.UnitCount) or 0, up, ab, #(cfg.Skips or {}), tostring(cfg.LastWave or "?"), tostring(cfg.MaxWave or "?"))
end

local macroNameInput = ""
local recordToggleRef = {t = nil}

local function startRecording()
    if not hookReady then
        recorder.status = "Executor không hỗ trợ hook, không ghi được"
        return false
    end
    recorder.events = {}
    recorder.skips = {}
    recorder.skipRemote = nil
    recorder.difficulty = nil
    recorder.place = nil
    recorder.remotes = {}
    recorder.units = {}
    recorder.pending = 0
    recorder.claimed = {}
    recorder.finalSeen = false
    recorder.zeroSince = nil
    recorder.startedAt = clockNow()
    local w, mx = getWaveInfo()
    recorder.lastWave = w
    recorder.maxWave = mx or 0
    recorder.waveStartAt = clockNow()
    recorder.skipSince = isShown(PATH_SKIP) and clockNow() or nil
    recorder.voteSince = isShown(PATH_VOTE) and clockNow() or nil
    recorder.active = true
    G.NxsMacroActive = true
    recorder.status = "Đang ghi... | Hook: " .. hookInfo
    return true
end

local function stopRecording(auto)
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
    local cfg = compileConfig(name)
    local text, path = saveMacro(cfg)
    recorder.status = (auto and "Hết trận, tự dừng ghi. " or "") .. "Đã lưu " .. path .. "\n" .. configSummary(cfg)
    pcall(showConfigPanel, name .. "  |  " .. path, text, configSummary(cfg))
end

autoStop.fn = function()
    if not recorder.active then
        return
    end
    task.spawn(stopRecording, true)
    local tg = recordToggleRef.t
    if tg then
        task.spawn(function()
            pcall(function()
                tg:Set(false, true)
            end)
        end)
    end
end

local playback = {
    playing = false,
    autoReplay = true,
    keepSpeed = true,
    status = "Chưa chạy",
    file = nil,
    runId = 0,
}

local PLACE_OFFSETS = {{0, 0}}
do
    for _, ring in ipairs({{1, 8}, {2, 8}, {3, 12}}) do
        local r, n = ring[1], ring[2]
        for k = 0, n - 1 do
            local a = (k / n) * math.pi * 2
            PLACE_OFFSETS[#PLACE_OFFSETS + 1] = {math.cos(a) * r, math.sin(a) * r}
        end
    end
end

local function jitterPos(pos, minMag, maxMag)
    local function axis()
        local amount = minMag + math.random() * (maxMag - minMag)
        if math.random(1, 2) == 1 then
            return -amount
        end
        return amount
    end
    local mode = math.random(1, 3)
    local dx, dz = 0, 0
    if mode ~= 2 then
        dx = axis()
    end
    if mode ~= 1 then
        dz = axis()
    end
    return Vector3.new(pos.X + dx, pos.Y, pos.Z + dz)
end

local lastRestart = 0
local function restartGame()
    if clockNow() - lastRestart < 8 then
        return false
    end
    lastRestart = clockNow()
    local cur = contextMode() and currentContext() or nil
    if cur then
        fireRemote("RestartGame", "InvokeServer", {cur, false, n = 2}, 5)
    else
        fireRemote("RestartGame", "InvokeServer", {n = 0}, 5)
    end
    return true
end

local function speedSelected()
    local st = nil
    pcall(function()
        local b = player.PlayerGui.GameGuiNoInset.Screen.Top.WaveControls.WaveControls.GameSpeed.Speeds:FindFirstChild("2")
        if b then
            local c = b.UIGradient.Color.Keypoints[1].Value
            st = c.G > 0.8 and c.R < 0.6
        end
    end)
    return st
end

local function buildPlaceArgs(cfg, ev, pos, attempt, refs)
    local p = cfg.Place or {}
    local args = deserializeArgs(p.Args or {n = 2}, refs)
    local uIdx = tonumber(p.UnitIndex) or 1
    local dIdx = tonumber(p.DataIndex) or 2
    local data = {}
    for k, v in pairs(p.Template or {Valid = true, Rotation = 180}) do
        data[k] = v
    end
    data.Position = pos
    data.Attempt = attempt
    if type(data.Rotation) == "number" then
        data.Rotation = data.Rotation + math.random(-2, 2)
    end
    local r = p.Rot
    if type(r) == "table" and #r == 9 then
        data.CF = CFrame.new(pos.X, pos.Y, pos.Z, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9])
    else
        data.CF = CFrame.new(pos)
    end
    args[uIdx] = ev.Unit
    args[dIdx] = data
    local n = math.max(tonumber(args.n) or 0, uIdx, dIdx)
    args.n = n
    return args
end

local function playOnce(cfg, runId)
    local function alive()
        return playback.playing and playback.runId == runId
    end
    local refs = {}
    local claimed = {}
    local gameOver = false
    local restartedAt = playback.restartedAt
    playback.restartedAt = nil

    playback.status = "Đợi trận bắt đầu"
    local t0 = clockNow()
    while alive() do
        if isShown(PATH_GAMEEND) then
            return "ended"
        end
        if isShown(PATH_VOTE) then
            local d = cfg.Difficulty
            local since = clockNow()
            local nextVote = since + (d and math.max(0, tonumber(d.Delay) or 0) or 0)
            while alive() and isShown(PATH_VOTE) do
                if d and clockNow() >= nextVote then
                    nextVote = clockNow() + 3
                    playback.status = "Vote độ khó"
                    fireRemote(d.Remote, d.Method, deserializeArgs(d.Args or {n = 0}, refs), 5)
                end
                task.wait(0.2)
            end
            break
        end
        local waitLimit = restartedAt and 25 or 3
        if clockNow() - t0 > waitLimit and getWaveInfo() >= 1 then
            break
        end
        if clockNow() - t0 > 60 then
            break
        end
        task.wait(0.2)
    end
    if not alive() then
        return "stopped"
    end

    local waveStart = {}
    local curWave = getWaveInfo()
    waveStart[curWave] = clockNow()
    task.spawn(function()
        while alive() and not gameOver do
            local w = getWaveInfo()
            if w ~= curWave then
                curWave = w
                waveStart[w] = clockNow()
            end
            if isShown(PATH_GAMEEND) then
                task.wait(0.3)
                if isShown(PATH_GAMEEND) then
                    gameOver = true
                end
            end
            task.wait(0.1)
        end
    end)

    task.spawn(function()
        local lastSpeed, lastAuto = -100, -100
        local sentBlind = false
        while alive() and not gameOver do
            if playback.keepSpeed then
                local sel = speedSelected()
                if sel == false and clockNow() - lastSpeed >= 5 then
                    lastSpeed = clockNow()
                    fireRemote("ChangeTickSpeed", "FireServer", {2, n = 1}, 3)
                elseif sel == nil and not sentBlind then
                    sentBlind = true
                    fireRemote("ChangeTickSpeed", "FireServer", {2, n = 1}, 3)
                end
            end
            if autoSkipColorState() == true and clockNow() - lastAuto >= 3 then
                lastAuto = clockNow()
                fireRemote("SetAutoSkip", "FireServer", {false, n = 1}, 3)
            end
            task.wait(0.5)
        end
    end)

    task.spawn(function()
        local byWave = {}
        for _, sk in ipairs(cfg.Skips or {}) do
            byWave[tonumber(sk.Wave) or 0] = tonumber(sk.Delay) or 0
        end
        local sr = cfg.SkipRemote or {Remote = "SkipWave", Method = "FireServer", Args = {n = 0}}
        local done = {}
        local was = false
        local since = nil
        while alive() and not gameOver do
            local shown = isShown(PATH_SKIP)
            if shown and not was then
                since = clockNow()
            end
            was = shown
            local w = curWave
            if shown and since and not done[w] and byWave[w] ~= nil then
                done[w] = true
                local s0 = since
                local delay = byWave[w]
                task.spawn(function()
                    while alive() and not gameOver and clockNow() - s0 < delay do
                        task.wait(0.05)
                    end
                    if alive() and not gameOver and curWave == w and isShown(PATH_SKIP) then
                        fireRemote(sr.Remote, sr.Method, deserializeArgs(sr.Args or {n = 0}, refs), 5)
                    end
                end)
            end
            task.wait(0.05)
        end
    end)

    local remotes = cfg.Remotes or {}
    local function waitTime(ev)
        local w = tonumber(ev.Wave) or 0
        while alive() and not gameOver and curWave < w do
            playback.status = string.format("Wave %d | Đợi wave %d", curWave, w)
            task.wait(0.1)
        end
        if curWave == w then
            local base = waveStart[w] or clockNow()
            while alive() and not gameOver and curWave == w and clockNow() - base < (tonumber(ev.Delay) or 0) do
                task.wait(0.05)
            end
        end
    end

    local function placeUnit(ev, idx, total)
        local price = tonumber((cfg.Price or {})[ev.Unit]) or tonumber(ev.Cost) or 0
        local baseCost = price
        local base = Vector3.new(ev.Pos[1], ev.Pos[2], ev.Pos[3])
        local jMin, jMax, ring = 0.05, 0.2, 1
        for attempt = 1, 80 do
            while alive() and not gameOver and price > 0 and getCash() < price do
                playback.status = string.format("Wave %d | Đợi tiền %s/%s đặt %s (%d/%d)", curWave, math.floor(getCash()), price, ev.Unit, idx, total)
                task.wait(0.2)
            end
            if not alive() or gameOver then
                return false
            end
            playback.status = string.format("Wave %d | Đặt %s (%d/%d)", curWave, ev.Unit, idx, total)
            local off = PLACE_OFFSETS[ring]
            local pos = jitterPos(Vector3.new(base.X + off[1], base.Y, base.Z + off[2]), jMin, jMax)
            task.wait(0.1 + math.random() * 0.35)
            local before = {}
            for _, m in ipairs(unitModels(ev.Unit)) do
                before[m] = true
            end
            local cashAt = getCash()
            local p = cfg.Place or {}
            local ok, res = fireRemote(p.Remote or "PlaceUnit", p.Method or "InvokeServer", buildPlaceArgs(cfg, ev, pos, attempt, refs), 6)
            local model = nil
            if not (ok and remoteRejected(res)) then
                model = waitNewUnit(ev.Unit, pos, before, 1.5, claimed)
            end
            if model then
                refs[ev.Ref] = {model = model, ret = firstScalar(ok and res or nil), attrs = modelAttrs(model)}
                return true
            end
            if ok and remoteRejected(res) and baseCost > 0 then
                price = math.min(math.max(price, math.floor(cashAt) + 1), math.floor(baseCost * 1.5))
            end
            local floor = jMax <= 0.0601
            jMax = math.max(0.06, jMax - 0.02)
            jMin = math.min(0.05, jMax * 0.5)
            if floor then
                jMin, jMax = 0.05, 0.2
                ring = ring % #PLACE_OFFSETS + 1
            end
            task.wait(0.3)
        end
        return false
    end

    local totalPlace = 0
    for _, ev in ipairs(cfg.Events or {}) do
        if ev.Type == "Place" then
            totalPlace = totalPlace + 1
        end
    end
    local placed = 0
    for _, ev in ipairs(cfg.Events or {}) do
        if not alive() or gameOver then
            break
        end
        waitTime(ev)
        if not alive() or gameOver then
            break
        end
        if ev.Type == "Place" then
            placed = placed + 1
            placeUnit(ev, placed, totalPlace)
        elseif ev.Type == "UpgradeAll" then
            local tpl = remotes.UpgradeAll or {Remote = "UpgradeAll", Method = "InvokeServer", Args = {n = 0}}
            local w = tonumber(ev.Wave) or 0
            local need = tonumber(ev.Cost) or 0
            while alive() and not gameOver and need > 0 and getCash() < need and curWave <= w do
                playback.status = string.format("Wave %d | Đợi tiền Upgrade All %s/%s", curWave, math.floor(getCash()), need)
                task.wait(0.1)
            end
            if alive() and not gameOver then
                playback.status = string.format("Wave %d | Upgrade All", curWave)
                fireRemote(tpl.Remote, tpl.Method, deserializeArgs(tpl.Args or {n = 0}, refs), 5)
            end
        elseif ev.Type == "Ability" then
            local args, missing = deserializeArgs(ev.Args or {n = 0}, refs)
            if not missing then
                playback.status = string.format("Wave %d | Dùng kỹ năng", curWave)
                fireRemote(ev.Remote or "ActivateUnitAbility", ev.Method or "InvokeServer", args, 5)
            end
        end
    end

    while alive() and not gameOver do
        playback.status = string.format("Wave %d | Macro xong, đợi hết trận", curWave)
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
        playback.status = "Chọn file macro trước"
        return false
    end
    local cfg = loadMacroFile(playback.file)
    if not cfg then
        playback.status = "Không đọc được " .. tostring(playback.file)
        return false
    end
    if cfg.Version ~= 3 then
        playback.status = "File macro bản cũ không chạy được, hãy ghi lại bằng bản mới"
        return false
    end
    playback.playing = true
    playback.runId = playback.runId + 1
    local runId = playback.runId
    task.spawn(function()
        while playback.playing and playback.runId == runId do
            local okRun, result = pcall(playOnce, cfg, runId)
            if not okRun then
                playback.status = "Lỗi: " .. tostring(result)
                task.wait(1)
            end
            if not (playback.playing and playback.runId == runId) then
                break
            end
            if result == "ended" then
                if playback.autoReplay then
                    playback.status = "Hết trận | Chơi lại"
                    while playback.playing and playback.runId == runId and isShown(PATH_GAMEEND) do
                        if restartGame() then
                            playback.restartedAt = clockNow()
                        end
                        task.wait(0.5)
                    end
                else
                    playback.playing = false
                    playback.status = "Hết trận"
                    break
                end
            end
            task.wait(0.3)
        end
    end)
    return true
end

local function stopPlayback()
    playback.playing = false
    playback.runId = playback.runId + 1
    playback.status = "Đã dừng"
end

local WINDOW_TITLE = "Nexus Stella Macro"
local Window = redzlib:MakeWindow({
    Title = WINDOW_TITLE,
    SubTitle = "By nhat0258",
    SaveFolder = "NxsMacro_UI.json"
})

local UserInputService = game:GetService("UserInputService")
local LOGO_STATE_FILE = "NxsMacro_UIState.json"

local function findMacroWindowGui()
    local found = nil
    local roots = {}
    pcall(function()
        if gethui then
            roots[#roots + 1] = gethui()
        end
    end)
    pcall(function()
        roots[#roots + 1] = game:GetService("CoreGui")
    end)
    for _, root in ipairs(roots) do
        pcall(function()
            for _, g in ipairs(root:GetChildren()) do
                if not found and g.Name == "redz Library V5" then
                    for _, d in ipairs(g:GetDescendants()) do
                        if d:IsA("TextLabel") and d.Text == WINDOW_TITLE then
                            found = g
                            break
                        end
                    end
                end
            end
        end)
        if found then
            break
        end
    end
    return found
end

local function saveLogoState(hidden)
    pcall(function()
        writefile(LOGO_STATE_FILE, HttpService:JSONEncode({UIHidden = hidden}))
    end)
end

local function createLogo()
    local parent = guiParent()
    pcall(function()
        local old = parent:FindFirstChild("NxsMacroLogoGui")
        if old then
            old:Destroy()
        end
    end)
    local sg = Instance.new("ScreenGui")
    sg.Name = "NxsMacroLogoGui"
    sg.ResetOnSpawn = false
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    sg.DisplayOrder = 10000
    sg.Parent = parent

    local btn = Instance.new("ImageButton")
    btn.Name = "Logo"
    btn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    btn.BackgroundTransparency = 0.5
    btn.Position = UDim2.new(0.1, 0, 0.22, 0)
    btn.Size = UDim2.new(0, 50, 0, 50)
    btn.AutoButtonColor = false
    btn.Active = true
    btn.Parent = sg
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 12)
    c.Parent = btn
    local st = Instance.new("UIStroke")
    st.Color = Color3.fromRGB(192, 132, 252)
    st.Thickness = 1.5
    st.Transparency = 0.2
    st.Parent = btn
    local tag = Instance.new("TextLabel")
    tag.BackgroundColor3 = Color3.fromRGB(124, 58, 237)
    tag.AnchorPoint = Vector2.new(0.5, 0)
    tag.Position = UDim2.new(0.5, 0, 1, 2)
    tag.Size = UDim2.new(0, 46, 0, 14)
    tag.Font = Enum.Font.GothamBold
    tag.TextSize = 10
    tag.TextColor3 = Color3.fromRGB(255, 255, 255)
    tag.Text = "MACRO"
    tag.Parent = btn
    local tc = Instance.new("UICorner")
    tc.CornerRadius = UDim.new(0, 6)
    tc.Parent = tag

    task.spawn(function()
        local ok, img = pcall(function()
            local fileName = "NexusLogo_ATx.png"
            if not isfile(fileName) then
                writefile(fileName, game:HttpGet("https://raw.githubusercontent.com/nguyennhlat2004/Roblox-Api/main/ATx.png"))
            end
            return getcustomasset(fileName)
        end)
        if ok and img then
            btn.Image = img
        else
            btn.Image = "rbxassetid://13347535978"
        end
    end)

    local dragging, moved, dragStart, startPos, dragInput = false, false, nil, nil, nil
    btn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            moved = false
            dragStart = input.Position
            startPos = btn.Position
            dragInput = input
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if not dragging or not dragStart then
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseMovement or input == dragInput or input.UserInputType == Enum.UserInputType.Touch then
            local delta = input.Position - dragStart
            if math.abs(delta.X) > 6 or math.abs(delta.Y) > 6 then
                moved = true
            end
            if moved then
                btn.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if not dragging then
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
            if not moved then
                local g = findMacroWindowGui()
                if g then
                    g.Enabled = not g.Enabled
                    saveLogoState(not g.Enabled)
                end
            end
        end
    end)
end

pcall(createLogo)

task.spawn(function()
    local hidden = false
    pcall(function()
        if isfile(LOGO_STATE_FILE) then
            local d = HttpService:JSONDecode(readfile(LOGO_STATE_FILE))
            hidden = type(d) == "table" and d.UIHidden == true
        end
    end)
    if hidden then
        task.wait(0.5)
        local g = findMacroWindowGui()
        if g then
            g.Enabled = false
        end
    end
end)

local TabMacro = Window:MakeTab({"Macro", "play"})
local TabHistory = Window:MakeTab({"Lịch sử", "list"})

TabMacro:AddSection({"Ghi Macro"})

TabMacro:AddTextBox({
    Name = "Tên Macro",
    Description = "Tên file khi lưu",
    PlaceholderText = "Garden Grind L5",
    Callback = function(Value)
        macroNameInput = tostring(Value or "")
    end
})

local recordToggle = nil
recordToggle = TabMacro:AddToggle({
    Name = "Ghi Macro",
    Description = "Chỉ ghi: Vote độ khó, Skip từng wave, Đặt unit, Upgrade All, Kỹ năng. Tự dừng và lưu khi hết wave cuối và hết enemy",
    Default = false,
    Callback = function(Value)
        if Value then
            if not startRecording() then
                task.defer(function()
                    pcall(function()
                        recordToggle:Set(false, true)
                    end)
                end)
            end
        else
            task.spawn(stopRecording, false)
        end
    end
})
recordToggleRef.t = recordToggle

local recordParagraph = TabMacro:AddParagraph({"Trạng thái ghi", hookReady and ("Chưa ghi | Hook: " .. hookInfo) or "Executor không hỗ trợ hook, không ghi được"})

TabMacro:AddSection({"Chạy Macro"})

local playDropdown = TabMacro:AddDropdown({
    Name = "File Macro",
    Options = historyNames(),
    Default = "",
    Callback = function(Value)
        if type(Value) == "string" and Value ~= "" then
            playback.file = Value
        end
    end
})

TabMacro:AddToggle({
    Name = "Tự chơi lại",
    Description = "Hết trận tự restart, vote lại và chạy tiếp",
    Default = true,
    Flag = "NxsAutoReplay",
    Callback = function(Value)
        playback.autoReplay = Value == true
    end
})

TabMacro:AddToggle({
    Name = "Giữ tốc độ x2",
    Default = true,
    Flag = "NxsKeepSpeed",
    Callback = function(Value)
        playback.keepSpeed = Value == true
    end
})

local playToggle = nil
playToggle = TabMacro:AddToggle({
    Name = "Chạy Macro",
    Default = false,
    Callback = function(Value)
        if Value then
            if startPlayback() == false then
                task.defer(function()
                    pcall(function()
                        playToggle:Set(false, true)
                    end)
                end)
            end
        else
            stopPlayback()
        end
    end
})

local playParagraph = TabMacro:AddParagraph({"Trạng thái chạy", "Chưa chạy"})

local historySelected = nil
local historyParagraph = nil

local function historySummary(fileName)
    local cfg = loadMacroFile(fileName)
    for _, e in ipairs(readHistory()) do
        if e.file == fileName then
            return string.format("%s\nTạo lúc: %s\n%s", tostring(e.name), tostring(e.created), cfg and configSummary(cfg) or "")
        end
    end
    if cfg then
        return string.format("%s\nTạo lúc: %s\n%s", tostring(cfg.Name), tostring(cfg.CreatedAt), configSummary(cfg))
    end
    return "Không đọc được file"
end

local historyDropdown = TabHistory:AddDropdown({
    Name = "Macro đã lưu",
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

historyParagraph = TabHistory:AddParagraph({"Thông tin Macro", "Chọn một macro"})

TabHistory:AddButton({
    Name = "Xem Config",
    Description = "Mở bảng config để xem và sao chép",
    Callback = function()
        if not historySelected then
            return
        end
        local cfg, text = loadMacroFile(historySelected)
        if text then
            pcall(showConfigPanel, historySelected, text, cfg and configSummary(cfg) or "")
        end
    end
})

TabHistory:AddButton({
    Name = "Sao chép Config",
    Callback = function()
        if not historySelected then
            return
        end
        local _, text = loadMacroFile(historySelected)
        if text and historyParagraph then
            local ok = copyText(text)
            pcall(function()
                historyParagraph:SetDesc(ok and ("Đã sao chép " .. historySelected) or "Executor không hỗ trợ sao chép")
            end)
        end
    end
})

TabHistory:AddButton({
    Name = "Dùng để chạy",
    Callback = function()
        if historySelected then
            playback.file = historySelected
            playback.status = "Đã chọn " .. historySelected
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
    Name = "Xóa Macro",
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
            historyParagraph:SetDesc("Đã xóa")
        end)
        refreshLists()
    end
})

TabHistory:AddButton({
    Name = "Làm mới",
    Callback = refreshLists
})

local lastCount = #historyNames()
task.spawn(function()
    while true do
        pcall(function()
            if recorder.active then
                local np, nu, na, ns = 0, 0, 0, 0
                for _, ev in ipairs(recorder.events) do
                    if not ev.Failed then
                        if ev.Type == "Place" then
                            np = np + 1
                        elseif ev.Type == "UpgradeAll" then
                            nu = nu + 1
                        elseif ev.Type == "Ability" then
                            na = na + 1
                        end
                    end
                end
                for _ in pairs(recorder.skips) do
                    ns = ns + 1
                end
                recordParagraph:SetDesc(string.format("%s\nWave %d/%d | Đặt %d | Upgrade All %d | Kỹ năng %d | Skip %d wave | Vote: %s", recorder.status, recorder.lastWave, recorder.maxWave or 0, np, nu, na, ns, recorder.difficulty and "có" or "chưa"))
            else
                recordParagraph:SetDesc(recorder.status)
            end
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
