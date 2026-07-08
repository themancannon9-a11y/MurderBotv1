local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local Camera = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer
local HttpService = game:GetService("HttpService")
local VIM = game:GetService("VirtualInputManager")

local function readJSON(path)
    local ok, data = pcall(readfile, path)
    if ok then
        local ok2, json = pcall(HttpService.JSONDecode, HttpService, data)
        return ok2 and json or {}
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
local scanRadius = 120
local scanStep = 20
local lastScan = 0

function MapScanner.scan()
    if tick() - lastScan < 3 then return end
    lastScan = tick()
    local char = LocalPlayer.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local center = root.Position
    local origin = center + Vector3.new(0,2,0)
    local newWaypoints = {}
    for angle = 0, 360, scanStep do
        local dir = Vector3.new(math.cos(math.rad(angle)), 0, math.sin(math.rad(angle)))
        local ray = Ray.new(origin, dir * scanRadius)
        local hit, pos = workspace:FindPartOnRayWithIgnoreList(ray, {char})
        if hit then
            local leftDir = Vector3.new(-dir.Z, 0, dir.X)
            local rayL = Ray.new(origin + leftDir * 4, dir * scanRadius)
            local hitL = workspace:FindPartOnRayWithIgnoreList(rayL, {char})
            local rayR = Ray.new(origin - leftDir * 4, dir * scanRadius)
            local hitR = workspace:FindPartOnRayWithIgnoreList(rayR, {char})
            if hitL and not hitR then
                table.insert(newWaypoints, {pos = pos + leftDir * 3, type = "doorway"})
            elseif not hitL and hitR then
                table.insert(newWaypoints, {pos = pos - leftDir * 3, type = "doorway"})
            elseif hitL and hitR then
                table.insert(newWaypoints, {pos = pos, type = "doorway"})
            end
        else
            table.insert(newWaypoints, {pos = center + dir * (scanRadius*0.7), type = "open"})
        end
    end
    waypoints = newWaypoints
end

local target = nil
local aimSpeed = 0.25
local state = "IDLE"
local ambushPoint = nil
local patienceEnd = 0
local nextWaypointIndex = 1
local pathWaypoints = {}
local stuckCheck = 0
local lastPos = Vector3.zero
local throwCooldown = 0

local function aimAt(position)
    if not position then return end
    local camCF = Camera.CFrame
    local dir = (position - camCF.Position).Unit
    local newLook = CFrame.lookAt(camCF.Position, camCF.Position + dir)
    Camera.CFrame = camCF:Lerp(newLook, aimSpeed)
end

local function setMovementTarget(pos)
    local char = LocalPlayer.Character
    if not char then return end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local path = PathfindingService:CreatePath()
    local success, err = pcall(function()
        path:ComputeAsync(root.Position, pos)
    end)
    if success and path.Status == Enum.PathStatus.Success then
        pathWaypoints = {}
        for _, wp in ipairs(path:GetWaypoints()) do
            table.insert(pathWaypoints, wp.Position)
        end
        nextWaypointIndex = 1
    else
        pathWaypoints = {pos}
        nextWaypointIndex = 1
    end
    stuckCheck = tick()
    lastPos = root.Position
end

