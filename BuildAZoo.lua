--[[
	Build A Zoo — Hub Script (Xeno)
	Multi-tab UI: Main | Fishing | Movements | Settings
	Language: EN / VN toggle
	Author: generated for user via MCP reverse-engineering
]]

--// Services
local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local RunService         = game:GetService("RunService")
local UserInputService   = game:GetService("UserInputService")
local Workspace          = game:GetService("Workspace")
local TweenService       = game:GetService("TweenService")
local VirtualUser        = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer
local Remote      = ReplicatedStorage:WaitForChild("Remote")

--// Remotes (verified via reverse-engineering)
local CharacterRE = Remote:FindFirstChild("CharacterRE")
local LotteryRE   = Remote:FindFirstChild("LotteryRE")
local ConveyorRE  = Remote:FindFirstChild("ConveyorRE")
local PetRE       = Remote:FindFirstChild("PetRE")
local FishingRE   = Remote:FindFirstChild("FishingRE")
local SeasonPassRE= Remote:FindFirstChild("SeasonPassRE")
local DinoEventRE = Remote:FindFirstChild("DinoEventRE")

--// Player data (replicated attributes)
local function getData()
	local pg = LocalPlayer:FindFirstChild("PlayerGui")
	return pg and pg:FindFirstChild("Data")
end

--============================================================
--  STATE
--============================================================
local State = {
	-- Main
	AutoClaimCoins   = false,
	ClaimDelay       = 1.0,
	CoinsX2AntiLag   = false,
	AutoLotto        = false,
	AutoConveyor     = false,
	NoClient         = false,
	AutoDinoTasks    = false,
	AutoSeasonPass   = false,
	-- Fishing
	AutoFish         = false,
	WaterMethodDelay = 0.5,
	InfiniteAutoFish = false,
	AutoFishDelay    = 1.0,
	InstantSkip      = false,
	FullAutoFish     = false,
	-- Movements
	AntiAFK          = false,
	InfiniteJump     = false,
	WalkSpeed        = 16,
	WalkSpeedOn      = false,
	Noclip           = false,
	Gravity          = 196.2,
	JumpPower        = 50,
	JumpPowerOn      = false,
	FieldOfView      = 70,
	-- Settings
	Language         = "EN",
	UIBlur           = false,
	UITransparency   = 0,
	MinimizeKey      = Enum.KeyCode.RightControl,
}

--============================================================
--  LANGUAGE STRINGS
--============================================================
local L = {
	EN = {
		Title="Build A Zoo Hub", Main="Main", Fishing="Fishing", Movements="Movements", Settings="Settings",
		AutoClaimCoins="Auto Claim Coins", ClaimDelay="Claim Delay", CoinsX2="Coins X2 / Anti Lag",
		NoClient="No Client (Hide Others)", DinoTasks="Dino Tasks", SeasonPass="Auto Claim Season Pass",
		AutoLotto="Auto Lotto", AutoConveyor="Auto Conveyor",
		AutoFish="Auto Fish / Water Method", WaterDelay="Water Method Delay",
		InfFish="Infinite Auto Fish / Any Position", FishDelay="Auto Fish Delay",
		InstantSkip="Instant Skip", FullFish="Full Auto Fish",
		AntiAFK="Anti AFK", InfJump="Infinite Jump", WalkSpeed="Walk Speed", Noclip="Noclip",
		Gravity="Gravity", JumpPower="Jump Power", FOV="Field of View",
		MinKey="Minimize Keybind", UIBlur="UI Blur", UITrans="UI Transparency", Lang="Language",
	},
	VN = {
		Title="Build A Zoo Hub", Main="Chính", Fishing="Câu Cá", Movements="Di Chuyển", Settings="Cài Đặt",
		AutoClaimCoins="Tự Động Nhặt Xu", ClaimDelay="Độ Trễ Nhặt", CoinsX2="Nhân Đôi Xu / Chống Lag",
		NoClient="Ẩn Người Chơi Khác", DinoTasks="Nhiệm Vụ Khủng Long", SeasonPass="Tự Nhận Season Pass",
		AutoLotto="Tự Quay Số", AutoConveyor="Tự Băng Chuyền",
		AutoFish="Tự Câu Cá / Cách Nước", WaterDelay="Độ Trễ Cách Nước",
		InfFish="Câu Vô Hạn / Mọi Vị Trí", FishDelay="Độ Trễ Câu",
		InstantSkip="Bỏ Qua Tức Thì", FullFish="Tự Câu Toàn Bộ",
		AntiAFK="Chống Treo (AFK)", InfJump="Nhảy Vô Hạn", WalkSpeed="Tốc Độ Chạy", Noclip="Xuyên Tường",
		Gravity="Trọng Lực", JumpPower="Lực Nhảy", FOV="Góc Nhìn (FOV)",
		MinKey="Phím Thu Nhỏ", UIBlur="Làm Mờ Nền", UITrans="Độ Trong Suốt", Lang="Ngôn Ngữ",
	},
}
local function T(k) return (L[State.Language] or L.EN)[k] or k end

