local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local Camera = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer

local CONFIG_FILE = "Nexus Stella - Door.json"
local isDirty = false

local DefaultStates = {
    Key = false, Door = false, Book = false, Coins = false,
    Lever = false, Items = false, ChestBox = false, Fuse = false, FullBright = false,
    BoostSpeed = false, RestoreCam = false, CamSensitivity = 50, CamDist = 10,
    FigureESP = false, PlayerESP = false, InstantInteract = false,

    RushESP = false, AmbushESP = false,

    NotifyEntity = false,
    NotifyTargets = { Rush = true, Ambush = true, Figure = true },
    AutoOpenDoor = false, AutoCollectBook = false,
    AutoCollectCoins = false, AutoCollectKey = false, AutoCollectItems = false,
    AutoCollectFuse = false, AutoCollectLever = false, AutoLootChest = "None",
    AutoSave = false
}

local Cache = {
    Items = {},
    States = {}
}

for k, v in pairs(DefaultStates) do
    Cache.States[k] = v
end

local function LoadConfig()
    if readfile and isfile and isfile(CONFIG_FILE) then
        local success, result = pcall(function()
            return HttpService:JSONDecode(readfile(CONFIG_FILE))
        end)
        if success and type(result) == "table" then
            for k, v in pairs(result) do
                if Cache.States[k] ~= nil then
                    Cache.States[k] = v
                end
            end
        end
    end
end

local function SaveConfig()
    if writefile then
        pcall(function()
            writefile(CONFIG_FILE, HttpService:JSONEncode(Cache.States))
        end)
    end
end

LoadConfig()

task.spawn(function()
    while task.wait(2) do
        if Cache.States.AutoSave and isDirty then
            SaveConfig()
            isDirty = false
        end
    end
end)

pcall(function()
    game:BindToClose(function()
        if Cache.States.AutoSave and isDirty then
            SaveConfig()
        end
    end)
end)

local CurrentRooms
do
    local ok, res = pcall(function() return workspace:WaitForChild("CurrentRooms", 10) end)
    if ok then CurrentRooms = res end
    if not CurrentRooms then CurrentRooms = workspace:FindFirstChild("CurrentRooms") end
end

local RedzLib = loadstring(game:HttpGet("https://raw.githubusercontent.com/nhat0258/Redz-UI-Library/refs/heads/main/Main.lua"))()

local UserSettings
pcall(function() UserSettings = UserSettings():GetService("UserGameSettings") end)

local DefaultLighting = {
    Brightness = Lighting.Brightness,
    ClockTime = Lighting.ClockTime,
    FogEnd = Lighting.FogEnd,
    GlobalShadows = Lighting.GlobalShadows,
    OutdoorAmbient = Lighting.OutdoorAmbient
}

local WindowName = "Nexus Stella ⭐"
local Window = RedzLib:MakeWindow({
    Title = WindowName,
    SubTitle = "By nhat0258 | v2.0.8",
    Icon = "rbxassetid://13347535978",
    Theme = "Dark"
})

local MainTab = Window:MakeTab({ Name = "Main", Icon = "eye" })
local MiscTab = Window:MakeTab({ Name = "Misc", Icon = "component" })
local ConfigTab = Window:MakeTab({ Name = "Config", Icon = "file-text" })

local ESP_Folder = CoreGui:FindFirstChild("ESP_Storage") or Instance.new("Folder", CoreGui)
ESP_Folder.Name = "ESP_Storage"

local camYaw, camPitch, camDist = 0, 0, Cache.States.CamDist
local MIN_ZOOM, MAX_ZOOM = 0, 50
local AutoOpenState = { LastDoor = nil, LastWasInRange = false }

local function CreateLogo()
    if CoreGui:FindFirstChild("NexusLogoGui") then
        CoreGui:FindFirstChild("NexusLogoGui"):Destroy()
    end
    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "NexusLogoGui"
    ScreenGui.Parent = CoreGui
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    ScreenGui.DisplayOrder = 10000

    local LogoButton = Instance.new("ImageButton")
    LogoButton.Name = "Logo"
    LogoButton.Parent = ScreenGui
    LogoButton.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    LogoButton.BackgroundTransparency = 0.5
    LogoButton.Position = UDim2.new(0.1, 0, 0.1, 0)
    LogoButton.Size = UDim2.new(0, 50, 0, 50)
    LogoButton.Active = true
    LogoButton.Draggable = true

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
            if not isfile(fileName) then writefile(fileName, game:HttpGet(url)) end
            return getcustomasset(fileName)
        end)
        LogoButton.Image = (ok and imgAsset) or "rbxassetid://13347535978"
    end)

    LogoButton.MouseButton1Click:Connect(function()
        for _, gui in pairs(CoreGui:GetChildren()) do
            if gui:IsA("ScreenGui") and gui.Name ~= "NexusLogoGui" and gui.Name ~= "RobloxGui" then
                for _, desc in pairs(gui:GetDescendants()) do
                    if desc:IsA("TextLabel") and desc.Text == WindowName then
                        gui.Enabled = not gui.Enabled
                        return
                    end
                end
            end
        end
    end)
end
CreateLogo()

local function IsDoorLocked(doorModel)
    if not doorModel or not doorModel:IsA("Model") then return false end
    local doorPart = doorModel:FindFirstChild("Door")
    local lockPart = doorModel:FindFirstChild("Lock")
    if not doorPart or not lockPart then return false end
    if not doorPart:IsA("MeshPart") or not lockPart:IsA("MeshPart") then return false end
    return true
end

