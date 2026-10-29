-- Main.server.luau (v2)
-- サーバーの入口。データ保存・泡の生成と回収・ポータル・ショップ検証・課金処理に加え、
-- v2では レアリティ / 天候ミューテーション / コンボ / クリティカル / フレーバー回転 /
-- オフライン報酬 / サーバー全体ラック / 図鑑 / コード / ミッション階段 を担当する。
-- お金に関わる処理はすべてサーバー側で検証する。

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local MessagingService = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local WorldBuilder = require(script.Parent:WaitForChild("WorldBuilder"))

----------------------------------------------------------------
-- リモート
----------------------------------------------------------------
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage

local function makeRemote(name: string): RemoteEvent
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = remotes
	return remote
end

local purchaseUpgradeRemote = makeRemote("PurchaseUpgrade")
local requestRebirthRemote = makeRemote("RequestRebirth")
local redeemCodeRemote = makeRemote("RedeemCode")
local purchaseLegacyRemote = makeRemote("PurchaseLegacy")
local charmOfferRemote = makeRemote("CharmOffer") -- サーバー → クライアント: チャーム3択の提示
local charmSelectRemote = makeRemote("CharmSelect")
local notifyRemote = makeRemote("Notify") -- サーバー → 個人通知
local collectEffectRemote = makeRemote("CollectEffect") -- サーバー → 本人に回収演出
local announcementRemote = makeRemote("Announcement") -- サーバー → 全員への告知

local function notify(player: Player, message: string)
	notifyRemote:FireClient(player, message)
end

local function announce(message: string)
	announcementRemote:FireAllClients(message)
end

----------------------------------------------------------------
-- ワールド生成と全体状態（天候・サーバーラック・フレーバー在庫）
----------------------------------------------------------------
local world, portalPrompts, flavorPrompt, stockLabel = WorldBuilder.Build()
local bubbleFolder = world:WaitForChild("Bubbles")

local currentWeather = nil -- Config.Weather.Events の要素 or nil
local serverLuckEndsAt = 0
local currentFlavor = Config.RollFlavor()
local flavorEndsAt = os.time() + Config.Flavors.StockSeconds

workspace:SetAttribute("WeatherName", "")
workspace:SetAttribute("WeatherEndsAt", 0)
workspace:SetAttribute("ServerLuckEndsAt", 0)
workspace:SetAttribute("FlavorName", currentFlavor.Name)
workspace:SetAttribute("FlavorEndsAt", flavorEndsAt)

