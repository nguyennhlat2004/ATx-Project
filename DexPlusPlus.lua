local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local env = type(getgenv) == "function" and getgenv() or _G

if env.DexDumpClose then
    pcall(env.DexDumpClose)
end

local old = CoreGui:FindFirstChild("DexGitExport")
if old then old:Destroy() end
local oldOpen = CoreGui:FindFirstChild("DexGitExportOpen")
if oldOpen then oldOpen:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "DexGitExport"
gui.ResetOnSpawn = false
gui.DisplayOrder = 10001
gui.Parent = CoreGui

local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(330, 315)
panel.Position = UDim2.new(0.5, -165, 0.2, 0)
panel.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
panel.BorderSizePixel = 0
panel.Active = true
panel.Draggable = true
panel.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = panel

local function label(text, y, height)
    local item = Instance.new("TextLabel")
    item.BackgroundTransparency = 1
    item.Position = UDim2.fromOffset(12, y)
    item.Size = UDim2.new(1, -24, 0, height)
    item.Font = Enum.Font.Gotham
    item.TextSize = 13
    item.TextColor3 = Color3.fromRGB(235, 235, 235)
    item.TextWrapped = true
    item.TextXAlignment = Enum.TextXAlignment.Left
    item.Text = text
    item.Parent = panel
    return item
end

local title = label("Dex++ · GitHub Export", 10, 24)
title.Font = Enum.Font.GothamBold
title.TextSize = 16

local status = label("Đang tải Dex++...", 220, 82)
status.TextYAlignment = Enum.TextYAlignment.Top

local tokenField = Instance.new("TextBox")
tokenField.Position = UDim2.fromOffset(12, 42)
tokenField.Size = UDim2.new(1, -24, 0, 34)
tokenField.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
tokenField.TextColor3 = Color3.fromRGB(255, 255, 255)
tokenField.PlaceholderColor3 = Color3.fromRGB(160, 160, 160)
tokenField.PlaceholderText = "Dán token GitHub rồi nhấn Enter"
tokenField.ClearTextOnFocus = false
tokenField.Text = ""
tokenField.Font = Enum.Font.Gotham
tokenField.TextSize = 13
tokenField.Parent = panel

local function button(text, x, y, width)
    local item = Instance.new("TextButton")
    item.Position = UDim2.fromOffset(x, y)
    item.Size = UDim2.fromOffset(width, 34)
    item.BackgroundColor3 = Color3.fromRGB(46, 46, 46)
    item.BorderSizePixel = 0
    item.TextColor3 = Color3.fromRGB(245, 245, 245)
    item.Font = Enum.Font.GothamSemibold
    item.TextSize = 12
    item.Text = text
    item.Parent = panel
    local round = Instance.new("UICorner")
    round.CornerRadius = UDim.new(0, 6)
    round.Parent = item
    return item
end

local decompileButton = button("Decompile: ON", 12, 88, 148)
local captureButton = button("Xuất lên GitHub", 170, 88, 148)
local cancelButton = button("Hủy xuất", 12, 130, 96)
local clearButton = button("Xóa token", 117, 130, 96)
local hideButton = button("Ẩn", 222, 130, 96)
local info = label("Repo công khai · giữ 3 bản trên main · mã có thể gửi tới ByteFall khi decompile.", 174, 42)
info.TextColor3 = Color3.fromRGB(255, 195, 110)

local openGui = Instance.new("ScreenGui")
openGui.Name = "DexGitExportOpen"
openGui.ResetOnSpawn = false
openGui.DisplayOrder = 10001
openGui.Parent = CoreGui
local openButton = Instance.new("TextButton")
openButton.Size = UDim2.fromOffset(92, 34)
openButton.Position = UDim2.new(0, 12, 0.5, -17)
openButton.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
openButton.TextColor3 = Color3.fromRGB(255, 255, 255)
openButton.Font = Enum.Font.GothamBold
openButton.TextSize = 12
openButton.Text = "Dex Export"
openButton.Visible = false
openButton.Active = true
openButton.Draggable = true
openButton.Parent = openGui
local openCorner = Instance.new("UICorner")
openCorner.CornerRadius = UDim.new(0, 6)
openCorner.Parent = openButton

