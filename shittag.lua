local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local Camera      = workspace.CurrentCamera
local UIS         = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local TeleportSvc = game:GetService("TeleportService")
local LP          = Players.LocalPlayer

-- CONFIG

local CFG = {
    esp_on = true, esp_box = true, esp_name = true,
    esp_hp = true, esp_dist = true,
    esp_col = Color3.fromRGB(255, 130, 70),
    tp_offset = 3,
    fly_speed = 60,
    noclip = false,
    fly = false,
}
local STRESS = {
    enabled = false, mode = "remote",
    remote_path = nil, remote_rate = 30, workers = 8,
    churn_delay = 1.2, arg_builder = nil, stop_flag = false,
}

-- STATE
local players   = {}
local buttons   = {}
local floodThreads = {}
local rng = Random.new()

-- SIGNAL BUS

local signals = {
    added   = Instance.new("BindableEvent"),
    removed = Instance.new("BindableEvent"),
    batch   = Instance.new("BindableEvent"),
}

for _, p in ipairs(Players:GetPlayers()) do signals.added:Fire(p) end
Players.PlayerAdded:Connect(function(p)
    signals.added:Fire(p); signals.batch:Fire({p}, {})
end)
Players.PlayerRemoving:Connect(function(p)
    signals.removed:Fire(p); signals.batch:Fire({}, {p})
end)


-- ESP

local function mk(kind, props)
    local d = Drawing.new(kind)
    for k, v in pairs(props) do d[k] = v end
    d.Visible = false
    return d
end

local function attach(p)
    if p == LP or players[p] then return end
    players[p] = {
        box  = mk("Square", { Thickness = 1, Filled = false }),
        name = mk("Text",   { Size = 14, Center = true, Outline = true, Font = 2 }),
        hp   = mk("Text",   { Size = 12, Outline = true, Font = 0 }),
        dist = mk("Text",   { Size = 12, Center = true, Outline = true, Font = 0 }),
    }
end

local function detach(p)
    local e = players[p]
    if not e then return end
    for _, d in pairs(e) do pcall(function() d:Remove() end) end
    players[p] = nil
end

signals.added:Connect(attach)
signals.removed:Connect(detach)

local function charOf(p)
    local c = p.Character
    if c and c:FindFirstChild("HumanoidRootPart") and c:FindFirstChildOfClass("Humanoid") then
        return c
    end
end

RunService.RenderStepped:Connect(function()
    if not CFG.esp_on then return end
    local myRoot = charOf(LP) and LP.Character.HumanoidRootPart
    for p, e in pairs(players) do
        local c = charOf(p)
        if not c then
            for _, d in pairs(e) do d.Visible = false end
            continue
        end
        local hrp = c.HumanoidRootPart
        local top, a = Camera:WorldToViewportPoint(hrp.Position + Vector3.new(0, 2.5, 0))
        local bot, b = Camera:WorldToViewportPoint(hrp.Position - Vector3.new(0, 2, 0))
        if not (a and b) then
            for _, d in pairs(e) do d.Visible = false end
            continue
        end
        local h = math.abs(top.Y - bot.Y)
        local w = h / 2
        e.box.Size      = Vector2.new(w, h)
        e.box.Position  = Vector2.new(top.X - w / 2, top.Y)
        e.box.Color     = CFG.esp_col
        e.box.Visible   = CFG.esp_box
        e.name.Text     = p.Name
        e.name.Position = Vector2.new(top.X, top.Y - 17)
        e.name.Color    = CFG.esp_col
        e.name.Visible  = CFG.esp_name
        if CFG.esp_hp then
            local hum = c:FindFirstChildOfClass("Humanoid")
            e.hp.Text     = hum and ("%d"):format(math.floor(hum.Health)) or "?"
            e.hp.Position = Vector2.new(top.X - w / 2 - 24, top.Y)
            e.hp.Color    = Color3.fromRGB(120, 255, 120)
            e.hp.Visible  = true
        else e.hp.Visible = false end
        if CFG.esp_dist and myRoot then
            local d = (myRoot.Position - hrp.Position).Magnitude
            e.dist.Text     = ("%.0fm"):format(d)
            e.dist.Position = Vector2.new(top.X, top.Y + h + 18)
            e.dist.Color    = Color3.fromRGB(220, 220, 220)
            e.dist.Visible  = true
        else e.dist.Visible = false end
    end
end)