-- 天候サイクル: 通常 → イベント → 通常…
task.spawn(function()
	while true do
		task.wait(Config.Weather.NormalSeconds)
		local event = Config.Weather.Events[math.random(1, #Config.Weather.Events)]
		currentWeather = event
		workspace:SetAttribute("WeatherName", event.Name)
		workspace:SetAttribute("WeatherEndsAt", os.time() + Config.Weather.EventSeconds)
		Lighting.Ambient = event.SkyColor
		Lighting.OutdoorAmbient = event.SkyColor
		announce(string.format("🌦 天候イベント「%s」発生! %s変異の泡が出るかも!", event.Name, event.MutationName))
		task.wait(Config.Weather.EventSeconds)
		currentWeather = nil
		workspace:SetAttribute("WeatherName", "")
		workspace:SetAttribute("WeatherEndsAt", 0)
		Lighting.Ambient = Color3.fromRGB(110, 120, 140)
		Lighting.OutdoorAmbient = Color3.fromRGB(110, 120, 140)
		announce("天候が元に戻った")
	end
end)

-- フレーバー在庫の回転と看板更新
task.spawn(function()
	while true do
		if os.time() >= flavorEndsAt then
			currentFlavor = Config.RollFlavor()
			flavorEndsAt = os.time() + Config.Flavors.StockSeconds
			workspace:SetAttribute("FlavorName", currentFlavor.Name)
			workspace:SetAttribute("FlavorEndsAt", flavorEndsAt)
			flavorPrompt.ObjectText = currentFlavor.Name .. "フレーバー"
		end
		local remain = math.max(0, flavorEndsAt - os.time())
		stockLabel.Text = string.format("フレーバーショップ\n%s (×%g) %dコイン\n在庫あと %d 秒", currentFlavor.Name, currentFlavor.Multiplier, currentFlavor.Cost, remain)
		task.wait(1)
	end
end)

----------------------------------------------------------------
-- プレイヤーデータ
----------------------------------------------------------------
local store = DataStoreService:GetDataStore(Config.DataStoreName)
local sessions: { [Player]: any } = {}

local function buildValueObjects(player: Player, data: any)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local function intValue(parent: Instance, name: string, value: number): IntValue
		local v = Instance.new("IntValue")
		v.Name = name
		v.Value = value
		v.Parent = parent
		return v
	end
	intValue(leaderstats, "Coins", data.Coins)
	intValue(leaderstats, "Bubbles", data.Bubbles)
	intValue(leaderstats, "Rebirths", data.Rebirths)
	leaderstats.Parent = player

	local stats = Instance.new("Folder")
	stats.Name = "Stats"
	intValue(stats, "ValueLevel", data.ValueLevel)
	intValue(stats, "SpeedLevel", data.SpeedLevel)
	intValue(stats, "MagnetLevel", data.MagnetLevel)
	intValue(stats, "LuckLevel", data.LuckLevel)
	intValue(stats, "TotalBubbles", data.TotalBubbles)
	intValue(stats, "TotalEarned", data.TotalEarned)
	intValue(stats, "MilestoneBoost", data.MilestoneBoost)
	intValue(stats, "LegacyPoints", data.LegacyPoints)
	stats.Parent = player

	for zoneId, unlocked in pairs(data.UnlockedZones) do
		player:SetAttribute("Unlocked_" .. zoneId, unlocked == true)
	end
	for rarityId, found in pairs(data.DiscoveredRarities) do
		player:SetAttribute("Discovered_" .. rarityId, found == true)
	end
end

-- レガシー所持とチャームをクライアント表示用アトリビュートへ同期する
local function syncLegacyAttributes(player: Player, data: any)
	for _, node in ipairs(Config.LegacyNodes) do
		player:SetAttribute("OwnedLegacy_" .. node.Id, data.OwnedLegacy[node.Id] == true)
	end
	player:SetAttribute("HasAutoWalk", data.OwnedLegacy["AutoWalk"] == true)
	local charm = Config.FindCharm(data.ActiveCharm or "")
	player:SetAttribute("ActiveCharmName", charm and charm.Name or "")
end

local function ownsLegacy(data: any, nodeId: string): boolean
	return data and data.OwnedLegacy and data.OwnedLegacy[nodeId] == true
end

local function loadData(player: Player): any
	local data = Config.DefaultData()
	local ok, saved = pcall(function()
		return store:GetAsync("player_" .. player.UserId)
	end)
	if ok and type(saved) == "table" then
		for key, value in pairs(saved) do
			data[key] = value
		end
	elseif not ok then
		warn("[AquaBubble] DataStore load failed (StudioではAPIアクセス許可が必要): ", saved)
	end
	return data
end

local function saveData(player: Player)
	local data = sessions[player]
	if not data then
		return
	end
	local snapshot = {
		Coins = player.leaderstats.Coins.Value,
		Bubbles = player.leaderstats.Bubbles.Value,
		Rebirths = player.leaderstats.Rebirths.Value,
		ValueLevel = player.Stats.ValueLevel.Value,
		SpeedLevel = player.Stats.SpeedLevel.Value,
		MagnetLevel = player.Stats.MagnetLevel.Value,
		LuckLevel = player.Stats.LuckLevel.Value,
		TotalBubbles = player.Stats.TotalBubbles.Value,
		TotalEarned = player.Stats.TotalEarned.Value,
		MilestoneBoost = player.Stats.MilestoneBoost.Value,
		LastSeen = os.time(),
		UnlockedZones = data.UnlockedZones,
		RedeemedCodes = data.RedeemedCodes,
		DiscoveredRarities = data.DiscoveredRarities,
		LegacyPoints = player.Stats.LegacyPoints.Value,
		OwnedLegacy = data.OwnedLegacy,
		ActiveCharm = data.ActiveCharm,
		WeekKey = data.WeekKey,
		WeeklyEarned = data.WeeklyEarned,
	}
	local ok, err = pcall(function()
		store:SetAsync("player_" .. player.UserId, snapshot)
	end)
	if not ok then
		warn("[AquaBubble] DataStore save failed: ", err)
	end
end

local function applyStats(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local speed = 16 + 2 * player.Stats.SpeedLevel.Value
		if sessions[player] and sessions[player].HasVip then
			speed += 8
		end
		if sessions[player] and sessions[player].ActiveCharm == "Swift" then
			speed += 6
		end
		humanoid.WalkSpeed = speed
	end
end

-- 週間キーの生成（週間ランキングのリセット判定用）
local function currentWeekKey(): string
	local t = os.date("*t", os.time()) :: any
	local week = math.floor((t.yday - 1) / 7) + 1
	return string.format("%d-W%02d", t.year, week)
end

-- チャーム3択を提示する（重複なしランダム）
local function offerCharms(player: Player)
	local data = sessions[player]
	if not data then
		return
	end
	local pool = {}
	for _, charm in ipairs(Config.Charms) do
		table.insert(pool, charm.Id)
	end
	local offered = {}
	for _ = 1, 3 do
		local idx = math.random(1, #pool)
		table.insert(offered, table.remove(pool, idx))
	end
	data.CharmOffered = offered
	charmOfferRemote:FireClient(player, offered)
end

local function refreshGamePasses(player: Player)
	local data = sessions[player]
	if not data then
		return
	end
	local function owns(passId: number): boolean
		if passId == 0 then
			return false
		end
		local ok, result = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
		end)
		return ok and result == true
	end
	data.HasDoubleCoins = owns(Config.GamePasses.DoubleCoins)
	data.HasAutoCollect = owns(Config.GamePasses.AutoCollect)
	data.HasVip = owns(Config.GamePasses.Vip)
	data.HasLucky = owns(Config.GamePasses.Lucky)
	player:SetAttribute("HasDoubleCoins", data.HasDoubleCoins)
	player:SetAttribute("HasVip", data.HasVip)
end

-- フレンドが同じサーバーにいると+10%（Fischの共有体験ボーナス式）
local function refreshFriendBoost()
	for _, player in ipairs(Players:GetPlayers()) do
		local data = sessions[player]
		if data then
			task.spawn(function()
				local boost = false
				for _, other in ipairs(Players:GetPlayers()) do
					if other ~= player then
						local ok, areFriends = pcall(function()
							return player:IsFriendsWith(other.UserId)
						end)
						if ok and areFriends then
							boost = true
							break
						end
					end
				end
				data.FriendBoost = boost
				player:SetAttribute("FriendBoost", boost)
			end)
		end
	end
end

Players.PlayerAdded:Connect(function(player)
	local data = loadData(player)
	data.ComboCount = 0
	data.LastCollectAt = 0
	data.FlavorId = ""
	data.FlavorEndsAt = 0
	data.GoldenNext = ownsLegacy(data, "GoldenSpawn")
	if data.WeekKey ~= currentWeekKey() then
		data.WeekKey = currentWeekKey()
		data.WeeklyEarned = 0
	end
	sessions[player] = data
	buildValueObjects(player, data)
	syncLegacyAttributes(player, data)
	refreshGamePasses(player)
	player.CharacterAdded:Connect(function()
		task.wait(0.2)
		applyStats(player)
	end)

	-- オフライン報酬（泡ジャー）: 前回退出からの経過ぶんを上限付きで付与
	local lastSeen = data.LastSeen or 0
	if lastSeen > 0 then
		local elapsed = os.time() - lastSeen
		if elapsed >= Config.Offline.MinSeconds then
			local capSeconds = Config.Offline.CapSeconds
			local rateMult = 1
			if ownsLegacy(data, "OfflinePlus") then
				capSeconds = capSeconds * 2
				rateMult = 2
			end
			local capped = math.min(elapsed, capSeconds)
			local rate = Config.Offline.BasePerMinute * rateMult * (1 + data.ValueLevel) * (1 + 0.5 * data.Rebirths) * (1 + data.MilestoneBoost / 100)
			local grant = math.floor(capped / 60 * rate)
			if grant > 0 then
				player.leaderstats.Coins.Value += grant
				task.delay(2, function()
					notify(player, string.format("おかえり! いない間に泡ジャーが %d コイン貯めてくれた", grant))
				end)
			end
		end
	end

	notify(player, "ようこそ! 泡に触ってコインを集めよう。レア泡は図鑑に登録されるよ")
	task.delay(1, refreshFriendBoost)
	-- チャームが未選択なら3択を提示する（このランの個性）
	if (data.ActiveCharm or "") == "" then
		task.delay(3, function()
			if sessions[player] then
				offerCharms(player)
			end
		end)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	saveData(player)
	sessions[player] = nil
	task.delay(1, refreshFriendBoost)
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		saveData(player)
	end
end)

task.spawn(function()
	while true do
		task.wait(Config.AutosaveSeconds)
		for _, player in ipairs(Players:GetPlayers()) do
			saveData(player)
		end
	end
end)

----------------------------------------------------------------
-- 泡の生成（レアリティ＋天候ミューテーション＋演出）
----------------------------------------------------------------
local function rarityIndex(rarityId: string): number
	for i, rarity in ipairs(Config.Rarities) do
		if rarity.Id == rarityId then
			return i
		end
	end
	return 1
end

local function burstEffect(position: Vector3, color: Color3, count: number)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	part.Position = position
	part.Parent = workspace
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.Lifetime = NumberRange.new(0.4, 0.9)
	emitter.Speed = NumberRange.new(6, 14)
	emitter.SpreadAngle = Vector2.new(360, 360)
	emitter.Rate = 0
	emitter.Parent = part
	emitter:Emit(count)
	Debris:AddItem(part, 1)
end

local function collectBubble(player: Player, bubble: BasePart)
	if bubble:GetAttribute("Collected") then
		return
	end
	bubble:SetAttribute("Collected", true)
	local data = sessions[player]
	if not data then
		bubble:Destroy()
		return
	end

	local zoneValue = bubble:GetAttribute("Value") or 1
	local rarity = Config.Rarities[rarityIndex(bubble:GetAttribute("RarityId") or "Common")]
	local mutationMult = bubble:GetAttribute("MutationMult") or 1
	local mutationName = bubble:GetAttribute("MutationName") or ""

	-- 運による格上げ抽選（個人の運が効く場所）
	local tier = rarityIndex(rarity.Id)
	local upgradeChance = player.Stats.LuckLevel.Value * 0.02 + (data.HasLucky and 0.10 or 0)
	if ownsLegacy(data, "LuckySoul") then
		upgradeChance += 0.08
	end
	if data.ActiveCharm == "Lucky" then
		upgradeChance += 0.12
	end
	if tier < #Config.Rarities and math.random() < upgradeChance then
		tier += 1
		rarity = Config.Rarities[tier]
	end
	-- ゴールデンスポーン: ラン最初の泡はレア以上確定
	if data.GoldenNext then
		data.GoldenNext = false
		if tier < 3 then
			tier = 3
			rarity = Config.Rarities[tier]
		end
	end
	-- 個人変異（ミュータントスタート / レインダンサー）
	if mutationMult <= 1 then
		if ownsLegacy(data, "MutantStart") and math.random() < 0.05 then
			local options = { 5, 20, 50 }
			mutationMult = options[math.random(1, #options)]
			mutationName = "変異"
		elseif data.ActiveCharm == "Rain" and math.random() < 0.15 then
			mutationMult = 10
			mutationName = "雨"
		end
	end

	-- コンボ（持続時間はレガシーとチャームで伸びる）
	local comboWindow = Config.Combo.WindowSeconds
	if ownsLegacy(data, "ComboKeeper") then
		comboWindow += 2
	end
	if data.ActiveCharm == "Swift" then
		comboWindow += 2
	end
	local now = os.clock()
	if now - (data.LastCollectAt or 0) <= comboWindow then
		data.ComboCount = math.min((data.ComboCount or 0) + 1, Config.Combo.MaxCombo)
	else
		data.ComboCount = 1
	end
	data.LastCollectAt = now
	local comboMult = 1 + data.ComboCount * Config.Combo.PerCombo

	-- クリティカル
	local critChance = Config.Critical.BaseChance + player.Stats.LuckLevel.Value * Config.Critical.PerLuckLevel
	if data.ActiveCharm == "Lucky" then
		critChance += 0.05
	end
	local isCrit = math.random() < critChance

	-- 倍率チェーン
	local reward = zoneValue * rarity.ValueMultiplier * mutationMult
	reward *= (1 + player.Stats.ValueLevel.Value)
	reward *= (1 + 0.5 * player.leaderstats.Rebirths.Value)
	reward *= (1 + player.Stats.MilestoneBoost.Value / 100)
	reward *= comboMult
	if data.HasDoubleCoins then
		reward *= 2
	end
	if os.time() < serverLuckEndsAt then
		reward *= 2
	end
	if data.FriendBoost then
		reward *= 1.1
	end
	if data.FlavorId ~= "" and os.time() < (data.FlavorEndsAt or 0) then
		local flavor = Config.FindFlavor(data.FlavorId)
		if flavor then
			reward *= flavor.Multiplier
		end
	end
	if mutationMult > 1 then
		if ownsLegacy(data, "WeatherMagnet") then
			reward *= 1.3
		end
		if data.ActiveCharm == "Mutant" then
			reward *= 1.5
		end
	end
	if data.ActiveCharm == "Greed" then
		reward *= 1.3
	end
	if isCrit then
		reward *= Config.Critical.Multiplier
	end
	reward = math.floor(reward)

	player.leaderstats.Coins.Value += reward
	player.leaderstats.Bubbles.Value += 1
	player.Stats.TotalBubbles.Value += 1
	player.Stats.TotalEarned.Value += reward
	data.WeeklyEarned = (data.WeeklyEarned or 0) + reward

	-- 図鑑登録（初回はボーナス）
	if not data.DiscoveredRarities[rarity.Id] then
		data.DiscoveredRarities[rarity.Id] = true
		player:SetAttribute("Discovered_" .. rarity.Id, true)
		local bonus = 50 * tier * tier
		player.leaderstats.Coins.Value += bonus
		notify(player, string.format("📖 図鑑登録! %s（%dコイン ボーナス）", rarity.Name, bonus))
	end

	-- ミッション階段（累計泡）
	local reached = 0
	for _, threshold in ipairs(Config.Milestones) do
		if player.Stats.TotalBubbles.Value >= threshold then
			reached += 1
		end
	end
	local expectedBoost = reached * Config.MilestoneBoostPerTier
	if expectedBoost > player.Stats.MilestoneBoost.Value then
		player.Stats.MilestoneBoost.Value = expectedBoost
		announce(string.format("🏆 %s さんが累計 %d 個の泡を達成! 永久倍率 +%d%%", player.DisplayName, Config.Milestones[reached], expectedBoost))
	end

	-- 演出
	burstEffect(bubble.Position, rarity.Color, 14 + tier * 8)
	if tier >= 5 then
		announce(string.format("✨ %s さんが %s%s の泡をゲット! +%d コイン", player.DisplayName, mutationName, rarity.Name, reward))
	end
	-- ミシックは全サーバーへ告知（MessagingService、連投は60秒に1回まで）
	if tier >= 6 and os.time() - (data.LastMythicPublish or 0) >= 60 then
		data.LastMythicPublish = os.time()
		pcall(function()
			MessagingService:PublishAsync("AquaMythic", player.DisplayName)
		end)
	end
	collectEffectRemote:FireClient(player, reward, rarity.Id, isCrit, data.ComboCount, mutationName, comboWindow)
	bubble:Destroy()
end

local function spawnBubble(zone: any)
	local rarity = Config.RollRarity(zone.RareBonus)
	local bubble = Instance.new("Part")
	bubble.Name = "Bubble"
	bubble.Shape = Enum.PartType.Ball
	local size = (math.random(18, 30) / 10) * (1 + (rarityIndex(rarity.Id) - 1) * 0.18)
	bubble.Size = Vector3.new(size, size, size)
	local offsetX = math.random(-40, 40)
	local offsetZ = math.random(-40, 40)
	bubble.Position = zone.Center + Vector3.new(offsetX, 4, offsetZ)
	bubble.Color = rarity.Color
	bubble.Material = Enum.Material.Glass
	bubble.Transparency = 0.3
	bubble.Anchored = true
	bubble.CanCollide = false
	bubble:SetAttribute("IsBubble", true)
	bubble:SetAttribute("ZoneId", zone.Id)
	bubble:SetAttribute("Value", zone.BubbleValue)
	bubble:SetAttribute("RarityId", rarity.Id)

	-- 天候ミューテーション抽選
	if currentWeather and math.random() < currentWeather.MutationChance then
		bubble:SetAttribute("MutationMult", currentWeather.MutationMultiplier)
		bubble:SetAttribute("MutationName", currentWeather.MutationName)
		bubble.Color = currentWeather.Color
		bubble.Transparency = 0.1
	end

	-- レアリティ演出: 光とキラキラと名札
	local tier = rarityIndex(rarity.Id)
	if tier >= 3 then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = rarity.Color
		sparkles.Parent = bubble
	end
	if tier >= 5 then
		local light = Instance.new("PointLight")
		light.Color = rarity.Color
		light.Range = 18
		light.Brightness = 2
		light.Parent = bubble
	end
	if tier >= 4 then
		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.new(0, 140, 0, 40)
		billboard.StudsOffset = Vector3.new(0, 3, 0)
		billboard.Parent = bubble
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = (bubble:GetAttribute("MutationName") or "") .. rarity.Name
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
		label.TextColor3 = rarity.Color
		label.Parent = billboard
	end

	-- ゆらゆら浮くアニメーション
	local basePos = bubble.Position
	local tween = TweenService:Create(bubble, TweenInfo.new(math.random(10, 16) / 10, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Position = basePos + Vector3.new(0, 1.2, 0) })
	tween:Play()

	bubble.Touched:Connect(function(hit)
		local character = hit.Parent
		if not character then
			return
		end
		local player = Players:GetPlayerFromCharacter(character)
		if player then
			collectBubble(player, bubble)
		end
	end)
	bubble.Parent = bubbleFolder
end

task.spawn(function()
	while true do
		for _, zone in ipairs(Config.Zones) do
			local count = 0
			for _, bubble in ipairs(bubbleFolder:GetChildren()) do
				if bubble:GetAttribute("ZoneId") == zone.Id then
					count += 1
				end
			end
			for _ = count + 1, zone.MaxBubbles do
				spawnBubble(zone)
			end
		end
		task.wait(1)
	end
end)

-- 磁石
task.spawn(function()
	while true do
		task.wait(0.4)
		for _, player in ipairs(Players:GetPlayers()) do
			local data = sessions[player]
			local character = player.Character
			if data and character then
				local radius = Config.MagnetRadius(player.Stats.MagnetLevel.Value, data.HasAutoCollect == true)
				-- レガシー/チャームによる磁石の底上げ
				if radius <= 0 and (ownsLegacy(data, "MagnetAura") or data.ActiveCharm == "Magnet") then
					radius = 10
				elseif radius > 0 and data.ActiveCharm == "Magnet" then
					radius += 10
				end
				local root = character:FindFirstChild("HumanoidRootPart")
				if radius > 0 and root then
					for _, bubble in ipairs(bubbleFolder:GetChildren()) do
						if bubble:IsA("BasePart") and (bubble.Position - root.Position).Magnitude <= radius then
							collectBubble(player, bubble)
						end
					end
				end
			end
		end
	end
end)

----------------------------------------------------------------
-- ポータル / フレーバー購入
----------------------------------------------------------------
for _, prompt in ipairs(portalPrompts) do
	prompt.Triggered:Connect(function(player)
		local pad = prompt.Parent :: BasePart
		local zoneId = pad:GetAttribute("ZoneId")
		local zone
		for _, candidate in ipairs(Config.Zones) do
			if candidate.Id == zoneId then
				zone = candidate
			end
		end
		if not zone then
			return
		end
		local data = sessions[player]
		if not data then
			return
		end
		if not data.UnlockedZones[zoneId] then
			if player.leaderstats.Coins.Value < zone.UnlockCost then
				notify(player, string.format("%s の解放には %d コイン必要です", zone.Name, zone.UnlockCost))
				return
			end
			player.leaderstats.Coins.Value -= zone.UnlockCost
			data.UnlockedZones[zoneId] = true
			player:SetAttribute("Unlocked_" .. zoneId, true)
			notify(player, zone.Name .. " を解放した!")
		end
		local character = player.Character
		if character then
			character:PivotTo(CFrame.new(zone.Center + Vector3.new(0, 4, 20)))
		end
	end)
end

flavorPrompt.Triggered:Connect(function(player)
	local data = sessions[player]
	if not data then
		return
	end
	if player.leaderstats.Coins.Value < currentFlavor.Cost then
		notify(player, "コインが足りません")
		return
	end
	player.leaderstats.Coins.Value -= currentFlavor.Cost
	data.FlavorId = currentFlavor.Id
	data.FlavorEndsAt = os.time() + currentFlavor.DurationSeconds
	player:SetAttribute("FlavorName", currentFlavor.Name)
	player:SetAttribute("FlavorEndsAt", data.FlavorEndsAt)
	notify(player, string.format("%sフレーバー! %d分間 獲得×%g", currentFlavor.Name, currentFlavor.DurationSeconds / 60, currentFlavor.Multiplier))
end)

----------------------------------------------------------------
-- ショップ検証（アップグレード / リバース / コード）
----------------------------------------------------------------
purchaseUpgradeRemote.OnServerEvent:Connect(function(player, upgradeId)
	if type(upgradeId) ~= "string" then
		return
	end
	local def = Config.Upgrades[upgradeId]
	if not def then
		return
	end
	local levelValue = player.Stats:FindFirstChild(upgradeId .. "Level")
	if not levelValue then
		return
	end
	if levelValue.Value >= def.MaxLevel then
		notify(player, "すでに最大レベルです")
		return
	end
	local cost = Config.UpgradeCost(upgradeId, levelValue.Value)
	if player.leaderstats.Coins.Value < cost then
		notify(player, "コインが足りません")
		return
	end
	player.leaderstats.Coins.Value -= cost
	levelValue.Value += 1
	applyStats(player)
	notify(player, string.format("%s が Lv.%d になった!", def.Name, levelValue.Value))
end)

requestRebirthRemote.OnServerEvent:Connect(function(player)
	local cost = Config.RebirthCost(player.leaderstats.Rebirths.Value)
	if player.leaderstats.Coins.Value < cost then
		notify(player, string.format("リバースには %d コイン必要です", cost))
		return
	end
	local data = sessions[player]
	player.leaderstats.Rebirths.Value += 1
	local gainedPoints = player.leaderstats.Rebirths.Value
	player.Stats.LegacyPoints.Value += gainedPoints
	-- リセットするのはコインとレベルだけ（ゾーン・図鑑・ミッションは保持する）
	player.leaderstats.Coins.Value = 0
	player.Stats.ValueLevel.Value = 0
	player.Stats.SpeedLevel.Value = 0
	player.Stats.LuckLevel.Value = 0
	if not (data and ownsLegacy(data, "Keeper")) then
		player.Stats.MagnetLevel.Value = 0
	end
	if data and ownsLegacy(data, "HeadStart") then
		player.leaderstats.Coins.Value = 500
	end
	if data then
		data.ActiveCharm = ""
		player:SetAttribute("ActiveCharmName", "")
		data.GoldenNext = ownsLegacy(data, "GoldenSpawn")
		data.ComboCount = 0
	end
	applyStats(player)
	announce(string.format("🌀 %s さんが %d 回目のリバース! レガシーポイント +%d", player.DisplayName, player.leaderstats.Rebirths.Value, gainedPoints))
	notify(player, string.format("リバース成功! 永久倍率 +%d%% / レガシーポイント +%d。新しいチャームを選んでね", player.leaderstats.Rebirths.Value * 50, gainedPoints))
	task.delay(1, function()
		if sessions[player] then
			offerCharms(player)
		end
	end)
end)

-- レガシーツリー購入
purchaseLegacyRemote.OnServerEvent:Connect(function(player, nodeId)
	if type(nodeId) ~= "string" then
		return
	end
	local data = sessions[player]
	local node = Config.FindLegacyNode(nodeId)
	if not data or not node then
		return
	end
	if data.OwnedLegacy[nodeId] then
		return
	end
	if node.Requires ~= "" and not data.OwnedLegacy[node.Requires] then
		notify(player, "先に前提アビリティが必要です")
		return
	end
	if player.Stats.LegacyPoints.Value < node.Cost then
		notify(player, "レガシーポイントが足りません（転生で貯まります）")
		return
	end
	player.Stats.LegacyPoints.Value -= node.Cost
	data.OwnedLegacy[nodeId] = true
	if nodeId == "GoldenSpawn" then
		data.GoldenNext = true
	end
	syncLegacyAttributes(player, data)
	announce(string.format("🌳 %s さんがレガシー「%s」を解放!", player.DisplayName, node.Name))
end)

-- チャーム選択
charmSelectRemote.OnServerEvent:Connect(function(player, charmId)
	if type(charmId) ~= "string" then
		return
	end
	local data = sessions[player]
	if not data or not data.CharmOffered then
		return
	end
	local valid = false
	for _, offeredId in ipairs(data.CharmOffered) do
		if offeredId == charmId then
			valid = true
		end
	end
	if not valid then
		return
	end
	data.ActiveCharm = charmId
	data.CharmOffered = nil
	local charm = Config.FindCharm(charmId)
	player:SetAttribute("ActiveCharmName", charm and charm.Name or "")
	applyStats(player)
	notify(player, string.format("🔮 チャーム「%s」を選んだ! %s", charm and charm.Name or "", charm and charm.Description or ""))
end)

redeemCodeRemote.OnServerEvent:Connect(function(player, code)
	if type(code) ~= "string" then
		return
	end
	local data = sessions[player]
	if not data then
		return
	end
	local normalized = string.upper(string.gsub(code, "%s+", ""))
	local reward = Config.Codes[normalized]
	if not reward then
		notify(player, "そのコードは存在しません")
		return
	end
	if data.RedeemedCodes[normalized] then
		notify(player, "そのコードは使用済みです")
		return
	end
	data.RedeemedCodes[normalized] = true
	player.leaderstats.Coins.Value += reward.Coins
	notify(player, string.format("コード交換成功! %d コイン", reward.Coins))
end)

----------------------------------------------------------------
-- 収益化
----------------------------------------------------------------
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(userId, passId, wasPurchased)
	if not wasPurchased then
		return
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		refreshGamePasses(player)
		applyStats(player)
		notify(player, "ゲームパスが有効になった!")
	end
end)

MarketplaceService.ProcessReceipt = function(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- サーバー全体ラック
	local luck = Config.Products.ServerLuck
	if luck.Id ~= 0 and luck.Id == receiptInfo.ProductId then
		serverLuckEndsAt = math.max(serverLuckEndsAt, os.time()) + luck.DurationSeconds
		workspace:SetAttribute("ServerLuckEndsAt", serverLuckEndsAt)
		player:SetAttribute("LuckBuyer", true)
		announce(string.format("🍀 %s さんがサーバー全体ラックを購入! 全員15分間コイン×2!", player.DisplayName))
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	for _, product in pairs(Config.Products) do
		if product.GrantCoins and product.Id ~= 0 and product.Id == receiptInfo.ProductId then
			player.leaderstats.Coins.Value += product.GrantCoins
			notify(player, string.format("%s を受け取った!", product.Label))
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

----------------------------------------------------------------
-- 承認欲求システム: 称号タグ / オーラ / ランキング壁 / 表彰台の像 / 全サーバー告知
----------------------------------------------------------------
local function updateTitle(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local head = character:FindFirstChild("Head")
	local statsFolder = player:FindFirstChild("Stats")
	if not head or not statsFolder then
		return
	end
	local totalEarned = statsFolder:FindFirstChild("TotalEarned")
	if not totalEarned then
		return
	end
	local title = Config.TitleFor(totalEarned.Value)
	local tag = head:FindFirstChild("TitleTag")
	if not tag then
		tag = Instance.new("BillboardGui")
		tag.Name = "TitleTag"
		tag.Size = UDim2.new(0, 220, 0, 54)
		tag.StudsOffset = Vector3.new(0, 3.4, 0)
		tag.AlwaysOnTop = true
		tag.Parent = head
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "NameLabel"
		nameLabel.Size = UDim2.new(1, 0, 0, 0.5)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextScaled = true
		nameLabel.TextColor3 = Color3.new(1, 1, 1)
		nameLabel.Parent = tag
		local titleLabel = Instance.new("TextLabel")
		titleLabel.Name = "TitleLabel"
		titleLabel.Size = UDim2.new(1, 0, 0, 0.5)
		titleLabel.Position = UDim2.new(0, 0, 0.5, 0)
		titleLabel.BackgroundTransparency = 1
		titleLabel.Font = Enum.Font.GothamBold
		titleLabel.TextScaled = true
		titleLabel.Parent = tag
	end
	local isLuckBuyer = player:GetAttribute("LuckBuyer") and os.time() < serverLuckEndsAt
	tag.NameLabel.Text = (isLuckBuyer and "🍀 " or "") .. player.DisplayName
	tag.NameLabel.TextColor3 = isLuckBuyer and Color3.fromRGB(255, 210, 60) or Color3.new(1, 1, 1)
	tag.TitleLabel.Text = title.Name
	tag.TitleLabel.TextColor3 = title.Color
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		task.wait(1)
		updateTitle(player)
		-- 上位者オーラ（リバース2回以上 or ミッション倍率+30%以上）
		local character = player.Character
		local statsFolder = player:FindFirstChild("Stats")
		local leaderstatsFolder = player:FindFirstChild("leaderstats")
		if character and statsFolder and leaderstatsFolder then
			local root = character:FindFirstChild("HumanoidRootPart")
			local milestone = statsFolder:FindFirstChild("MilestoneBoost")
			local rebirths = leaderstatsFolder:FindFirstChild("Rebirths")
			if root and milestone and rebirths and (rebirths.Value >= 2 or milestone.Value >= 30) then
				local aura = Instance.new("ParticleEmitter")
				aura.Color = ColorSequence.new(rebirths.Value >= 5 and Color3.fromRGB(255, 190, 60) or Color3.fromRGB(110, 220, 255))
				aura.Lifetime = NumberRange.new(0.8, 1.4)
				aura.Rate = 14
				aura.Speed = NumberRange.new(1, 3)
				aura.Size = NumberSequence.new(1.1)
				aura.Parent = root
			end
		end
	end)
end)

-- ミシックの全サーバー告知を受け取る
pcall(function()
	MessagingService:SubscribeAsync("AquaMythic", function(message)
		announce("🌍 [全サーバー] " .. tostring(message.Data) .. " さんがミシックの泡をゲット!")
	end)
end)

-- ランキング壁（このサーバー）
local function fillBoard(boardName: string, lines: { string })
	local board = world:FindFirstChild(boardName)
	if not board then
		return
	end
	local gui = board:FindFirstChild("BoardGui")
	if not gui then
		return
	end
	for i = 1, 8 do
		local row = gui:FindFirstChild("Row" .. i)
		if row then
			row.Text = lines[i] or ""
		end
	end
end

task.spawn(function()
	while true do
		local sorted = Players:GetPlayers()
		table.sort(sorted, function(a, b)
			local av = a:FindFirstChild("Stats") and a.Stats:FindFirstChild("TotalEarned") and a.Stats.TotalEarned.Value or 0
			local bv = b:FindFirstChild("Stats") and b.Stats:FindFirstChild("TotalEarned") and b.Stats.TotalEarned.Value or 0
			return av > bv
		end)
		local lines = {}
		for i, p in ipairs(sorted) do
			if i <= 8 then
				local statsFolder = p:FindFirstChild("Stats")
				local earned = statsFolder and statsFolder:FindFirstChild("TotalEarned")
				local earnedValue = earned and earned.Value or 0
				local title = Config.TitleFor(earnedValue)
				lines[i] = string.format("%d. %s [%s] 累計 %d", i, p.DisplayName, title.Name, earnedValue)
			end
		end
		fillBoard("ServerBoard", lines)
		for _, p in ipairs(Players:GetPlayers()) do
			updateTitle(p)
		end
		task.wait(15)
	end
end)

-- 週間グローバルランキング（OrderedDataStore）
local weeklyStore = DataStoreService:GetOrderedDataStore("WeeklyTop_v1")
task.spawn(function()
	while true do
		pcall(function()
			for _, p in ipairs(Players:GetPlayers()) do
				local data = sessions[p]
				if data and (data.WeeklyEarned or 0) > 0 then
					weeklyStore:SetAsync(tostring(p.UserId) .. ":" .. p.DisplayName, math.floor(data.WeeklyEarned))
				end
			end
			local pages = weeklyStore:GetSortedAsync(false, 8)
			local items = pages:GetCurrentPage()
			local lines = {}
			for i, item in ipairs(items) do
				local name = string.match(item.key, ":(.+)$") or item.key
				lines[i] = string.format("%d. %s — 今週 %d", i, name, item.value)
			end
			fillBoard("GlobalBoard", lines)
		end)
		task.wait(240)
	end
end)

-- 表彰台: このサーバーのTOP3の像を立てる
local podiumTops = { 4.2, 3.2, 2.6 }
local podiumColors = { Color3.fromRGB(255, 200, 40), Color3.fromRGB(200, 200, 210), Color3.fromRGB(200, 130, 70) }
task.spawn(function()
	while true do
		task.wait(30)
		local statuesFolder = world:FindFirstChild("Statues")
		if statuesFolder then
			statuesFolder:ClearAllChildren()
			local sorted = Players:GetPlayers()
			table.sort(sorted, function(a, b)
				local av = a:FindFirstChild("Stats") and a.Stats:FindFirstChild("TotalEarned") and a.Stats.TotalEarned.Value or 0
				local bv = b:FindFirstChild("Stats") and b.Stats:FindFirstChild("TotalEarned") and b.Stats.TotalEarned.Value or 0
				return av > bv
			end)
			for rank = 1, math.min(3, #sorted) do
				local p = sorted[rank]
				local basePos = Vector3.new(14 + (rank - 1) * 6.5, podiumTops[rank], 26)
				local model = Instance.new("Model")
				model.Name = "Statue_" .. p.Name
				model.Parent = statuesFolder
				local function statuePart(name: string, size: Vector3, offset: Vector3, color: Color3)
					local part = Instance.new("Part")
					part.Name = name
					part.Size = size
					part.Position = basePos + offset
					part.Color = color
					part.Material = Enum.Material.SmoothPlastic
					part.Anchored = true
					part.Parent = model
					return part
				end
				statuePart("Legs", Vector3.new(1.6, 1.6, 0.9), Vector3.new(0, 0.8, 0), Color3.fromRGB(70, 90, 140))
				statuePart("Torso", Vector3.new(2.1, 2.1, 1), Vector3.new(0, 2.65, 0), podiumColors[rank])
				local headPart = statuePart("Head", Vector3.new(1.5, 1.5, 1.5), Vector3.new(0, 4.5, 0), Color3.fromRGB(255, 215, 170))
				headPart.Shape = Enum.PartType.Ball
				local billboard = Instance.new("BillboardGui")
				billboard.Size = UDim2.new(0, 200, 0, 50)
				billboard.StudsOffset = Vector3.new(0, 3.6, 0)
				billboard.Parent = headPart
				local label = Instance.new("TextLabel")
				label.Size = UDim2.fromScale(1, 1)
				label.BackgroundTransparency = 1
				label.Text = string.format("%d位 %s\n%s", rank, p.DisplayName, Config.TitleFor(p.Stats.TotalEarned.Value).Name)
				label.TextScaled = true
				label.Font = Enum.Font.GothamBold
				label.TextColor3 = podiumColors[rank]
				label.Parent = billboard
			end
		end
	end
end)

-- ランドマーク泡: ふわふわ＋状態で色が変わる（全体ラック中は金色）
task.spawn(function()
	local fountain = world:WaitForChild("Fountain")
	local landmark = fountain:WaitForChild("LandmarkBubble")
	local basePos = landmark.Position
	TweenService:Create(landmark, TweenInfo.new(2.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Position = basePos + Vector3.new(0, 2.5, 0) }):Play()
	local light = landmark:FindFirstChildOfClass("PointLight")
	while true do
		local color = Color3.fromRGB(120, 215, 255)
		if os.time() < serverLuckEndsAt then
			color = Color3.fromRGB(255, 200, 60)
		elseif currentWeather then
			color = currentWeather.Color
		end
		landmark.Color = color
		if light then
			light.Color = color
		end
		task.wait(1)
	end
end)

-- バブルリフトと空島からの帰還
task.spawn(function()
	local lift = world:WaitForChild("BubbleLift")
	local lastLift: { [Player]: number } = {}
	lift.Touched:Connect(function(hit)
		local character = hit.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		if not player then
			return
		end
		if os.clock() - (lastLift[player] or 0) < 2.5 then
			return
		end
		lastLift[player] = os.clock()
		local root = character:FindFirstChild("HumanoidRootPart")
		if root then
			root.AssemblyLinearVelocity = Vector3.new(0, 74, 0)
		end
	end)
	local skyDeck = world:WaitForChild("SkyDeck")
	local returnPrompt = skyDeck:WaitForChild("ReturnPad"):WaitForChild("ReturnPrompt")
	returnPrompt.Triggered:Connect(function(player)
		local character = player.Character
		if character then
			character:PivotTo(CFrame.new(0, 5, 20))
		end
	end)
end)

print("[AquaBubble] Server started: " .. Config.GameName .. " " .. Config.Version)