--============================================================
--  NOTIFY
--============================================================
local function notify(title, text, dur)
	pcall(function()
		game:GetService("StarterGui"):SetCore("SendNotification", {
			Title = title, Text = text, Duration = dur or 3,
		})
	end)
end

--============================================================
--  HELPERS: character / hrp
--============================================================
local function getChar() return LocalPlayer.Character end
local function getHRP()
	local c = getChar()
	return c and c:FindFirstChild("HumanoidRootPart")
end
local function getHum()
	local c = getChar()
	return c and c:FindFirstChildOfClass("Humanoid")
end

--============================================================
--  FEATURE: AUTO CLAIM COINS  (works for ALL placed pets)
--  Mechanic: every owned pet produces coins collected via its
--  ProximityPrompt. The server validates your character distance
--  server-side, so we must be near the pet. We snapshot the
--  character CFrame, quickly "flick" to each pet (position-only),
--  enable + fire its prompt, then instantly restore — so from the
--  player's view you stay in one spot.
--  IMPORTANT: only BIG pets expose pending coins in the "Coin"
--  attribute. Small/garden pets ALWAYS report Coin=0 yet still hold
--  claimable coins (confirmed: firing a small pet's prompt gained
--  ~88M with Coin reading 0). So we must claim EVERY owned pet that
--  has a prompt — never gate on Coin>0, or small pets are skipped.
--  Fixes vs old version:
--    * claims every owned pet (dropped the Coin>0 filter) so small
--      garden pets are collected, not just big pets
--    * uses pet.Position (not pet.CFrame) so rotation never throws
--      the character off the grid
--    * force-enables the prompt (garden prompts are disabled until
--      someone is close) before firing
--    * does NOT anchor the HRP — anchoring makes the server reject
--      the position update so nothing gets claimed
--============================================================
local claimBusy = false
local function claimAllCoins()
	if claimBusy then return end
	claimBusy = true
	local ok, err = pcall(function()
		local hrp = getHRP()
		local petsFolder = Workspace:FindFirstChild("Pets")
		if not hrp or not petsFolder then return end
		local myId = LocalPlayer.UserId

		-- collect every owned pet that has a prompt (small pets report
		-- Coin=0 but still hold coins, so we do NOT filter on Coin)
		local targets = {}
		for _, pet in ipairs(petsFolder:GetChildren()) do
			if pet:GetAttribute("UserId") == myId then
				local prompt
				for _, d in ipairs(pet:GetDescendants()) do
					if d:IsA("ProximityPrompt") then prompt = d break end
				end
				if prompt then targets[#targets + 1] = { pet = pet, prompt = prompt } end
			end
		end
		if #targets == 0 then return end

		local origin = hrp.CFrame
		for _, t in ipairs(targets) do
			if not State.AutoClaimCoins then break end
			if t.pet.Parent then
				hrp.CFrame = CFrame.new(t.pet.Position + Vector3.new(0, 3, 0))
				task.wait(0.08)
				pcall(function() t.prompt.Enabled = true end)
				pcall(fireproximityprompt, t.prompt)
				task.wait(0.07)
			end
		end
		hrp.CFrame = origin
	end)
	claimBusy = false
	return ok
end

--============================================================
--  FEATURE: AUTO LOTTO
--============================================================
local function fireLotto()
	if not LotteryRE then return end
	local Data = getData()
	local asset = Data and Data:FindFirstChild("Asset")
	local tickets = asset and (asset:GetAttribute("LotteryTicket") or 0) or 0
	if tickets >= 1 then
		pcall(function() LotteryRE:FireServer({ event = "lottery" }) end)
	end
end

--============================================================
--  FEATURE: AUTO CONVEYOR (switch to newest unlocked line)
--============================================================
local function fireConveyor()
	if not ConveyorRE then return end
	local Data = getData()
	local gf = Data and Data:FindFirstChild("GameFlag")
	local maxLine = gf and (gf:GetAttribute("Conveyor") or 1) or 1
	pcall(function() ConveyorRE:FireServer("Switch", maxLine) end)
end

--============================================================
--  FEATURE: AUTO DINO TASKS / SEASON PASS (claim rewards)
--============================================================
local function fireDinoClaim()
	if not DinoEventRE then return end
	pcall(function() DinoEventRE:FireServer("ClaimAll") end)
	pcall(function() DinoEventRE:FireServer({ event = "claimall" }) end)
end
local function fireSeasonPassClaim()
	if not SeasonPassRE then return end
	pcall(function() SeasonPassRE:FireServer("ClaimAll") end)
	pcall(function() SeasonPassRE:FireServer({ event = "claimall" }) end)
end

--============================================================
--  FEATURE: AUTO FISH
--  Confirmed mechanic (game's own CS_AutoFish):
--    - GameFlag.AutoFishFlag drives the loop
--    - Char must sit on the fishing rod Attachment.WorldCFrame
--    - FishingRE:FireServer("ContinueAutoFish") advances a cast
--  InstantSkip / FullAutoFish just tighten the loop timing.
--============================================================
local function findFishAttachment()
	local best
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("Attachment") and d.Parent and d.Parent.Name:lower():find("fishingrob") then
			best = d
			local env = d:FindFirstAncestorWhichIsA("Model")
			if env and env:GetAttribute("IslandID") == LocalPlayer:GetAttribute("AssignedIslandName") then
				return d
			end
		end
	end
	return best
end

local function fireFishOnce()
	if not FishingRE then return end
	-- Optionally reposition onto rod unless "Any Position" (InfiniteAutoFish) is on
	if not State.InfiniteAutoFish then
		local att = findFishAttachment()
		local char = getChar()
		if att and char then pcall(function() char:PivotTo(att.WorldCFrame) end) end
	end
	pcall(function() FishingRE:FireServer("ContinueAutoFish") end)
	if State.InstantSkip or State.FullAutoFish then
		pcall(function() FishingRE:FireServer("SkipFishing") end)
		pcall(function() FishingRE:FireServer("Complete") end)
	end
end

--============================================================
--  FEATURE: MOVEMENTS
--============================================================
local function applyWalkSpeed()
	local hum = getHum()
	if hum then hum.WalkSpeed = State.WalkSpeedOn and State.WalkSpeed or 16 end
end
local function applyJumpPower()
	local hum = getHum()
	if hum then
		hum.UseJumpPower = true
		hum.JumpPower = State.JumpPowerOn and State.JumpPower or 50
	end
end
local function applyGravity()
	Workspace.Gravity = State.Gravity
end
local function applyFOV()
	local cam = Workspace.CurrentCamera
	if cam then cam.FieldOfView = State.FieldOfView end
end

-- Noclip loop
local noclipConn
local function setNoclip(on)
	State.Noclip = on
	if on then
		if noclipConn then return end
		noclipConn = RunService.Stepped:Connect(function()
			local char = getChar()
			if char and State.Noclip then
				for _, p in ipairs(char:GetDescendants()) do
					if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
				end
			end
		end)
	else
		if noclipConn then noclipConn:Disconnect() noclipConn = nil end
	end
end

-- Infinite Jump
UserInputService.JumpRequest:Connect(function()
	if State.InfiniteJump then
		local hum = getHum()
		if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
	end
end)

-- Anti AFK
LocalPlayer.Idled:Connect(function()
	if State.AntiAFK then
		pcall(function()
			VirtualUser:CaptureController()
			VirtualUser:ClickButton2(Vector2.new())
		end)
	end
end)

-- Re-apply movement values when character respawns
LocalPlayer.CharacterAdded:Connect(function()
	task.wait(1)
	applyWalkSpeed(); applyJumpPower()
	if State.Noclip then setNoclip(true) end
end)

--============================================================
--  AUTOMATION LOOPS
--============================================================
task.spawn(function()
	while true do
		if State.AutoClaimCoins then pcall(claimAllCoins) end
		task.wait(math.max(0.1, State.ClaimDelay))
	end
end)

task.spawn(function()
	while true do
		if State.AutoLotto then pcall(fireLotto) end
		task.wait(1.5)
	end
end)

task.spawn(function()
	while true do
		if State.AutoConveyor then pcall(fireConveyor) end
		task.wait(5)
	end
end)

task.spawn(function()
	while true do
		if State.AutoDinoTasks then pcall(fireDinoClaim) end
		if State.AutoSeasonPass then pcall(fireSeasonPassClaim) end
		task.wait(10)
	end
end)

task.spawn(function()
	while true do
		if State.AutoFish then pcall(fireFishOnce) end
		task.wait(math.max(0.1, State.AutoFishDelay))
	end
end)

-- keep FOV/gravity enforced lightly
task.spawn(function()
	while true do
		if State.FieldOfView ~= 70 then applyFOV() end
		task.wait(0.5)
	end
end)

--============================================================
--  UI FRAMEWORK
--============================================================
local COL = {
	Bg      = Color3.fromRGB(24, 26, 32),
	Panel   = Color3.fromRGB(32, 35, 43),
	Item    = Color3.fromRGB(40, 44, 54),
	Accent  = Color3.fromRGB(88, 132, 255),
	AccentOn= Color3.fromRGB(70, 200, 120),
	Text    = Color3.fromRGB(235, 238, 245),
	SubText = Color3.fromRGB(150, 156, 170),
	Off     = Color3.fromRGB(70, 74, 86),
}

local function corner(inst, r)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = inst; return c
end
local function pad(inst, p)
	local u = Instance.new("UIPadding")
	u.PaddingLeft = UDim.new(0,p); u.PaddingRight = UDim.new(0,p)
	u.PaddingTop = UDim.new(0,p); u.PaddingBottom = UDim.new(0,p)
	u.Parent = inst; return u
end

-- destroy old
local existing = (gethui and gethui() or game:GetService("CoreGui")):FindFirstChild("BAZ_Hub")
if existing then existing:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "BAZ_Hub"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.IgnoreGuiInset = true
pcall(function() ScreenGui.Parent = gethui and gethui() or game:GetService("CoreGui") end)
if not ScreenGui.Parent then ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

-- Blur (Settings > UI Blur)
local blur = Instance.new("BlurEffect")
blur.Size = 0
blur.Parent = game:GetService("Lighting")

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.new(0, 560, 0, 380)
Main.Position = UDim2.new(0.5, -280, 0.5, -190)
Main.BackgroundColor3 = COL.Bg
Main.BorderSizePixel = 0
Main.Parent = ScreenGui
corner(Main, 12)

local stroke = Instance.new("UIStroke")
stroke.Color = COL.Accent
stroke.Thickness = 1.5
stroke.Transparency = 0.4
stroke.Parent = Main

-- Title bar
local TitleBar = Instance.new("Frame")
TitleBar.Name = "TitleBar"
TitleBar.Size = UDim2.new(1, 0, 0, 42)
TitleBar.BackgroundColor3 = COL.Panel
TitleBar.BorderSizePixel = 0
TitleBar.Parent = Main
corner(TitleBar, 12)

local TitleLbl = Instance.new("TextLabel")
TitleLbl.BackgroundTransparency = 1
TitleLbl.Position = UDim2.new(0, 16, 0, 0)
TitleLbl.Size = UDim2.new(1, -120, 1, 0)
TitleLbl.Font = Enum.Font.GothamBold
TitleLbl.TextSize = 18
TitleLbl.TextColor3 = COL.Text
TitleLbl.TextXAlignment = Enum.TextXAlignment.Left
TitleLbl.Text = T("Title")
TitleLbl.Parent = TitleBar

-- Language pill (EN/VN) in titlebar
local LangBtn = Instance.new("TextButton")
LangBtn.Size = UDim2.new(0, 46, 0, 26)
LangBtn.Position = UDim2.new(1, -104, 0.5, -13)
LangBtn.BackgroundColor3 = COL.Accent
LangBtn.Text = State.Language
LangBtn.Font = Enum.Font.GothamBold
LangBtn.TextSize = 13
LangBtn.TextColor3 = COL.Text
LangBtn.AutoButtonColor = true
LangBtn.Parent = TitleBar
corner(LangBtn, 6)

-- Minimize button
local MinBtn = Instance.new("TextButton")
MinBtn.Size = UDim2.new(0, 26, 0, 26)
MinBtn.Position = UDim2.new(1, -52, 0.5, -13)
MinBtn.BackgroundColor3 = COL.Item
MinBtn.Text = "_"
MinBtn.Font = Enum.Font.GothamBold
MinBtn.TextSize = 16
MinBtn.TextColor3 = COL.Text
MinBtn.Parent = TitleBar
corner(MinBtn, 6)

-- Close button
local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 26, 0, 26)
CloseBtn.Position = UDim2.new(1, -22, 0.5, -13)
CloseBtn.BackgroundColor3 = Color3.fromRGB(200, 70, 70)
CloseBtn.Text = "X"
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 13
CloseBtn.TextColor3 = COL.Text
CloseBtn.Parent = TitleBar
corner(CloseBtn, 6)

-- Tab column
local TabCol = Instance.new("Frame")
TabCol.Name = "TabCol"
TabCol.Position = UDim2.new(0, 0, 0, 42)
TabCol.Size = UDim2.new(0, 130, 1, -42)
TabCol.BackgroundColor3 = COL.Panel
TabCol.BorderSizePixel = 0
TabCol.Parent = Main
local tabList = Instance.new("UIListLayout")
tabList.Padding = UDim.new(0, 6)
tabList.Parent = TabCol
pad(TabCol, 8)

-- Content area (scrolling)
local Content = Instance.new("ScrollingFrame")
Content.Name = "Content"
Content.Position = UDim2.new(0, 138, 0, 50)
Content.Size = UDim2.new(1, -146, 1, -58)
Content.BackgroundTransparency = 1
Content.BorderSizePixel = 0
Content.ScrollBarThickness = 4
Content.ScrollBarImageColor3 = COL.Accent
Content.CanvasSize = UDim2.new(0, 0, 0, 0)
Content.AutomaticCanvasSize = Enum.AutomaticSize.Y
Content.Parent = Main
local contentList = Instance.new("UIListLayout")
contentList.Padding = UDim.new(0, 8)
contentList.Parent = Content

--============================================================
--  WIDGET FACTORY  (widgets register a relabel fn for EN/VN)
--============================================================
local relabelers = {}   -- functions called on language switch
local tabs       = {}   -- name -> {btn=, page={widgets}}
local currentTab

local function makeRow(height)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -4, 0, height or 40)
	row.BackgroundColor3 = COL.Item
	row.BorderSizePixel = 0
	row.Visible = false
	row.Parent = Content
	corner(row, 8)
	return row