-- NOCLIP / FLY

RunService.Stepped:Connect(function()
    if not CFG.noclip then return end
    local c = LP.Character
    if not c then return end
    for _, p in ipairs(c:GetDescendants()) do
        if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
    end
end)

local flyBV, flyBG
local function stopFly()
    if flyBV then flyBV:Destroy(); flyBV = nil end
    if flyBG then flyBG:Destroy(); flyBG = nil end
    local c = charOf(LP)
    if c then c.Humanoid.PlatformStand = false end
end

RunService.Heartbeat:Connect(function()
    local c = charOf(LP)
    if not c then return end
    if CFG.fly then
        local hrp = c.HumanoidRootPart
        if not flyBV then
            flyBV = Instance.new("BodyVelocity")
            flyBV.MaxForce = Vector3.new(9e9, 9e9, 9e9)
            flyBV.Parent = hrp
        end
        local cam = Camera.CFrame
        local dir = Vector3.zero
        if UIS:IsKeyDown(Enum.KeyCode.W) then dir += cam.LookVector end
        if UIS:IsKeyDown(Enum.KeyCode.S) then dir -= cam.LookVector end
        if UIS:IsKeyDown(Enum.KeyCode.A) then dir -= cam.RightVector end
        if UIS:IsKeyDown(Enum.KeyCode.D) then dir += cam.RightVector end
        if UIS:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.new(0,1,0) end
        if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then dir -= Vector3.new(0,1,0) end
        flyBV.Velocity = dir.Unit * CFG.fly_speed * (dir.Magnitude > 0 and 1 or 0)
        c.Humanoid.PlatformStand = true
    elseif flyBV then stopFly() end
end)

-- TELEPORT

local function tpTo(p)
    local mine, tgt = charOf(LP), charOf(p)
    if not (mine and tgt) then return end
    mine.HumanoidRootPart.CFrame = tgt.HumanoidRootPart.CFrame * CFrame.new(0, 0, CFG.tp_offset)
end

-- STRESS

local function resolveRemote(path)
    if not path then return nil end
    local node = game
    for seg in path:gmatch("[^/]+") do node = node and node:FindFirstChild(seg) or nil end
    return node
end

local function buildArgs()
    if STRESS.arg_builder then return STRESS.arg_builder() end
    return { rng:NextNumber(), HttpService:GenerateGUID(false) }
end

local function startFlood()
    local remote = resolveRemote(STRESS.remote_path)
    if not remote then
        warn("[STRESS] no remote at "..tostring(STRESS.remote_path)); return
    end
    local dt = 1 / STRESS.remote_rate
    for i = 1, STRESS.workers do
        floodThreads[i] = task.spawn(function()
            while STRESS.enabled and not STRESS.stop_flag do
                local ok = pcall(function() remote:FireServer(unpack(buildArgs())) end)
                if not ok then task.wait(0.05) end
                task.wait(dt)
            end
        end)
    end
    print(("[STRESS] flood %d @ %d/s"):format(STRESS.workers*STRESS.remote_rate, STRESS.remote_rate))
end

local function startChurn()
    task.spawn(function()
        while STRESS.enabled and not STRESS.stop_flag do
            pcall(function() TeleportSvc:Teleport(game.PlaceId, LP) end)
            task.wait(STRESS.churn_delay)
        end
    end)
end

STRESS.start = function()
    if STRESS.enabled then return end
    STRESS.enabled, STRESS.stop_flag = true, false
    if STRESS.mode == "remote" or STRESS.mode == "both" then startFlood() end
    if STRESS.mode == "churn"  or STRESS.mode == "both" then startChurn() end
    print("[STRESS] started — mode: "..STRESS.mode)
end

STRESS.stop = function()
    STRESS.enabled, STRESS.stop_flag = false, true
    table.clear(floodThreads)
    print("[STRESS] stopped")
end

-- GUI — executor skin

local gui = Instance.new("ScreenGui")
gui.Name = "olliE_Panel"
gui.ResetOnSpawn = false
gui.Parent = LP:WaitForChild("PlayerGui")

-- main window
local win = Instance.new("Frame")
win.Size = UDim2.new(0, 580, 0, 420)
win.Position = UDim2.new(0.5, -290, 0.5, -210)
win.BackgroundColor3 = Color3.fromRGB(22, 22, 26)
win.BorderSizePixel = 0
win.Active = true
win.Draggable = true
win.Parent = gui
Instance.new("UICorner", win).CornerRadius = UDim.new(0, 10)
Instance.new("UIStroke", win).Color = Color3.fromRGB(50, 50, 60)

