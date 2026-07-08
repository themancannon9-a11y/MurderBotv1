local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local Camera = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer
local HttpService = game:GetService("HttpService")

local function readJSON(path)
    local success, data = pcall(readfile, path)
    if success then
        local ok, json = pcall(HttpService.JSONDecode, HttpService, data)
        return ok and json or {}
    end
    return {}
end

local function writeJSON(path, data)
    writefile(path, HttpService:JSONEncode(data))
end

if not isfolder("murderbot") then makefolder("murderbot") end
if not isfolder("murderbot/logs") then makefolder("murderbot/logs") end

local GameSense = {}
local roles = {}
local localRole = "Innocent"

function GameSense.detectRoles()
    for _, player in ipairs(Players:GetPlayers()) do
        local char = player.Character
        if char then
            local tool = char:FindFirstChildOfClass("Tool")
            if tool then
                if tool.Name == "Knife" then roles[player] = "Murderer"
                elseif tool.Name == "Gun" then roles[player] = "Sheriff"
                else roles[player] = "Innocent" end
            else roles[player] = "Innocent" end
        end
    end
    localRole = roles[LocalPlayer] or "Innocent"
end

function GameSense.getLocalRole() return localRole end
function GameSense.getRole(player) return roles[player] end
function GameSense.isAlive(player)
    local char = player.Character
    return char and char:FindFirstChild("Humanoid") and char.Humanoid.Health > 0
end

function GameSense.getEnemies()
    local enemies = {}
    if localRole == "Murderer" then
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and GameSense.isAlive(p) then table.insert(enemies, p) end
        end
    elseif localRole == "Sheriff" then
        for _, p in ipairs(Players:GetPlayers()) do
            if GameSense.getRole(p) == "Murderer" and GameSense.isAlive(p) then table.insert(enemies, p) end
        end
    end
    return enemies
end

LocalPlayer.CharacterAdded:Connect(function(char)
    local function onChildAdded(child)
        if child:IsA("Tool") then task.wait(0.1) GameSense.detectRoles() end
    end
    char.ChildAdded:Connect(onChildAdded)
    for _, child in ipairs(char:GetChildren()) do
        if child:IsA("Tool") then onChildAdded(child) end
    end
end)

local MapScanner = {}
local waypoints = {}
local scanRadius = 100
local scanStep = 15

function MapScanner.scan()
    local char = LocalPlayer.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local center = root.Position
    local origin = center + Vector3.new(0, 2, 0)
    local newWaypoints = {}
    for angle = 0, 360, scanStep do
        local dir = Vector3.new(math.cos(math.rad(angle)), 0, math.sin(math.rad(angle)))
        local ray = Ray.new(origin, dir * scanRadius)
        local hit, pos = workspace:FindPartOnRayWithIgnoreList(ray, {char})
        if not hit then
            local wp = center + dir * (scanRadius * 0.8)
            table.insert(newWaypoints, {pos = wp, type = "open"})
        else
            local left = Vector3.new(-dir.Z, 0, dir.X)
            local rayLeft = Ray.new(origin + left * 3, dir * scanRadius)
            local hitLeft = workspace:FindPartOnRayWithIgnoreList(rayLeft, {char})
            local rayRight = Ray.new(origin + left * -3, dir * scanRadius)
            local hitRight = workspace:FindPartOnRayWithIgnoreList(rayRight, {char})
            if hitLeft and not hitRight then
                table.insert(newWaypoints, {pos = pos + left * 3, type = "doorway_single"})
            elseif not hitLeft and hitRight then
                table.insert(newWaypoints, {pos = pos - left * 3, type = "doorway_single"})
            end
        end
    end
    waypoints = newWaypoints
end

local CombatAI = {}
local target = nil
local aimSpeed = 0.25
local state = "IDLE"
local ambushPoint = nil
local patienceEnd = 0

