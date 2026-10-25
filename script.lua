-- Player List GUI
-- Right Ctrl to toggle
-- Features: Spectate, Teleport, ESP, Color Picker

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Camera = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer

-- Pick GUI parent
local guiParent = (gethui and gethui()) or game:GetService("CoreGui")
if not pcall(function() return guiParent:GetChildren() end) then
    guiParent = LocalPlayer:WaitForChild("PlayerGui")
end

-- Clean up old copy
if guiParent:FindFirstChild("PlayerListGui") then
    guiParent.PlayerListGui:Destroy()
end

-- State
local spectating = nil
local expandedEntry = nil
local espEnabled = false
local espObjects = {}
local accentColor = Color3.fromRGB(0, 170, 255)

-- Helpers
local function round(obj, r)
    Instance.new("UICorner", obj).CornerRadius = UDim.new(0, r or 6)
end

local function label(parent, props)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.TextColor3 = Color3.new(1, 1, 1)
    l.TextSize = 13
    l.Font = Enum.Font.Gotham
    l.TextXAlignment = Enum.TextXAlignment.Left
    for k, v in pairs(props) do l[k] = v end
    l.Parent = parent
    return l
end

-- Main GUI
local Gui = Instance.new("ScreenGui")
Gui.Name = "PlayerListGui"
Gui.ResetOnSpawn = false
Gui.Parent = guiParent

local Main = Instance.new("Frame")
Main.Size = UDim2.new(0, 230, 0, 380)
Main.Position = UDim2.new(0, 10, 0.5, -190)
Main.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
Main.BorderSizePixel = 0
Main.Parent = Gui
round(Main, 10)

-- Accent border (updates with color picker)
local Border = Instance.new("UIStroke", Main)
Border.Color = accentColor
Border.Thickness = 1.5

-- Draggable top bar
local Bar = Instance.new("Frame")
Bar.Size = UDim2.new(1, 0, 0, 30)
Bar.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
Bar.BorderSizePixel = 0
Bar.Parent = Main
round(Bar, 10)

local Title = label(Bar, {
    Size = UDim2.new(1, -10, 1, 0),
    Position = UDim2.new(0, 10, 0, 0),
    Font = Enum.Font.GothamBold,
    Text = "Players"
})

-- Dragging logic
local dragging, dragStart, startPos

Bar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = input.Position
        startPos = Main.Position
    end
end)

Bar.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
    end
end)

UIS.InputChanged:Connect(function(input)
    if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
        local d = input.Position - dragStart
        Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end)

-- Color picker bar (below top bar)
local ColorFrame = Instance.new("Frame")
ColorFrame.Size = UDim2.new(1, -10, 0, 20)
ColorFrame.Position = UDim2.new(0, 5, 0, 34)
ColorFrame.BackgroundColor3 = Color3.new(1, 1, 1)
ColorFrame.BorderSizePixel = 0
ColorFrame.Parent = Main
round(ColorFrame, 4)

-- Gradient on the color bar
local gradient = Instance.new("UIGradient", ColorFrame)
gradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
    ColorSequenceKeypoint.new(0.15, Color3.fromRGB(255, 255, 0)),
    ColorSequenceKeypoint.new(0.3, Color3.fromRGB(0, 255, 0)),
    ColorSequenceKeypoint.new(0.45, Color3.fromRGB(0, 255, 255)),
    ColorSequenceKeypoint.new(0.6, Color3.fromRGB(0, 0, 255)),
    ColorSequenceKeypoint.new(0.75, Color3.fromRGB(255, 0, 255)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)),
})

-- Color picker indicator
local ColorIndicator = Instance.new("Frame")
ColorIndicator.Size = UDim2.new(0, 3, 1, 0)
ColorIndicator.BackgroundColor3 = Color3.new(1, 1, 1)
ColorIndicator.BorderSizePixel = 0
ColorIndicator.Parent = ColorFrame

-- Pick color when clicking the gradient bar
local pickingColor = false

local function applyColor(color)
    accentColor = color
    Border.Color = color

    -- Update all ESP highlights
    for _, obj in pairs(espObjects) do
        if obj and obj.Parent then
            obj.FillColor = color
            obj.OutlineColor = color
        end
    end
end

