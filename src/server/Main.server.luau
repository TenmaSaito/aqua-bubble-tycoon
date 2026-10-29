-- Main.server.luau
-- サーバーの入口。データ保存・泡の生成と回収・ポータル・ショップ検証・課金処理を担当する。
-- お金に関わる処理はすべてサーバー側で検証する（クライアントは表示と要求だけ）。

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local WorldBuilder = require(script.Parent:WaitForChild("WorldBuilder"))

----------------------------------------------------------------
-- リモート（クライアントとの通信口）
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
local notifyRemote = makeRemote("Notify") -- サーバー → クライアント通知

local function notify(player: Player, message: string)
	notifyRemote:FireClient(player, message)
end

----------------------------------------------------------------
-- ワールド生成
----------------------------------------------------------------
local world, portalPrompts = WorldBuilder.Build()
local bubbleFolder = world:WaitForChild("Bubbles")

----------------------------------------------------------------
-- プレイヤーデータ
----------------------------------------------------------------
local store = DataStoreService:GetDataStore(Config.DataStoreName)
local sessions: { [Player]: any } = {}

-- leaderstats と詳細ステータスを Value オブジェクトとして公開する
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
	stats.Parent = player

	for zoneId, unlocked in pairs(data.UnlockedZones) do
		player:SetAttribute("Unlocked_" .. zoneId, unlocked == true)
	end
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
	else
		if not ok then
			warn("[AquaBubble] DataStore load failed (StudioではAPIアクセス許可が必要): ", saved)
		end
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
		UnlockedZones = data.UnlockedZones,
	}
	local ok, err = pcall(function()
		store:SetAsync("player_" .. player.UserId, snapshot)
	end)
	if not ok then
		warn("[AquaBubble] DataStore save failed: ", err)
	end
end

-- 移動速度などデータ依存の見た目・能力を反映する
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
		humanoid.WalkSpeed = speed
	end
end

-- 保有ゲームパスを再確認する（IDが0のパスは常に未保有扱い）
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
	player:SetAttribute("HasDoubleCoins", data.HasDoubleCoins)
	player:SetAttribute("HasVip", data.HasVip)
end

Players.PlayerAdded:Connect(function(player)
	local data = loadData(player)
	sessions[player] = data
	buildValueObjects(player, data)
	refreshGamePasses(player)
	player.CharacterAdded:Connect(function()
		task.wait(0.2)
		applyStats(player)
	end)
	notify(player, "ようこそ! 泡に触ってコインを集めよう")
end)

Players.PlayerRemoving:Connect(function(player)
	saveData(player)
	sessions[player] = nil
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		saveData(player)
	end
end)

-- 定期オートセーブ
task.spawn(function()
	while true do
		task.wait(Config.AutosaveSeconds)
		for _, player in ipairs(Players:GetPlayers()) do
			saveData(player)
		end
	end
end)

----------------------------------------------------------------
-- 泡の生成と回収
----------------------------------------------------------------
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
	local reward = Config.CoinReward(zoneValue, player.Stats.ValueLevel.Value, player.leaderstats.Rebirths.Value, data.HasDoubleCoins == true)
	player.leaderstats.Coins.Value += reward
	player.leaderstats.Bubbles.Value += 1
	bubble:Destroy()
end

local function spawnBubble(zone: any)
	local bubble = Instance.new("Part")
	bubble.Name = "Bubble"
	bubble.Shape = Enum.PartType.Ball
	local size = math.random(18, 30) / 10
	bubble.Size = Vector3.new(size, size, size)
	local offsetX = math.random(-40, 40)
	local offsetZ = math.random(-40, 40)
	bubble.Position = zone.Center + Vector3.new(offsetX, 4, offsetZ)
	bubble.Color = Color3.fromRGB(140, 220, 255)
	bubble.Material = Enum.Material.Glass
	bubble.Transparency = 0.35
	bubble.Anchored = true
	bubble.CanCollide = false
	bubble:SetAttribute("IsBubble", true)
	bubble:SetAttribute("ZoneId", zone.Id)
	bubble:SetAttribute("Value", zone.BubbleValue)
	bubble.Parent = bubbleFolder

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
end

-- 各ゾーンの泡を上限まで維持する
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

-- 磁石: 近くの泡を自動回収する
task.spawn(function()
	while true do
		task.wait(0.4)
		for _, player in ipairs(Players:GetPlayers()) do
			local data = sessions[player]
			local character = player.Character
			if data and character then
				local radius = Config.MagnetRadius(player.Stats.MagnetLevel.Value, data.HasAutoCollect == true)
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
-- ポータル（ゾーン解放と移動）
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

----------------------------------------------------------------
-- ショップ（アップグレード / リバース）: サーバー側で必ず検証する
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
	player.leaderstats.Coins.Value = 0
	player.Stats.ValueLevel.Value = 0
	player.Stats.SpeedLevel.Value = 0
	player.Stats.MagnetLevel.Value = 0
	player.leaderstats.Rebirths.Value += 1
	applyStats(player)
	notify(player, string.format("リバース成功! 永久倍率が +%d%% になった", player.leaderstats.Rebirths.Value * 50))
end)

----------------------------------------------------------------
-- 収益化: ゲームパス購入の反映と、開発者製品の領収処理
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

-- 開発者製品（消費型コイン）はここでのみ付与する。二重付与防止は Roblox 側の領収仕組みに従う
MarketplaceService.ProcessReceipt = function(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	for _, product in pairs(Config.Products) do
		if product.Id ~= 0 and product.Id == receiptInfo.ProductId then
			player.leaderstats.Coins.Value += product.GrantCoins
			notify(player, string.format("%s を受け取った!", product.Label))
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end
	-- 未知の製品IDは付与しない
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

print("[AquaBubble] Server started: " .. Config.GameName)