local token
local busy = false
local canceled = false
local decompileEnabled = true
local closed = false
local baseUrl = "https://raw.githubusercontent.com/nguyennhlat2004/ATx-Project/main/DexPlusPlus_Base.lua"
local apiUrl = "https://api.github.com/repos/nguyennhlat2004/ATx-Project"

local function show(text)
    pcall(function()
        if not closed then status.Text = tostring(text) end
    end)
end

local function run(callback)
    return function(...)
        local ok, err = pcall(callback, ...)
        if not ok then show("Lỗi: " .. tostring(err)) end
    end
end

tokenField.FocusLost:Connect(run(function()
    local input = tokenField.Text
    tokenField.Text = ""
    if input ~= "" then
        token = input
        show("Đã nhận token tạm thời; ô nhập đã được xóa.")
    end
end))

decompileButton.MouseButton1Click:Connect(run(function()
    if busy then return end
    decompileEnabled = not decompileEnabled
    decompileButton.Text = decompileEnabled and "Decompile: ON" or "Decompile: OFF"
end))

cancelButton.MouseButton1Click:Connect(run(function()
    if busy then
        canceled = true
        show("Đang hủy; các blob chưa được gắn vào nhánh sẽ không xuất hiện trong thư mục dump.")
    end
end))

clearButton.MouseButton1Click:Connect(run(function()
    token = nil
    tokenField.Text = ""
    show("Đã xóa token trong bộ nhớ.")
end))

hideButton.MouseButton1Click:Connect(run(function()
    panel.Visible = false
    openButton.Visible = true
end))

openButton.MouseButton1Click:Connect(run(function()
    panel.Visible = true
    openButton.Visible = false
end))

local function checkCanceled()
    if canceled or closed then error("Đã hủy xuất.") end
end