local function IsHiddenName(n)
    return typeof(n) == "string" and (n == "Hidden" or n:find("Hidden"))
end

local function GetAnchorPart(inst)
    if not inst then return nil end
    if inst:IsA("BasePart") then return inst end
    if inst:IsA("Model") then
        return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart")
    end
    local p = inst.Parent
    if p and p:IsA("BasePart") then return p end
    return nil
end

local function FindItemInInventory(matchFn)
    local char = LocalPlayer.Character
    if char then
        for _, t in ipairs(char:GetChildren()) do
            if t:IsA("Tool") and matchFn(t.Name) then return t, true end
        end
    end
    local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") and matchFn(t.Name) then return t, false end
        end
    end
    return nil, false
end

local function GetLockpick()
    local char = LocalPlayer.Character
    if char then
        local t = char:FindFirstChild("Lockpick")
        if t and t:IsA("Tool") then return t, true end
    end
    local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
    if bp then
        local t = bp:FindFirstChild("Lockpick")
        if t and t:IsA("Tool") then return t, false end
    end
    return nil, false
end

local function EquipTool(tool)
    if not tool then return false end
    local char = LocalPlayer.Character
    if not char then return false end
    if tool.Parent == char then return true end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    pcall(function() hum:EquipTool(tool) end)
    return tool.Parent == char
end

workspace.DescendantAdded:Connect(function(obj)
    if Cache.States.InstantInteract and obj:IsA("ProximityPrompt") then
        obj.HoldDuration = 0
    end
end)

local function CreateHighlight(adornee, color, parent)
    local highlight = Instance.new("Highlight")
    highlight.Adornee = adornee
    highlight.FillColor = color
    highlight.OutlineColor = color
    highlight.FillTransparency = 0.5
    highlight.OutlineTransparency = 0
    pcall(function() highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop end)
    highlight.Parent = parent
    return highlight
end

local function CreateLabel(instance, text, color, anchorPart)
    if not instance or Cache.Items[instance] then return end
    local targetPart
    if anchorPart and anchorPart:IsA("BasePart") and anchorPart.Parent then
        targetPart = anchorPart
    elseif instance:IsA("BasePart") then
        targetPart = instance
    elseif instance:IsA("Model") then

        targetPart = instance:FindFirstChild("HumanoidRootPart")
            or instance.PrimaryPart
            or instance:FindFirstChildWhichIsA("BasePart")
    else
        targetPart = GetAnchorPart(instance)
    end
    if not targetPart then return end

    local hls = {}
    table.insert(hls, CreateHighlight(instance, color, ESP_Folder))

    local billboard = Instance.new("BillboardGui")
    billboard.Adornee = targetPart
    billboard.Size = UDim2.new(0, 100, 0, 50)
    billboard.StudsOffset = Vector3.new(0, 2, 0)
    billboard.AlwaysOnTop = true
    billboard.LightInfluence = 0
    billboard.MaxDistance = 0
    billboard.ResetOnSpawn = false
    billboard.Parent = ESP_Folder

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = color
    label.TextStrokeTransparency = 0.5
    label.TextStrokeColor3 = Color3.new(0, 0, 0)
    label.TextSize = 14
    label.Font = Enum.Font.FredokaOne
    label.Parent = billboard

    local line = nil
    if Drawing and Drawing.new then
        pcall(function()
            line = Drawing.new("Line")
            line.Thickness = 1
            line.Color = color
            line.Transparency = 1
            line.Visible = false
        end)
    end

    Cache.Items[instance] = {
        Billboard = billboard, Highlights = hls, Line = line,
        Part = targetPart, Instance = instance, Text = text, Color = color
    }
end

local function RemoveESP(instance)
    if Cache.Items[instance] then
        local d = Cache.Items[instance]
        pcall(function()
            if d.Billboard then d.Billboard:Destroy() end
            if d.Highlights then for _, h in ipairs(d.Highlights) do pcall(h.Destroy, h) end end
            if d.Line then d.Line:Remove() end
        end)
        Cache.Items[instance] = nil
    end
end

workspace.DescendantRemoving:Connect(function(obj)
    if Cache.Items[obj] then
        RemoveESP(obj)
    end
end)

if CurrentRooms then
    CurrentRooms.ChildRemoved:Connect(function(room)
        for inst, data in pairs(Cache.Items) do
            if data.Part and (data.Part == room or data.Part:IsDescendantOf(room)) then
                RemoveESP(inst)
            end
        end
    end)
end

local function ProcessItem(obj, roomNum)
    if not obj or not obj.Parent then return end

    pcall(function()
        if obj.Name == "KeyObtain" and Cache.States.Key then
            CreateLabel(obj, "Key " .. roomNum, Color3.fromRGB(0,255,0))
        elseif obj.Name == "LiveHintBook" and Cache.States.Book then
            CreateLabel(obj, "Book", Color3.fromRGB(0,150,255))
        elseif obj.Name == "GoldPile" and Cache.States.Coins then
            CreateLabel(obj, "Coins", Color3.fromRGB(255,255,0))
        elseif obj.Name == "LeverForGate" and Cache.States.Lever then
            CreateLabel(obj, "Lever", Color3.fromRGB(255,255,255))
        elseif obj.Name == "LiveBreakerPolePickup" and Cache.States.Fuse then
            CreateLabel(obj, "Fuse", Color3.fromRGB(0, 150, 255))
        elseif (obj.Name == "ChestBox" or obj.Name == "ChestBoxLocked") and Cache.States.ChestBox then
            local text = (obj.Name == "ChestBoxLocked") and "Chest Box | Locked" or "Chest Box"
            CreateLabel(obj, text, Color3.fromRGB(255, 255, 0))
        elseif Cache.States.Items and ({Vitamins=1, Bandage=1, Battery=1, Candle=1, Flashlight=1, Lockpick=1, Smoothie=1})[obj.Name] then
            CreateLabel(obj, obj.Name, Color3.fromRGB(255,128,0))
        end
    end)