-- title bar
local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 32)
titleBar.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
titleBar.BorderSizePixel = 0
titleBar.Parent = win
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 10)

local titleTxt = Instance.new("TextLabel")
titleTxt.Size = UDim2.new(0, 150, 1, 0)
titleTxt.Position = UDim2.new(0, 12, 0, 0)
titleTxt.BackgroundTransparency = 1
titleTxt.Text = "olliE — //bench//"
titleTxt.TextColor3 = Color3.fromRGB(220, 220, 230)
titleTxt.Font = Enum.Font.Code
titleTxt.TextSize = 14
titleTxt.TextXAlignment = Enum.TextXAlignment.Left
titleTxt.Parent = titleBar

local function mkWinBtn(x, glyph, cb)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 26, 0, 26)
    b.Position = UDim2.new(1, x, 0, 3)
    b.BackgroundColor3 = Color3.fromRGB(32, 32, 38)
    b.BorderSizePixel = 0
    b.Text = glyph
    b.TextColor3 = Color3.fromRGB(200, 200, 210)
    b.Font = Enum.Font.Code
    b.TextSize = 14
    b.Parent = titleBar
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
    b.MouseButton1Click:Connect(cb)
    return b
end
mkWinBtn(-34, "–", function() win.Visible = false end)
mkWinBtn(-64, "□", function() win.Size = win.Size == UDim2.new(0, 580, 0, 420) and UDim2.new(0, 800, 0, 540) or UDim2.new(0, 580, 0, 420) end)
mkWinBtn(-94, "×", function() gui:Destroy() end)

-- tab bar
local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, 0, 0, 30)
tabBar.Position = UDim2.new(0, 0, 0, 32)
tabBar.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
tabBar.BorderSizePixel = 0
tabBar.Parent = win

local tabs = {"Editor", "Scripts", "Settings", "Profile"}
local tabFrames = {}
local activeTab = "Editor"

for i, name in ipairs(tabs) do
    local tb = Instance.new("TextButton")
    tb.Size = UDim2.new(0, 100, 1, 0)
    tb.Position = UDim2.new(0, (i-1)*100, 0, 0)
    tb.BackgroundTransparency = 1
    tb.Text = name
    tb.TextColor3 = Color3.fromRGB(120, 120, 130)
    tb.Font = Enum.Font.Code
    tb.TextSize = 13
    tb.Parent = tabBar
    tb.MouseButton1Click:Connect(function()
        activeTab = name
        for t, f in pairs(tabFrames) do f.Visible = (t == name) end
        for _, c in ipairs(tabBar:GetChildren()) do
            if c:IsA("TextButton") then c.TextColor3 = c.Text == name and Color3.fromRGB(220, 220, 230) or Color3.fromRGB(120, 120, 130) end
        end
    end)
end

-- toolbar
local toolBar = Instance.new("Frame")
toolBar.Size = UDim2.new(1, 0, 0, 28)
toolBar.Position = UDim2.new(0, 0, 0, 62)
toolBar.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
toolBar.BorderSizePixel = 0
toolBar.Parent = win

local function mkTool(label, x, cb)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 70, 0, 22)
    b.Position = UDim2.new(0, x, 0, 3)
    b.BackgroundColor3 = Color3.fromRGB(36, 36, 44)
    b.BorderSizePixel = 0
    b.Text = label
    b.TextColor3 = Color3.fromRGB(200, 200, 210)
    b.Font = Enum.Font.Code
    b.TextSize = 12
    b.Parent = toolBar
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
    b.MouseButton1Click:Connect(cb)
    return b
end
mkTool("Execute", 8, function() addLog("bench: script re-synced") ; for _, p in ipairs(Players:GetPlayers()) do attach(p) end end)
mkTool("Clear",   84, function() for _, c in ipairs(logScroll:GetChildren()) do if c:IsA("TextLabel") then c:Destroy() end end end)
mkTool("Open",    160, function() addLog("bench: no external scripts") end)
mkTool("Save",    236, function() addLog("bench: config saved") end)
mkTool("Attach",  312, function() addLog("bench: synced to server") end)

