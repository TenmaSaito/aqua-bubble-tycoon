-- Main.client.luau (v2)
-- HUD・SHOP・演出（ポップアップ/告知バナー/コンボ/画面シェイク）をコードで生成する。
-- 購入の確定はすべてサーバー側。ここは表示と「要求を送る」だけ。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local purchaseUpgradeRemote = remotes:WaitForChild("PurchaseUpgrade")
local requestRebirthRemote = remotes:WaitForChild("RequestRebirth")
local redeemCodeRemote = remotes:WaitForChild("RedeemCode")
local notifyRemote = remotes:WaitForChild("Notify")
local collectEffectRemote = remotes:WaitForChild("CollectEffect")
local announcementRemote = remotes:WaitForChild("Announcement")

local leaderstats = player:WaitForChild("leaderstats")
local stats = player:WaitForChild("Stats")

local gui = Instance.new("ScreenGui")
gui.Name = "AquaHud"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local function addCorner(target: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = target
end

local function makeLabel(parent: Instance, size: UDim2, position: UDim2, text: string, textSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = size
	label.Position = position
	label.BackgroundColor3 = Color3.fromRGB(10, 60, 110)
	label.BackgroundTransparency = 0.25
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = textSize
	label.Text = text
	label.Parent = parent
	addCorner(label, 8)
	return label
end

local function findRarity(rarityId: string): any
	for _, rarity in ipairs(Config.Rarities) do
		if rarity.Id == rarityId then
			return rarity
		end
	end
	return Config.Rarities[1]
end

----------------------------------------------------------------
-- 上部バーとステータス行
----------------------------------------------------------------
local coinsLabel = makeLabel(gui, UDim2.new(0, 210, 0, 40), UDim2.new(0, 12, 0, 10), "Coins: 0", 20)
local bubblesLabel = makeLabel(gui, UDim2.new(0, 170, 0, 40), UDim2.new(0, 232, 0, 10), "Bubbles: 0", 20)
local rebirthLabel = makeLabel(gui, UDim2.new(0, 190, 0, 40), UDim2.new(0, 412, 0, 10), "Rebirth: 0", 20)

local function refreshTopBar()
	coinsLabel.Text = "Coins: " .. leaderstats.Coins.Value
	bubblesLabel.Text = "Bubbles: " .. leaderstats.Bubbles.Value
	rebirthLabel.Text = "Rebirth: " .. leaderstats.Rebirths.Value
end
leaderstats.Coins.Changed:Connect(refreshTopBar)
leaderstats.Bubbles.Changed:Connect(refreshTopBar)
leaderstats.Rebirths.Changed:Connect(refreshTopBar)
refreshTopBar()

-- 天候・全体ラック・フレーバー在庫などのライブステータス
local statusLabel = makeLabel(gui, UDim2.new(0, 590, 0, 34), UDim2.new(0, 12, 0, 56), "", 15)
statusLabel.TextXAlignment = Enum.TextXAlignment.Left

task.spawn(function()
	while true do
		local parts = {}
		local weatherName = workspace:GetAttribute("WeatherName")
		if weatherName and weatherName ~= "" then
			local remain = math.max(0, (workspace:GetAttribute("WeatherEndsAt") or 0) - os.time())
			table.insert(parts, "🌦 " .. weatherName .. " あと" .. remain .. "秒")
		end
		local luckEnds = workspace:GetAttribute("ServerLuckEndsAt") or 0
		if os.time() < luckEnds then
			table.insert(parts, "🍀 全体ラック×2 あと" .. (luckEnds - os.time()) .. "秒")
		end
		local flavorName = workspace:GetAttribute("FlavorName")
		if flavorName then
			local remain = math.max(0, (workspace:GetAttribute("FlavorEndsAt") or 0) - os.time())
			table.insert(parts, "🍬 在庫: " .. flavorName .. " あと" .. remain .. "秒")
		end
		local myFlavorEnds = player:GetAttribute("FlavorEndsAt") or 0
		if os.time() < myFlavorEnds then
			table.insert(parts, "✨ " .. (player:GetAttribute("FlavorName") or "") .. "バフ中 あと" .. (myFlavorEnds - os.time()) .. "秒")
		end
		if player:GetAttribute("FriendBoost") then
			table.insert(parts, "👥 フレンド+10%")
		end
		local charmName = player:GetAttribute("ActiveCharmName")
		if charmName and charmName ~= "" then
			table.insert(parts, "🔮 " .. charmName)
		end
		local weatherName = workspace:GetAttribute("WeatherName")
		local weatherEndsAt = workspace:GetAttribute("WeatherEndsAt") or 0
		if weatherName and weatherName ~= "" and weatherEndsAt > os.time() then
			table.insert(parts, string.format("🌦 %s あと%d秒", weatherName, weatherEndsAt - os.time()))
		else
			local nextWeatherAt = workspace:GetAttribute("NextWeatherAt") or 0
			if nextWeatherAt > os.time() then
				table.insert(parts, string.format("☀️ 次の天候まで %d秒", nextWeatherAt - os.time()))
			end
		end
		statusLabel.Text = "  " .. table.concat(parts, "  |  ")
		task.wait(0.5)
	end
end)

----------------------------------------------------------------
-- コンボメーター
----------------------------------------------------------------
local comboLabel = makeLabel(gui, UDim2.new(0, 300, 0, 38), UDim2.new(0.5, -150, 0, 100), "", 20)
comboLabel.Visible = false
local comboBarBack = Instance.new("Frame")
comboBarBack.Size = UDim2.new(0, 300, 0, 10)
comboBarBack.Position = UDim2.new(0.5, -150, 0, 140)
comboBarBack.BackgroundColor3 = Color3.fromRGB(20, 20, 40)
comboBarBack.BackgroundTransparency = 0.3
comboBarBack.Visible = false
comboBarBack.Parent = gui
addCorner(comboBarBack, 5)
local comboBar = Instance.new("Frame")
comboBar.Size = UDim2.fromScale(1, 1)
comboBar.BackgroundColor3 = Color3.fromRGB(255, 170, 40)
comboBar.Parent = comboBarBack
addCorner(comboBar, 5)

local displayCombo = 0
local lastCollectLocal = 0
local serverComboWindow = Config.Combo.WindowSeconds
task.spawn(function()
	while true do
		task.wait()
		if displayCombo > 0 then
			local remain = serverComboWindow - (os.clock() - lastCollectLocal)
			if remain <= 0 then
				displayCombo = 0
				comboLabel.Visible = false
				comboBarBack.Visible = false
			else
				comboLabel.Visible = true
				comboBarBack.Visible = true
				comboLabel.Text = string.format("🔥 %d COMBO (+%d%%)", displayCombo, math.floor(displayCombo * Config.Combo.PerCombo * 100))
				comboBar.Size = UDim2.fromScale(remain / serverComboWindow, 1)
			end
		end
	end
end)

----------------------------------------------------------------
-- 告知バナー（サーバー全体）
----------------------------------------------------------------
local banner = makeLabel(gui, UDim2.new(0, 720, 0, 52), UDim2.new(0.5, -360, 0, 160), "", 22)
banner.BackgroundColor3 = Color3.fromRGB(140, 40, 180)
banner.Visible = false
local bannerQueue: { string } = {}
local bannerBusy = false
local function processBannerQueue()
	if bannerBusy then
		return
	end
	bannerBusy = true
	while #bannerQueue > 0 do
		local message = table.remove(bannerQueue, 1)
		banner.Text = message
		banner.Visible = true
		task.wait(3.4)
	end
	banner.Visible = false
	bannerBusy = false
end
announcementRemote.OnClientEvent:Connect(function(message: string)
	table.insert(bannerQueue, message)
	task.spawn(processBannerQueue)
end)

----------------------------------------------------------------
-- 回収ポップアップ＋シェイク
----------------------------------------------------------------
local feed = Instance.new("Frame")
feed.Size = UDim2.new(0, 320, 0, 300)
feed.Position = UDim2.new(1, -332, 0, 120)
feed.BackgroundTransparency = 1
feed.Parent = gui
local feedLayout = Instance.new("UIListLayout")
feedLayout.FillDirection = Enum.FillDirection.Vertical
feedLayout.SortOrder = Enum.SortOrder.LayoutOrder
feedLayout.Padding = UDim.new(0, 4)
feedLayout.Parent = feed

local shakeTime = 0
RunService.RenderStepped:Connect(function(dt)
	if shakeTime > 0 then
		shakeTime -= dt
		local camera = workspace.CurrentCamera
		if camera then
			local offset = Vector3.new((math.random() - 0.5) * 0.7, (math.random() - 0.5) * 0.7, 0)
			camera.CFrame = camera.CFrame * CFrame.new(offset)
		end
	end
end)

local coinsScale = Instance.new("UIScale")
coinsScale.Parent = coinsLabel

-- 泡ポップ音: 単一のSoundだと再生中は次の音が鳴らないので、プールで重ねて鳴らす
local POP_POOL_SIZE = 10
local popPool = {}
for i = 1, POP_POOL_SIZE do
	local sound = Instance.new("Sound")
	sound.Name = "CollectPop" .. i
	sound.Volume = 0.55
	sound.Parent = SoundService
	table.insert(popPool, sound)
end
local popPoolIndex = 0
local function playPop(combo: number, isCrit: boolean)
	popPoolIndex = (popPoolIndex % POP_POOL_SIZE) + 1
	local sound = popPool[popPoolIndex]
	sound.PlaybackSpeed = isCrit and 0.95 or (1.4 + math.min(combo, 24) * 0.03)
	sound.Volume = isCrit and 0.7 or 0.55
	sound:Play()
end

-- 音源の自動選択: 以前指定した rbxasset://sounds/pop.wav は現在のRobloxに存在せず無音だった。
-- ContentProviderで実際に読み込めるか確認しながら、候補を順に試す
task.spawn(function()
	local ContentProvider = game:GetService("ContentProvider")
	local candidates = {}
	if Config.PopSoundId ~= "" then
		table.insert(candidates, Config.PopSoundId)
	end
	for _, candidate in ipairs({
		"rbxasset://sounds/splat.wav",
		"rbxasset://sounds/snap.wav",
		"rbxasset://sounds/electronicpingshort.wav",
	}) do
		table.insert(candidates, candidate)
	end
	local probe = popPool[1]
	for _, soundId in ipairs(candidates) do
		probe.SoundId = soundId
		pcall(function()
			ContentProvider:PreloadAsync({ probe })
		end)
		if probe.IsLoaded and probe.TimeLength > 0 then
			for _, sound in ipairs(popPool) do
				sound.SoundId = soundId
			end
			break
		end
	end
end)

-- レア専用サウンド: エピック以上でキラキラ音、レジェンダリー以上でファンファーレも重ねる
local function makeSoundPool(prefix: string, count: number, soundId: string, volume: number): ({ Sound }, () -> ())
	local pool = {}
	for i = 1, count do
		local sound = Instance.new("Sound")
		sound.Name = prefix .. i
		sound.SoundId = soundId
		sound.Volume = volume
		sound.Parent = SoundService
		table.insert(pool, sound)
	end
	local index = 0
	return pool, function()
		index = (index % count) + 1
		pool[index]:Play()
	end
end
local rarePingPool, playRarePing = makeSoundPool("RarePing", 3, "rbxasset://sounds/electronicpingshort.wav", 0.5)
rarePingPool[1].PlaybackSpeed = 1.3
local fanfarePool, playFanfare = makeSoundPool("Fanfare", 2, "rbxasset://sounds/victory.wav", 0.45)
task.spawn(function()
	local ContentProvider = game:GetService("ContentProvider")
	for _, pool in ipairs({ rarePingPool, fanfarePool }) do
		pcall(function()
			ContentProvider:PreloadAsync({ pool[1] })
		end)
		if not (pool[1].IsLoaded and pool[1].TimeLength > 0) then
			for _, sound in ipairs(pool) do
				sound.SoundId = ""
			end
		end
	end
end)
local function rarityTierOf(rarityId: string): number
	for i, rarity in ipairs(Config.Rarities) do
		if rarity.Id == rarityId then
			return i
		end
	end
	return 1
end

local popupOrder = 0
collectEffectRemote.OnClientEvent:Connect(function(reward: number, rarityId: string, isCrit: boolean, combo: number, mutationName: string, comboWindow: number)
	displayCombo = combo
	lastCollectLocal = os.clock()
	if comboWindow then
		serverComboWindow = comboWindow
	end
	playPop(combo, isCrit)
	local tier = rarityTierOf(rarityId)
	if tier >= 4 then
		playRarePing()
	end
	if tier >= 5 then
		playFanfare()
	end
	if reward >= 100 or isCrit then
		coinsScale.Scale = 1.18
		TweenService:Create(coinsScale, TweenInfo.new(0.25), { Scale = 1 }):Play()
	end
	local rarity = findRarity(rarityId)
	popupOrder += 1
	local label = Instance.new("TextLabel")
	label.LayoutOrder = popupOrder
	label.Size = UDim2.new(1, 0, 0, 34)
	label.BackgroundColor3 = rarity.Color
	label.BackgroundTransparency = 0.25
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = isCrit and 24 or 18
	label.Text = string.format("+%d  %s%s%s", reward, mutationName or "", rarity.Name, isCrit and "  💥CRITICAL!" or "")
	label.Parent = feed
	addCorner(label, 8)
	if isCrit or rarityId == "Legendary" or rarityId == "Mythic" then
		shakeTime = 0.35
	end
	task.delay(1.5, function()
		local tween = TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1, BackgroundTransparency = 1 })
		tween:Play()
		tween.Completed:Wait()
		label:Destroy()
	end)
end)