end

local DOOR_COLOR = Color3.fromRGB(160, 32, 240)

local function FollowPath(root, chain)
    local cur = root
    for _, name in ipairs(chain) do
        if not cur then return nil end
        local ok, child = pcall(function() return cur:FindFirstChild(name) end)
        if not ok then return nil end
        cur = child
    end
    return cur
end

local function ResolveDoorTarget(room)
    if not room or not room.Parent then return nil, nil end

    local doorModel = room:FindFirstChild("Door")

    local part = FollowPath(room, {"Door", "Door"})
    if part and part:IsA("BasePart") then
        return part, (doorModel and doorModel:IsA("Model")) and doorModel or part.Parent
    end

    local frame = FollowPath(room, {"Parts", "Start_DoorFrame"})
    if not frame then frame = FollowPath(room, {"Door", "Parts", "Start_DoorFrame"}) end
    if frame and frame:IsA("BasePart") then
        return frame, (doorModel and doorModel:IsA("Model")) and doorModel or frame.Parent
    end

    if doorModel then
        if doorModel:IsA("BasePart") then return doorModel, doorModel end
        local any = doorModel.PrimaryPart or doorModel:FindFirstChildWhichIsA("BasePart")
        if any then return any, doorModel end
    end
    return nil, nil
end

local function DoorText(doorModel, roomName)
    local locked = false
    if doorModel and doorModel:IsA("Model") then
        locked = IsDoorLocked(doorModel)
    end
    return locked and ("Door " .. roomName .. " | Locked") or ("Door " .. roomName)
end

local function ESPDoor(room, force)
    if not room or not room.Parent then return end
    local part, model = ResolveDoorTarget(room)
    if not part then return end
    local key = model or part
    local desired = DoorText(model, room.Name)
    local d = Cache.Items[key]

    if not d then
        CreateLabel(key, desired, DOOR_COLOR, part)
    elseif d.Text ~= desired or d.Part ~= part then
        RemoveESP(key)
        CreateLabel(key, desired, DOOR_COLOR, part)
    end
end

local function CheckRoom(room)
    local roomNum = room.Name

    for _, obj in ipairs(room:GetDescendants()) do
        ProcessItem(obj, roomNum)
    end

    room.DescendantAdded:Connect(function(obj)
        task.wait(0.2)
        ProcessItem(obj, roomNum)
    end)

    if Cache.States.Door then
        task.spawn(function()
            for _ = 1, 12 do
                if not room.Parent or not Cache.States.Door then return end
                local part, model = ResolveDoorTarget(room)
                if part then
                    ESPDoor(room)
                    if Cache.Items[model or part] then return end
                end
                task.wait(0.25)
            end
        end)
    end
end

if CurrentRooms then
    CurrentRooms.ChildAdded:Connect(function(room)
        task.spawn(function() pcall(CheckRoom, room) end)
    end)
end

local function RefreshAll()
    for i, _ in pairs(Cache.Items) do
        RemoveESP(i)
    end
    if CurrentRooms then
        for _, r in ipairs(CurrentRooms:GetChildren()) do
            task.spawn(function() pcall(CheckRoom, r) end)
        end
    end
end

task.spawn(function()
    while task.wait(0.5) do
        if Cache.States.Door and CurrentRooms then
            for _, room in ipairs(CurrentRooms:GetChildren()) do
                pcall(ESPDoor, room)
            end
        end
    end
end)

local function GetNotifyGui()
    local gui = CoreGui:FindFirstChild("NexusNotifyGui")
    if gui and gui:FindFirstChild("List") then return gui end
    if gui then gui:Destroy() end

    gui = Instance.new("ScreenGui")
    gui.Name = "NexusNotifyGui"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.DisplayOrder = 9999
    gui.Parent = CoreGui

    local list = Instance.new("Frame")
    list.Name = "List"
    list.BackgroundTransparency = 1
    list.AnchorPoint = Vector2.new(1, 1)
    list.Position = UDim2.new(1, -20, 1, -20)
    list.Size = UDim2.new(0, 320, 1, -40)
    list.Parent = gui

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 8)
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
    layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = list

    return gui
end

