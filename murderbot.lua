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
        if child:IsA("Tool") then wait(0.1) GameSense.detectRoles() end
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
local nextWaypointIndex = 1
local pathNodes = {}
local throwCooldown = 0
local strafeTimer = 0
local strafeDir = 1

local function pressKey1()
    VIM:SendKeyEvent(true, "1", false, game)
    wait(0.05)
    VIM:SendKeyEvent(false, "1", false, game)
end

local function hasLineOfSight(posA, posB)
    local dir = (posB - posA).Unit
    local dist = (posB - posA).Magnitude
    local char = LocalPlayer.Character
    local ignoreList = {char}
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character then table.insert(ignoreList, p.Character) end
    end
    local hit = workspace:FindPartOnRayWithIgnoreList(Ray.new(posA, dir * dist), ignoreList)
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

local function computePath(pos)
    local char = LocalPlayer.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local path = PathfindingService:CreatePath()
    local success = pcall(function()
        path:ComputeAsync(root.Position, pos)
    end)
    if success and path.Status == Enum.PathStatus.Success then
        pathNodes = {}
        for _, wp in ipairs(path:GetWaypoints()) do
            table.insert(pathNodes, wp.Position)
        end
        nextWaypointIndex = 1
    else
        pathNodes = {pos}
        nextWaypointIndex = 1
    end
end

local function getMovementDirection()
    local char = LocalPlayer.Character
    if not char then return Vector3.zero end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return Vector3.zero end
    local myPos = root.Position

    if #pathNodes == 0 then return Vector3.zero end
    if nextWaypointIndex > #pathNodes then return Vector3.zero end

    local targetWP = pathNodes[nextWaypointIndex]
    if (myPos - targetWP).Magnitude < 3 then
        nextWaypointIndex = nextWaypointIndex + 1
        if nextWaypointIndex > #pathNodes then return Vector3.zero end
        targetWP = pathNodes[nextWaypointIndex]
    end

    local direction = (targetWP - myPos) * Vector3.new(1,0,1)
    if direction.Magnitude < 0.1 then return Vector3.zero end
    return direction.Unit
end

local function avoidWalls(moveDir)
    local char = LocalPlayer.Character
    if not char then return moveDir end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return moveDir end
    local origin = root.Position + Vector3.new(0,1,0)
    local rayHit = raycastIgnoreSelf(origin, moveDir, 2.5)
    if rayHit then
        local left = Vector3.new(-moveDir.Z, 0, moveDir.X)
        local right = -left
        local hitL = raycastIgnoreSelf(origin, left, 2)
        local hitR = raycastIgnoreSelf(origin, right, 2)
        if not hitL then return left
        elseif not hitR then return right
        else return -moveDir end
    end
    return moveDir
end

local function ensureKnifeEquipped()
    local char = LocalPlayer.Character
    if not char then return false end
    local tool = char:FindFirstChildOfClass("Tool")
    if tool and tool.Name == "Knife" then
        return true
    end
    pressKey1()
    wait(0.2)
    tool = char:FindFirstChildOfClass("Tool")
    return tool and tool.Name == "Knife"
end

local function clickMB1()
    VIM:SendMouseButtonEvent(0, 0, 0, true, game, 0)
    wait(0.03)
    VIM:SendMouseButtonEvent(0, 0, 0, false, game, 0)
end

local function clickMB2()
    VIM:SendMouseButtonEvent(1, 1, 0, true, game, 0)
    wait(0.03)
    VIM:SendMouseButtonEvent(1, 1, 0, false, game, 0)
end

local function attackMelee()
    if not ensureKnifeEquipped() then return end
    clickMB1()
end

local function throwKnife()
    if not ensureKnifeEquipped() then return end
    clickMB2()
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

local function updateAI()
    local char = LocalPlayer.Character
    if not char then return end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root then return end

    humanoid.WalkSpeed = 24
    humanoid.AutoRotate = false

    local myPos = root.Position

    if not target or not GameSense.isAlive(target) then
        state = "IDLE"
        target = nil
        humanoid:Move(Vector3.zero)  -- Stop movement
        if localRole == "Innocent" and #doorways > 0 then
            computePath(doorways[math.random(#doorways)].pos)
        end
        return
    end

    local targetRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
    if not targetRoot then
        humanoid:Move(Vector3.zero)
        return
    end
    local targetPos = targetRoot.Position
    local dist = (targetPos - myPos).Magnitude
    local headPred = getPredictedHeadPos(target)
    if headPred then aimAt(headPred) end

    if state == "IDLE" then
        ambushPoint = selectAmbush()
        if ambushPoint then
            state = "MOVING_TO_AMBUSH"
            computePath(ambushPoint.pos)
        else
            state = "CHASE"
            computePath(targetPos)
        end
    elseif state == "MOVING_TO_AMBUSH" then
        if ambushPoint and (myPos - ambushPoint.pos).Magnitude < 6 then
            state = "WAITING"
            patienceEnd = tick() + math.random(3,8)
        end
    elseif state == "WAITING" then
        if tick() > patienceEnd or dist < 18 then
            state = "CHASE"
            computePath(targetPos)
        end
    elseif state == "CHASE" then
        computePath(targetPos)
        if hasLineOfSight(myPos + Vector3.new(0,1,0), targetRoot.Position + Vector3.new(0,1,0)) then
            if dist < 11 then
                attackMelee()
                updateThrow()
                if strafeTimer <= 0 then
                    strafeDir = math.random() > 0.5 and 1 or -1
                    strafeTimer = 0.5
                end
            elseif dist < 25 and localRole == "Murderer" then
                updateThrow()
            end
        end
        if dist > 80 then state = "IDLE" end
    end

    local moveDir = getMovementDirection()
    moveDir = avoidWalls(moveDir)

    if strafeTimer > 0 then
        local leftDir = Vector3.new(targetPos.Z - myPos.Z, 0, -(targetPos.X - myPos.X)).Unit
        moveDir = moveDir * 0.7 + leftDir * strafeDir * 0.3
        strafeTimer = strafeTimer - 0.05
    end

    humanoid:Move(moveDir)  -- WASD‑style instant movement
    local lookDir = targetPos - myPos
    lookDir = Vector3.new(lookDir.X, 0, lookDir.Z)
    if lookDir.Magnitude > 0.1 then
        root.CFrame = CFrame.lookAt(myPos, myPos + lookDir)
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
    wait(5)
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
            wait(20)
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
    if LocalPlayer.Character then
        local humanoid = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if humanoid then humanoid:Move(Vector3.zero) end
    end
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