----------------------------------------------------------------
-- 通知トースト
----------------------------------------------------------------
local toast = makeLabel(gui, UDim2.new(0, 560, 0, 44), UDim2.new(0.5, -280, 0, 224), "", 18)
toast.Visible = false
local toastToken = 0
notifyRemote.OnClientEvent:Connect(function(message: string)
	toastToken += 1
	local myToken = toastToken
	toast.Text = message
	toast.Visible = true
	task.wait(2.6)
	if toastToken == myToken then
		toast.Visible = false
	end
end)

----------------------------------------------------------------
-- SHOPパネル（スクロール）
----------------------------------------------------------------
local shopButton = Instance.new("TextButton")
shopButton.Size = UDim2.new(0, 130, 0, 52)
shopButton.Position = UDim2.new(1, -142, 0, 10)
shopButton.BackgroundColor3 = Color3.fromRGB(255, 140, 0)
shopButton.TextColor3 = Color3.new(1, 1, 1)
shopButton.Font = Enum.Font.GothamBold
shopButton.TextSize = 22
shopButton.Text = "SHOP"
shopButton.Parent = gui
addCorner(shopButton, 10)

local panel = Instance.new("ScrollingFrame")
panel.Size = UDim2.new(0, 470, 0, 560)
panel.Position = UDim2.new(0.5, -235, 0.5, -280)
panel.BackgroundColor3 = Color3.fromRGB(12, 45, 80)
panel.BackgroundTransparency = 0.08
panel.CanvasSize = UDim2.new(0, 0, 0, 1420)
panel.ScrollBarThickness = 8
panel.Visible = false
panel.Parent = gui
addCorner(panel, 12)