local NotifyOrder = 0
local function ShowNotification(title, message, color)
    local gui = GetNotifyGui()
    local list = gui:FindFirstChild("List")
    if not list then return end

    NotifyOrder = NotifyOrder + 1
    local accent = color or Color3.fromRGB(255, 255, 255)

    local card = Instance.new("Frame")
    card.Name = "Notification"
    card.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
    card.BackgroundTransparency = 0.1
    card.BorderSizePixel = 0
    card.Size = UDim2.new(1, 0, 0, 62)
    card.Position = UDim2.new(1, 60, 0, 0)
    card.LayoutOrder = NotifyOrder
    card.ClipsDescendants = true
    card.Parent = list

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = card

    local stroke = Instance.new("UIStroke")
    stroke.Color = accent
    stroke.Thickness = 1
    stroke.Transparency = 0.35
    stroke.Parent = card

    local bar = Instance.new("Frame")
    bar.BackgroundColor3 = accent
    bar.BorderSizePixel = 0
    bar.Size = UDim2.new(0, 4, 1, 0)
    bar.Parent = card

    local titleLabel = Instance.new("TextLabel")
    titleLabel.BackgroundTransparency = 1
    titleLabel.Position = UDim2.new(0, 16, 0, 8)
    titleLabel.Size = UDim2.new(1, -28, 0, 18)
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextSize = 14
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.TextColor3 = accent
    titleLabel.Text = title
    titleLabel.Parent = card

    local msgLabel = Instance.new("TextLabel")
    msgLabel.BackgroundTransparency = 1
    msgLabel.Position = UDim2.new(0, 16, 0, 28)
    msgLabel.Size = UDim2.new(1, -28, 0, 26)
    msgLabel.Font = Enum.Font.GothamMedium
    msgLabel.TextSize = 16
    msgLabel.TextWrapped = true
    msgLabel.TextXAlignment = Enum.TextXAlignment.Left
    msgLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    msgLabel.Text = message
    msgLabel.Parent = card

    card.Position = UDim2.new(1, 60, 0, 0)
    task.spawn(function()
        pcall(function()
            TweenService:Create(card, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = UDim2.new(0, 0, 0, 0)}):Play()
        end)
    end)

    task.delay(5, function()
        pcall(function()
            TweenService:Create(card, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Position = UDim2.new(1, 60, 0, 0)}):Play()
        end)
        task.wait(0.3)
        if card and card.Parent then card:Destroy() end
    end)
end

local EntityDefs = {
    Rush = {
        Display = "Rush",
        Message = "Rush Is Comming !",
        Color = Color3.fromRGB(255, 55, 55),
        State = "RushESP"
    },
    Ambush = {
        Display = "Ambush",
        Message = "Ambush Is Comming !",
        Color = Color3.fromRGB(255, 140, 0),
        State = "AmbushESP"
    },
    Figure = {
        Display = "Figure",
        Message = "Figure Is Comming !",
        Color = Color3.fromRGB(255, 0, 90),
        State = "FigureESP"
    }
}

local EntityPaths = {
    Rush = { "RushMoving", "RushNew", "RushEntity" },
    Ambush = { "AmbushMoving", "AmbushNew", "AmbushEntity" },
    Figure = { "FigureRig", "FigureSetup" }
}

local function FindEntityRoot(name)
    for _, candidate in ipairs(EntityPaths[name] or {}) do
        local found = workspace:FindFirstChild(candidate, true)
        if found then return found, candidate end
    end
    return nil, nil
end

local function GetEntityInstances(name)
    local list = {}
    local found, candidate = FindEntityRoot(name)
    if found then
        if candidate == "FigureSetup" then
            found = found:FindFirstChild("FigureRig") or found:FindFirstChildWhichIsA("Model", true) or found
        end
        table.insert(list, found)
    end
    return list
end

local EntityPresence = { Rush = false, Ambush = false, Figure = false }

local function IsNotifyEnabled(name)
    if not Cache.States.NotifyEntity then return false end
    local targets = Cache.States.NotifyTargets
    if type(targets) ~= "table" then return false end
    return targets[name] == true
end

task.spawn(function()
    while task.wait(0.2) do
        for name, def in pairs(EntityDefs) do
            local instances = GetEntityInstances(name)
            local present = #instances > 0

            if present and Cache.States[def.State] then
                for _, inst in ipairs(instances) do
                    if not Cache.Items[inst] then
                        pcall(CreateLabel, inst, def.Display, def.Color)
                    end
                end
            end

            if present and not EntityPresence[name] then
                EntityPresence[name] = true
                if IsNotifyEnabled(name) then
                    ShowNotification("Nexus Notification ⭐", def.Message, def.Color)
                end
            elseif not present and EntityPresence[name] then
                EntityPresence[name] = false
            end
        end
    end
end)

local function updateCameraState()
    if not Cache.States.RestoreCam then return end
    Camera.CameraType = (camDist <= 0) and Enum.CameraType.Custom or Enum.CameraType.Scriptable
end

MainTab:AddSection({ Name = "ESP Object" })
MainTab:AddToggle({ Name = "ESP Key", Default = Cache.States.Key, Callback = function(v) Cache.States.Key = v; isDirty = true; RefreshAll() end })
MainTab:AddToggle({ Name = "ESP Door", Default = Cache.States.Door, Callback = function(v) Cache.States.Door = v; isDirty = true; RefreshAll() end })
MainTab:AddToggle({ Name = "ESP Book", Default = Cache.States.Book, Callback = function(v) Cache.States.Book = v; isDirty = true; RefreshAll() end })
MainTab:AddToggle({ Name = "ESP Coins", Default = Cache.States.Coins, Callback = function(v) Cache.States.Coins = v; isDirty = true; RefreshAll() end })
MainTab:AddToggle({ Name = "ESP Lever", Default = Cache.States.Lever, Callback = function(v) Cache.States.Lever = v; isDirty = true; RefreshAll() end })
MainTab:AddToggle({ Name = "ESP Fuse", Default = Cache.States.Fuse, Callback = function(v) Cache.States.Fuse = v; isDirty = true; RefreshAll() end })
MainTab:AddToggle({ Name = "ESP Chest Box", Default = Cache.States.ChestBox, Callback = function(v) Cache.States.ChestBox = v; isDirty = true; RefreshAll() end })
MainTab:AddToggle({ Name = "ESP Items", Default = Cache.States.Items, Callback = function(v) Cache.States.Items = v; isDirty = true; RefreshAll() end })

