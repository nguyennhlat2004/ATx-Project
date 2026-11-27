local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local function fallbackNotify(content)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "Petapeta",
            Text = tostring(content),
            Duration = 8
        })
    end)
end

local loaded, Fluent = pcall(function()
    return loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
end)

if not loaded or not Fluent then
    fallbackNotify("Không thể tải Fluent UI: " .. tostring(Fluent))
    return
end

local function notify(content, duration)
    local ok = pcall(function()
        Fluent:Notify({
            Title = "Petapeta",
            Content = tostring(content),
            Duration = duration or 6
        })
    end)
    if not ok then
        fallbackNotify(content)
    end
end

local initialized, initError = pcall(function()
    local env = getgenv and getgenv() or nil
    if env and env.PetapetaCleanup then
        pcall(env.PetapetaCleanup)
    end

    local Window = Fluent:CreateWindow({
        Title = "Petapeta",
        SubTitle = "Main",
        TabWidth = 130,
        Size = UDim2.fromOffset(500, 360),
        Acrylic = false,
        Theme = "Darker",
        MinimizeKey = Enum.KeyCode.LeftControl
    })

    local Main = Window:AddTab({ Title = "Main", Icon = "home" })
    local alive = true
    local roomFolder
    local itemFolder
    local roomFolderConnections = {}
    local itemFolderConnections = {}
    local rooms = {}
    local boxes = {}
    local keys = {}
    local originalHolds = {}
    local autoCollectKey = false
    local lastBackgroundError = 0

    local function disconnectAll(connections)
        for _, connection in ipairs(connections) do
            connection:Disconnect()
        end
        table.clear(connections)
    end

    local function backgroundError(err)
        if os.clock() - lastBackgroundError >= 10 then
            lastBackgroundError = os.clock()
            notify("Lỗi tác vụ ngầm: " .. tostring(err))
        end
    end

    local function guarded(callback)
        local ok, err = pcall(callback)
        if not ok then
            backgroundError(err)
        end
    end

    local function findPosition(object)
        if object:IsA("BasePart") then
            return object.CFrame
        end
        if object:IsA("Model") then
            return object:GetPivot()
        end
        local part = object:FindFirstChildWhichIsA("BasePart", true)
        return part and part.CFrame or nil
    end

    local function characterRoot()
        local player = Players.LocalPlayer
        local character = player and player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if not root then
            error("Không tìm thấy HumanoidRootPart. Hãy đợi nhân vật xuất hiện.")
        end
        return character, root
    end

    local function teleportTo(object)
        local character = characterRoot()
        local target = findPosition(object)
        if not target then
            error("Không tìm thấy vị trí của đối tượng.")
        end
        character:PivotTo(target * CFrame.new(0, 3, 4))
    end

    local function nearest(objects, root)
        local best, bestDistance
        for object in pairs(objects) do
            if object.Parent then
                local cf = findPosition(object)
                if cf then
                    local distance = (cf.Position - root.Position).Magnitude
                    if not bestDistance or distance < bestDistance then
                        best = object
                        bestDistance = distance
                    end
                end
            end
        end
        return best
    end

    local function removeRoom(room)
        local entry = rooms[room]
        if not entry then
            return
        end
        disconnectAll(entry.connections)
        disconnectAll(entry.promptConnections)
        rooms[room] = nil
    end

    local function refreshRoom(room)
        local entry = rooms[room]
        if not entry then
            return
        end
        disconnectAll(entry.promptConnections)
        local props = room:FindFirstChild("Props")
        entry.safe = props and props:FindFirstChild("Safe") or nil
        local paper = room:FindFirstChild("HintPaper")
        local surface = paper and paper:FindFirstChild("SurfaceGui")
        local label = surface and surface:FindFirstChild("TextLabel")
        entry.hint = label and label:IsA("TextLabel") and label or nil
        entry.paper = paper

        local function watchPrompt(prompt)
            if not prompt:IsA("ProximityPrompt") then
                return
            end
            local function enable()
                guarded(function()
                    if alive and prompt.Parent and not prompt.Enabled then
                        prompt.Enabled = true
                    end
                end)
            end
            table.insert(entry.promptConnections, prompt:GetPropertyChangedSignal("Enabled"):Connect(enable))
            enable()
        end

        if entry.safe then
            watchPrompt(entry.safe)
            for _, descendant in ipairs(entry.safe:GetDescendants()) do
                watchPrompt(descendant)
            end
        end
    end

    local function addRoom(room)
        if not room:IsA("Model") or room.Name ~= "Room" or rooms[room] then
            return
        end
        local entry = { connections = {}, promptConnections = {}, pending = false }
        rooms[room] = entry
        local function scheduleRefresh()
            if entry.pending then
                return
            end
            entry.pending = true
            task.defer(function()
                entry.pending = false
                guarded(function()
                    if alive and rooms[room] == entry then
                        refreshRoom(room)
                    end
                end)
            end)
        end
        table.insert(entry.connections, room.DescendantAdded:Connect(scheduleRefresh))
        table.insert(entry.connections, room.DescendantRemoving:Connect(scheduleRefresh))
        refreshRoom(room)
    end

    local function bindRooms(folder)
        if roomFolder == folder then
            return
        end
        disconnectAll(roomFolderConnections)
        for room in pairs(rooms) do
            removeRoom(room)
        end
        roomFolder = folder
        if not folder then
            return
        end
        for _, room in ipairs(folder:GetChildren()) do
            addRoom(room)
        end
        table.insert(roomFolderConnections, folder.ChildAdded:Connect(function(room)
            guarded(function()
                addRoom(room)
            end)
        end))
        table.insert(roomFolderConnections, folder.ChildRemoved:Connect(function(room)
            guarded(function()
                removeRoom(room)
            end)
        end))
    end

    local function addBox(object)
        if object.Name:match("^OfudaBox%d+$") then
            boxes[object] = true
        end
    end

    local function restoreHold(prompt)
        local original = originalHolds[prompt]
        if original ~= nil then
            pcall(function()
                if prompt.Parent and prompt.HoldDuration == 0 then
                    prompt.HoldDuration = original
                end
            end)
            originalHolds[prompt] = nil
        end
    end

    local function removeKey(key)
        local entry = keys[key]
        if not entry then
            return
        end
        if entry.prompt then
            restoreHold(entry.prompt)
        end
        disconnectAll(entry.connections)
        keys[key] = nil
    end

    local function addKey(key)
        if key.Name ~= "Key" or keys[key] then
            return
        end
        local entry = { connections = {}, pending = false }
        keys[key] = entry
        local function refreshPrompt()
            local point = key:FindFirstChild("InteractPoint")
            local prompt = point and point:FindFirstChild("ItemInteractP")
            if prompt and not prompt:IsA("ProximityPrompt") then
                prompt = nil
            end
            if entry.prompt and entry.prompt ~= prompt then
                restoreHold(entry.prompt)
            end
            entry.prompt = prompt
        end
        local function scheduleRefresh()
            if entry.pending then
                return
            end
            entry.pending = true
            task.defer(function()
                entry.pending = false
                guarded(function()
                    if alive and keys[key] == entry then
                        refreshPrompt()
                    end
                end)
            end)
        end
        table.insert(entry.connections, key.DescendantAdded:Connect(scheduleRefresh))
        table.insert(entry.connections, key.DescendantRemoving:Connect(scheduleRefresh))
        refreshPrompt()
    end

    local function addItem(item)
        addBox(item)
        addKey(item)
    end

    local function bindItems(folder)
        if itemFolder == folder then
            return
        end
        disconnectAll(itemFolderConnections)
        table.clear(boxes)
        for key in pairs(keys) do
            removeKey(key)
        end
        itemFolder = folder
        if not folder then
            return
        end
        for _, item in ipairs(folder:GetChildren()) do
            addItem(item)
        end
        table.insert(itemFolderConnections, folder.ChildAdded:Connect(function(item)
            guarded(function()
                addItem(item)
            end)
        end))
        table.insert(itemFolderConnections, folder.ChildRemoved:Connect(function(item)
            guarded(function()
                boxes[item] = nil
                removeKey(item)
            end)
        end))
    end

    local function refreshPaths()
        local client = Workspace:FindFirstChild("Client")
        local mirror = client and client:FindFirstChild("Mirror")
        bindRooms(mirror and mirror:FindFirstChild("Rooms"))
        local server = Workspace:FindFirstChild("Server")
        bindItems(server and server:FindFirstChild("SpawnedItems"))
    end

    local function runCallback(callback)
        return function(...)
            local ok, err = pcall(callback, ...)
            if not ok then
                notify("Lỗi: " .. tostring(err))
            end
        end
    end

    local Teleport = Main:AddSection("Teleport")

    Teleport:AddButton({
        Title = "Teleport To Safe",
        Callback = runCallback(function()
            refreshPaths()
            local _, root = characterRoot()
            local safes = {}
            for _, entry in pairs(rooms) do
                if entry.safe and entry.safe.Parent then
                    safes[entry.safe] = true
                end
            end
            local safe = nearest(safes, root)
            if not safe then
                error("Không tìm thấy Safe trong các Room đã tải.")
            end
            teleportTo(safe)
        end)
    })

    Teleport:AddButton({
        Title = "Teleport To Ofuda Box",
        Callback = runCallback(function()
            refreshPaths()
            local _, root = characterRoot()
            local box = nearest(boxes, root)
            if not box then
                error("Không tìm thấy Ofuda Box trong SpawnedItems.")
            end
            teleportTo(box)
        end)
    })

    Teleport:AddButton({
        Title = "Teleport To Key",
        Callback = runCallback(function()
            refreshPaths()
            local _, root = characterRoot()
            local available = {}
            for key in pairs(keys) do
                if key.Parent then
                    available[key] = true
                end
            end
            local key = nearest(available, root)
            if not key then
                error("Không tìm thấy Key trong SpawnedItems.")
            end
            teleportTo(key)
        end)
    })

    local Aura = Main:AddSection("Aura")
    local autoKeyToggle
    autoKeyToggle = Aura:AddToggle("AutoCollectKey", {
        Title = "Auto Collect Key",
        Default = false,
        Callback = runCallback(function(value)
            if value and type(fireproximityprompt) ~= "function" then
                notify("Executor không hỗ trợ fireproximityprompt.")
                if autoKeyToggle then
                    autoKeyToggle:SetValue(false)
                end
                return
            end
            autoCollectKey = value
            if not value then
                for prompt in pairs(originalHolds) do
                    restoreHold(prompt)
                end
                return
            end
            refreshPaths()
            local found = false
            for _, entry in pairs(keys) do
                if entry.prompt and entry.prompt.Parent then
                    found = true
                    break
                end
            end
            if not found then
                notify("Chưa tìm thấy ItemInteractP của Key; sẽ tiếp tục chờ.")
            end
        end)
    })

    local Other = Main:AddSection("Khác")

    Other:AddButton({
        Title = "Show Hint Paper",
        Callback = runCallback(function()
            refreshPaths()
            local labels = {}
            local papers = {}
            for _, entry in pairs(rooms) do
                if entry.hint and entry.hint.Parent and entry.paper and entry.paper.Parent then
                    labels[entry.paper] = entry.hint
                    papers[entry.paper] = true
                end
            end
            local player = Players.LocalPlayer
            local character = player and player.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            local paper = root and nearest(papers, root) or nil
            if not paper then
                paper = next(papers)
            end
            local label = paper and labels[paper]
            if not label then
                error("Không tìm thấy HintPaper hoặc TextLabel trong các Room đã tải.")
            end
            if label.Text == "" then
                error("Hint Paper không có nội dung.")
            end
            notify(label.Text, 25)
        end)
    })

    local oldLogo = CoreGui:FindFirstChild("NexusLogoGui")
    if oldLogo then
        oldLogo:Destroy()
    end

    local logoGui = Instance.new("ScreenGui")
    logoGui.Name = "NexusLogoGui"
    logoGui.ResetOnSpawn = false
    logoGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    logoGui.DisplayOrder = 10000
    logoGui.Parent = CoreGui

    local logo = Instance.new("ImageButton")
    logo.Name = "Logo"
    logo.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    logo.BackgroundTransparency = 0.5
    logo.Position = UDim2.new(0.1, 0, 0.1, 0)
    logo.Size = UDim2.fromOffset(50, 50)
    logo.Active = true
    logo.Draggable = true
    logo.Image = "rbxassetid://13347535978"
    logo.Parent = logoGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = logo

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(255, 255, 255)
    stroke.Thickness = 1
    stroke.Transparency = 0.5
    stroke.Parent = logo

    task.spawn(function()
        local ok, asset = pcall(function()
            if type(isfile) ~= "function" or type(writefile) ~= "function" or type(getcustomasset) ~= "function" then
                return nil
            end
            local fileName = "NexusLogo_ATx.png"
            if not isfile(fileName) then
                writefile(fileName, game:HttpGet("https://raw.githubusercontent.com/nguyennhlat2004/Roblox-Api/main/ATx.png"))
            end
            return getcustomasset(fileName)
        end)
        if ok and asset and alive and logo.Parent then
            logo.Image = asset
        end
    end)

    logo.MouseButton1Click:Connect(runCallback(function()
        Window:Minimize()
    end))

    if env then
        env.PetapetaCleanup = function()
            alive = false
            disconnectAll(roomFolderConnections)
            disconnectAll(itemFolderConnections)
            for room in pairs(rooms) do
                removeRoom(room)
            end
            for key in pairs(keys) do
                removeKey(key)
            end
            for prompt in pairs(originalHolds) do
                restoreHold(prompt)
            end
            table.clear(boxes)
            pcall(function()
                logoGui:Destroy()
            end)
            pcall(function()
                Fluent:Destroy()
            end)
        end
    end

    Window:SelectTab(1)
    Window:Minimize()
    guarded(refreshPaths)
    task.spawn(function()
        while alive do
            guarded(refreshPaths)
            task.wait(2)
        end
    end)
    task.spawn(function()
        while alive do
            if autoCollectKey then
                guarded(function()
                    local _, root = characterRoot()
                    for _, entry in pairs(keys) do
                        local prompt = entry.prompt
                        if prompt and prompt.Parent then
                            guarded(function()
                                if originalHolds[prompt] == nil then
                                    originalHolds[prompt] = prompt.HoldDuration
                                end
                                if prompt.HoldDuration ~= 0 then
                                    prompt.HoldDuration = 0
                                end
                                local holder = prompt.Parent
                                local position
                                if holder:IsA("Attachment") then
                                    position = holder.WorldPosition
                                else
                                    local cf = findPosition(holder)
                                    position = cf and cf.Position
                                end
                                if not position then
                                    error("Không tìm thấy vị trí ItemInteractP của Key.")
                                end
                                if prompt.Enabled and (position - root.Position).Magnitude <= prompt.MaxActivationDistance then
                                    fireproximityprompt(prompt)
                                end
                            end)
                        end
                    end
                end)
            end
            task.wait(0.2)
        end
    end)
    notify("Đã tải. Nhấn logo để mở giao diện.")
end)

if not initialized then
    notify("Không thể khởi tạo: " .. tostring(initError), 8)
end