local title = makeLabel(panel, UDim2.new(1, -20, 0, 40), UDim2.new(0, 10, 0, 8), "SHOP - アップグレード / 図鑑", 20)
title.BackgroundTransparency = 1

shopButton.MouseButton1Click:Connect(function()
	panel.Visible = not panel.Visible
end)

local rowY = 56
local function makeUpgradeRow(upgradeId: string)
	local def = Config.Upgrades[upgradeId]
	local levelValue = stats:WaitForChild(upgradeId .. "Level")
	local row = makeLabel(panel, UDim2.new(1, -20, 0, 58), UDim2.new(0, 10, 0, rowY), "", 15)
	row.TextXAlignment = Enum.TextXAlignment.Left
	local buy = Instance.new("TextButton")
	buy.Size = UDim2.new(0, 104, 0, 38)
	buy.Position = UDim2.new(1, -114, 0.5, -19)
	buy.BackgroundColor3 = Color3.fromRGB(0, 170, 90)
	buy.TextColor3 = Color3.new(1, 1, 1)
	buy.Font = Enum.Font.GothamBold
	buy.TextSize = 16
	buy.Text = "買う"
	buy.Parent = row
	addCorner(buy, 8)
	local function refresh()
		if levelValue.Value >= def.MaxLevel then
			row.Text = string.format("  %s  Lv.MAX\n  %s", def.Name, def.Description)
			buy.Text = "MAX"
		else
			local cost = Config.UpgradeCost(upgradeId, levelValue.Value)
			row.Text = string.format("  %s  Lv.%d\n  %s", def.Name, levelValue.Value, def.Description)
			buy.Text = cost .. " C"
		end
	end
	levelValue.Changed:Connect(refresh)
	leaderstats.Coins.Changed:Connect(refresh)
	refresh()
	buy.MouseButton1Click:Connect(function()
		purchaseUpgradeRemote:FireServer(upgradeId)
	end)
	rowY += 68