MainTab:AddSection({ Name = "ESP Entity" })
MainTab:AddToggle({ Name = "ESP Rush", Desc = "workspace.RushMoving", Default = Cache.States.RushESP, Callback = function(v) Cache.States.RushESP = v; isDirty = true; RefreshAll() end })
MainTab:AddToggle({ Name = "ESP Ambush", Desc = "workspace.AmbushMoving", Default = Cache.States.AmbushESP, Callback = function(v) Cache.States.AmbushESP = v; isDirty = true; RefreshAll() end })
MainTab:AddToggle({ Name = "ESP Figure", Default = Cache.States.FigureESP, Callback = function(v) Cache.States.FigureESP = v; isDirty = true; RefreshAll() end })
MainTab:AddToggle({ Name = "ESP Player", Default = Cache.States.PlayerESP, Callback = function(v) Cache.States.PlayerESP = v; isDirty = true; RefreshAll() end })

MainTab:AddSection({ Name = "Notification Entity" })
MainTab:AddToggle({ Name = "Notify Entity", Default = Cache.States.NotifyEntity, Callback = function(v)
    Cache.States.NotifyEntity = v
    isDirty = true
    if v then
        for name, def in pairs(EntityDefs) do
            if IsNotifyEnabled(name) and #GetEntityInstances(name) > 0 then
                ShowNotification("Nexus Notification ⭐", def.Message, def.Color)
            end
        end
    end
end })

local EntityOptionSet = { Rush = true, Ambush = true, Figure = true }

local function BuildTargets(source)
    local t = { Rush = false, Ambush = false, Figure = false }
    if type(source) ~= "table" then return t end
    for name, value in pairs(source) do
        if type(name) == "string" and t[name] ~= nil then
            if value then t[name] = true end
        elseif type(name) == "number" and type(value) == "string" and t[value] ~= nil then
            t[value] = true
        end
    end
    return t
end

local function GetTargetDefaults()
    local saved = Cache.States.NotifyTargets
    local out = {}
    local any = false
    if type(saved) == "table" then
        for name, value in pairs(EntityOptionSet) do
            if saved[name] then out[name] = true; any = true end
        end
    end
    if not any then
        for name in pairs(EntityOptionSet) do out[name] = true end
    end
    return out
end

local notifyDropdownInit = true

local NotifyDropdown = MainTab:AddDropdown({
    Name = "Select Entity",
    Desc = "Rush / Ambush / Figure",
    Options = EntityOptionSet,
    Default = GetTargetDefaults(),
    MultiSelect = true,
    Callback = function(selected)
        if notifyDropdownInit then
            notifyDropdownInit = false
            return
        end
        Cache.States.NotifyTargets = BuildTargets(selected)
        isDirty = true
    end
})

MainTab:AddButton({
    Name = "Test Notify",
    Callback = function()
        for name, def in pairs(EntityDefs) do
            if IsNotifyEnabled(name) then
                ShowNotification("Nexus Notification ⭐", def.Message, def.Color)
                return
            end
        end
        ShowNotification("Nexus Notification ⭐", "Rush Is Comming !", Color3.fromRGB(255, 55, 55))
    end
})

MainTab:AddToggle({ Name = "Full Bright", Default = Cache.States.FullBright, Callback = function(v)
    Cache.States.FullBright = v
    isDirty = true
    if v then
        DefaultLighting.Brightness = Lighting.Brightness
        DefaultLighting.ClockTime = Lighting.ClockTime
        DefaultLighting.FogEnd = Lighting.FogEnd
        DefaultLighting.GlobalShadows = Lighting.GlobalShadows
        DefaultLighting.OutdoorAmbient = Lighting.OutdoorAmbient
    else
        task.wait()
        Lighting.Brightness = DefaultLighting.Brightness
        Lighting.ClockTime = DefaultLighting.ClockTime
        Lighting.FogEnd = DefaultLighting.FogEnd
        Lighting.GlobalShadows = DefaultLighting.GlobalShadows
        Lighting.OutdoorAmbient = DefaultLighting.OutdoorAmbient
    end
end })

local DefaultSpeedBoost
do
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    pcall(function() DefaultSpeedBoost = char:GetAttribute("SpeedBoost") end)
end

MiscTab:AddToggle({ Name = "Boost Speed", Default = Cache.States.BoostSpeed, Callback = function(v)
    Cache.States.BoostSpeed = v
    isDirty = true
    if not v then
        local char = LocalPlayer.Character
        if char then
            pcall(function() char:SetAttribute("SpeedBoost", DefaultSpeedBoost) end)
        end
    end
end })
MiscTab:AddToggle({ Name = "Auto Open Door", Default = Cache.States.AutoOpenDoor, Callback = function(v) Cache.States.AutoOpenDoor = v; isDirty = true; AutoOpenState.LastDoor = nil; AutoOpenState.LastWasInRange = false end })
MiscTab:AddToggle({ Name = "Auto Collect Book", Default = Cache.States.AutoCollectBook, Callback = function(v) Cache.States.AutoCollectBook = v; isDirty = true end })
MiscTab:AddToggle({ Name = "Auto Collect Coins", Default = Cache.States.AutoCollectCoins, Callback = function(v) Cache.States.AutoCollectCoins = v; isDirty = true end })
MiscTab:AddToggle({ Name = "Auto Collect Key", Default = Cache.States.AutoCollectKey, Callback = function(v) Cache.States.AutoCollectKey = v; isDirty = true end })
MiscTab:AddToggle({ Name = "Auto Collect Items", Default = Cache.States.AutoCollectItems, Callback = function(v) Cache.States.AutoCollectItems = v; isDirty = true end })
MiscTab:AddToggle({ Name = "Auto Collect Fuse", Default = Cache.States.AutoCollectFuse, Callback = function(v) Cache.States.AutoCollectFuse = v; isDirty = true end })
MiscTab:AddToggle({ Name = "Auto Lever", Default = Cache.States.AutoCollectLever, Callback = function(v) Cache.States.AutoCollectLever = v; isDirty = true end })

