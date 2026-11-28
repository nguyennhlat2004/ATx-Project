local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

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
    local itemFolder
    local itemFolderConnections = {}
    local boxes = {}
    local keys = {}
    local dolls = {}
    local dollNames = {
        DollBlue = "Doll Blue",
        DollRed = "Doll Red",
        DollWhite = "Doll White",
        DollYellow = "Doll Yellow",
        DollBlackHead = "Doll Black Head"
    }
    local originalHolds = {}
    local autoCollectKey = false
    local lastBackgroundError = 0
    local lightingOriginal = {}
    local lightingTargets = {
        Ambient = Color3.fromRGB(255, 255, 255),
        OutdoorAmbient = Color3.fromRGB(255, 255, 255),
        Brightness = 2,
        GlobalShadows = false,
        FogStart = 0,
        FogEnd = 100000,
        ClockTime = 0
    }

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
        if object:IsA("Attachment") then
            return object.WorldCFrame
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

    local teleportTo

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
        if dollNames[item.Name] and (item:IsA("Model") or item:IsA("BasePart")) then
            dolls[item] = dollNames[item.Name]
        end
    end

    local function bindItems(folder)
        if itemFolder == folder then
            return
        end
        disconnectAll(itemFolderConnections)
        table.clear(boxes)
        table.clear(dolls)
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
                dolls[item] = nil
                removeKey(item)
            end)
        end))
    end

    local function refreshPaths()
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

    local RunService = game:GetService("RunService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local HttpService = game:GetService("HttpService")
    local Player = Window:AddTab({ Title = "Player", Icon = "user" })
    local mapFolder
    local mapConnections = {}
    local mapDoors = {}
    local mapTouches = {}
    local mapSafes = {}
    local mapPapers = {}
    local dollRoomPapers = {}
    local mapHides = {}
    local safePrompts = {}
    local safePromptConnections = {}
    local enemies = {}
    local espEntries = {}
    local espEnabled = { Items = false, Dolls = false, Enemy = false, Hide = false }
    local featureConnections = {}
    local flyActive = false
    local flySerial = 0
    local tpWalk = false
    local tpSpeed = 16
    local safeAura = false
    local safeJob = false
    local safeAttempted = {}
    local uploadToken = nil
    local safeGeneration = 0
    local lastSafeNotice = -math.huge
    local espGui = Instance.new("ScreenGui")
    espGui.Name = "PetapetaESP"
    espGui.ResetOnSpawn = false
    espGui.IgnoreGuiInset = true
    espGui.DisplayOrder = -100
    espGui.Parent = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui") or CoreGui

    local function findAncestorNamed(object, name)
        local current = object
        while current and current ~= Workspace do
            if current.Name == name then
                return current
            end
            current = current.Parent
        end
        return nil
    end

    local function removeMapObject(object)
        mapDoors[object] = nil
        mapTouches[object] = nil
        mapSafes[object] = nil
        mapPapers[object] = nil
        dollRoomPapers[object] = nil
        mapHides[object] = nil
        safePrompts[object] = nil
        local connection = safePromptConnections[object]
        if connection then
            connection:Disconnect()
            safePromptConnections[object] = nil
        end
    end

    local function addMapObject(object)
        if object:IsA("Model") and object.Name:match("^Fusuma%d+$") then
            mapDoors[object] = true
        elseif object:IsA("Model") and object.Name == "Safe" then
            mapSafes[object] = true
        elseif (object:IsA("Model") or object:IsA("BasePart")) and object.Name == "HintPaper" then
            mapPapers[object] = true
        elseif object.Name == "Paper" and object.Parent and object.Parent.Name == "DollHouseGimic" then
            dollRoomPapers[object] = true
        elseif object:IsA("Model") and object.Name == "HideTansu" then
            mapHides[object] = true
        elseif object:IsA("BasePart") and (object.Name == "EventArea" or object.Name == "closePart") then
            mapTouches[object] = true
        elseif object:IsA("ProximityPrompt") and findAncestorNamed(object, "Safe") then
            if object.Name == "focus" and object.Parent and object.Parent.Name == "InteractPoint" and object.Parent.Parent and object.Parent.Parent.Name == "Safe" then
                safePrompts[object] = true
            end
            local function enable()
                guarded(function()
                    if alive and object.Parent and not object.Enabled then
                        object.Enabled = true
                    end
                end)
            end
            safePromptConnections[object] = object:GetPropertyChangedSignal("Enabled"):Connect(enable)
            enable()
        end
    end

    local function bindMap(folder)
        if folder == mapFolder then
            return
        end
        disconnectAll(mapConnections)
        for prompt, connection in pairs(safePromptConnections) do
            connection:Disconnect()
            safePromptConnections[prompt] = nil
        end
        table.clear(mapDoors)
        table.clear(mapTouches)
        table.clear(mapSafes)
        table.clear(mapPapers)
        table.clear(dollRoomPapers)
        table.clear(mapHides)
        table.clear(safePrompts)
        mapFolder = folder
        if not folder then
            return
        end
        for _, object in ipairs(folder:GetDescendants()) do
            addMapObject(object)
        end
        table.insert(mapConnections, folder.DescendantAdded:Connect(function(object)
            guarded(function()
                addMapObject(object)
            end)
        end))
        table.insert(mapConnections, folder.DescendantRemoving:Connect(function(object)
            guarded(function()
                removeMapObject(object)
            end)
        end))
    end

    local oldRefreshPaths = refreshPaths
    refreshPaths = function()
        oldRefreshPaths()
        local server = Workspace:FindFirstChild("Server")
        local generated = server and server:FindFirstChild("MapGenerated")
        bindMap(generated and generated:FindFirstChild("Rooms"))
        local client = Workspace:FindFirstChild("Client")
        local enemyFolder = client and client:FindFirstChild("Enemy")
        local clientEnemy = enemyFolder and enemyFolder:FindFirstChild("ClientEnemy")
        local enemy = clientEnemy and clientEnemy:FindFirstChild("EnemyModel")
        table.clear(enemies)
        if enemy and enemy:IsA("Model") then
            enemies[enemy] = true
        end
    end

    local function promptPosition(prompt)
        local holder = prompt.Parent
        if not holder then
            return nil
        end
        if holder:IsA("Attachment") then
            return holder.WorldPosition
        end
        local cf = findPosition(holder)
        return cf and cf.Position or nil
    end

    local function tryDoor(door, character, root)
        local prim = door:FindFirstChild("Prim", true)
        if prim then
            for _, descendant in ipairs(prim:GetDescendants()) do
                if descendant:IsA("ProximityPrompt") and descendant.Enabled then
                    local position = promptPosition(descendant)
                    if position and (position - root.Position).Magnitude <= descendant.MaxActivationDistance and type(fireproximityprompt) == "function" then
                        guarded(function()
                            fireproximityprompt(descendant)
                        end)
                    end
                end
            end
        end
        if type(firetouchinterest) == "function" then
            for part in pairs(mapTouches) do
                if part.Parent and (part.Position - root.Position).Magnitude <= 12 then
                    guarded(function()
                        firetouchinterest(root, part, 0)
                        firetouchinterest(root, part, 1)
                    end)
                end
            end
        end
    end

    local function doorPoint(door, from)
        local prim = door:FindFirstChild("Prim", true)
        local cf = prim and findPosition(prim) or findPosition(door)
        if not cf then
            return nil
        end
        local side = (from - cf.Position):Dot(cf.LookVector) >= 0 and 1 or -1
        return cf.Position + cf.LookVector * side * 3, cf.Position
    end

    teleportTo = function(target)
        if flyActive then
            error("Đang bay tới mục tiêu khác.")
        end
        local character, root = characterRoot()
        local targetCF = findPosition(target)
        if not targetCF then
            error("Không tìm thấy vị trí của mục tiêu.")
        end
        refreshPaths()
        local targetPosition = targetCF.Position
        local side = (root.Position - targetPosition):Dot(targetCF.LookVector) >= 0 and 1 or -1
        local finish = targetPosition + targetCF.LookVector * side * 4 + Vector3.new(0, 2, 0)
        local start = root.Position
        local path = finish - start
        local pathLengthSquared = path:Dot(path)
        local candidates = {}
        if pathLengthSquared > 1 then
            for door in pairs(mapDoors) do
                if door.Parent then
                    local point = doorPoint(door, start)
                    if point then
                        local projection = (point - start):Dot(path) / pathLengthSquared
                        if projection > 0 and projection < 1 and (point - (start + path * projection)).Magnitude <= 12 then
                            table.insert(candidates, { door = door, point = point, order = projection })
                        end
                    end
                end
            end
        end
        table.sort(candidates, function(a, b)
            return a.order < b.order
        end)
        local waypoints = {}
        for i = 1, math.min(#candidates, 8) do
            table.insert(waypoints, candidates[i])
        end
        table.insert(waypoints, { point = finish })
        local length = 0
        local previous = start
        for _, waypoint in ipairs(waypoints) do
            length = length + (waypoint.point - previous).Magnitude
            previous = waypoint.point
        end
        local duration = math.clamp(length / 200, 0.2, 3)
        flyActive = true
        flySerial = flySerial + 1
        local serial = flySerial
        local collisions = {}
        local added
        local humanoid = character:FindFirstChildWhichIsA("Humanoid")
        local oldPlatform = humanoid and humanoid.PlatformStand
        local function disableCollision(part)
            if part:IsA("BasePart") and collisions[part] == nil then
                collisions[part] = part.CanCollide
                part.CanCollide = false
            end
        end
        local success, failure = pcall(function()
            for _, part in ipairs(character:GetDescendants()) do
                disableCollision(part)
            end
            added = character.DescendantAdded:Connect(function(part)
                guarded(function()
                    disableCollision(part)
                end)
            end)
            if humanoid then
                humanoid.PlatformStand = true
            end
            for _, waypoint in ipairs(waypoints) do
                if not alive or serial ~= flySerial or not root.Parent or Players.LocalPlayer.Character ~= character then
                    error("Đã hủy chuyến bay.")
                end
                local from = root.Position
                local segment = (waypoint.point - from).Magnitude
                local segmentTime = math.max(0.01, duration * segment / math.max(length, 1))
                local elapsed = 0
                while elapsed < segmentTime do
                    if not alive or serial ~= flySerial or not root.Parent or Players.LocalPlayer.Character ~= character then
                        error("Đã hủy chuyến bay.")
                    end
                    local delta = RunService.Heartbeat:Wait()
                    elapsed = elapsed + delta
                    local position = from:Lerp(waypoint.point, math.min(elapsed / segmentTime, 1))
                    local look = waypoint.point - position
                    if look.Magnitude < 0.01 then
                        look = targetPosition - position
                    end
                    if look.Magnitude < 0.01 then
                        look = root.CFrame.LookVector
                    end
                    root.AssemblyLinearVelocity = Vector3.new()
                    character:PivotTo(CFrame.lookAt(position, position + look))
                end
                if waypoint.door and waypoint.door.Parent then
                    tryDoor(waypoint.door, character, root)
                end
            end
            local direction = targetPosition - root.Position
            if direction.Magnitude > 0.01 then
                character:PivotTo(CFrame.lookAt(root.Position, targetPosition))
                local camera = Workspace.CurrentCamera
                if camera then
                    camera.CFrame = CFrame.lookAt(camera.CFrame.Position, targetPosition)
                end
            end
        end)
        if added then
            added:Disconnect()
        end
        for part, value in pairs(collisions) do
            pcall(function()
                if part.Parent then
                    part.CanCollide = value
                end
            end)
        end
        if humanoid and humanoid.Parent then
            pcall(function()
                humanoid.PlatformStand = oldPlatform
            end)
        end
        flyActive = false
        if not success then
            error(failure)
        end
    end

    local function getCircleFrames(safe, index)
        local door = safe:FindFirstChild("Door")
        local lock = door and door:FindFirstChild("Lock")
        local circle = lock and lock:FindFirstChild("Circle" .. index)
        local gui = circle and circle:FindFirstChild("SurfaceGui")
        if not gui then
            return nil
        end
        local frames = {}
        for _, object in ipairs(gui:GetChildren()) do
            if object:IsA("Frame") then
                local labels = {}
                for _, label in ipairs(object:GetDescendants()) do
                    if label:IsA("TextLabel") then
                        table.insert(labels, label.Text)
                    end
                end
                if #labels > 0 then
                    table.insert(frames, { name = object.Name, order = object.LayoutOrder, xScale = object.Position.X.Scale, xOffset = object.Position.X.Offset, yScale = object.Position.Y.Scale, yOffset = object.Position.Y.Offset, labels = labels })
                end
            end
        end
        return frames
    end

    local function closestSafe(root)
        local all = {}
        for safe in pairs(mapSafes) do
            if safe.Parent then all[safe] = true end
        end
        local readable = {}
        for safe in pairs(all) do
            local door = safe:FindFirstChild("Door")
            local lock = door and door:FindFirstChild("Lock")
            if lock and lock:FindFirstChild("Circle1") and lock:FindFirstChild("Circle2") and lock:FindFirstChild("Circle3") then
                readable[safe] = true
            end
        end
        return nearest(readable, root) or nearest(all, root)
    end

    local function hintLabel(paper)
        local gui = paper and (paper:FindFirstChild("SurfaceGui") or paper:FindFirstChildWhichIsA("SurfaceGui", true))
        local label = gui and (gui:FindFirstChild("TextLabel") or gui:FindFirstChildWhichIsA("TextLabel", true))
        if label and label:IsA("TextLabel") then
            return label
        end
        return nil
    end

    local function closestHint(root)
        local available = {}
        for paper in pairs(mapPapers) do
            local label = hintLabel(paper)
            if paper.Parent and label and label.Text ~= "" then
                available[paper] = true
            end
        end
        return nearest(available, root)
    end

    local function safeIsOpen(safe)
        local value = safe and safe:FindFirstChild("Unlocked")
        return value and value:IsA("BoolValue") and value.Value == true
    end

    local function safeNote(text)
        if os.clock() - lastSafeNotice > 12 then
            lastSafeNotice = os.clock()
            notify(text)
        end
    end

    local function makeSafeData()
        refreshPaths()
        local _, root = characterRoot()
        local safe = closestSafe(root)
        if not safe then
            error("Không tìm thấy Safe để xuất dữ liệu.")
        end
        local circles = {}
        for i = 1, 3 do
            circles[i] = getCircleFrames(safe, i) or {}
        end
        local hints = {}
        for paper in pairs(mapPapers) do
            local label = hintLabel(paper)
            if paper.Parent and label then
                table.insert(hints, { path = label:GetFullName(), text = label.Text })
            end
        end
        return HttpService:JSONEncode({ safePath = safe:GetFullName(), circles = circles, hints = hints })
    end

    local function exportSafe()
        local data = makeSafeData()
        local saved = false
        local copied = false
        if type(writefile) == "function" then
            saved = pcall(writefile, "Petapeta_Safe_Diagnostic.json", data)
        end
        if type(setclipboard) == "function" then
            copied = pcall(setclipboard, data)
        end
        if not saved and not copied then
            error("Executor không hỗ trợ writefile hoặc setclipboard.")
        end
        notify("Đã xuất dữ liệu Safe" .. (saved and " vào Petapeta_Safe_Diagnostic.json" or "") .. (copied and " và clipboard" or "") .. ". Hãy gửi dữ liệu cho mình.", 12)
    end

    local diagnosticEvents = {}
    local diagnosticSnapshots = {}
    local diagnosticActive = false
    local diagnosticDecompile = false
    local diagnosticHook
    local diagnosticStatus = "not started"

    local function diagnosticValue(value, depth, privateArguments)
        local kind = typeof(value)
        if kind == "nil" then return "nil" end
        if kind == "boolean" or kind == "number" then
            if kind == "number" and (value ~= value or value == math.huge or value == -math.huge) then return tostring(value) end
            return value
        end
        if kind == "string" then
            local lower = value:lower()
            if privateArguments then
                local allowed = value == "" or value:match("^%d+$") or lower == "open" or lower == "close" or lower == "left" or lower == "right"
                if not allowed and #value <= 24 then
                    local ok, isKatakana = pcall(function()
                        local count = 0
                        for _, codepoint in utf8.codes(value) do
                            count = count + 1
                            if codepoint < 0x30A0 or codepoint > 0x30FF then return false end
                        end
                        return count > 0 and count <= 6
                    end)
                    allowed = ok and isKatakana
                end
                if not allowed then return "[redacted]" end
            end
            if #value > 60 or lower:find("token", 1, true) or lower:find("password", 1, true) or lower:find("cookie", 1, true) or lower:find("github_pat", 1, true) then
                return "[redacted]"
            end
            return value
        end
        if kind == "Instance" then
            local ok, name = pcall(function() return value:GetFullName() end)
            return { class = value.ClassName, path = ok and name or value.Name }
        end
        if kind == "table" then
            if depth >= 3 then return "[depth limit]" end
            local result = {}
            local count = 0
            for key, item in pairs(value) do
                count = count + 1
                if count > 30 then
                    result.truncated = true
                    break
                end
                if type(key) == "number" and key >= 1 and key <= 100 and key % 1 == 0 then
                    result[tostring(key)] = diagnosticValue(item, depth + 1, privateArguments)
                elseif type(key) == "string" and (key == "index" or key == "value" or key == "code" or key == "rotation" or key == "circle" or key == "position") then
                    result[key] = diagnosticValue(item, depth + 1, privateArguments)
                end
            end
            return result
        end
        return tostring(value)
    end

    local function diagnosticProperty(object, name, output)
        local ok, value = pcall(function() return object[name] end)
        if ok then output[name] = diagnosticValue(value, 0) end
    end

    local function diagnosticNode(object, parentId, id)
        local node = { id = id, parent = parentId, name = object.Name, class = object.ClassName, properties = {}, attributes = {} }
        local attrsOk, attributes = pcall(function() return object:GetAttributes() end)
        if attrsOk then
            for name, value in pairs(attributes) do
                local lower = name:lower()
                if lower:find("token", 1, true) or lower:find("password", 1, true) or lower:find("cookie", 1, true) or lower:find("secret", 1, true) then
                    node.attributes[name] = "[redacted]"
                else
                    node.attributes[name] = diagnosticValue(value, 0)
                end
            end
        end
        local properties = {}
        if object:IsA("BasePart") then
            properties = { "CFrame", "Size", "Transparency", "CanCollide", "Anchored", "CanTouch" }
        elseif object:IsA("Attachment") then
            properties = { "CFrame", "WorldCFrame" }
        elseif object:IsA("ProximityPrompt") then
            properties = { "Enabled", "ActionText", "ObjectText", "HoldDuration", "MaxActivationDistance", "RequiresLineOfSight", "KeyboardKeyCode", "Style" }
        elseif object:IsA("GuiObject") then
            properties = { "Visible", "Position", "Size", "AnchorPoint", "Rotation", "LayoutOrder", "AbsolutePosition", "AbsoluteSize", "ZIndex" }
            if object:IsA("TextLabel") or object:IsA("TextButton") then
                table.insert(properties, "Text")
                table.insert(properties, "TextColor3")
            end
        elseif object:IsA("SurfaceGui") then
            properties = { "Enabled", "Face", "AlwaysOnTop", "CanvasSize", "Adornee" }
        elseif object:IsA("ValueBase") then
            properties = { "Value" }
        elseif object:IsA("Model") then
            properties = { "WorldPivot", "PrimaryPart" }
        elseif object:IsA("LuaSourceContainer") then
            properties = { "Disabled", "RunContext" }
        end
        for _, name in ipairs(properties) do
            diagnosticProperty(object, name, node.properties)
        end
        return node
    end

    local function diagnosticTree(root, limit)
        local nodes = {}
        local queue = { { object = root, parent = 0 } }
        local index = 1
        while index <= #queue and #nodes < limit do
            local item = queue[index]
            index = index + 1
            local id = #nodes + 1
            local ok, node = pcall(diagnosticNode, item.object, item.parent, id)
            if ok then
                table.insert(nodes, node)
                local childrenOk, children = pcall(function() return item.object:GetChildren() end)
                if childrenOk then
                    for _, child in ipairs(children) do
                        table.insert(queue, { object = child, parent = id })
                    end
                end
            end
        end
        return { nodes = nodes, truncated = index <= #queue, limit = limit }
    end

    local function diagnosticSafe()
        local player = Players.LocalPlayer
        local character = player and player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        return root and closestSafe(root) or nil
    end

    local function diagnosticSnapshot(label)
        refreshPaths()
        local safe = diagnosticSafe()
        if not safe then error("Không tìm thấy Safe. Hãy đến gần Safe và thử lại.") end
        local hints = {}
        for paper in pairs(mapPapers) do
            if paper.Parent then
                local text = hintLabel(paper)
                table.insert(hints, { path = paper:GetFullName(), text = text and text.Text or "", position = tostring(findPosition(paper)) })
                if #hints >= 30 then break end
            end
        end
        local ui = {}
        local playerGui = Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if playerGui then
            local seen = {}
            for _, object in ipairs(playerGui:GetDescendants()) do
                local lower = object.Name:lower()
                if (lower:find("safe", 1, true) or lower:find("dial", 1, true) or lower:match("^lock")) and not seen[object] then
                    local ancestor = object.Parent
                    local nested = false
                    while ancestor and ancestor ~= playerGui do
                        if seen[ancestor] then nested = true break end
                        ancestor = ancestor.Parent
                    end
                    if not nested then
                        seen[object] = true
                        table.insert(ui, { path = object:GetFullName(), tree = diagnosticTree(object, 400) })
                        if #ui >= 5 then break end
                    end
                end
            end
        end
        return { phase = label, time = os.time(), safePath = safe:GetFullName(), tree = diagnosticTree(safe, 2000), hints = hints, ui = ui }
    end

    local function installDiagnosticHook()
        if not env or type(hookmetamethod) ~= "function" or type(getnamecallmethod) ~= "function" or type(newcclosure) ~= "function" then
            return nil, "Executor thiếu hookmetamethod, getnamecallmethod, newcclosure hoặc getgenv."
        end
        local existing = env.PetapetaSafeDiagnosticHook
        if type(existing) == "table" and existing.installed then return existing end
        local state = { installed = false, busy = false, handler = nil }
        local original
        local ok = pcall(function()
            original = hookmetamethod(game, "__namecall", newcclosure(function(object, ...)
                if not state.busy and state.handler then
                    local method = getnamecallmethod()
                    if method == "FireServer" or method == "InvokeServer" then
                        local allowed = true
                        if type(checkcaller) == "function" then
                            local checked, result = pcall(checkcaller)
                            if checked and result then allowed = false end
                        end
                        if allowed then
                            state.busy = true
                            pcall(state.handler, object, method, ...)
                            state.busy = false
                        end
                    end
                end
                return original(object, ...)
            end))
        end)
        if not ok or type(original) ~= "function" then
            return nil, "Không cài được hook ghi remote."
        end
        state.installed = true
        env.PetapetaSafeDiagnosticHook = state
        return state
    end

    local function onDiagnosticRemote(object, method, ...)
        if not diagnosticActive or #diagnosticEvents >= 250 or typeof(object) ~= "Instance" then return end
        if not object:IsA("RemoteEvent") and not object:IsA("RemoteFunction") then return end
        local count = select("#", ...)
        local args = {}
        for i = 1, math.min(count, 8) do
            args[i] = diagnosticValue(select(i, ...), 0, true)
        end
        table.insert(diagnosticEvents, { time = os.clock(), path = object:GetFullName(), class = object.ClassName, method = method, argumentCount = count, arguments = args })
    end

    local function startSafeCapture()
        diagnosticActive = false
        table.clear(diagnosticEvents)
        table.clear(diagnosticSnapshots)
        table.insert(diagnosticSnapshots, diagnosticSnapshot("before"))
        local state, failure = installDiagnosticHook()
        if state then
            diagnosticHook = state
            diagnosticActive = true
            state.handler = onDiagnosticRemote
            diagnosticStatus = "recording"
            notify("Đang ghi Safe. Hãy mở khóa, xoay các vòng và bấm Mở; sau đó bấm Stop Safe Capture.", 12)
        else
            diagnosticStatus = failure
            notify("Đã chụp trạng thái Safe nhưng không ghi được remote: " .. failure, 12)
        end
    end

    local function stopSafeCapture()
        diagnosticActive = false
        if diagnosticHook and diagnosticHook.handler == onDiagnosticRemote then diagnosticHook.handler = nil end
        diagnosticStatus = "stopped"
        table.insert(diagnosticSnapshots, diagnosticSnapshot("after"))
        notify("Đã lưu " .. #diagnosticEvents .. " remote liên quan và trạng thái sau. Hãy xuất hoặc upload log.", 10)
    end

    local function diagnosticScripts(safe)
        local result = { enabled = diagnosticDecompile, records = {}, limit = 10 }
        if not diagnosticDecompile then return result end
        local decompiler = decompile or (env and env.decompile)
        if type(decompiler) ~= "function" then
            result.error = "Executor không có hàm decompile. Dex có thể cung cấp hàm này nếu được bật."
            return result
        end
        local candidates = {}
        local seen = {}
        local function consider(object, insideSafe)
            if seen[object] or not object:IsA("LuaSourceContainer") then return end
            local viable = object:IsA("LocalScript") or object:IsA("ModuleScript")
            if object:IsA("Script") then
                local ok, context = pcall(function() return object.RunContext end)
                viable = ok and context == Enum.RunContext.Client
            end
            if not viable then return end
            local name = object.Name:lower()
            if insideSafe or name:find("safe", 1, true) or name:find("lock", 1, true) or name:find("memo", 1, true) or name:find("focus", 1, true) or name:find("gimmick", 1, true) then
                seen[object] = true
                table.insert(candidates, object)
            end
        end
        if safe then
            for _, object in ipairs(safe:GetDescendants()) do consider(object, true) end
        end
        local player = Players.LocalPlayer
        local sources = { ReplicatedStorage }
        local scripts = player and player:FindFirstChild("PlayerScripts")
        local gui = player and player:FindFirstChildOfClass("PlayerGui")
        if scripts then table.insert(sources, scripts) end
        if gui then table.insert(sources, gui) end
        for _, source in ipairs(sources) do
            for _, object in ipairs(source:GetDescendants()) do consider(object, false) end
        end
        result.candidateCount = #candidates
        for i = 1, math.min(#candidates, 10) do
            local object = candidates[i]
            local record = { path = object:GetFullName(), class = object.ClassName, status = "pending" }
            local finished = false
            local success, source
            task.spawn(function()
                success, source = pcall(decompiler, object)
                finished = true
            end)
            local deadline = os.clock() + 5
            while not finished and os.clock() < deadline do task.wait(0.1) end
            if not finished then
                record.status = "timeout"
            elseif not success or type(source) ~= "string" then
                record.status = "failed"
            else
                record.status = "ok"
                record.source = source:sub(1, 50000)
                record.truncated = #source > 50000
            end
            table.insert(result.records, record)
        end
        return result
    end

    local oldMakeSafeData = makeSafeData
    makeSafeData = function()
        local snapshot = diagnosticSnapshot("export")
        local safe = diagnosticSafe()
        local basicOk, basic = pcall(oldMakeSafeData)
        local parsed = nil
        if basicOk then
            local ok, value = pcall(function() return HttpService:JSONDecode(basic) end)
            if ok then parsed = value end
        end
        return HttpService:JSONEncode({
            version = 2,
            captureStatus = diagnosticStatus,
            remoteFilter = "all outgoing remotes during capture; string arguments redacted except simple safe values",
            basic = parsed,
            snapshots = diagnosticSnapshots,
            current = snapshot,
            remotes = diagnosticEvents,
            remoteLimit = 250,
            scripts = diagnosticScripts(safe)
        })
    end

    local function runSafeJob(safe, prompt, generation)
        if safeJob then return end
        safeJob = true
        local ok, err = pcall(function()
            local event = ReplicatedStorage:FindFirstChild("MemoTextColorUpdateEvent")
            if not event or not event:IsA("RemoteEvent") then
                error("Không tìm thấy MemoTextColorUpdateEvent.")
            end
            if type(fireproximityprompt) ~= "function" then
                error("Executor không hỗ trợ fireproximityprompt.")
            end
            local _, root = characterRoot()
            local paper = closestHint(root)
            local label = paper and hintLabel(paper)
            if not label or label.Text == "" then
                error("Chưa tìm thấy Hint Paper tầng hiện tại.")
            end
            local symbols = { "イ", "ロ", "ハ", "ニ", "ホ", "ヘ", "ト", "チ", "リ", "ヌ", "ル", "ヲ" }
            local numbers = {}
            for index, symbol in ipairs(symbols) do
                numbers[symbol] = index
            end
            local target = {}
            local chars = {}
            for _, codepoint in utf8.codes(label.Text) do
                local symbol = utf8.char(codepoint)
                if numbers[symbol] then
                    table.insert(chars, symbol)
                    table.insert(target, numbers[symbol])
                elseif not symbol:match("^%s$") then
                    error("Hint Paper có ký tự chưa biết: " .. symbol)
                end
            end
            if #target ~= 3 then
                error("Hint Paper phải có đúng 3 ký tự.")
            end
            for index = 1, 3 do
                local frames = getCircleFrames(safe, index)
                local found = false
                for _, frame in ipairs(frames or {}) do
                    for _, text in ipairs(frame.labels) do
                        if text == chars[index] then found = true end
                    end
                end
                if not found then
                    error("Không thấy ký tự " .. chars[index] .. " ở Circle" .. index .. ".")
                end
            end
            if not alive or not safeAura or generation ~= safeGeneration or not safe.Parent or not prompt.Parent then
                return
            end
            local position = promptPosition(prompt)
            if not position or (position - root.Position).Magnitude > prompt.MaxActivationDistance then
                error("Đã rời khỏi tầm Safe.InteractPoint.focus.")
            end
            if safeIsOpen(safe) then
                notify("Safe đã được báo mở.")
                return
            end
            fireproximityprompt(prompt)
            task.wait(0.3)
            if not alive or not safeAura or generation ~= safeGeneration or not safe.Parent then return end
            event:FireServer(target)
            safeAttempted[safe] = true
            task.wait(0.3)
            if safeIsOpen(safe) then
                notify("Safe đã được báo mở.")
            else
                notify("Đã gửi mã " .. table.concat(target, ", ") .. ". Chưa xác nhận Safe mở; remote có thể chỉ cập nhật màu Memo.", 12)
            end
        end)
        safeJob = false
        if not ok then
            safeNote("Safe Aura: " .. tostring(err))
        end
    end

    local function renderPart(object)
        if object:IsA("BasePart") then
            return object
        end
        if object:IsA("Model") then
            return object.PrimaryPart or object:FindFirstChildWhichIsA("BasePart", true)
        end
        return nil
    end

    local function destroyEsp(object)
        local entry = espEntries[object]
        if entry then
            entry.highlight:Destroy()
            entry.billboard:Destroy()
            entry.line:Destroy()
            espEntries[object] = nil
        end
    end

    local function createEsp(object, kind, title, color)
        local part = renderPart(object)
        if not part then return end
        local highlight = Instance.new("Highlight")
        highlight.Adornee = object
        highlight.FillColor = color
        highlight.OutlineColor = color
        highlight.FillTransparency = 0.65
        highlight.OutlineTransparency = 0
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.Parent = espGui
        local billboard = Instance.new("BillboardGui")
        billboard.Adornee = part
        billboard.AlwaysOnTop = true
        billboard.Size = UDim2.fromOffset(180, 52)
        billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
        billboard.Parent = espGui
        local text = Instance.new("TextLabel")
        text.BackgroundTransparency = 1
        text.Size = UDim2.fromScale(1, 1)
        text.Font = Enum.Font.FredokaOne
        text.TextSize = 14
        text.TextColor3 = color
        text.TextStrokeTransparency = 0
        text.Parent = billboard
        local line = Instance.new("Frame")
        line.AnchorPoint = Vector2.new(0.5, 0.5)
        line.BackgroundColor3 = color
        line.BorderSizePixel = 0
        line.Visible = false
        line.Parent = espGui
        espEntries[object] = { highlight = highlight, billboard = billboard, text = text, line = line, part = part, kind = kind, title = title }
    end

    local function collectEsp()
        local wanted = {}
        if espEnabled.Items then
            for key in pairs(keys) do wanted[key] = { "Items", "Key", Color3.fromRGB(0, 255, 100) } end
            for box in pairs(boxes) do wanted[box] = { "Items", box.Name, Color3.fromRGB(0, 255, 100) } end
            for paper in pairs(mapPapers) do
                wanted[paper] = { "Items", "Hint Paper", Color3.fromRGB(0, 255, 100) }
            end
            for safe in pairs(mapSafes) do
                local door = safe:FindFirstChild("Door")
                if door and (door:IsA("Model") or door:IsA("BasePart")) then
                    wanted[door] = { "Items", "Safe", Color3.fromRGB(0, 255, 100) }
                end
            end
        end
        if espEnabled.Dolls then
            for doll, title in pairs(dolls) do
                wanted[doll] = { "Dolls", title, Color3.fromRGB(0, 255, 100) }
            end
        end
        if espEnabled.Enemy then
            for enemy in pairs(enemies) do wanted[enemy] = { "Enemy", "Petapeta", Color3.fromRGB(255, 50, 50) } end
        end
        if espEnabled.Hide then
            for hide in pairs(mapHides) do wanted[hide] = { "Hide", "Tủ trốn", Color3.fromRGB(255, 225, 0) } end
        end
        for object, entry in pairs(espEntries) do
            if not wanted[object] or not object.Parent or not entry.part.Parent or entry.part ~= object and not entry.part:IsDescendantOf(object) then
                destroyEsp(object)
            end
        end
        for object, info in pairs(wanted) do
            if object.Parent and not espEntries[object] then
                guarded(function() createEsp(object, info[1], info[2], info[3]) end)
            end
        end
    end

    local function updateEsp()
        local camera = Workspace.CurrentCamera
        local player = Players.LocalPlayer
        local character = player and player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if not camera or not root then
            for _, entry in pairs(espEntries) do
                entry.line.Visible = false
                entry.billboard.Enabled = false
                entry.highlight.Enabled = false
            end
            return
        end
        for object, entry in pairs(espEntries) do
            if object.Parent and entry.part.Parent then
                entry.billboard.Enabled = true
                entry.highlight.Enabled = true
                local pos = entry.part.Position
                local distance = root and math.floor((pos - root.Position).Magnitude + 0.5) or 0
                entry.text.Text = entry.title .. "\n" .. distance .. " studs"
                local point, visible = camera:WorldToViewportPoint(pos)
                entry.line.Visible = visible and point.Z > 0
                if entry.line.Visible then
                    local origin = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y)
                    local dest = Vector2.new(point.X, point.Y)
                    local diff = dest - origin
                    entry.line.Position = UDim2.fromOffset((origin.X + dest.X) / 2, (origin.Y + dest.Y) / 2)
                    entry.line.Size = UDim2.fromOffset(diff.Magnitude, 1)
                    entry.line.Rotation = math.deg(math.atan2(diff.Y, diff.X))
                end
            end
        end
    end

    local function uploadSafeData()
        if not uploadToken or uploadToken == "" then
            error("Hãy nhập token GitHub vào ô phía trên trước khi tải log.")
        end
        local requestFn = request or http_request or (syn and syn.request) or (http and http.request)
        if type(requestFn) ~= "function" then
            error("Executor không hỗ trợ HTTP request.")
        end
        local data = makeSafeData()
        local api = "https://api.github.com/repos/nguyennhlat2004/ATx-Project"
        local function github(method, path, body)
            local options = {
                Url = api .. path,
                Method = method,
                Headers = {
                    Authorization = "Bearer " .. uploadToken,
                    Accept = "application/vnd.github+json",
                    ["Content-Type"] = "application/json",
                    ["X-GitHub-Api-Version"] = "2022-11-28"
                }
            }
            if body then options.Body = HttpService:JSONEncode(body) end
            local success, result = pcall(requestFn, options)
            if not success or type(result) ~= "table" then
                error("Không thể kết nối API GitHub.")
            end
            local code = tonumber(result.StatusCode or result.Status or 0) or 0
            if code < 200 or code >= 300 then
                error("GitHub API trả mã " .. tostring(code) .. ". Kiểm tra token, quyền repo hoặc nhánh main.")
            end
            local parsed, decoded = pcall(function() return HttpService:JSONDecode(result.Body or "") end)
            if not parsed or type(decoded) ~= "table" then
                error("Không đọc được phản hồi từ GitHub API.")
            end
            return decoded
        end
        local ref = github("GET", "/git/ref/heads/main")
        local parent = ref.object and ref.object.sha
        if not parent then error("Không đọc được commit main.") end
        local commit = github("GET", "/git/commits/" .. parent)
        local baseTree = commit.tree and commit.tree.sha
        if not baseTree then error("Không đọc được tree main.") end
        local blob = github("POST", "/git/blobs", { content = data, encoding = "utf-8" })
        if not blob.sha then error("Không tạo được blob log.") end
        local tree = github("POST", "/git/trees", { base_tree = baseTree, tree = { { path = "Petapeta_Safe_Diagnostic.json", mode = "100644", type = "blob", sha = blob.sha } } })
        if not tree.sha then error("Không tạo được tree log.") end
        local newCommit = github("POST", "/git/commits", { message = "", tree = tree.sha, parents = { parent } })
        if not newCommit.sha then error("Không tạo được commit rỗng cho log.") end
        github("PATCH", "/git/refs/heads/main", { sha = newCommit.sha, force = false })
        uploadToken = nil
        notify("Đã tải Petapeta_Safe_Diagnostic.json lên GitHub; token đã xóa khỏi bộ nhớ script.", 10)
    end

    local SafeSection = Main:AddSection("Safe Aura")
    SafeSection:AddToggle("SafeAura", {
        Title = "Auto Open Safe (Thử nghiệm)",
        Default = false,
        Callback = runCallback(function(value)
            safeAura = value
            safeGeneration = safeGeneration + 1
            if value then
                table.clear(safeAttempted)
                notify("Safe Aura đọc Hint Paper và gửi mã một lần; chưa xác nhận remote mở Safe.", 10)
            end
        end)
    })
    SafeSection:AddButton({ Title = "Start Safe Capture", Callback = runCallback(startSafeCapture) })
    SafeSection:AddButton({ Title = "Stop Safe Capture", Callback = runCallback(stopSafeCapture) })
    SafeSection:AddToggle("SafeDiagnosticDecompile", {
        Title = "Include Decompiled Scripts",
        Default = false,
        Callback = runCallback(function(value)
            diagnosticDecompile = value
            if value then
                notify("Cảnh báo: decompiler có thể gửi bytecode tới bên thứ ba. Source sẽ nằm trong log công khai khi upload.", 15)
            end
        end)
    })
    SafeSection:AddButton({ Title = "Export Safe Data", Callback = runCallback(exportSafe) })
    local tokenInput
    local clearingToken = false
    tokenInput = SafeSection:AddInput("SafeUploadToken", {
        Title = "GitHub Token (tạm thời)",
        Placeholder = "Dán token rồi xác nhận",
        Finished = true,
        Callback = runCallback(function(value)
            if clearingToken or value == "" then return end
            uploadToken = value
            clearingToken = true
            if tokenInput then tokenInput:SetValue("") end
            clearingToken = false
            notify("Đã nhận token trong bộ nhớ; ô nhập đã được xóa.")
        end)
    })
    SafeSection:AddButton({ Title = "Upload Safe Data to GitHub", Callback = runCallback(uploadSafeData) })

    local EspSection = Main:AddSection("ESP")
    EspSection:AddToggle("EspItems", { Title = "ESP Items", Default = false, Callback = runCallback(function(value)
        espEnabled.Items = value
        if value then
            refreshPaths()
            if not next(keys) and not next(boxes) and not next(mapPapers) and not next(mapSafes) then notify("Chưa tìm thấy items; ESP sẽ tiếp tục chờ.") end
        end
    end) })
    EspSection:AddToggle("EspDolls", { Title = "ESP Doll", Default = false, Callback = runCallback(function(value)
        espEnabled.Dolls = value
        if value then
            refreshPaths()
            if not next(dolls) then notify("Chưa tìm thấy Doll hoặc DollBlackHead; ESP sẽ tiếp tục chờ.") end
        end
    end) })
    EspSection:AddToggle("EspEnemy", { Title = "ESP Petapeta", Default = false, Callback = runCallback(function(value)
        espEnabled.Enemy = value
        if value then
            refreshPaths()
            if not next(enemies) then notify("Chưa tìm thấy ClientEnemy.EnemyModel; ESP sẽ tiếp tục chờ.") end
        end
    end) })
    EspSection:AddToggle("EspHide", { Title = "ESP Tủ Trốn", Default = false, Callback = runCallback(function(value)
        espEnabled.Hide = value
        if value then
            refreshPaths()
            if not next(mapHides) then notify("Chưa tìm thấy HideTansu; ESP sẽ tiếp tục chờ.") end
        end
    end) })

    local PlayerSection = Player:AddSection("Walk Speed")
    PlayerSection:AddToggle("TPWalk", { Title = "Walk Speed", Default = false, Callback = runCallback(function(value) tpWalk = value end) })
    PlayerSection:AddSlider("TPWalkSpeed", { Title = "Speed (stud/s)", Default = 16, Min = 16, Max = 200, Rounding = 0, Callback = runCallback(function(value) tpSpeed = value end) })

    table.insert(featureConnections, RunService.Heartbeat:Connect(function(delta)
        guarded(function()
            if tpWalk and not flyActive then
                local player = Players.LocalPlayer
                local character = player and player.Character
                local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
                if humanoid and humanoid.Health > 0 and humanoid.MoveDirection.Magnitude > 0 then
                    local extra = math.max(0, tpSpeed - humanoid.WalkSpeed)
                    character:TranslateBy(humanoid.MoveDirection * extra * delta)
                end
            end
        end)
    end))
    table.insert(featureConnections, RunService.RenderStepped:Connect(function()
        guarded(updateEsp)
    end))
    task.spawn(function()
        while alive do
            guarded(collectEsp)
            task.wait(1)
        end
    end)
    task.spawn(function()
        while alive do
            if safeAura and not safeJob then
                guarded(function()
                    local player = Players.LocalPlayer
                    local character = player and player.Character
                    local root = character and character:FindFirstChild("HumanoidRootPart")
                    if root then
                        local prompt, promptDistance
                        for candidate in pairs(safePrompts) do
                            local position = promptPosition(candidate)
                            if position then
                                local distance = (position - root.Position).Magnitude
                                if not promptDistance or distance < promptDistance then
                                    prompt = candidate
                                    promptDistance = distance
                                end
                            end
                        end
                        if not prompt then
                            safeNote("Chưa tìm thấy Safe.InteractPoint.focus; hãy tìm Hint Paper trước.")
                        else
                            local position = promptPosition(prompt)
                            local safe = prompt.Parent and prompt.Parent.Parent
                            if not safe then
                                safeNote("Chưa tìm thấy Safe trong các Room đã tải.")
                            elseif safeIsOpen(safe) then
                                safeNote("Safe gần nhất đã mở.")
                            elseif position and (position - root.Position).Magnitude <= prompt.MaxActivationDistance and not safeAttempted[safe] then
                                local generation = safeGeneration
                                task.spawn(function() runSafeJob(safe, prompt, generation) end)
                            end
                        end
                    end
                end)
            end
            task.wait(1)
        end
    end)

    local Teleport = Main:AddSection("Teleport")

    Teleport:AddButton({
        Title = "Teleport To Safe",
        Callback = runCallback(function()
            refreshPaths()
            local _, root = characterRoot()
            local doors = {}
            for safe in pairs(mapSafes) do
                local door = safe:FindFirstChild("Door")
                if door and door.Parent then
                    doors[door] = true
                end
            end
            local door = nearest(doors, root)
            if not door then
                error("Không tìm thấy Safe.Door trong Server.MapGenerated.Rooms.")
            end
            teleportTo(door)
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

    Teleport:AddButton({
        Title = "Teleport To Hint Paper",
        Callback = runCallback(function()
            refreshPaths()
            local _, root = characterRoot()
            local paper = nearest(mapPapers, root)
            if not paper then
                error("Không tìm thấy HintPaper trong Server.MapGenerated.Rooms.")
            end
            teleportTo(paper)
        end)
    })

    for _, name in ipairs({ "DollBlue", "DollRed", "DollWhite", "DollYellow", "DollBlackHead" }) do
        local targetName = name
        local title = dollNames[targetName]
        Teleport:AddButton({
            Title = "Teleport To " .. title,
            Callback = runCallback(function()
                refreshPaths()
                local _, root = characterRoot()
                local available = {}
                for doll in pairs(dolls) do
                    if doll.Parent and doll.Name == targetName then
                        available[doll] = true
                    end
                end
                local doll = nearest(available, root)
                if not doll then
                    error("Không tìm thấy " .. title .. " trong SpawnedItems.")
                end
                teleportTo(doll)
            end)
        })
    end

    Teleport:AddButton({
        Title = "Teleport To Doll Room",
        Callback = runCallback(function()
            refreshPaths()
            local _, root = characterRoot()
            local paper = nearest(dollRoomPapers, root)
            if not paper then
                error("Không tìm thấy DollHouseGimic.Paper trong Server.MapGenerated.Rooms.")
            end
            teleportTo(paper)
        end)
    })

    local Aura = Main:AddSection("Collect Aura")
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
            local _, root = characterRoot()
            local paper = closestHint(root)
            local label = paper and hintLabel(paper)
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
            diagnosticActive = false
            if diagnosticHook and diagnosticHook.handler == onDiagnosticRemote then diagnosticHook.handler = nil end
            safeAura = false
            safeGeneration = safeGeneration + 1
            flySerial = flySerial + 1
            uploadToken = nil
            disconnectAll(featureConnections)
            disconnectAll(mapConnections)
            for prompt, connection in pairs(safePromptConnections) do
                connection:Disconnect()
                safePromptConnections[prompt] = nil
            end
            for object in pairs(espEntries) do
                destroyEsp(object)
            end
            pcall(function() espGui:Destroy() end)
            disconnectAll(itemFolderConnections)
            for key in pairs(keys) do
                removeKey(key)
            end
            for prompt in pairs(originalHolds) do
                restoreHold(prompt)
            end
            table.clear(boxes)
            table.clear(dolls)
            for property, value in pairs(lightingOriginal) do
                pcall(function()
                    Lighting[property] = value
                end)
            end
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
            guarded(function()
                for property, value in pairs(lightingTargets) do
                    guarded(function()
                        if lightingOriginal[property] == nil then
                            lightingOriginal[property] = Lighting[property]
                        end
                        if Lighting[property] ~= value then
                            Lighting[property] = value
                        end
                    end)
                end
                for _, atmosphere in ipairs(Lighting:GetDescendants()) do
                    if atmosphere:IsA("Atmosphere") then
                        guarded(function()
                            atmosphere:Destroy()
                        end)
                    end
                end
            end)
            task.wait(0.5)
        end
    end)
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
                    local player = Players.LocalPlayer
                    local character = player and player.Character
                    local root = character and character:FindFirstChild("HumanoidRootPart")
                    if not root then return end
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