end

makeUpgradeRow("Value")
makeUpgradeRow("Speed")
makeUpgradeRow("Magnet")
makeUpgradeRow("Luck")

-- リバース行
local rebirthRow = makeLabel(panel, UDim2.new(1, -20, 0, 58), UDim2.new(0, 10, 0, rowY), "", 15)
rebirthRow.TextXAlignment = Enum.TextXAlignment.Left
local rebirthBuy = Instance.new("TextButton")
rebirthBuy.Size = UDim2.new(0, 104, 0, 38)
rebirthBuy.Position = UDim2.new(1, -114, 0.5, -19)
rebirthBuy.BackgroundColor3 = Color3.fromRGB(170, 60, 220)
rebirthBuy.TextColor3 = Color3.new(1, 1, 1)
rebirthBuy.Font = Enum.Font.GothamBold
rebirthBuy.TextSize = 16
rebirthBuy.Text = "転生"
rebirthBuy.Parent = rebirthRow
addCorner(rebirthBuy, 8)
local function refreshRebirth()
	local cost = Config.RebirthCost(leaderstats.Rebirths.Value)
	rebirthRow.Text = string.format("  リバース（転生） 現在 %d 回\n  コインとレベルをリセットし、永久倍率+50%%", leaderstats.Rebirths.Value)
	rebirthBuy.Text = cost .. " C"
end
leaderstats.Rebirths.Changed:Connect(refreshRebirth)
refreshRebirth()
rebirthBuy.MouseButton1Click:Connect(function()
	requestRebirthRemote:FireServer()
end)
rowY += 68