MiscTab:AddDropdown({
    Name = "Auto Loot Chest Box",
    Options = {"None", "Chest Box", "Chest Box Locked", "All"},
    Default = Cache.States.AutoLootChest,
    Callback = function(v) Cache.States.AutoLootChest = v; isDirty = true end
})

MiscTab:AddToggle({ Name = "Instant Interaction", Default = Cache.States.InstantInteract, Callback = function(v)
    Cache.States.InstantInteract = v
    isDirty = true
    if v and CurrentRooms then
        for _, obj in pairs(CurrentRooms:GetDescendants()) do
            if obj:IsA("ProximityPrompt") then obj.HoldDuration = 0 end
        end
    end
end })

MiscTab:AddToggle({ Name = "Restore Cam", Default = Cache.States.RestoreCam, Callback = function(v)
    Cache.States.RestoreCam = v
    isDirty = true
    if v then
        camYaw = 0
        updateCameraState()
    else
        Camera.CameraType = Enum.CameraType.Custom
        Camera.FieldOfView = 70
    end
end })

MiscTab:AddSlider({ Name = "Cam Sensitivity", Min = 1, Max = 100, Default = Cache.States.CamSensitivity, Callback = function(v) Cache.States.CamSensitivity = v; isDirty = true end })
MiscTab:AddSlider({ Name = "Zoom Distance", Min = 0, Max = 50, Default = Cache.States.CamDist, Callback = function(v)
    Cache.States.CamDist = v
    camDist = v
    isDirty = true
    updateCameraState()
end })

MiscTab:AddButton({ Name = "Drop Items", Callback = function()
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.X, false, game)
    task.wait(0.05)
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.X, false, game)
end })

ConfigTab:AddToggle({
    Name = "Auto Save Config",
    Default = Cache.States.AutoSave,
    Callback = function(v)
        Cache.States.AutoSave = v
        isDirty = true
    end
})

ConfigTab:AddButton({
    Name = "Save Config Now",
    Callback = function()
        SaveConfig()
        isDirty = false
    end
})

ConfigTab:AddButton({
    Name = "Reset Config",
    Callback = function()
        if isfile and isfile(CONFIG_FILE) then
            pcall(function() delfile(CONFIG_FILE) end)
        end
        for k, v in pairs(DefaultStates) do
            Cache.States[k] = v
        end
        RefreshAll()
    end
})

UserInputService.InputChanged:Connect(function(input, processed)
    if not Cache.States.RestoreCam or processed then return end
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        if camDist > 0 then
            local sens = 0.2
            pcall(function() sens = UserSettings.MouseSensitivity end)
            local scale = ((input.UserInputType == Enum.UserInputType.Touch) and 0.15 or (sens * 0.8)) * (Cache.States.CamSensitivity / 10)
            camYaw = camYaw - input.Delta.X * scale
            camPitch = math.clamp(camPitch - input.Delta.Y * scale, -80, 80)
        end
    elseif input.UserInputType == Enum.UserInputType.MouseWheel then
        camDist = math.clamp(camDist - input.Position.Z * 2, MIN_ZOOM, MAX_ZOOM)
        Cache.States.CamDist = camDist
        isDirty = true
        updateCameraState()
    end
end)

RunService.RenderStepped:Connect(function()
    if Cache.States.FullBright then
        Lighting.Brightness = 2
        Lighting.ClockTime = 14
        Lighting.FogEnd = 100000
        Lighting.GlobalShadows = false
        Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 128)
    end

    local char = LocalPlayer.Character

    if Cache.States.BoostSpeed and char then
        pcall(function() char:SetAttribute("SpeedBoost", 3.5) end)
    end

    if Cache.States.RestoreCam and camDist > 0 then
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if root then
            local rot = CFrame.fromEulerAnglesYXZ(math.rad(camPitch), math.rad(camYaw), 0)
            Camera.CFrame = CFrame.new(root.Position + Vector3.new(0,2,0)) * rot * CFrame.new(0,0,camDist)
            root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, math.rad(camYaw), 0)
            if Camera.FieldOfView ~= 70 then Camera.FieldOfView = 70 end
        end
    end

    if Camera.FieldOfView ~= 70 then
        pcall(function() Camera.FieldOfView = 70 end)
    end

    for inst, d in pairs(Cache.Items) do
        local stillAlive = d.Instance and d.Instance.Parent
        if stillAlive then
            local anchor = d.Part
            if not anchor or not anchor.Parent then
                if d.Instance:IsA("Model") then
                    anchor = d.Instance.PrimaryPart or d.Instance:FindFirstChildWhichIsA("BasePart")
                elseif d.Instance:IsA("BasePart") then
                    anchor = d.Instance
                end
                if anchor then
                    d.Part = anchor
                    if d.Billboard then d.Billboard.Adornee = anchor end
                end
            end

            if d.Highlights then
                for _, h in ipairs(d.Highlights) do
                    if h and h.Parent then
                        if not h.Adornee or not h.Adornee.Parent then
                            h.Adornee = d.Instance
                        end
                    end
                end
            end

            if d.Billboard and (not d.Billboard.Adornee or not d.Billboard.Adornee.Parent) and anchor then
                d.Billboard.Adornee = anchor
            end

            if d.Line and anchor then
                local pos
                local ok = pcall(function() pos = anchor.Position end)
                if ok and pos then
                    local ok2, vp, onScreen = pcall(function()
                        return Camera:WorldToViewportPoint(pos)
                    end)
                    if ok2 and vp and onScreen == true then
                        local vs = Camera.ViewportSize
                        if vs and vs.X > 0 and vs.Y > 0 then
                            d.Line.From = Vector2.new(vs.X/2, vs.Y)
                            d.Line.To = Vector2.new(vp.X, vp.Y)
                            d.Line.Visible = true
                        else
                            d.Line.Visible = false
                        end
                    else
                        d.Line.Visible = false
                    end
                else
                    d.Line.Visible = false
                end
            elseif d.Line then
                d.Line.Visible = false
            end
        else
            RemoveESP(inst)
        end
    end