local function pickColor(input)
    local x = math.clamp((input.Position.X - ColorFrame.AbsolutePosition.X) / ColorFrame.AbsoluteSize.X, 0, 1)
    ColorIndicator.Position = UDim2.new(x, -1, 0, 0)

    -- Sample color from the gradient at position x
    local keypoints = {
        {0, Color3.fromRGB(255, 0, 0)},
        {0.15, Color3.fromRGB(255, 255, 0)},
        {0.3, Color3.fromRGB(0, 255, 0)},
        {0.45, Color3.fromRGB(0, 255, 255)},
        {0.6, Color3.fromRGB(0, 0, 255)},
        {0.75, Color3.fromRGB(255, 0, 255)},
        {1, Color3.fromRGB(255, 0, 0)},
    }

    local color = keypoints[1][2]
    for i = 1, #keypoints - 1 do
        if x >= keypoints[i][1] and x <= keypoints[i + 1][1] then
            local t = (x - keypoints[i][1]) / (keypoints[i + 1][1] - keypoints[i][1])
            color = keypoints[i][2]:Lerp(keypoints[i + 1][2], t)
            break
        end
    end

    applyColor(color)
end

ColorFrame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        pickingColor = true
        pickColor(input)
    end
end)

ColorFrame.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        pickingColor = false
    end
end)

UIS.InputChanged:Connect(function(input)
    if pickingColor and input.UserInputType == Enum.UserInputType.MouseMovement then
        pickColor(input)
    end
end)

-- ESP toggle button
local ESPBtn = Instance.new("TextButton")
ESPBtn.Size = UDim2.new(1, -10, 0, 24)
ESPBtn.Position = UDim2.new(0, 5, 0, 58)
ESPBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
ESPBtn.TextColor3 = Color3.new(1, 1, 1)
ESPBtn.TextSize = 12
ESPBtn.Font = Enum.Font.GothamBold
ESPBtn.Text = "ESP: OFF"
ESPBtn.AutoButtonColor = false
ESPBtn.Parent = Main
round(ESPBtn, 5)

-- ESP functions
local function createESP(player)
    local function apply(character)
        if not character then return end

        -- Remove old highlight if it exists
        if espObjects[player.UserId] then
            espObjects[player.UserId]:Destroy()
        end

        local highlight = Instance.new("Highlight")
        highlight.Name = "ESP_" .. player.UserId
        highlight.FillColor = accentColor
        highlight.FillTransparency = 0.7
        highlight.OutlineColor = accentColor
        highlight.OutlineTransparency = 0.3
        highlight.Adornee = character
        highlight.Parent = character
        espObjects[player.UserId] = highlight
    end

    -- Apply to current character
    apply(player.Character)

    -- Reapply when they respawn
    player.CharacterAdded:Connect(function(char)
        task.wait(0.5)
        if espEnabled then
            apply(char)
        end
    end)
end

local function removeESP(player)
    if espObjects[player.UserId] then
        espObjects[player.UserId]:Destroy()
        espObjects[player.UserId] = nil
    end
end

local function toggleESP()
    espEnabled = not espEnabled
    ESPBtn.Text = espEnabled and "ESP: ON" or "ESP: OFF"
    ESPBtn.BackgroundColor3 = espEnabled and accentColor or Color3.fromRGB(40, 40, 40)

    if espEnabled then
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer then
                createESP(p)
            end
        end
    else
        for _, p in ipairs(Players:GetPlayers()) do
            removeESP(p)
        end
    end
end

ESPBtn.MouseButton1Click:Connect(toggleESP)

-- Scroll frame for player list
local ScrollFrame = Instance.new("ScrollingFrame")
ScrollFrame.Size = UDim2.new(1, -10, 1, -92)
ScrollFrame.Position = UDim2.new(0, 5, 0, 86)
ScrollFrame.BackgroundTransparency = 1
ScrollFrame.ScrollBarThickness = 3
ScrollFrame.ScrollBarImageColor3 = accentColor
ScrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
ScrollFrame.Parent = Main

local ListLayout = Instance.new("UIListLayout", ScrollFrame)
ListLayout.Padding = UDim.new(0, 3)

ListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    ScrollFrame.CanvasSize = UDim2.new(0, 0, 0, ListLayout.AbsoluteContentSize.Y)
end)

-- Actions
local function resetCamera()
    local char = LocalPlayer.Character
    if char then
        Camera.CameraSubject = char:FindFirstChildOfClass("Humanoid")
    end
    spectating = nil
end

local function spectate(player)
    if spectating == player then
        resetCamera()
        return
    end
    local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
    if hum then
        Camera.CameraSubject = hum
        spectating = player
    end
end

local function teleportTo(player)
    local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    local tRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if myRoot and tRoot then
        myRoot.CFrame = tRoot.CFrame * CFrame.new(0, 0, 3)
    end
end