-- 課金行
local function makePurchaseRow(labelText: string, id: number, onClick: () -> ())
	local row = makeLabel(panel, UDim2.new(1, -20, 0, 46), UDim2.new(0, 10, 0, rowY), "  " .. labelText, 15)
	row.TextXAlignment = Enum.TextXAlignment.Left
	local buy = Instance.new("TextButton")
	buy.Size = UDim2.new(0, 104, 0, 32)
	buy.Position = UDim2.new(1, -114, 0.5, -16)
	buy.BackgroundColor3 = id ~= 0 and Color3.fromRGB(220, 170, 0) or Color3.fromRGB(100, 100, 100)
	buy.TextColor3 = Color3.new(1, 1, 1)
	buy.Font = Enum.Font.GothamBold
	buy.TextSize = 14
	buy.Text = id ~= 0 and "Robuxで買う" or "ID未設定"
	buy.Parent = row
	addCorner(buy, 8)
	if id ~= 0 then
		buy.MouseButton1Click:Connect(onClick)
	end
	rowY += 54
end

makePurchaseRow("ゲームパス: コイン2倍", Config.GamePasses.DoubleCoins, function()
	MarketplaceService:PromptGamePassPurchase(player, Config.GamePasses.DoubleCoins)
end)
makePurchaseRow("ゲームパス: 磁石の範囲2倍", Config.GamePasses.AutoCollect, function()
	MarketplaceService:PromptGamePassPurchase(player, Config.GamePasses.AutoCollect)
end)
makePurchaseRow("ゲームパス: レア率1.5倍", Config.GamePasses.Lucky, function()
	MarketplaceService:PromptGamePassPurchase(player, Config.GamePasses.Lucky)
end)
makePurchaseRow("全体ラック×2 (15分・全員)", Config.Products.ServerLuck.Id, function()
	MarketplaceService:PromptProductPurchase(player, Config.Products.ServerLuck.Id)
end)
makePurchaseRow("開発者製品: " .. Config.Products.CoinsSmall.Label, Config.Products.CoinsSmall.Id, function()
	MarketplaceService:PromptProductPurchase(player, Config.Products.CoinsSmall.Id)
end)
makePurchaseRow("開発者製品: " .. Config.Products.CoinsLarge.Label, Config.Products.CoinsLarge.Id, function()
	MarketplaceService:PromptProductPurchase(player, Config.Products.CoinsLarge.Id)
end)

-- コード入力行
local codeRow = makeLabel(panel, UDim2.new(1, -20, 0, 46), UDim2.new(0, 10, 0, rowY), "  コード入力", 15)
codeRow.TextXAlignment = Enum.TextXAlignment.Left
local codeBox = Instance.new("TextBox")
codeBox.Size = UDim2.new(0, 190, 0, 32)
codeBox.Position = UDim2.new(0, 130, 0.5, -16)
codeBox.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
codeBox.TextColor3 = Color3.fromRGB(20, 20, 20)
codeBox.Font = Enum.Font.GothamBold
codeBox.TextSize = 15
codeBox.PlaceholderText = "コードを入力"
codeBox.Text = ""
codeBox.Parent = codeRow
addCorner(codeBox, 8)
local codeBuy = Instance.new("TextButton")
codeBuy.Size = UDim2.new(0, 80, 0, 32)
codeBuy.Position = UDim2.new(1, -90, 0.5, -16)
codeBuy.BackgroundColor3 = Color3.fromRGB(0, 150, 220)
codeBuy.TextColor3 = Color3.new(1, 1, 1)
codeBuy.Font = Enum.Font.GothamBold
codeBuy.TextSize = 14
codeBuy.Text = "交換"
codeBuy.Parent = codeRow
addCorner(codeBuy, 8)
codeBuy.MouseButton1Click:Connect(function()
	if codeBox.Text ~= "" then
		redeemCodeRemote:FireServer(codeBox.Text)
		codeBox.Text = ""
	end
end)
rowY += 54

-- 図鑑（レアリティ一覧・確率は全表示）
local indexTitle = makeLabel(panel, UDim2.new(1, -20, 0, 36), UDim2.new(0, 10, 0, rowY), "  📖 泡図鑑（確率は通常時のもの）", 16)
indexTitle.TextXAlignment = Enum.TextXAlignment.Left
indexTitle.BackgroundTransparency = 1
rowY += 42
for _, rarity in ipairs(Config.Rarities) do
	local row = makeLabel(panel, UDim2.new(1, -20, 0, 34), UDim2.new(0, 10, 0, rowY), "", 14)
	row.TextXAlignment = Enum.TextXAlignment.Left
	local function refreshIndex()
		local found = player:GetAttribute("Discovered_" .. rarity.Id)
		local pct, oneIn = Config.RarityChanceText(rarity, 1)
		row.Text = string.format("  %s %s  価値×%d  確率 %.2f%% (1 in %d)", found and "✓" or "？", rarity.Name, rarity.ValueMultiplier, pct, oneIn)
		row.TextColor3 = found and rarity.Color or Color3.fromRGB(150, 150, 150)
	end
	player:GetAttributeChangedSignal("Discovered_" .. rarity.Id):Connect(refreshIndex)
	refreshIndex()
	rowY += 40
