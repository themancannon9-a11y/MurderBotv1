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
local doorways = {}
local lastMapScan = 0
local scanRadius = 150
local scanStep = 15

local function raycastIgnoreSelf(origin, direction, maxDist)
    local char = LocalPlayer.Character
    local ignore = char and {char} or {}
    return workspace:FindPartOnRayWithIgnoreList(Ray.new(origin, direction), ignore)
end

function MapScanner.scan()
    if tick() - lastMapScan < 5 then return end
    lastMapScan = tick()
    local char = LocalPlayer.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local center = root.Position
    local origin = center + Vector3.new(0,2,0)
    local newDoorways = {}

    for angle = 0, 360, scanStep do
        local dir = Vector3.new(math.cos(math.rad(angle)), 0, math.sin(math.rad(angle)))
        local hit, hitPos = raycastIgnoreSelf(origin, dir, scanRadius)
        if hit then
            local leftDir = Vector3.new(-dir.Z, 0, dir.X)
            local rightDir = -leftDir
            local rayL = Ray.new(origin + leftDir * 4, dir * scanRadius)
            local rayR = Ray.new(origin + rightDir * 4, dir * scanRadius)
            local hitL = workspace:FindPartOnRayWithIgnoreList(rayL, {char})
            local hitR = workspace:FindPartOnRayWithIgnoreList(rayR, {char})
            if hitL and not hitR then
                table.insert(newDoorways, {pos = hitPos + leftDir * 3, normal = leftDir})
            elseif not hitL and hitR then
                table.insert(newDoorways, {pos = hitPos + rightDir * 3, normal = rightDir})
            elseif hitL and hitR then
                table.insert(newDoorways, {pos = hitPos, normal = dir})
            end
        end
    end
    if #newDoorways > 0 then doorways = newDoorways end
end

local target = nil
local aimSpeed = 0.22
local state = "IDLE"
local ambushPoint = nil
local patienceEnd = 0
local pathWaypoints = {}
local nextWaypointIndex = 1
local stuckCheck = 0
local lastPos = Vector3.zero
local throwCooldown = 0
local combatStrafing = 0
local strafeDir = 0

local function hasLineOfSight(posA, posB)
    local dir = (posB - posA).Unit
    local dist = (posB - posA).Magnitude
    local ray = Ray.new(posA, dir * dist)
    local char = LocalPlayer.Character
    local ignoreList = {char}
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character then table.insert(ignoreList, p.Character) end
    end
    local hit = workspace:FindPartOnRayWithIgnoreList(ray, ignoreList)
    return not hit
end

local function getPredictedHeadPos(player)
    local char = player.Character
    if not char then return nil end
    local head = char:FindFirstChild("Head")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not head or not root then return nil end
    local velocity = root.Velocity or Vector3.zero
    local dist = (head.Position - Camera.CFrame.Position).Magnitude
    local travelTime = dist / 100
    return head.Position + velocity * travelTime
end

local function aimAt(pos)
    if not pos then return end
    local camCF = Camera.CFrame
    local dir = (pos - camCF.Position).Unit
    Camera.CFrame = camCF:Lerp(CFrame.lookAt(camCF.Position, camCF.Position + dir), aimSpeed)
end