local function redact(value, secret)
    if type(value) ~= "string" or not secret or secret == "" then return value end
    local pieces = {}
    local start = 1
    while true do
        local first, last = value:find(secret, start, true)
        if not first then
            pieces[#pieces + 1] = value:sub(start)
            break
        end
        pieces[#pieces + 1] = value:sub(start, first - 1)
        pieces[#pieces + 1] = "[redacted]"
        start = last + 1
    end
    return table.concat(pieces)
end

local function base64(data)
    local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local out = {}
    for i = 1, #data, 3 do
        local a = data:byte(i) or 0
        local b = data:byte(i + 1) or 0
        local c = data:byte(i + 2) or 0
        local number = a * 65536 + b * 256 + c
        local n1 = math.floor(number / 262144) % 64 + 1
        local n2 = math.floor(number / 4096) % 64 + 1
        local n3 = math.floor(number / 64) % 64 + 1
        local n4 = number % 64 + 1
        local third = i + 1 <= #data and alphabet:sub(n3, n3) or "="
        local fourth = i + 2 <= #data and alphabet:sub(n4, n4) or "="
        out[#out + 1] = alphabet:sub(n1, n1) .. alphabet:sub(n2, n2) .. third .. fourth
    end
    return table.concat(out)
end

local function safeString(value, secret)
    value = redact(value, secret)
    local valid, count = pcall(utf8.len, value)
    if not valid or count == nil then
        return { type = "binary", encoding = "base64", data = base64(value) }
    end
    return value
end

local function serialize(value, secret, depth)
    local kind = typeof(value)
    if kind == "nil" then return { type = "nil" } end
    if kind == "boolean" then return value end
    if kind == "number" then
        if value ~= value or value == math.huge or value == -math.huge then return { type = "number", value = tostring(value) } end
        return value
    end
    if kind == "string" then return safeString(value, secret) end
    if kind == "Instance" then
        local ok, path = pcall(function() return value:GetFullName() end)
        return { type = "Instance", class = value.ClassName, path = redact(ok and path or value.Name, secret) }
    end
    if kind == "table" then
        if depth >= 3 then return { type = "table", status = "depth_limit" } end
        local items = {}
        local total = 0
        for key, item in pairs(value) do
            total = total + 1
            if total <= 100 then
                items[#items + 1] = { key = serialize(key, secret, depth + 1), value = serialize(item, secret, depth + 1) }
            end
        end
        return { type = "table", items = items, total = total, truncated = total > 100 }
    end
    return { type = kind, value = redact(tostring(value), secret) }
end

local function github(method, path, body, secret, raw)
    checkCanceled()
    local requestFn = request or http_request or (syn and syn.request) or (http and http.request)
    if type(requestFn) ~= "function" then error("Executor không hỗ trợ HTTP request.") end
    local options = {
        Url = apiUrl .. path,
        Method = method,
        Headers = {
            Authorization = "Bearer " .. secret,
            Accept = "application/vnd.github+json",
            ["Content-Type"] = "application/json",
            ["X-GitHub-Api-Version"] = "2022-11-28"
        }
    }
    if body then options.Body = raw and body or HttpService:JSONEncode(body) end
    local ok, response = pcall(requestFn, options)
    if not ok or type(response) ~= "table" then error("Không kết nối được GitHub API.") end
    local code = tonumber(response.StatusCode or response.Status or 0) or 0
    if code < 200 or code >= 300 then
        error("GitHub API trả HTTP " .. tostring(code) .. ". Kiểm tra quyền token, giới hạn API hoặc thử lại.")
    end
    local decoded, result = pcall(function() return HttpService:JSONDecode(response.Body or "") end)
    if not decoded or type(result) ~= "table" then error("Phản hồi GitHub không hợp lệ.") end
    return result
end

local function getDexDependencies()
    local getter = env.DexDumpGetDeps
    if type(getter) ~= "function" then error("Dex++ chưa tải xong hoặc khởi tạo lỗi. Chờ rồi thử lại.") end
    local deps = getter()
    if type(deps) ~= "table" or type(deps.API) ~= "table" or type(deps.API.GetMember) ~= "function" then
        error("Không lấy được API properties từ Dex++.")
    end
    return deps
end

local function decompileScript(object, deps)
    if not decompileEnabled then return nil, "disabled" end
    local allowed = object:IsA("LocalScript") or object:IsA("ModuleScript")
    if object:IsA("Script") then
        local ok, context = pcall(function() return object.RunContext end)
        allowed = ok and context == Enum.RunContext.Client
    end
    if not allowed then return nil, "server_code_not_available_on_client" end
    local readOk, direct = pcall(function() return object.Source end)
    if readOk and type(direct) == "string" and direct ~= "" then return direct, "source" end
    local dec = deps.env and deps.env.decompile or decompile
    if type(dec) ~= "function" then return nil, "decompiler_unavailable" end
    local complete = false
    local success, result
    local thread = task.spawn(function()
        success, result = pcall(dec, object)
        complete = true
    end)
    local deadline = os.clock() + 12
    while not complete and os.clock() < deadline do
        checkCanceled()
        task.wait(0.1)
    end
    if not complete then
        pcall(task.cancel, thread)
        return nil, "timeout"
    end
    if not success or type(result) ~= "string" then return nil, "failed" end
    return result, "decompiler_returned"
end

local function export(secret)
    if not secret or secret == "" then error("Hãy nhập token GitHub rồi nhấn Enter.") end
    local deps = getDexDependencies()
    local api = deps.API
    local ref = github("GET", "/git/ref/heads/main", nil, secret)
    local parent = ref.object and ref.object.sha
    if not parent then error("Không đọc được HEAD của main.") end
    local parentCommit = github("GET", "/git/commits/" .. parent, nil, secret)
    local baseTree = parentCommit.tree and parentCommit.tree.sha
    if not baseTree then error("Không đọc được tree của main.") end
    local existing = github("GET", "/git/trees/" .. baseTree .. "?recursive=1", nil, secret)
    if existing.truncated then error("GitHub trả tree bị cắt; dừng để tránh xóa nhầm bản dump.") end
    if type(existing.tree) ~= "table" then error("Không đọc được danh sách file trong repo.") end
    local snapshotId = tostring(os.time()) .. "_" .. string.format("%06d", math.random(0, 999999))
    local prefix = "DexDumps/" .. snapshotId .. "/"
    local groups = {}
    for _, item in ipairs(existing.tree) do
        if item.type == "blob" and type(item.path) == "string" then
            local group = item.path:match("^DexDumps/(%d+_%d+)/")
            if group then
                groups[group] = groups[group] or {}
                table.insert(groups[group], item.path)
            end
        end
    end
    if groups[snapshotId] then error("Mã bản dump đã tồn tại; vui lòng thử lại.") end
    local groupNames = {}
    for name in pairs(groups) do table.insert(groupNames, name) end
    table.sort(groupNames)
    local deletePaths = {}
    for i = 1, math.max(0, #groupNames - 2) do
        for _, path in ipairs(groups[groupNames[i]]) do table.insert(deletePaths, path) end
    end
    local changes = {}
    local buffer = {}
    local bufferBytes = 0
    local partNumber = 0
    local count = 0
    local scriptsSeen = 0
    local scriptsReturned = 0
    local scriptsFailed = 0
    local propertiesFailed = 0
    local function flush()
        if bufferBytes == 0 then return end
        checkCanceled()
        partNumber = partNumber + 1
        local content = table.concat(buffer, "\n") .. "\n"
        if #content > 90000000 then error("Một bản ghi vượt giới hạn kích thước blob.") end
        show("Đang tải phần " .. partNumber .. " · " .. count .. " đối tượng...")
        local blob = github("POST", "/git/blobs", { content = content, encoding = "utf-8" }, secret)
        if not blob.sha then error("Không tạo được blob GitHub.") end
        table.insert(changes, { path = prefix .. string.format("part-%06d.jsonl", partNumber), mode = "100644", type = "blob", sha = blob.sha })
        buffer = {}
        bufferBytes = 0
    end
    local function addRecord(record)
        local ok, line = pcall(function() return HttpService:JSONEncode(record) end)
        if not ok then error("Không mã hóa được một bản ghi JSON.") end
        if bufferBytes > 0 and bufferBytes + #line + 1 > 524288 then flush() end
        table.insert(buffer, line)
        bufferBytes = bufferBytes + #line + 1
    end
    addRecord({ kind = "meta", version = 1, created = os.time(), placeId = game.PlaceId, decompile = decompileEnabled, note = "Client-visible instances only. Protected properties and server-only source may be unavailable. Token and TextBox text are redacted." })
    local stack = {}
    local getNil = deps.env and deps.env.getnilinstances or getnilinstances or get_nil_instances
    if type(getNil) == "function" then
        local ok, instances = pcall(getNil)
        if ok and type(instances) == "table" then
            for _, object in ipairs(instances) do
                local valid, parent = pcall(function() return object.Parent end)
                if typeof(object) == "Instance" and valid and parent == nil and object ~= game then
                    table.insert(stack, { object = object, parent = 0, group = "nil_instances" })
                end
            end
        end
    end
    table.insert(stack, { object = game, parent = 0, group = "game" })
    local visited = {}
    local nextId = 0
    local classProperties = {}
    while #stack > 0 do
        checkCanceled()
        local item = table.remove(stack)
        local object = item.object
        if not visited[object] and object ~= gui and object ~= openGui then
            visited[object] = true
            local exists, className = pcall(function() return object.ClassName end)
            if exists then
                nextId = nextId + 1
                local id = nextId
                count = count + 1
                local node = { kind = "instance", id = id, parent = item.parent, group = item.group, class = className, properties = {}, attributes = {}, unreadableProperties = {} }
                local nameOk, name = pcall(function() return object.Name end)
                node.name = nameOk and redact(name, secret) or "[unavailable]"
                local attrOk, attributes = pcall(function() return object:GetAttributes() end)
                if attrOk then
                    for key, value in pairs(attributes) do
                        local lower = tostring(key):lower()
                        local cleanKey = redact(tostring(key), secret)
                        if lower:find("token", 1, true) or lower:find("password", 1, true) or lower:find("cookie", 1, true) or lower:find("secret", 1, true) then
                            node.attributes[cleanKey] = "[redacted]"
                        else
                            local converted, result = pcall(serialize, value, secret, 0)
                            node.attributes[cleanKey] = converted and result or "[unavailable]"
                        end
                    end
                else
                    node.attributesStatus = "unavailable"
                end
                if not classProperties[className] then
                    local ok, properties = pcall(api.GetMember, className, "Properties")
                    classProperties[className] = ok and properties or {}
                end
                for _, property in ipairs(classProperties[className]) do
                    local key = property.Name
                    local lower = key:lower()
                    if key ~= "Parent" and key ~= "Name" and key ~= "Source" then
                        if lower:find("token", 1, true) or lower:find("password", 1, true) or lower:find("cookie", 1, true) or lower:find("secret", 1, true) or (key == "Text" and object:IsA("TextBox")) then
                            node.properties[key] = "[redacted]"
                        else
                            local ok, value = pcall(function() return object[key] end)
                            if ok then
                                local converted, result = pcall(serialize, value, secret, 0)
                                node.properties[key] = converted and result or "[unavailable]"
                            else
                                table.insert(node.unreadableProperties, key)
                                propertiesFailed = propertiesFailed + 1
                            end
                        end
                    end
                end
                addRecord(node)
                if object:IsA("LuaSourceContainer") then
                    scriptsSeen = scriptsSeen + 1
                    show("Đang đọc script " .. scriptsSeen .. " · đối tượng " .. count .. "...")
                    local source, scriptStatus = decompileScript(object, deps)
                    if source then
                        scriptsReturned = scriptsReturned + 1
                        source = redact(source, secret)
                        local total = math.max(1, math.ceil(#source / 48000))
                        addRecord({ kind = "script", instanceId = id, status = scriptStatus, encoding = "base64", chunks = total, bytes = #source })
                        for n = 1, total do
                            checkCanceled()
                            local chunk = source:sub((n - 1) * 48000 + 1, n * 48000)
                            addRecord({ kind = "script_chunk", instanceId = id, index = n, data = base64(chunk) })
                            if n % 4 == 0 then task.wait() end
                        end
                    else
                        scriptsFailed = scriptsFailed + 1
                        addRecord({ kind = "script", instanceId = id, status = scriptStatus })
                    end
                end
                local ok, children = pcall(function() return object:GetChildren() end)
                if ok then
                    for i = #children, 1, -1 do
                        table.insert(stack, { object = children[i], parent = id, group = item.group })
                    end
                else
                    addRecord({ kind = "children_unavailable", instanceId = id })
                end
                if count % 30 == 0 then
                    show("Đã quét " .. count .. " đối tượng · " .. scriptsSeen .. " scripts.")
                    task.wait()
                end
            end
        end
    end
    addRecord({ kind = "summary", objects = count, scripts = scriptsSeen, sourceReturned = scriptsReturned, sourceUnavailable = scriptsFailed, unreadableProperties = propertiesFailed, finished = os.time() })
    flush()
    checkCanceled()
    local entries = {}
    for _, change in ipairs(changes) do table.insert(entries, HttpService:JSONEncode(change)) end
    for _, path in ipairs(deletePaths) do
        table.insert(entries, "{\"path\":" .. HttpService:JSONEncode(path) .. ",\"mode\":\"100644\",\"type\":\"blob\",\"sha\":null}")
    end
    local rawTree = "{\"base_tree\":" .. HttpService:JSONEncode(baseTree) .. ",\"tree\":[" .. table.concat(entries, ",") .. "]}"
    show("Đang cập nhật nhánh main...")
    local tree = github("POST", "/git/trees", rawTree, secret, true)
    if not tree.sha then error("Không tạo được tree GitHub.") end
    local commit = github("POST", "/git/commits", { message = "", tree = tree.sha, parents = { parent } }, secret)
    if not commit.sha then error("Không tạo được commit.") end
    github("PATCH", "/git/refs/heads/main", { sha = commit.sha, force = false }, secret)
    show("Đã tải " .. count .. " đối tượng, " .. partNumber .. " phần. Folder: " .. prefix)
end

captureButton.MouseButton1Click:Connect(run(function()
    if busy then show("Đang xuất, hãy đợi hoặc bấm Hủy.") return end
    local secret = token
    if not secret or secret == "" then show("Hãy nhập token GitHub rồi nhấn Enter.") return end
    token = nil
    tokenField.Text = ""
    busy = true
    canceled = false
    task.spawn(function()
        local ok, err = pcall(export, secret)
        busy = false
        if not ok then show("Lỗi: " .. redact(tostring(err), secret)) end
        secret = nil
    end)
end))

env.DexDumpClose = function()
    canceled = true
    closed = true
    token = nil
    pcall(function() gui:Destroy() end)
    pcall(function() openGui:Destroy() end)
end

task.spawn(function()
    local ok, err = pcall(function()
        local source = game:HttpGet(baseUrl)
        local chunk = loadstring(source)
        if not chunk then error("Không biên dịch được Dex++ gốc.") end
        chunk()
    end)
    if not ok then
        show("Dex++ khởi tạo lỗi: " .. tostring(err))
    elseif not closed then
        show("Dex++ đã tải. Nhập token để xuất Explorer.")
    end
end)
