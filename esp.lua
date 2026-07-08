local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Camera = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer

local espModule = {}
local active = false
local roleColors = {
    Murderer = Color3.fromRGB(255, 70, 70),
    Sheriff = Color3.fromRGB(70, 150, 255),
    Innocent = Color3.fromRGB(100, 255, 100)
}
local playerDrawings = {}
local connection = nil

local function createDrawing(ctype)
    local d = Drawing.new(ctype)
    d.Visible = false
    return d
end

local function getRoleColor(player)
    local char = player.Character
    if not char then return roleColors.Innocent end
    for _, child in ipairs(char:GetChildren()) do
        if child:IsA("Tool") then
            if child.Name == "Knife" then return roleColors.Murderer
            elseif child.Name == "Gun" then return roleColors.Sheriff end
        end
    end
    return roleColors.Innocent
end

local function getJointPos(char, name, fallback)
    local part = char:FindFirstChild(name)
    if part then return part.Position end
    return fallback
end

local function updatePlayer(player)
    local drawings = playerDrawings[player.UserId]
    if not drawings then
        drawings = {
            lines = {},
            name = createDrawing("Text"),
            headCircle = createDrawing("Circle")
        }
        for i = 1, 15 do drawings.lines[i] = createDrawing("Line") end
        drawings.name.Size = 13
        drawings.name.Center = true
        drawings.name.Outline = true
        drawings.name.OutlineColor = Color3.new(0,0,0)
        drawings.headCircle.Thickness = 2
        drawings.headCircle.Filled = false
        drawings.headCircle.NumSides = 12
        playerDrawings[player.UserId] = drawings
    end

    local char = player.Character
    if not char then
        for _, l in ipairs(drawings.lines) do l.Visible = false end
        drawings.name.Visible = false
        drawings.headCircle.Visible = false
        return
    end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    local head = char:FindFirstChild("Head")
    if not humanoid or not root or not head or humanoid.Health <= 0 then
        for _, l in ipairs(drawings.lines) do l.Visible = false end
        drawings.name.Visible = false
        drawings.headCircle.Visible = false
        return
    end

    local color = getRoleColor(player)
    local isR15 = (humanoid.RigType == Enum.HumanoidRigType.R15)
    local torsoPos = isR15 and getJointPos(char, "UpperTorso", root.Position) or getJointPos(char, "Torso", root.Position)
    local lowerTorso = isR15 and getJointPos(char, "LowerTorso", torsoPos) or torsoPos

    local function limbPos(upper, lower, default)
        local up = char:FindFirstChild(upper)
        if up then return up.Position end
        local lo = char:FindFirstChild(lower)
        if lo then return lo.Position end
        return default
    end

    local points = {
        Head = head.Position,
        Torso = torsoPos,
        LowerTorso = lowerTorso,
        LeftShoulder = limbPos("LeftUpperArm", "Left Arm", torsoPos + Vector3.new(-1,0,0)),
        LeftElbow = limbPos("LeftLowerArm", "Left Arm", torsoPos + Vector3.new(-1.5,-0.5,0)),
        LeftHand = limbPos("LeftHand", "Left Arm", torsoPos + Vector3.new(-2,-1,0)),
        RightShoulder = limbPos("RightUpperArm", "Right Arm", torsoPos + Vector3.new(1,0,0)),
        RightElbow = limbPos("RightLowerArm", "Right Arm", torsoPos + Vector3.new(1.5,-0.5,0)),
        RightHand = limbPos("RightHand", "Right Arm", torsoPos + Vector3.new(2,-1,0)),
        LeftHip = limbPos("LeftUpperLeg", "Left Leg", lowerTorso + Vector3.new(-0.5,-0.5,0)),
        LeftKnee = limbPos("LeftLowerLeg", "Left Leg", lowerTorso + Vector3.new(-0.5,-2,0)),
        LeftFoot = limbPos("LeftFoot", "Left Leg", lowerTorso + Vector3.new(-0.5,-3.5,0)),
        RightHip = limbPos("RightUpperLeg", "Right Leg", lowerTorso + Vector3.new(0.5,-0.5,0)),
        RightKnee = limbPos("RightLowerLeg", "Right Leg", lowerTorso + Vector3.new(0.5,-2,0)),
        RightFoot = limbPos("RightFoot", "Right Leg", lowerTorso + Vector3.new(0.5,-3.5,0))
    }

    local screen = {}
    for k, v in pairs(points) do
        local pos, onScreen = Camera:WorldToScreenPoint(v)
        screen[k] = Vector2.new(pos.X, pos.Y)
        screen[k.."_on"] = onScreen
    end

    local connections
    if isR15 then
        connections = {
            {"Head","Torso"}, {"Torso","LowerTorso"},
            {"Torso","LeftShoulder"}, {"LeftShoulder","LeftElbow"}, {"LeftElbow","LeftHand"},
            {"Torso","RightShoulder"}, {"RightShoulder","RightElbow"}, {"RightElbow","RightHand"},
            {"LowerTorso","LeftHip"}, {"LeftHip","LeftKnee"}, {"LeftKnee","LeftFoot"},
            {"LowerTorso","RightHip"}, {"RightHip","RightKnee"}, {"RightKnee","RightFoot"}
        }
    else
        connections = {
            {"Head","Torso"}, {"Torso","LeftShoulder"}, {"Torso","RightShoulder"},
            {"Torso","LeftHip"}, {"Torso","RightHip"}
        }
    end

    for i, pair in ipairs(connections) do
        local line = drawings.lines[i]
        if line then
            local a = screen[pair[1]]
            local b = screen[pair[2]]
            local aOn = screen[pair[1].."_on"]
            local bOn = screen[pair[2].."_on"]
            if a and b and aOn and bOn then
                line.From = a
                line.To = b
                line.Color = color
                line.Visible = true
            else
                line.Visible = false
            end
        end
    end
    for i = #connections+1, #drawings.lines do
        drawings.lines[i].Visible = false
    end

    local headScr, headOn = Camera:WorldToScreenPoint(head.Position + Vector3.new(0,0.6,0))
    drawings.name.Text = player.Name
    drawings.name.Color = color
    drawings.name.Position = Vector2.new(headScr.X, headScr.Y)
    drawings.name.Visible = headOn

    local headRadius = 0.4
    local rightVec = Camera.CFrame.RightVector * headRadius
    local topVec = Camera.CFrame.UpVector * headRadius
    local p1, on1 = Camera:WorldToScreenPoint(head.Position + rightVec)
    local p2, on2 = Camera:WorldToScreenPoint(head.Position + topVec)
    if on1 and on2 then
        local radiusScreen = (Vector2.new(p1.X, p1.Y) - Vector2.new(p2.X, p2.Y)).Magnitude
        drawings.headCircle.Position = Vector2.new(headScr.X, headScr.Y)
        drawings.headCircle.Radius = radiusScreen
        drawings.headCircle.Color = color
        drawings.headCircle.Visible = true
    else
        drawings.headCircle.Visible = false
    end
end

function espModule.start()
    if active then return end
    active = true
    connection = RunService.RenderStepped:Connect(function()
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then updatePlayer(player) end
        end
        for userId, drawings in pairs(playerDrawings) do
            if not Players:GetPlayerByUserId(userId) then
                for _, l in ipairs(drawings.lines) do l:Remove() end
                drawings.name:Remove()
                drawings.headCircle:Remove()
                playerDrawings[userId] = nil
            end
        end
    end)
end

function espModule.stop()
    active = false
    if connection then connection:Disconnect() end
    for _, drawings in pairs(playerDrawings) do
        for _, l in ipairs(drawings.lines) do l:Remove() end
        drawings.name:Remove()
        drawings.headCircle:Remove()
    end
    playerDrawings = {}
end

return espModule