end

-- ミッション階段の進捗
local missionRow = makeLabel(panel, UDim2.new(1, -20, 0, 58), UDim2.new(0, 10, 0, rowY), "", 14)
missionRow.TextXAlignment = Enum.TextXAlignment.Left
local function refreshMission()
	local total = stats.TotalBubbles.Value
	local nextTarget = nil
	for _, threshold in ipairs(Config.Milestones) do
		if total < threshold then
			nextTarget = threshold
			break
		end
	end
	if nextTarget then
		missionRow.Text = string.format("  🏆 累計の泡: %d 個\n  次の永久倍率まで あと %d 個（現在 +%d%%）", total, nextTarget - total, stats.MilestoneBoost.Value)
	else
		missionRow.Text = string.format("  🏆 累計の泡: %d 個\n  ミッション全達成! 永久倍率 +%d%%", total, stats.MilestoneBoost.Value)
	end
end
stats.TotalBubbles.Changed:Connect(refreshMission)
stats.MilestoneBoost.Changed:Connect(refreshMission)
refreshMission()

----------------------------------------------------------------
-- v3: レガシーパネル / チャーム選択 / オートウォーク / パネルの閉じるボタン
----------------------------------------------------------------
local purchaseLegacyRemote = remotes:WaitForChild("PurchaseLegacy")
local charmOfferRemote = remotes:WaitForChild("CharmOffer")
local charmSelectRemote = remotes:WaitForChild("CharmSelect")

local function makeSideButton(order: number, text: string, color: Color3): TextButton
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(0, 130, 0, 44)
	button.Position = UDim2.new(1, -142, 0, 70 + (order - 1) * 52)
	button.BackgroundColor3 = color
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 17
	button.Text = text
	button.Parent = gui
	addCorner(button, 10)
	return button
end

-- SHOPパネルの閉じるボタン
local shopClose = Instance.new("TextButton")
shopClose.Size = UDim2.new(0, 36, 0, 36)
shopClose.Position = UDim2.new(1, -44, 0, 8)
shopClose.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
shopClose.TextColor3 = Color3.new(1, 1, 1)
shopClose.Font = Enum.Font.GothamBold
shopClose.TextSize = 18
shopClose.Text = "✕"
shopClose.Parent = panel
addCorner(shopClose, 8)
shopClose.MouseButton1Click:Connect(function()
	panel.Visible = false
end)

-- レガシーパネル
local legacyButton = makeSideButton(1, "🌳 LEGACY", Color3.fromRGB(140, 60, 220))
local legacyPanel = Instance.new("ScrollingFrame")
legacyPanel.Size = UDim2.new(0, 470, 0, 560)
legacyPanel.Position = UDim2.new(0.5, -235, 0.5, -280)
legacyPanel.BackgroundColor3 = Color3.fromRGB(45, 18, 80)
legacyPanel.BackgroundTransparency = 0.08
legacyPanel.CanvasSize = UDim2.new(0, 0, 0, 900)
legacyPanel.ScrollBarThickness = 8
legacyPanel.Visible = false
legacyPanel.Parent = gui
addCorner(legacyPanel, 12)
legacyButton.MouseButton1Click:Connect(function()
	legacyPanel.Visible = not legacyPanel.Visible
	panel.Visible = false
end)

local legacyTitle = makeLabel(legacyPanel, UDim2.new(1, -20, 0, 40), UDim2.new(0, 10, 0, 8), "🌳 レガシーツリー", 20)
legacyTitle.BackgroundTransparency = 1
local legacyClose = Instance.new("TextButton")
legacyClose.Size = UDim2.new(0, 36, 0, 36)
legacyClose.Position = UDim2.new(1, -44, 0, 8)
legacyClose.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
legacyClose.TextColor3 = Color3.new(1, 1, 1)
legacyClose.Font = Enum.Font.GothamBold
legacyClose.TextSize = 18
legacyClose.Text = "✕"
legacyClose.Parent = legacyPanel
addCorner(legacyClose, 8)
legacyClose.MouseButton1Click:Connect(function()
	legacyPanel.Visible = false
end)

local legacyY = 56
local function refreshLegacyTitle()
	legacyTitle.Text = string.format("🌳 レガシーツリー（⭐ %d ポイント）", stats.LegacyPoints.Value)
