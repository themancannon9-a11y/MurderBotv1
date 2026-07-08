local repoBase = "https://raw.githubusercontent.com/themancannon9-a11y/MurderBotv1/refs/heads/main"
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local ESPModule = nil
local BotModule = nil
local preloadDone = false

task.spawn(function()
    local ok1, espCode = pcall(game.HttpGet, game, repoBase .. "/esp.lua")
    local ok2, botCode = pcall(game.HttpGet, game, repoBase .. "/murderbot.lua")
    if ok1 and ok2 then
        local espLoader, espErr = loadstring(espCode)
        local botLoader, botErr = loadstring(botCode)
        if espLoader and botLoader then
            ESPModule = espLoader
            BotModule = botLoader
            preloadDone = true
        end
    end
end)

local screenGui = Instance.new("ScreenGui")
screenGui.Parent = game.CoreGui

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 260, 0, 260)
mainFrame.Position = UDim2.new(0.5, -130, 0.4, -130)
mainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Draggable = true
mainFrame.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = mainFrame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 32)
title.Position = UDim2.new(0, 0, 0, 8)
title.BackgroundTransparency = 1
title.Text = "MurderBot v2"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.Font = Enum.Font.GothamBold
title.TextSize = 18
title.Parent = mainFrame

local sep = Instance.new("Frame")
sep.Size = UDim2.new(1, -20, 0, 1)
sep.Position = UDim2.new(0, 10, 0, 44)
sep.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
sep.BorderSizePixel = 0
sep.Parent = mainFrame

local function makeButton(parent, posY, text)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -20, 0, 36)
    btn.Position = UDim2.new(0, 10, 0, posY)
    btn.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
    btn.BorderSizePixel = 0
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(200, 200, 210)
    btn.Font = Enum.Font.GothamSemibold
    btn.TextSize = 15
    btn.AutoButtonColor = false
    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 6)
    btnCorner.Parent = btn
    btn.Parent = parent
    btn.MouseEnter:Connect(function()
        btn.BackgroundColor3 = Color3.fromRGB(55, 55, 65)
    end)
    btn.MouseLeave:Connect(function()
        btn.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
    end)
    return btn
end

local espToggle = makeButton(mainFrame, 56, "ESP: OFF")
local botToggle = makeButton(mainFrame, 100, "Enable Bot [OFF]")

local espStatus = Instance.new("TextLabel")
espStatus.Size = UDim2.new(1, -20, 0, 18)
espStatus.Position = UDim2.new(0, 10, 0, 148)
espStatus.BackgroundTransparency = 1
espStatus.Text = "ESP Module: Preloading..."
espStatus.TextColor3 = Color3.fromRGB(170, 170, 180)
espStatus.Font = Enum.Font.Gotham
espStatus.TextSize = 12
espStatus.Parent = mainFrame

local botStatus = Instance.new("TextLabel")
botStatus.Size = UDim2.new(1, -20, 0, 18)
botStatus.Position = UDim2.new(0, 10, 0, 170)
botStatus.BackgroundTransparency = 1
botStatus.Text = "Bot Module: Preloading..."
botStatus.TextColor3 = Color3.fromRGB(170, 170, 180)
botStatus.Font = Enum.Font.Gotham
botStatus.TextSize = 12
botStatus.Parent = mainFrame

task.spawn(function()
    while not preloadDone do task.wait(0.5) end
    espStatus.Text = "ESP Module: Ready"
    botStatus.Text = "Bot Module: Ready"
end)

local espActive = false
local botActive = false
local espInstance = nil
local botInstance = nil

local function toggleESP()
    if not preloadDone or not ESPModule then return end
    if not espInstance then
        local success, result = pcall(ESPModule)
        if success and type(result) == "table" and result.start then
            espInstance = result
        else
            return
        end
    end
    espActive = not espActive
    if espActive then
        espInstance.start()
        espToggle.Text = "ESP: ON"
        espToggle.BackgroundColor3 = Color3.fromRGB(0, 150, 80)
    else
        espInstance.stop()
        espToggle.Text = "ESP: OFF"
        espToggle.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
    end
end

local function toggleBot()
    if not preloadDone or not BotModule then return end
    if not botInstance then
        local success, result = pcall(BotModule)
        if success and type(result) == "table" and result.start then
            botInstance = result
        else
            return
        end
    end
    botActive = not botActive
    if botActive then
        botInstance.start()
        botToggle.Text = "Enable Bot [ON]"
        botToggle.BackgroundColor3 = Color3.fromRGB(0, 150, 80)
    else
        botInstance.stop()
        botToggle.Text = "Enable Bot [OFF]"
        botToggle.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
    end
end

espToggle.MouseButton1Click:Connect(toggleESP)
botToggle.MouseButton1Click:Connect(toggleBot)
