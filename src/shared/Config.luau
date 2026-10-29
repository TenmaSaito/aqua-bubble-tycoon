-- Config.luau
-- ゲーム全体で共有する設定・バランス表。
-- ★ お金を稼ぐためのIDはここに集約した。
--   Roblox公開後に Creator Hub で作ったゲームパス / 開発者製品のIDを
--   0 の場所へ貼るだけで課金が有効になる（手順は README.md 参照）。

local Config = {}

Config.GameName = "Aqua Bubble Tycoon"
Config.DataStoreName = "AquaBubbleTycoon_v1"
Config.AutosaveSeconds = 120

-- 収益化ID（公開後に差し替える。0 = 未設定で、その機能は無効表示になる）
Config.GamePasses = {
	-- コイン獲得量が2倍になる永続パス
	DoubleCoins = 0,
	-- 磁石（自動回収）の範囲が2倍になる永続パス
	AutoCollect = 0,
	-- VIP: 移動速度+8＆名前の横にVIP表示（コスメ寄り）
	Vip = 0,
}

Config.Products = {
	-- 開発者製品（消費型）。購入するたびにコインが付与される
	CoinsSmall = { Id = 0, GrantCoins = 1000, Label = "コイン 1,000" },
	CoinsLarge = { Id = 0, GrantCoins = 15000, Label = "コイン 15,000" },
}

-- ゾーン定義。奥のゾーンほど泡の価値が高い
Config.Zones = {
	{ Id = "Beach", Name = "ビーチ", UnlockCost = 0, BubbleValue = 1, MaxBubbles = 18, Center = Vector3.new(0, 0, 0), Color = Color3.fromRGB(245, 222, 160) },
	{ Id = "Coral", Name = "サンゴ礁", UnlockCost = 500, BubbleValue = 5, MaxBubbles = 18, Center = Vector3.new(150, 0, 0), Color = Color3.fromRGB(255, 150, 170) },
	{ Id = "Deep", Name = "深海", UnlockCost = 5000, BubbleValue = 25, MaxBubbles = 18, Center = Vector3.new(300, 0, 0), Color = Color3.fromRGB(70, 110, 220) },
}

-- アップグレード定義。Cost は BaseCost * CostGrowth ^ 現在レベル
Config.Upgrades = {
	Value = { Name = "泡の価値アップ", BaseCost = 100, CostGrowth = 1.8, MaxLevel = 20, Description = "1レベルごとに獲得コイン+100%" },
	Speed = { Name = "移動速度アップ", BaseCost = 50, CostGrowth = 1.6, MaxLevel = 16, Description = "1レベルごとに WalkSpeed +2" },
	Magnet = { Name = "磁石アップ", BaseCost = 150, CostGrowth = 1.9, MaxLevel = 10, Description = "近くの泡を自動回収。1レベルごとに範囲+4" },
}

-- アップグレードの次のコストを返す
function Config.UpgradeCost(upgradeId: string, currentLevel: number): number
	local def = Config.Upgrades[upgradeId]
	if not def then
		return math.huge
	end
	return math.floor(def.BaseCost * (def.CostGrowth ^ currentLevel))
end

-- リバース（転生）のコスト。回数ごとに3倍になる
function Config.RebirthCost(rebirths: number): number
	return 10000 * (3 ^ rebirths)
end

-- 泡1個で得られるコイン量
-- 基本値 × 価値レベル × リバース倍率（1回ごとに+50%） × 2倍パス
function Config.CoinReward(zoneValue: number, valueLevel: number, rebirths: number, hasDoubleCoins: boolean): number
	local reward = zoneValue * (1 + valueLevel) * (1 + 0.5 * rebirths)
	if hasDoubleCoins then
		reward *= 2
	end
	return math.floor(reward)
end

-- 磁石の回収範囲（スタッド）
function Config.MagnetRadius(magnetLevel: number, hasAutoCollect: boolean): number
	if magnetLevel <= 0 then
		return 0
	end
	local radius = 6 + 4 * magnetLevel
	if hasAutoCollect then
		radius *= 2
	end
	return radius
end

-- 新規プレイヤーの初期データ
function Config.DefaultData()
	return {
		Coins = 0,
		Bubbles = 0,
		Rebirths = 0,
		ValueLevel = 0,
		SpeedLevel = 0,
		MagnetLevel = 0,
		UnlockedZones = { Beach = true },
	}
end

return Config