local function aimAt(position)
    if not position then return end
    local camCF = Camera.CFrame
    local dir = (position - camCF.Position).Unit
    local newLook = CFrame.lookAt(camCF.Position, camCF.Position + dir)
    Camera.CFrame = camCF:Lerp(newLook, aimSpeed)
end

local function moveTo(targetPosition)
    local char = LocalPlayer.Character
    if not char then return end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local path = PathfindingService:CreatePath()
    local success, err = pcall(function()
        path:ComputeAsync(root.Position, targetPosition)
    end)
    if success and path.Status == Enum.PathStatus.Success then
        local waypoints = path:GetWaypoints()
        for _, wp in ipairs(waypoints) do
            humanoid:MoveTo(wp.Position)
            humanoid.MoveToFinished:Wait(0.3)
        end
    else
        humanoid:MoveTo(targetPosition)
    end
end

local function attack()
    local char = LocalPlayer.Character
    if not char then return end
    local tool = char:FindFirstChildOfClass("Tool")
    if tool then
        tool:Activate()
        task.wait(0.3)
        if tool.Parent then tool:Deactivate() end
    end
end

local function selectAmbushPoint(targetPlayer)
    if not targetPlayer or not targetPlayer.Character then return nil end
    local tpos = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not tpos then return nil end
    local bestDist = math.huge
    local bestWp = nil
    for _, wp in ipairs(waypoints) do
        local distToTarget = (wp.pos - tpos.Position).Magnitude
        local distToMe = (wp.pos - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude
        if distToTarget < 40 and distToMe < 80 and wp.type == "doorway_single" then
            if distToMe < bestDist then
                bestDist = distToMe
                bestWp = wp
            end
        end
    end
    return bestWp
end

local function updateAI()
    if not target then
        state = "IDLE"
        return
    end
    local myPos = LocalPlayer.Character.HumanoidRootPart.Position
    local targetPos = target.Character.HumanoidRootPart.Position
    local dist = (targetPos - myPos).Magnitude

    if state == "IDLE" then
        ambushPoint = selectAmbushPoint(target)
        if ambushPoint then
            state = "MOVING_TO_AMBUSH"
        else
            state = "CHASE"
        end
    elseif state == "MOVING_TO_AMBUSH" then
        moveTo(ambushPoint.pos)
        if (myPos - ambushPoint.pos).Magnitude < 8 then
            state = "WAITING"
            patienceEnd = tick() + math.random(6, 15)
        end
    elseif state == "WAITING" then
        if tick() > patienceEnd then
            state = "CHASE"
        elseif dist < 15 then
            state = "ATTACKING"
        end
    elseif state == "CHASE" then
        moveTo(targetPos)
        aimAt(target.Character.Head.Position)
        if dist < 12 and localRole == "Murderer" then
            attack()
        elseif localRole == "Sheriff" then
            attack()
        end
        if dist > 40 then state = "IDLE" end
    elseif state == "ATTACKING" then
        aimAt(target.Character.Head.Position)
        moveTo(targetPos)
        if dist < 12 and localRole == "Murderer" then
            attack()
        elseif localRole == "Sheriff" then
            attack()
        end
    end
end

local Recorder = {}
local recording = false
local currentLog = {}
local targetUserId = nil
local lastTargetCheck = 0

function Recorder.startRecording(enemyPlayer)
    if recording then return end
    recording = true
    currentLog = {}
    targetUserId = enemyPlayer and enemyPlayer.UserId
    lastTargetCheck = tick()
end

function Recorder.stopRecording(reason)
    if not recording then return end
    recording = false
    local filename = "murderbot/logs/" .. os.date("%Y-%m-%d_%H-%M-%S") .. ".json"
    writeJSON(filename, currentLog)
    currentLog = {}
    targetUserId = nil
end

function Recorder.recordFrame(stateData, actionData)
    if not recording then return end
    table.insert(currentLog, {
        timestamp = tick(),
        state = stateData,
        action = actionData
    })
    if tick() - lastTargetCheck > 60 then
        lastTargetCheck = tick()
        if targetUserId then
            local targetPlayer = Players:GetPlayerByUserId(targetUserId)
            if not targetPlayer or not targetPlayer.Parent then
                Recorder.stopRecording("target_left")
            end
        end
    end
end

function Recorder.onLocalDeath()
    task.wait(5)
    if targetUserId then
        local target = Players:GetPlayerByUserId(targetUserId)
        if not target or not target.Parent then
            Recorder.stopRecording("target_left_after_death")
        end
    end
end

local DeathLogger = {}
local deathLogs = {}

function DeathLogger.loadDeaths()
    if isfile("murderbot/deathlog.json") then
        deathLogs = readJSON("murderbot/deathlog.json")
    end
end

function DeathLogger.logDeath(logData)
    table.insert(deathLogs, logData)
    writeJSON("murderbot/deathlog.json", deathLogs)
end

local Trainer = {}
local modelPath = "murderbot/model.nn"
local model = {}

function Trainer.loadModel()
    if isfile(modelPath) then model = readJSON(modelPath) end
end

function Trainer.trainFromLogs()
    local logFiles = listfiles("murderbot/logs/")
    local allFrames = {}
    for _, file in ipairs(logFiles) do
        local data = readJSON(file)
        for _, frame in ipairs(data) do
            table.insert(allFrames, frame)
        end
    end
    if #allFrames > 0 then
        model.trained = true
        writeJSON(modelPath, model)
    end
end

function Trainer.processDeathLogs()
    for _, deathLog in ipairs(deathLogs) do
        for _, frame in ipairs(deathLog.frames or {}) do
            model.deathAvoid = true
        end
    end
    writeJSON(modelPath, model)
end

local BackgroundReplayer = {}
local replayThread = nil

function BackgroundReplayer.start()
    if replayThread then return end
    replayThread = task.spawn(function()
        while true do
            if #deathLogs > 0 then
                Trainer.processDeathLogs()
            end
            task.wait(15)
        end
    end)
end

local botModule = {}
local active = false
local heartbeatConn

function botModule.start()
    if active then return end
    active = true
    Trainer.loadModel()
    DeathLogger.loadDeaths()
    Trainer.trainFromLogs()
    BackgroundReplayer.start()

    heartbeatConn = RunService.Heartbeat:Connect(function()
        if not active then heartbeatConn:Disconnect(); return end
        GameSense.detectRoles()
        local enemies = GameSense.getEnemies()
        if #enemies == 0 then
            target = nil
        else
            local bestDist = math.huge
            for _, enemy in ipairs(enemies) do
                if enemy.Character and enemy.Character:FindFirstChild("Head") then
                    local pos = enemy.Character.Head.Position
                    local _, onScreen = Camera:WorldToScreenPoint(pos)
                    if onScreen then
                        local d = (pos - Camera.CFrame.Position).Magnitude
                        if d < bestDist then
                            bestDist = d
                            target = enemy
                        end
                    end
                end
            end
        end
        MapScanner.scan()
        updateAI()
        if recording then
            local stateData = {
                myPos = LocalPlayer.Character and LocalPlayer.Character:GetPivot().Position,
                targetPos = target and target.Character and target.Character:GetPivot().Position,
                role = localRole,
                state = state
            }
            local actionData = { target = target and target.UserId }
            Recorder.recordFrame(stateData, actionData)
        end
    end)
    if target and #GameSense.getEnemies() > 0 then
        Recorder.startRecording(target)
    end
end

function botModule.stop()
    active = false
    if heartbeatConn then heartbeatConn:Disconnect() end
    target = nil
    Recorder.stopRecording("bot_disabled")
end

LocalPlayer.CharacterAdded:Connect(function(char)
    local humanoid = char:WaitForChild("Humanoid")
    humanoid.Died:Connect(function()
        if active and recording then
            Recorder.onLocalDeath()
        end
    end)
end)

return botModule