-- Player entry
local function createEntry(player)
    if player == LocalPlayer then return end

    local Entry = Instance.new("Frame")
    Entry.Name = "Entry_" .. player.UserId
    Entry.Size = UDim2.new(1, 0, 0, 32)
    Entry.BackgroundTransparency = 1
    Entry.Parent = ScrollFrame

    Instance.new("UIListLayout", Entry).Padding = UDim.new(0, 2)

    -- Name button
    local NameBtn = Instance.new("TextButton")
    NameBtn.Size = UDim2.new(1, 0, 0, 32)
    NameBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
    NameBtn.TextColor3 = Color3.new(1, 1, 1)
    NameBtn.TextSize = 13
    NameBtn.Font = Enum.Font.GothamBold
    NameBtn.Text = "  " .. player.DisplayName
    NameBtn.TextXAlignment = Enum.TextXAlignment.Left
    NameBtn.AutoButtonColor = false
    NameBtn.Parent = Entry
    round(NameBtn, 6)

    NameBtn.MouseEnter:Connect(function() NameBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60) end)
    NameBtn.MouseLeave:Connect(function() NameBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 45) end)

    -- Actions frame (hidden)
    local Actions = Instance.new("Frame", Entry)
    Actions.Size = UDim2.new(1, 0, 0, 28)
    Actions.BackgroundTransparency = 1
    Actions.Visible = false

    local row = Instance.new("UIListLayout", Actions)
    row.FillDirection = Enum.FillDirection.Horizontal
    row.Padding = UDim.new(0, 4)

    -- Spectate button
    local SpecBtn = Instance.new("TextButton")
    SpecBtn.Size = UDim2.new(0.5, -2, 0, 26)
    SpecBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    SpecBtn.TextColor3 = Color3.new(1, 1, 1)
    SpecBtn.TextSize = 12
    SpecBtn.Font = Enum.Font.Gotham
    SpecBtn.Text = "Spectate"
    SpecBtn.AutoButtonColor = false
    SpecBtn.Parent = Actions
    round(SpecBtn, 5)

    SpecBtn.MouseEnter:Connect(function() SpecBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60) end)
    SpecBtn.MouseLeave:Connect(function() SpecBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40) end)
    SpecBtn.MouseButton1Click:Connect(function() spectate(player) end)

    -- Teleport button
    local TpBtn = Instance.new("TextButton")
    TpBtn.Size = UDim2.new(0.5, -2, 0, 26)
    TpBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    TpBtn.TextColor3 = Color3.new(1, 1, 1)
    TpBtn.TextSize = 12
    TpBtn.Font = Enum.Font.Gotham
    TpBtn.Text = "Teleport"
    TpBtn.AutoButtonColor = false
    TpBtn.Parent = Actions
    round(TpBtn, 5)

    TpBtn.MouseEnter:Connect(function() TpBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60) end)
    TpBtn.MouseLeave:Connect(function() TpBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40) end)
    TpBtn.MouseButton1Click:Connect(function() teleportTo(player) end)

    -- Expand/collapse
    NameBtn.MouseButton1Click:Connect(function()
        if expandedEntry and expandedEntry ~= Entry then
            local old = expandedEntry:FindFirstChild("Frame")
            if old then old.Visible = false end
            expandedEntry.Size = UDim2.new(1, 0, 0, 32)
        end

        Actions.Visible = not Actions.Visible
        Entry.Size = Actions.Visible and UDim2.new(1, 0, 0, 62) or UDim2.new(1, 0, 0, 32)
        expandedEntry = Actions.Visible and Entry or nil
    end)

    -- If ESP is on, apply it to this new player
    if espEnabled then
        createESP(player)
    end
end

-- Remove entry
local function removeEntry(player)
    local entry = ScrollFrame:FindFirstChild("Entry_" .. player.UserId)
    if entry then
        if expandedEntry == entry then expandedEntry = nil end
        entry:Destroy()
    end
    removeESP(player)
    if spectating == player then resetCamera() end
end

-- Update title with count
local function updateTitle()
    Title.Text = "Players [" .. #Players:GetPlayers() .. "]"
end

-- Toggle GUI
UIS.InputBegan:Connect(function(input, processed)
    if not processed and input.KeyCode == Enum.KeyCode.RightControl then
        Main.Visible = not Main.Visible
    end
end)

-- Keep spectating after respawn
LocalPlayer.CharacterAdded:Connect(function()
    if spectating then
        task.wait(0.5)
        spectate(spectating)
    end
end)

-- Initialize
for _, p in ipairs(Players:GetPlayers()) do
    createEntry(p)
end
updateTitle()

Players.PlayerAdded:Connect(function(p)
    createEntry(p)
    updateTitle()
    if espEnabled then createESP(p) end
end)

Players.PlayerRemoving:Connect(function(p)
    removeEntry(p)
    updateTitle()
end)