end)

task.spawn(function()
    while task.wait(0.5) do

        if Cache.States.PlayerESP then
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LocalPlayer and plr.Character and not Cache.Items[plr.Character] then
                    CreateLabel(plr.Character, plr.Name, Color3.fromRGB(173, 216, 230))
                end
            end
        end
    end
end)

local function GetDoorPosition(doorModel)
    local p = doorModel:FindFirstChild("Door")
    if p and p:IsA("BasePart") then return p.Position end
    if doorModel.PrimaryPart then return doorModel.PrimaryPart.Position end
    local any = doorModel:FindFirstChildWhichIsA("BasePart")
    if any then return any.Position end
    return nil
end

local function FindNearestDoor(rootPos)
    local bestRoom, bestDoor, bestDist = nil, nil, math.huge
    if not CurrentRooms then return nil, nil, math.huge end
    for _, room in ipairs(CurrentRooms:GetChildren()) do
        local door = room:FindFirstChild("Door")
        if door and door:IsA("Model") then
            local pos = GetDoorPosition(door)
            if pos then
                local dist = (rootPos - pos).Magnitude
                if dist < bestDist then
                    bestDist = dist
                    bestRoom = room
                    bestDoor = door
                end
            end
        end
    end
    return bestRoom, bestDoor, bestDist
end

local function GetKeyTool()
    local char = LocalPlayer.Character
    if char then
        local k = char:FindFirstChild("Key")
        if k then return k, true end
    end
    local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
    if bp then
        local k = bp:FindFirstChild("Key")
        if k then return k, false end
    end
    return nil, false
end

local function ForceEquipKey()
    local char = LocalPlayer.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    local keyTool, holding = GetKeyTool()
    if not keyTool then return false end
    if holding then return true end
    hum:UnequipTools()
    task.wait()
    pcall(function() hum:EquipTool(keyTool) end)
    return true
end

local function FindInteractPrompt(rootPos, maxDist)
    local bestPrompt, bestDist = nil, math.huge
    if not CurrentRooms then return nil end

    for _, obj in ipairs(CurrentRooms:GetDescendants()) do
        if obj:IsA("ProximityPrompt") and obj.ActionText == "Interact" then
            local parent = obj.Parent
            if parent and parent:IsA("BasePart") then
                local dist = (rootPos - parent.Position).Magnitude
                if dist <= maxDist and dist < bestDist then
                    bestDist = dist
                    bestPrompt = obj
                end
            end
        end
    end
    return bestPrompt
end

task.spawn(function()
    while task.wait(0.1) do
        if Cache.States.AutoOpenDoor then
            local char = LocalPlayer.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            if root then
                local room, door, dist = FindNearestDoor(root.Position)
                if door then
                    local locked = IsDoorLocked(door)
                    if locked then
                        if dist <= 17.5 then
                            local keyTool, holdingKey = GetKeyTool()
                            if not keyTool then
                                AutoOpenState.LastWasInRange = false
                            else
                                if AutoOpenState.LastDoor ~= door or not AutoOpenState.LastWasInRange then
                                    AutoOpenState.LastDoor = door
                                    AutoOpenState.LastWasInRange = true
                                    if not holdingKey then ForceEquipKey() end
                                end
                                if holdingKey then
                                    local prompt = FindInteractPrompt(root.Position, 17.5)
                                    if prompt then
                                        pcall(function() prompt.HoldDuration = 0 end)
                                        pcall(function() prompt.Enabled = true end)
                                        pcall(function() fireproximityprompt(prompt) end)
                                    end
                                else
                                    ForceEquipKey()
                                end
                            end
                        else
                            AutoOpenState.LastWasInRange = false
                        end
                    else
                        AutoOpenState.LastWasInRange = false
                        if dist <= 25 then
                            pcall(function() door.ClientOpen:FireServer() end)
                        end
                    end
                else
                    AutoOpenState.LastDoor = nil
                    AutoOpenState.LastWasInRange = false
                end
            end
        end
    end
end)

local function CleanHiddenInDoor(doorModel)
    if not doorModel then return end
    for _, child in ipairs(doorModel:GetDescendants()) do
        if IsHiddenName(child.Name) then pcall(function() child:Destroy() end) end
    end
end

local function HookDoor(doorModel)
    if not doorModel or doorModel:GetAttribute("__HiddenHooked") then return end
    doorModel:SetAttribute("__HiddenHooked", true)
    CleanHiddenInDoor(doorModel)
    doorModel.DescendantAdded:Connect(function(obj)
        if IsHiddenName(obj.Name) then pcall(function() obj:Destroy() end) end
    end)
    doorModel.DescendantRemoving:Connect(function(obj)
        if IsHiddenName(obj.Name) and obj.Parent then pcall(function() obj:Destroy() end) end
    end)
end