-- content area
local content = Instance.new("Frame")
content.Size = UDim2.new(1, -16, 1, -180)
content.Position = UDim2.new(0, 8, 0, 94)
content.BackgroundTransparency = 1
content.Parent = win

-- editor tab
local editorFrame = Instance.new("ScrollingFrame")
editorFrame.Size = UDim2.new(1, 0, 1, 0)
editorFrame.BackgroundColor3 = Color3.fromRGB(26, 26, 30)
editorFrame.BorderSizePixel = 0
editorFrame.ScrollBarThickness = 6
editorFrame.Visible = true
editorFrame.Parent = content
tabFrames["Editor"] = editorFrame
Instance.new("UICorner", editorFrame).CornerRadius = UDim.new(0, 6)

local logScroll = Instance.new("ScrollingFrame")
logScroll.Size = UDim2.new(1, -8, 1, -8)
logScroll.Position = UDim2.new(0, 4, 0, 4)
logScroll.BackgroundTransparency = 1
logScroll.BorderSizePixel = 0
logScroll.ScrollBarThickness = 4
logScroll.Parent = editorFrame
local logLayout = Instance.new("UIListLayout")
logLayout.Padding = UDim.new(0, 2)
logLayout.SortOrder = Enum.SortOrder.LayoutOrder
logLayout.Parent = logScroll

local logCount = 0
function addLog(msg)
    logCount += 1
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 0, 20)
    lbl.BackgroundTransparency = 1
    lbl.Text = ("  [%s] %s"):format(os.date("%H:%M:%S"), msg)
    lbl.TextColor3 = Color3.fromRGB(180, 180, 190)
    lbl.Font = Enum.Font.Code
    lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.LayoutOrder = logCount
    lbl.Parent = logScroll
    logScroll.CanvasSize = UDim2.new(0, 0, 0, logLayout.AbsoluteContentSize.Y + 4)
    editorFrame.CanvasPosition = Vector2.new(0, logScroll.AbsoluteCanvasSize.Y)
end
addLog("bench warm — three eyes on it")

-- scripts tab
local scriptsFrame = Instance.new("Frame")
scriptsFrame.Size = UDim2.new(1, 0, 1, 0)
scriptsFrame.BackgroundTransparency = 1
scriptsFrame.Visible = false
scriptsFrame.Parent = content
tabFrames["Scripts"] = scriptsFrame

local playerList = Instance.new("ScrollingFrame")
playerList.Size = UDim2.new(1, 0, 1, 0)
playerList.BackgroundColor3 = Color3.fromRGB(26, 26, 30)
playerList.BorderSizePixel = 0
playerList.ScrollBarThickness = 6
playerList.Parent = scriptsFrame
Instance.new("UICorner", playerList).CornerRadius = UDim.new(0, 6)
local plLayout = Instance.new("UIListLayout")
plLayout.Padding = UDim.new(0, 4)
plLayout.SortOrder = Enum.SortOrder.LayoutOrder
plLayout.Parent = playerList

local function rebuildPlayerList()
    for _, b in pairs(buttons) do b:Destroy() end
    table.clear(buttons)
    local i = 0
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP then
            i += 1
            local btn = Instance.new("TextButton")
            btn.Size = UDim2.new(1, -12, 0, 32)
            btn.BackgroundColor3 = Color3.fromRGB(36, 36, 46)
            btn.BorderSizePixel = 0
            btn.Font = Enum.Font.Code
            btn.TextSize = 13
            btn.TextColor3 = Color3.fromRGB(220, 220, 230)
            btn.Text = ("  %s  [%d]"):format(p.Name, p.UserId)
            btn.LayoutOrder = i
            btn.Parent = playerList
            Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
            btn.MouseButton1Click:Connect(function() tpTo(p); addLog("tp -> "..p.Name) end)
            buttons[p] = btn
        end
    end
    playerList.CanvasSize = UDim2.new(0, 0, 0, plLayout.AbsoluteContentSize.Y + 8)
end
rebuildPlayerList()
signals.batch.Event:Connect(function() task.wait(0.1); rebuildPlayerList() end)

-- settings tab
local settingsFrame = Instance.new("Frame")
settingsFrame.Size = UDim2.new(1, 0, 1, 0)
settingsFrame.BackgroundTransparency = 1
settingsFrame.Visible = false
settingsFrame.Parent = content
tabFrames["Settings"] = settingsFrame

