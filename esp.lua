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

local function createDrawing(ctype, color)
    local d = Drawing.new(ctype)
    if color then d.Color = color end
    d.Visible = false
    return d
end

local function initPlayer(player)
    local drawings = {
        lines = {},
        name = createDrawing("Text")
    }
    for i = 1, 15 do
        drawings.lines[i] = createDrawing("Line")
    end
    drawings.name.Size = 14
    drawings.name.Center = true
    drawings.name.Outline = true
    drawings.name.OutlineColor = Color3.new(0, 0, 0)
    playerDrawings[player.UserId] = drawings
end

local function getRoleColor(player)
    for _, child in ipairs(player.Character and player.Character:GetChildren() or {}) do
        if child:IsA("Tool") then
            if child.Name == "Knife" then return roleColors.Murderer
            elseif child.Name == "Gun" then return roleColors.Sheriff
            end
        end
    end
    return roleColors.Innocent
end

local function updatePlayer(player)
    local drawings = playerDrawings[player.UserId]
    if not drawings then
        initPlayer(player)
        drawings = playerDrawings[player.UserId]
    end
    local char = player.Character
    if not char then
        for _, line in ipairs(drawings.lines) do line.Visible = false end
        drawings.name.Visible = false
        return
    end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then
        for _, line in ipairs(drawings.lines) do line.Visible = false end
        drawings.name.Visible = false
        return
    end

    local head = char:FindFirstChild("Head")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not head or not root then return end

    local color = getRoleColor(player)
    local isR15 = humanoid.RigType == Enum.HumanoidRigType.R15

    local points = {}
    if isR15 then
        local upper = char:FindFirstChild("UpperTorso") or root
        local lower = char:FindFirstChild("LowerTorso") or upper
        points = {
            Head = head.Position,
            UpperTorso = upper.Position,
            LowerTorso = lower.Position,
            LeftUpperArm = (char:FindFirstChild("LeftUpperArm") or upper).Position,
            LeftLowerArm = (char:FindFirstChild("LeftLowerArm") or char:FindFirstChild("LeftUpperArm") or upper).Position,
            LeftHand = (char:FindFirstChild("LeftHand") or char:FindFirstChild("LeftLowerArm") or upper).Position,
            RightUpperArm = (char:FindFirstChild("RightUpperArm") or upper).Position,
            RightLowerArm = (char:FindFirstChild("RightLowerArm") or char:FindFirstChild("RightUpperArm") or upper).Position,
            RightHand = (char:FindFirstChild("RightHand") or char:FindFirstChild("RightLowerArm") or upper).Position,
            LeftUpperLeg = (char:FindFirstChild("LeftUpperLeg") or lower).Position,
            LeftLowerLeg = (char:FindFirstChild("LeftLowerLeg") or char:FindFirstChild("LeftUpperLeg") or lower).Position,
            LeftFoot = (char:FindFirstChild("LeftFoot") or char:FindFirstChild("LeftLowerLeg") or lower).Position,
            RightUpperLeg = (char:FindFirstChild("RightUpperLeg") or lower).Position,
            RightLowerLeg = (char:FindFirstChild("RightLowerLeg") or char:FindFirstChild("RightUpperLeg") or lower).Position,
            RightFoot = (char:FindFirstChild("RightFoot") or char:FindFirstChild("RightLowerLeg") or lower).Position
        }
    else
        local torso = char:FindFirstChild("Torso") or root
        local leftArm = char:FindFirstChild("Left Arm") or torso
        local rightArm = char:FindFirstChild("Right Arm") or torso
        local leftLeg = char:FindFirstChild("Left Leg") or torso
        local rightLeg = char:FindFirstChild("Right Leg") or torso
        points = {
            Head = head.Position,
            Torso = torso.Position,
            LeftArm = leftArm.Position,
            RightArm = rightArm.Position,
            LeftLeg = leftLeg.Position,
            RightLeg = rightLeg.Position
        }
    end

    local screen = {}
    for k, v in pairs(points) do
        local pos, onScreen = Camera:WorldToScreenPoint(v)
        screen[k] = {pos = Vector2.new(pos.X, pos.Y), onScreen = onScreen}
    end

    local connections
    if isR15 then
        connections = {
            {"Head", "UpperTorso"}, {"UpperTorso", "LowerTorso"},
            {"UpperTorso", "LeftUpperArm"}, {"LeftUpperArm", "LeftLowerArm"}, {"LeftLowerArm", "LeftHand"},
            {"UpperTorso", "RightUpperArm"}, {"RightUpperArm", "RightLowerArm"}, {"RightLowerArm", "RightHand"},
            {"LowerTorso", "LeftUpperLeg"}, {"LeftUpperLeg", "LeftLowerLeg"}, {"LeftLowerLeg", "LeftFoot"},
            {"LowerTorso", "RightUpperLeg"}, {"RightUpperLeg", "RightLowerLeg"}, {"RightLowerLeg", "RightFoot"}
        }
    else
        connections = {
            {"Head", "Torso"}, {"Torso", "LeftArm"}, {"Torso", "RightArm"},
            {"Torso", "LeftLeg"}, {"Torso", "RightLeg"}
        }
    end

    for i, pair in ipairs(connections) do
        local line = drawings.lines[i]
        if line then
            local a = screen[pair[1]]
            local b = screen[pair[2]]
            if a and b and a.onScreen and b.onScreen then
                line.From = a.pos
                line.To = b.pos
                line.Color = color
                line.Visible = true
            else
                line.Visible = false
            end
        end
    end

    for i = #connections + 1, #drawings.lines do
        drawings.lines[i].Visible = false
    end

    local headScr, onScreen = Camera:WorldToScreenPoint(head.Position + Vector3.new(0, 0.8, 0))
    drawings.name.Text = player.Name
    drawings.name.Color = color
    drawings.name.Position = Vector2.new(headScr.X, headScr.Y)
    drawings.name.Visible = onScreen
end

function espModule.start()
    if active then return end
    active = true
    connection = RunService.RenderStepped:Connect(function()
        if not active then connection:Disconnect(); return end
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                updatePlayer(player)
            end
        end
        for userId, drawings in pairs(playerDrawings) do
            if not Players:GetPlayerByUserId(userId) then
                for _, line in ipairs(drawings.lines) do line:Remove() end
                drawings.name:Remove()
                playerDrawings[userId] = nil
            end
        end
    end)
end

function espModule.stop()
    active = false
    if connection then connection:Disconnect() end
    for _, drawings in pairs(playerDrawings) do
        for _, line in ipairs(drawings.lines) do line:Remove() end
        drawings.name:Remove()
    end
    playerDrawings = {}
end

return espModule