end

-- Toggle: labelKey, initial, callback(bool)
local function addToggle(labelKey, getInit, cb)
	local row = makeRow(40)
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Position = UDim2.new(0, 12, 0, 0)
	lbl.Size = UDim2.new(1, -70, 1, 0)
	lbl.Font = Enum.Font.GothamMedium
	lbl.TextSize = 14
	lbl.TextColor3 = COL.Text
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Text = T(labelKey)
	lbl.Parent = row

	local sw = Instance.new("TextButton")
	sw.Size = UDim2.new(0, 44, 0, 22)
	sw.Position = UDim2.new(1, -56, 0.5, -11)
	sw.Text = ""
	sw.AutoButtonColor = false
	sw.Parent = row
	corner(sw, 11)
	local knob = Instance.new("Frame")
	knob.Size = UDim2.new(0, 18, 0, 18)
	knob.Position = UDim2.new(0, 2, 0.5, -9)
	knob.BorderSizePixel = 0
	knob.BackgroundColor3 = COL.Text
	knob.Parent = sw
	corner(knob, 9)

	local function render(on)
		sw.BackgroundColor3 = on and COL.AccentOn or COL.Off
		knob:TweenPosition(on and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9),
			Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.15, true)
	end
	local state = getInit()
	render(state)
	sw.MouseButton1Click:Connect(function()
		state = not state
		render(state)
		cb(state)
	end)
	table.insert(relabelers, function() lbl.Text = T(labelKey) end)
	return row