end
stats.LegacyPoints.Changed:Connect(refreshLegacyTitle)
refreshLegacyTitle()

for _, node in ipairs(Config.LegacyNodes) do
	local row = makeLabel(legacyPanel, UDim2.new(1, -20, 0, 58), UDim2.new(0, 10, 0, legacyY), "", 14)
	row.TextXAlignment = Enum.TextXAlignment.Left
	local buy = Instance.new("TextButton")
	buy.Size = UDim2.new(0, 104, 0, 38)
	buy.Position = UDim2.new(1, -114, 0.5, -19)
	buy.TextColor3 = Color3.new(1, 1, 1)
	buy.Font = Enum.Font.GothamBold
	buy.TextSize = 15
	buy.Parent = row
	addCorner(buy, 8)
	local function refreshNode()
		local owned = player:GetAttribute("OwnedLegacy_" .. node.Id)
		local prereqOk = node.Requires == "" or player:GetAttribute("OwnedLegacy_" .. node.Requires)
		row.Text = string.format("  [%s] %s（⭐%d）\n  %s", node.Branch, node.Name, node.Cost, node.Description)
		if owned then
			buy.Text = "解放済み"
			buy.BackgroundColor3 = Color3.fromRGB(90, 90, 90)
		elseif not prereqOk then
			buy.Text = "前提が必要"
			buy.BackgroundColor3 = Color3.fromRGB(120, 90, 60)
		else
			buy.Text = "解放する"
			buy.BackgroundColor3 = Color3.fromRGB(150, 70, 230)
		end
	end
	player:GetAttributeChangedSignal("OwnedLegacy_" .. node.Id):Connect(refreshNode)
	if node.Requires ~= "" then
		player:GetAttributeChangedSignal("OwnedLegacy_" .. node.Requires):Connect(refreshNode)
	end
	refreshNode()
	buy.MouseButton1Click:Connect(function()
		purchaseLegacyRemote:FireServer(node.Id)
	end)
	legacyY += 66
end

-- チャーム3択ポップアップ
local charmPanel = Instance.new("Frame")
charmPanel.Size = UDim2.new(0, 640, 0, 210)
charmPanel.Position = UDim2.new(0.5, -320, 0.5, -60)
charmPanel.BackgroundColor3 = Color3.fromRGB(30, 20, 70)
charmPanel.BackgroundTransparency = 0.05
charmPanel.Visible = false
charmPanel.Parent = gui
addCorner(charmPanel, 14)
local charmTitle = makeLabel(charmPanel, UDim2.new(1, -20, 0, 40), UDim2.new(0, 10, 0, 8), "🔮 このランのチャームを選ぼう（転生まで有効）", 19)
charmTitle.BackgroundTransparency = 1