local function moveAlongPath()
    local char = LocalPlayer.Character
    if not char then return end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    if #pathWaypoints == 0 then return end
    if nextWaypointIndex > #pathWaypoints then return end

    local targetWP = pathWaypoints[nextWaypointIndex]
    humanoid:MoveTo(targetWP)
    if (root.Position - targetWP).Magnitude < 3 then
        nextWaypointIndex = nextWaypointIndex + 1
    end
    if tick() - stuckCheck > 2 then
        if (root.Position - lastPos).Magnitude < 0.5 then
            nextWaypointIndex = math.min(nextWaypointIndex + 1, #pathWaypoints)
            stuckCheck = tick()
        end
        lastPos = root.Position
        stuckCheck = tick()
    end
end

local function attackMelee()
    local char = LocalPlayer.Character
    if not char then return end
    local tool = char:FindFirstChildOfClass("Tool")
    if tool then
        tool:Activate()
    else
        VIM:SendMouseButtonEvent(0, 0, 0, true, game, 0)
        task.wait(0.05)
        VIM:SendMouseButtonEvent(0, 0, 0, false, game, 0)
    end
end

local function throwKnife()
    local char = LocalPlayer.Character
    if not char then return end
    local tool = char:FindFirstChildOfClass("Tool")
    if tool and tool.Name == "Knife" then
        VIM:SendMouseButtonEvent(1, 1, 0, true, game, 0)
        task.wait(0.1)
        VIM:SendMouseButtonEvent(1, 1, 0, false, game, 0)
    end
end

local function updateThrow()
    if localRole == "Murderer" and tick() > throwCooldown then
        throwKnife()
        throwCooldown = tick() + 2.5
    end
end

local function selectAmbushPoint(targetPlayer)
    if not targetPlayer or not targetPlayer.Character then return nil end
    local tpos = targetPlayer.Character.HumanoidRootPart.Position
    local myPos = LocalPlayer.Character.HumanoidRootPart.Position
    local best = nil
    local bestScore = -math.huge
    for _, wp in ipairs(waypoints) do
        if wp.type == "doorway" then
            local distToTarget = (wp.pos - tpos).Magnitude
            local distToMe = (wp.pos - myPos).Magnitude
            local score = -distToTarget*2 - distToMe
            if distToTarget < 50 and distToMe < 80 then
                if score > bestScore then
                    bestScore = score
                    best = wp
                end
            end
        end
    end
    return best
end

local function updateAI()
    local char = LocalPlayer.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local myPos = root.Position

    if not target or not GameSense.isAlive(target) then
        state = "IDLE"
        target = nil
        if localRole == "Innocent" then
            if #waypoints > 0 then
                local wp = waypoints[math.random(#waypoints)]
                setMovementTarget(wp.pos)
                moveAlongPath()
            end
        else
            pathWaypoints = {}
        end
        return
    end

    local targetRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
    if not targetRoot then return end
    local targetPos = targetRoot.Position
    local dist = (targetPos - myPos).Magnitude

    if state == "IDLE" then
        ambushPoint = selectAmbushPoint(target)
        if ambushPoint then
            state = "MOVING_TO_AMBUSH"
            setMovementTarget(ambushPoint.pos)
        else
            state = "CHASE"
            setMovementTarget(targetPos)
        end
    elseif state == "MOVING_TO_AMBUSH" then
        if ambushPoint and (myPos - ambushPoint.pos).Magnitude < 5 then
            state = "WAITING"
            patienceEnd = tick() + math.random(5,12)
        else
            moveAlongPath()
        end
    elseif state == "WAITING" then
        if tick() > patienceEnd or dist < 12 then
            state = "CHASE"
            setMovementTarget(targetPos)
        end
    elseif state == "CHASE" then
        setMovementTarget(targetPos)
        moveAlongPath()
        aimAt(target.Character.Head.Position)
        if dist < 10 then
            if localRole == "Murderer" then
                attackMelee()
                updateThrow()
            elseif localRole == "Sheriff" then
                attackMelee()
            end
        end
        if dist > 60 then state = "IDLE" end
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
    table.insert(currentLog, {timestamp = tick(), state = stateData, action = actionData})
    if tick() - lastTargetCheck > 60 then
        lastTargetCheck = tick()
        if targetUserId and not Players:GetPlayerByUserId(targetUserId) then
            Recorder.stopRecording("target_left")
        end
    end
end

function Recorder.onLocalDeath()
    task.wait(5)
    if targetUserId and not Players:GetPlayerByUserId(targetUserId) then
        Recorder.stopRecording("target_left_after_death")
    end
end

local DeathLogger = {}
local deathLogs = {}
function DeathLogger.loadDeaths()
    if isfile("murderbot/deathlog.json") then deathLogs = readJSON("murderbot/deathlog.json") end
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
    local files = listfiles("murderbot/logs/")
    local all = {}
    for _, f in ipairs(files) do
        local data = readJSON(f)
        for _, fr in ipairs(data) do table.insert(all, fr) end
    end
    if #all > 0 then model.trained = true; writeJSON(modelPath, model) end
end
function Trainer.processDeathLogs()
    for _, dl in ipairs(deathLogs) do
        model.deathData = true
    end
    writeJSON(modelPath, model)
end

local BackgroundReplayer = {}
local replayThread = nil
function BackgroundReplayer.start()
    if replayThread then return end
    replayThread = task.spawn(function()
        while true do
            if #deathLogs > 0 then Trainer.processDeathLogs() end
            task.wait(20)
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
    local enemies = GameSense.getEnemies()
    if #enemies > 0 then target = enemies[1]; Recorder.startRecording(target) end

    heartbeatConn = RunService.Heartbeat:Connect(function()
        if not active then heartbeatConn:Disconnect(); return end
        GameSense.detectRoles()
        MapScanner.scan()
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
            if target and not recording then Recorder.startRecording(target) end
        end
        updateAI()
        if recording and target then
            local stateData = {
                myPos = LocalPlayer.Character and LocalPlayer.Character:GetPivot().Position,
                targetPos = target.Character and target.Character:GetPivot().Position,
                role = localRole,
                state = state
            }
            local actionData = {target = target.UserId}
            Recorder.recordFrame(stateData, actionData)
        end
    end)
end

function botModule.stop()
    active = false
    if heartbeatConn then heartbeatConn:Disconnect() end
    pathWaypoints = {}
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