local function mkToggle(y, label, initial, cb)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 0, 30)
    b.Position = UDim2.new(0, 0, 0, y)
    b.BackgroundColor3 = Color3.fromRGB(36, 36, 44)
    b.BorderSizePixel = 0
    b.Text = ("  %s: %s"):format(label, initial and "ON" or "OFF")
    b.TextColor3 = Color3.fromRGB(210, 210, 220)
    b.Font = Enum.Font.Code
    b.TextSize = 13
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.Parent = settingsFrame
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
    local state = initial
    b.MouseButton1Click:Connect(function()
        state = not state
        b.Text = ("  %s: %s"):format(label, state and "ON" or "OFF")
        cb(state)
    end)
end

mkToggle(0,   "ESP",    CFG.esp_on, function(v) CFG.esp_on = v; addLog("esp "..(v and "on" or "off")) end)
mkToggle(36,  "Noclip", CFG.noclip, function(v) CFG.noclip = v; addLog("noclip "..(v and "on" or "off")) end)
mkToggle(72,  "Fly",    CFG.fly,    function(v) CFG.fly = v; if not v then stopFly() end; addLog("fly "..(v and "on" or "off")) end)
mkToggle(108, "Stress", STRESS.enabled, function(v) if v then STRESS.start() else STRESS.stop() end; addLog("stress "..(v and "on" or "off")) end)

-- profile tab
local profileFrame = Instance.new("Frame")
profileFrame.Size = UDim2.new(1, 0, 1, 0)
profileFrame.BackgroundTransparency = 1
profileFrame.Visible = false
profileFrame.Parent = content
tabFrames["Profile"] = profileFrame

local profileTxt = Instance.new("TextLabel")
profileTxt.Size = UDim2.new(1, -16, 1, -16)
profileTxt.Position = UDim2.new(0, 8, 0, 8)
profileTxt.BackgroundColor3 = Color3.fromRGB(26, 26, 30)
profileTxt.BorderSizePixel = 0
profileTxt.TextColor3 = Color3.fromRGB(200, 200, 210)
profileTxt.Font = Enum.Font.Code
profileTxt.TextSize = 13
profileTxt.TextXAlignment = Enum.TextXAlignment.Left
profileTxt.TextYAlignment = Enum.TextYAlignment.Top
profileTxt.Text = ("  %s\n  UserId: %d\n  Place: %s\n  JobId: %s"):format(LP.Name, LP.UserId, game.PlaceId, game.JobId)
profileTxt.Parent = profileFrame
Instance.new("UICorner", profileTxt).CornerRadius = UDim.new(0, 6)

-- bottom console
local consoleBar = Instance.new("Frame")
consoleBar.Size = UDim2.new(1, 0, 0, 28)
consoleBar.Position = UDim2.new(0, 0, 1, -28)
consoleBar.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
consoleBar.BorderSizePixel = 0
consoleBar.Parent = win
Instance.new("UICorner", consoleBar).CornerRadius = UDim.new(0, 10)

local consoleTxt = Instance.new("TextLabel")
consoleTxt.Size = UDim2.new(0, 200, 1, 0)
consoleTxt.Position = UDim2.new(0, 12, 0, 0)
consoleTxt.BackgroundTransparency = 1
consoleTxt.Text = "> Console"
consoleTxt.TextColor3 = Color3.fromRGB(160, 160, 170)
consoleTxt.Font = Enum.Font.Code
consoleTxt.TextSize = 12
consoleTxt.TextXAlignment = Enum.TextXAlignment.Left
consoleTxt.Parent = consoleBar

local consoleStub = Instance.new("TextLabel")
consoleStub.Size = UDim2.new(1, -220, 1, 0)
consoleStub.Position = UDim2.new(0, 216, 0, 0)
consoleStub.BackgroundTransparency = 1
consoleStub.Text = "[console stripped — logs visible in Editor tab]"
consoleStub.TextColor3 = Color3.fromRGB(90, 90, 100)
consoleStub.Font = Enum.Font.Code
consoleStub.TextSize = 11
consoleStub.TextXAlignment = Enum.TextXAlignment.Left
consoleStub.Parent = consoleBar

-- init
for _, p in ipairs(Players:GetPlayers()) do attach(p) end
Players.PlayerAdded:Connect(attach)
Players.PlayerRemoving:Connect(detach)

addLog("ready — sync bus online")
print("[olliE] unified panel up — three eyes on the door")