end

-- Slider: labelKey, min, max, getInit, cb(number), decimals
local function addSlider(labelKey, minV, maxV, getInit, cb, decimals)
	local row = makeRow(52)
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Position = UDim2.new(0, 12, 0, 4)
	lbl.Size = UDim2.new(1, -24, 0, 20)
	lbl.Font = Enum.Font.GothamMedium
	lbl.TextSize = 14
	lbl.TextColor3 = COL.Text
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Parent = row

	local track = Instance.new("Frame")
	track.Position = UDim2.new(0, 12, 0, 34)
	track.Size = UDim2.new(1, -24, 0, 8)
	track.BackgroundColor3 = COL.Off
	track.BorderSizePixel = 0
	track.Parent = row
	corner(track, 4)
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = COL.Accent
	fill.BorderSizePixel = 0
	fill.Parent = track
	corner(fill, 4)

	local value = getInit()
	local function fmt(v)
		if decimals and decimals > 0 then return string.format("%."..decimals.."f", v) end
		return tostring(math.floor(v))
	end
	local function render()
		local a = (value - minV) / (maxV - minV)
		a = math.clamp(a, 0, 1)
		fill.Size = UDim2.new(a, 0, 1, 0)
		lbl.Text = T(labelKey) .. ": " .. fmt(value)
	end
	render()

	local dragging = false
	local function setFromX(x)
		local a = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		value = minV + a * (maxV - minV)
		if not decimals or decimals == 0 then value = math.floor(value + 0.5) end
		render()
		cb(value)
	end
	track.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = true; setFromX(i.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			setFromX(i.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	table.insert(relabelers, render)
	return row
end

--============================================================
--  TAB SYSTEM
--============================================================
local function selectTab(name)
	currentTab = name
	for n, t in pairs(tabs) do
		local sel = (n == name)
		t.btn.BackgroundColor3 = sel and COL.Accent or COL.Item
		for _, w in ipairs(t.page) do w.Visible = sel end
	end
end

local function addTab(nameKey)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 0, 36)
	btn.BackgroundColor3 = COL.Item
	btn.Text = T(nameKey)
	btn.Font = Enum.Font.GothamMedium
	btn.TextSize = 14
	btn.TextColor3 = COL.Text
	btn.AutoButtonColor = false
	btn.Parent = TabCol
	corner(btn, 8)
	local entry = { btn = btn, page = {}, key = nameKey }
	tabs[nameKey] = entry
	btn.MouseButton1Click:Connect(function() selectTab(nameKey) end)
	table.insert(relabelers, function() btn.Text = T(nameKey) end)
	-- widgets added while this tab is "active target"
	entry.add = function(widget) table.insert(entry.page, widget) end
	return entry
end

--============================================================
--  BUILD TABS + WIDGETS
--============================================================
-- MAIN
local mainTab = addTab("Main")
mainTab.add(addToggle("AutoClaimCoins", function() return State.AutoClaimCoins end, function(v) State.AutoClaimCoins = v end))
mainTab.add(addSlider("ClaimDelay", 0.1, 5, function() return State.ClaimDelay end, function(v) State.ClaimDelay = v end, 1))
mainTab.add(addToggle("CoinsX2", function() return State.CoinsX2AntiLag end, function(v)
	State.CoinsX2AntiLag = v
	-- Anti-Lag: lower rendering + hide far pets for perf; toggles graphics quality
	pcall(function()
		if v then
			for _, p in ipairs(Workspace:GetDescendants()) do
				if p:IsA("ParticleEmitter") or p:IsA("Trail") then p.Enabled = false end
			end
			settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
		end
	end)
end))
mainTab.add(addToggle("AutoLotto", function() return State.AutoLotto end, function(v) State.AutoLotto = v end))
mainTab.add(addToggle("AutoConveyor", function() return State.AutoConveyor end, function(v) State.AutoConveyor = v end))
mainTab.add(addToggle("NoClient", function() return State.NoClient end, function(v)
	State.NoClient = v
	pcall(function()
		local myModel = LocalPlayer.Character and LocalPlayer.Character.Name
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= LocalPlayer and plr.Character then
				for _, part in ipairs(plr.Character:GetDescendants()) do
					if part:IsA("BasePart") or part:IsA("Decal") then
						part.Transparency = v and 1 or 0
					end
				end
			end
		end
	end)
end))
mainTab.add(addToggle("DinoTasks", function() return State.AutoDinoTasks end, function(v) State.AutoDinoTasks = v end))
mainTab.add(addToggle("SeasonPass", function() return State.AutoSeasonPass end, function(v) State.AutoSeasonPass = v end))

-- FISHING
local fishTab = addTab("Fishing")
fishTab.add(addToggle("AutoFish", function() return State.AutoFish end, function(v) State.AutoFish = v end))
fishTab.add(addSlider("WaterDelay", 0.1, 3, function() return State.WaterMethodDelay end, function(v) State.WaterMethodDelay = v end, 1))
fishTab.add(addToggle("InfFish", function() return State.InfiniteAutoFish end, function(v) State.InfiniteAutoFish = v end))
fishTab.add(addSlider("FishDelay", 0.1, 5, function() return State.AutoFishDelay end, function(v) State.AutoFishDelay = v end, 1))
fishTab.add(addToggle("InstantSkip", function() return State.InstantSkip end, function(v) State.InstantSkip = v end))
fishTab.add(addToggle("FullFish", function() return State.FullAutoFish end, function(v) State.FullAutoFish = v end))

-- MOVEMENTS
local moveTab = addTab("Movements")
moveTab.add(addToggle("AntiAFK", function() return State.AntiAFK end, function(v) State.AntiAFK = v end))
moveTab.add(addToggle("InfJump", function() return State.InfiniteJump end, function(v) State.InfiniteJump = v end))
moveTab.add(addToggle("WalkSpeed", function() return State.WalkSpeedOn end, function(v) State.WalkSpeedOn = v; applyWalkSpeed() end))
moveTab.add(addSlider("WalkSpeed", 16, 250, function() return State.WalkSpeed end, function(v) State.WalkSpeed = v; applyWalkSpeed() end, 0))
moveTab.add(addToggle("Noclip", function() return State.Noclip end, function(v) setNoclip(v) end))
moveTab.add(addSlider("Gravity", 0, 196.2, function() return State.Gravity end, function(v) State.Gravity = v; applyGravity() end, 0))
moveTab.add(addToggle("JumpPower", function() return State.JumpPowerOn end, function(v) State.JumpPowerOn = v; applyJumpPower() end))
moveTab.add(addSlider("JumpPower", 50, 350, function() return State.JumpPower end, function(v) State.JumpPower = v; applyJumpPower() end, 0))
moveTab.add(addSlider("FOV", 40, 120, function() return State.FieldOfView end, function(v) State.FieldOfView = v; applyFOV() end, 0))

-- SETTINGS
local setTab = addTab("Settings")
setTab.add(addToggle("UIBlur", function() return State.UIBlur end, function(v)
	State.UIBlur = v
	TweenService:Create(blur, TweenInfo.new(0.3), { Size = v and 18 or 0 }):Play()
end))
setTab.add(addSlider("UITrans", 0, 1, function() return State.UITransparency end, function(v)
	State.UITransparency = v
	Main.BackgroundTransparency = v
	TitleBar.BackgroundTransparency = v
	TabCol.BackgroundTransparency = v
end, 2))

selectTab("Main")

--============================================================
--  LANGUAGE SWITCH
--============================================================
LangBtn.MouseButton1Click:Connect(function()
	State.Language = (State.Language == "EN") and "VN" or "EN"
	LangBtn.Text = State.Language
	TitleLbl.Text = T("Title")
	for _, fn in ipairs(relabelers) do pcall(fn) end
	notify(T("Title"), State.Language == "VN" and "Đã chuyển sang Tiếng Việt" or "Switched to English", 2)
end)

--============================================================
--  DRAGGING
--============================================================
do
	local dragging, dragStart, startPos
	TitleBar.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = true; dragStart = i.Position; startPos = Main.Position
			i.Changed:Connect(function()
				if i.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)
	UserInputService.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			local d = i.Position - dragStart
			Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end)
end

--============================================================
--  MINIMIZE / CLOSE / KEYBIND
--============================================================
local minimized = false
local savedSize = Main.Size
local function setMinimized(m)
	minimized = m
	if m then
		savedSize = Main.Size
		Main:TweenSize(UDim2.new(0, 560, 0, 42), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.2, true)
		Content.Visible = false; TabCol.Visible = false
	else
		Main:TweenSize(savedSize, Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.2, true)
		task.delay(0.05, function() Content.Visible = true; TabCol.Visible = true end)
	end
end
MinBtn.MouseButton1Click:Connect(function() setMinimized(not minimized) end)
CloseBtn.MouseButton1Click:Connect(function()
	ScreenGui:Destroy()
	blur:Destroy()
end)

UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.KeyCode == State.MinimizeKey then
		setMinimized(not minimized)
	end
end)

--============================================================
--  STARTUP
--============================================================
applyFOV()
notify("Build A Zoo Hub", "Loaded • EN/VN • " .. (State.MinimizeKey.Name) .. " to minimize", 5)