charmOfferRemote.OnClientEvent:Connect(function(offeredIds: { string })
	for _, child in ipairs(charmPanel:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	charmPanel.Visible = true
	for i, charmId in ipairs(offeredIds) do
		local charm = Config.FindCharm(charmId)
		if charm then
			local button = Instance.new("TextButton")
			button.Size = UDim2.new(0, 196, 0, 130)
			button.Position = UDim2.new(0, 12 + (i - 1) * 208, 0, 60)
			button.BackgroundColor3 = Color3.fromRGB(90, 50, 180)
			button.TextColor3 = Color3.new(1, 1, 1)
			button.Font = Enum.Font.GothamBold
			button.TextSize = 16
			button.Text = "🔮 " .. charm.Name .. "\n\n" .. charm.Description
			button.TextWrapped = true
			button.Parent = charmPanel
			addCorner(button, 12)
			button.MouseButton1Click:Connect(function()
				charmSelectRemote:FireServer(charmId)
				charmPanel.Visible = false
			end)
		end
	end
end)

-- オートウォーク（レガシー解放後のみ表示。一番近い泡へ歩く）
local autoButton = makeSideButton(2, "🤖 AUTO: OFF", Color3.fromRGB(70, 70, 90))
autoButton.Visible = player:GetAttribute("HasAutoWalk") == true
player:GetAttributeChangedSignal("HasAutoWalk"):Connect(function()
	autoButton.Visible = player:GetAttribute("HasAutoWalk") == true
end)

local autoWalkEnabled = false
autoButton.MouseButton1Click:Connect(function()
	autoWalkEnabled = not autoWalkEnabled
	autoButton.Text = autoWalkEnabled and "🤖 AUTO: ON" or "🤖 AUTO: OFF"
	autoButton.BackgroundColor3 = autoWalkEnabled and Color3.fromRGB(0, 170, 90) or Color3.fromRGB(70, 70, 90)
end)

task.spawn(function()
	local gameWorld = workspace:WaitForChild("GameWorld")
	local bubblesFolder = gameWorld:WaitForChild("Bubbles")
	while true do
		task.wait(0.6)
		if autoWalkEnabled then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if root and humanoid then
				local nearest, nearestDist = nil, math.huge
				for _, bubble in ipairs(bubblesFolder:GetChildren()) do
					if bubble:IsA("BasePart") then
						local dist = (bubble.Position - root.Position).Magnitude
						if dist < nearestDist then
							nearest, nearestDist = bubble, dist
						end
					end
				end
				if nearest and nearestDist > 3 then
					humanoid:MoveTo(nearest.Position)
				end
			end
		end
	end
end)

-- 天候イベントのド派手バナー＋全画面フラッシュ
local flashFrame = Instance.new("Frame")
flashFrame.Size = UDim2.fromScale(1, 1)
flashFrame.BackgroundColor3 = Color3.new(1, 1, 1)
flashFrame.BackgroundTransparency = 1
flashFrame.BorderSizePixel = 0
flashFrame.Parent = gui

local weatherBanner = makeLabel(gui, UDim2.new(0, 760, 0, 96), UDim2.new(0.5, -380, 0, 110), "", 42)
weatherBanner.Visible = false
weatherBanner.TextColor3 = Color3.new(1, 1, 1)
addCorner(weatherBanner, 16)
local bannerScale = Instance.new("UIScale")
bannerScale.Parent = weatherBanner

workspace:GetAttributeChangedSignal("WeatherName"):Connect(function()
	local weatherName = workspace:GetAttribute("WeatherName")
	if weatherName and weatherName ~= "" then
		local eventColor = Color3.fromRGB(120, 200, 255)
		for _, event in ipairs(Config.Weather.Events) do
			if event.Name == weatherName then
				eventColor = event.Color
			end
		end
		weatherBanner.Text = "🌦 " .. weatherName .. " 発生!! 🌦"
		weatherBanner.BackgroundColor3 = eventColor
		weatherBanner.BackgroundTransparency = 0.15
		weatherBanner.Visible = true
		bannerScale.Scale = 1.35
		TweenService:Create(bannerScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		flashFrame.BackgroundColor3 = eventColor
		flashFrame.BackgroundTransparency = 0.45
		TweenService:Create(flashFrame, TweenInfo.new(0.8), { BackgroundTransparency = 1 }):Play()
		task.delay(3.2, function()
			weatherBanner.Visible = false
		end)
	end
end)

-- ワープパネル（解放済みゾーンへの移動）
local teleportRemote = remotes:WaitForChild("TeleportTo")
local warpButton = makeSideButton(3, "🌀 WARP", Color3.fromRGB(0, 150, 190))
local warpPanel = Instance.new("Frame")
warpPanel.Size = UDim2.new(0, 300, 0, 60 + #Config.Zones * 62)
warpPanel.Position = UDim2.new(0.5, -150, 0.5, -(60 + #Config.Zones * 62) / 2)
warpPanel.BackgroundColor3 = Color3.fromRGB(10, 50, 80)
warpPanel.BackgroundTransparency = 0.08
warpPanel.Visible = false
warpPanel.Parent = gui
addCorner(warpPanel, 12)
local warpTitle = makeLabel(warpPanel, UDim2.new(1, -20, 0, 40), UDim2.new(0, 10, 0, 8), "🌀 ワープ先を選ぶ", 19)
warpTitle.BackgroundTransparency = 1
warpButton.MouseButton1Click:Connect(function()
	warpPanel.Visible = not warpPanel.Visible
end)
for i, zone in ipairs(Config.Zones) do
	local zoneButton = Instance.new("TextButton")
	zoneButton.Size = UDim2.new(1, -40, 0, 52)
	zoneButton.Position = UDim2.new(0, 20, 0, 52 + (i - 1) * 62)
	zoneButton.BackgroundColor3 = zone.Color
	zoneButton.TextColor3 = Color3.new(1, 1, 1)
	zoneButton.Font = Enum.Font.GothamBold
	zoneButton.TextSize = 18
	zoneButton.Text = zone.Name
	zoneButton.Parent = warpPanel
	addCorner(zoneButton, 10)
	local function refreshZoneButton()
		local unlocked = player:GetAttribute("Unlocked_" .. zone.Id)
		zoneButton.Text = unlocked and zone.Name or (zone.Name .. "（未解放）")
		zoneButton.BackgroundColor3 = unlocked and zone.Color or Color3.fromRGB(90, 90, 90)
	end
	player:GetAttributeChangedSignal("Unlocked_" .. zone.Id):Connect(refreshZoneButton)
	refreshZoneButton()
	zoneButton.MouseButton1Click:Connect(function()
		teleportRemote:FireServer(zone.Id)
		warpPanel.Visible = false
	end)
end

-- ゾーン結界の切り替えは Barrier.client.luau が担当する（エラー耐性のため分離）