local function setPathTo(pos)
    local char = LocalPlayer.Character
    if not char then return end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root then return end

    local path = PathfindingService:CreatePath()
    local success = pcall(function()
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
    local root = char:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root then return end
    if #pathWaypoints == 0 then return end
    if nextWaypointIndex > #pathWaypoints then return end

    local targetWP = pathWaypoints[nextWaypointIndex]
    humanoid:MoveTo(targetWP)

    if (root.Position - targetWP).Magnitude < 3 then
        nextWaypointIndex = nextWaypointIndex + 1
    end

    if tick() - stuckCheck > 1.5 then
        local moved = (root.Position - lastPos).Magnitude
        if moved < 0.5 then
            nextWaypointIndex = math.min(nextWaypointIndex + 1, #pathWaypoints)
            stuckCheck = tick()
        end
        lastPos = root.Position
        stuckCheck = tick()
    end
end

local function clickMB1()
    VIM:SendMouseButtonEvent(0, 0, 0, true, game, 0)
    task.wait(0.05)
    VIM:SendMouseButtonEvent(0, 0, 0, false, game, 0)
end

local function clickMB2()
    VIM:SendMouseButtonEvent(1, 1, 0, true, game, 0)
    task.wait(0.05)
    VIM:SendMouseButtonEvent(1, 1, 0, false, game, 0)
end

local function attackMelee()
    local char = LocalPlayer.Character
    if not char then return end
    local tool = char:FindFirstChildOfClass("Tool")
    if tool then
        tool:Activate()
    else
        clickMB1()
    end
end

local function throwKnife()
    local char = LocalPlayer.Character
    if not char then return end
    local tool = char:FindFirstChildOfClass("Tool")
    if tool and tool.Name == "Knife" then
        clickMB2()
    end
end

local function updateThrow()
    if localRole == "Murderer" and tick() > throwCooldown then
        throwKnife()
        throwCooldown = tick() + 2.5
    end
end

local function selectAmbush()
    if not target or not target.Character or not LocalPlayer.Character then return nil end
    local targetPos = target.Character.HumanoidRootPart.Position
    local myPos = LocalPlayer.Character.HumanoidRootPart.Position
    local best = nil
    local bestScore = -math.huge
    for _, door in ipairs(doorways) do
        local dPos = door.pos
        local distToTarget = (dPos - targetPos).Magnitude
        local distToMe = (dPos - myPos).Magnitude
        if distToTarget < 50 and distToMe < 100 then
            local score = -distToTarget*2 - distToMe
            if score > bestScore then
                bestScore = score
                best = door
            end
        end
    end
    return best
end

local function avoidWalls()
    local char = LocalPlayer.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local dir = root.Velocity
    if dir.Magnitude < 0.5 then return end
    dir = dir.Unit
    local rayOrigin = root.Position + Vector3.new(0,1,0)
    local rayDir = dir
    local hit = raycastIgnoreSelf(rayOrigin, rayDir, 3)
    if hit then
        local left = Vector3.new(-dir.Z, 0, dir.X)
        local right = -left
        local hitL = raycastIgnoreSelf(rayOrigin, left, 2)
        local hitR = raycastIgnoreSelf(rayOrigin, right, 2)
        if not hitL then
            root.Velocity = root.Velocity + left * 30
        elseif not hitR then
            root.Velocity = root.Velocity + right * 30
        end
    end
end

local function updateAI()
    local char = LocalPlayer.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid then return end
    local myPos = root.Position

    avoidWalls()

    if not target or not GameSense.isAlive(target) then
        state = "IDLE"
        target = nil
        if localRole == "Innocent" and doorways[math.random(#doorways)] then
            local wander = doorways[math.random(#doorways)].pos
            setPathTo(wander)
            moveAlongPath()
        else
            pathWaypoints = {}
        end
        return
    end

    local targetRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
    if not targetRoot then return end
    local targetPos = targetRoot.Position
    local dist = (targetPos - myPos).Magnitude
    local headPred = getPredictedHeadPos(target)
    if headPred then aimAt(headPred) end

    if state == "IDLE" then
        ambushPoint = selectAmbush()
        if ambushPoint then
            state = "MOVING_TO_AMBUSH"
            setPathTo(ambushPoint.pos)
        else
            state = "CHASE"
            setPathTo(targetPos)
        end
    elseif state == "MOVING_TO_AMBUSH" then
        if ambushPoint and (myPos - ambushPoint.pos).Magnitude < 6 then
            state = "WAITING"
            patienceEnd = tick() + math.random(4,10)
        else
            moveAlongPath()
        end
    elseif state == "WAITING" then
        if tick() > patienceEnd or dist < 15 then
            state = "CHASE"
            setPathTo(targetPos)
        end
    elseif state == "CHASE" then
        setPathTo(targetPos)
        moveAlongPath()

        if hasLineOfSight(myPos + Vector3.new(0,1,0), targetRoot.Position + Vector3.new(0,1,0)) then
            if dist < 12 then
                if localRole == "Murderer" then
                    attackMelee()
                    updateThrow()
                    combatStrafing = 1
                    strafeDir = math.random() > 0.5 and 1 or -1
                elseif localRole == "Sheriff" then
                    attackMelee()
                end
            elseif dist < 30 and localRole == "Murderer" then
                updateThrow()
            end
        end

        if combatStrafing > 0 then
            local leftDir = Vector3.new(-targetRoot.Position.Z + myPos.Z, 0, targetRoot.Position.X - myPos.X).Unit
            humanoid:MoveTo(myPos + leftDir * strafeDir * 3)
            combatStrafing = combatStrafing - 0.05
        end

        if dist > 80 then state = "IDLE" end
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
    MapScanner.scan()
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
                aiState = state
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