local function HookRoomForHidden(room)
    local door = room:FindFirstChild("Door")
    if door and door:IsA("Model") then HookDoor(door) end
    room.ChildAdded:Connect(function(child)
        if child.Name == "Door" and child:IsA("Model") then HookDoor(child) end
    end)
end

task.spawn(function()
    if not CurrentRooms then return end
    for _, room in ipairs(CurrentRooms:GetChildren()) do
        pcall(HookRoomForHidden, room)
    end
    CurrentRooms.ChildAdded:Connect(function(room)
        task.wait(0.1)
        pcall(HookRoomForHidden, room)
    end)
end)

local function ForceZeroHoldForSpecialPrompts(obj)
    if not obj or not obj:IsA("ProximityPrompt") then return end
    local parent = obj.Parent
    if not parent then return end
    if obj.Name == "ActivateEventPrompt" and parent.Name == "LiveHintBook" then
        pcall(function() obj.HoldDuration = 0 end)
        return
    end
    if obj.ActionText == "Interact" then
        local p = parent
        while p and p ~= workspace do
            if p.Name == "Door" and p:IsA("Model") and IsDoorLocked(p) then
                pcall(function() obj.HoldDuration = 0 end)
                return
            end
            p = p.Parent
        end
    end
end

if CurrentRooms then
    for _, obj in ipairs(CurrentRooms:GetDescendants()) do
        ForceZeroHoldForSpecialPrompts(obj)
    end
end

workspace.DescendantAdded:Connect(function(obj)
    task.wait(0.1)
    ForceZeroHoldForSpecialPrompts(obj)
end)

local CollectTargets = {
    LiveHintBook = "AutoCollectBook",
    GoldPile = "AutoCollectCoins",
    KeyObtain = "AutoCollectKey",
    Vitamins = "AutoCollectItems",
    Bandage = "AutoCollectItems",
    Battery = "AutoCollectItems",
    Candle = "AutoCollectItems",
    Flashlight = "AutoCollectItems",
    Lockpick = "AutoCollectItems",
    Smoothie = "AutoCollectItems",
    LiveBreakerPolePickup = "AutoCollectFuse",
    LeverForGate = "AutoCollectLever"
}

local function FireAllPromptsIn(container, rootPos)
    for _, obj in ipairs(container:GetDescendants()) do
        if obj:IsA("ProximityPrompt") then
            pcall(function() obj.HoldDuration = 0 end)
            local anchor = obj.Parent
            if anchor and not anchor:IsA("BasePart") then anchor = GetAnchorPart(anchor) end
            if anchor and anchor:IsA("BasePart") then
                local dist = (rootPos - anchor.Position).Magnitude
                local maxD = obj.MaxActivationDistance
                if maxD <= 0 then maxD = 10 end
                if dist <= maxD then
                    pcall(function() fireproximityprompt(obj) end)
                end
            end
        end
    end
end

local function TryFireCollectPrompt(target, rootPos)
    local anchor = GetAnchorPart(target)
    for _, obj in ipairs(target:GetDescendants()) do
        if obj:IsA("ProximityPrompt") then
            pcall(function() obj.HoldDuration = 0 end)
            local a = anchor or GetAnchorPart(obj)
            if a then
                local dist = (rootPos - a.Position).Magnitude
                local maxD = obj.MaxActivationDistance
                if maxD <= 0 then maxD = 10 end
                if dist <= maxD then
                    pcall(function() fireproximityprompt(obj) end)
                end
            end
        end
    end
end

local function FindEnclosingContainer(inst, names)
    local p = inst.Parent
    while p and p ~= workspace do
        for _, n in ipairs(names) do
            if p.Name == n then return p end
        end
        p = p.Parent
    end
    return nil
end

local function TryCollectKey(keyObtain, rootPos)
    local drawer = FindEnclosingContainer(keyObtain, {"DrawerContainer", "Drawer"})
    if drawer then
        local drawerAnchor = GetAnchorPart(drawer)
        if drawerAnchor then
            local distToDrawer = (rootPos - drawerAnchor.Position).Magnitude
            if distToDrawer <= 15 then
                FireAllPromptsIn(drawer, rootPos)
                task.wait(0.1)
                TryFireCollectPrompt(keyObtain, rootPos)
            end
        end
    else
        TryFireCollectPrompt(keyObtain, rootPos)
    end
end

task.spawn(function()
    while task.wait(0.2) do
        local char = LocalPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if root and CurrentRooms then
            local rootPos = root.Position
            local descendants = CurrentRooms:GetDescendants()

            for targetName, stateName in pairs(CollectTargets) do
                if Cache.States[stateName] then
                    for _, obj in ipairs(descendants) do
                        if obj.Name == targetName then
                            if targetName == "KeyObtain" then
                                TryCollectKey(obj, rootPos)
                            else
                                TryFireCollectPrompt(obj, rootPos)
                            end
                        end
                    end
                end
            end

            if Cache.States.AutoLootChest ~= "None" then
                for _, obj in ipairs(descendants) do
                    if (obj.Name == "ChestBox" and (Cache.States.AutoLootChest == "Chest Box" or Cache.States.AutoLootChest == "All")) or
                       (obj.Name == "ChestBoxLocked" and (Cache.States.AutoLootChest == "Chest Box Locked" or Cache.States.AutoLootChest == "All")) then

                        TryFireCollectPrompt(obj, rootPos)

                        if obj.Name == "ChestBoxLocked" then
                            local anchor = GetAnchorPart(obj)
                            if anchor and (rootPos - anchor.Position).Magnitude <= 15 then
                                local lockpick = GetLockpick()
                                if lockpick then
                                    EquipTool(lockpick)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end)

