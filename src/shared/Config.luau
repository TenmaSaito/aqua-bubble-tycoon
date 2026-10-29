-- Config.luau (v2)
-- ゲーム全体で共有する設定・バランス表。
-- v2では話題作の勝ち筋を移植した: レアリティ階段 / 天候ミューテーション /
-- 5分回転ショップ / オフライン報酬 / サーバー全体ラック / 図鑑 / コード / ミッション階段。
-- 課金IDは公開後に Creator Hub で作ったIDを 0 の場所へ貼るだけで有効になる。

local Config = {}

Config.GameName = "Aqua Bubble Tycoon"
Config.Version = "v2"
Config.DataStoreName = "AquaBubbleTycoon_v1" -- v1のセーブを引き継ぐため名前は変えない
Config.AutosaveSeconds = 120

-- 収益化ID（公開後に差し替える。0 = 未設定）
Config.GamePasses = {
	DoubleCoins = 0, -- コイン獲得量2倍（永続）
	AutoCollect = 0, -- 磁石の範囲2倍（永続）
	Vip = 0, -- 速度+8（永続）
	Lucky = 0, -- レア泡の出やすさ1.5倍（永続）
}

Config.Products = {
	CoinsSmall = { Id = 0, GrantCoins = 1000, Label = "コイン 1,000" },
	CoinsLarge = { Id = 0, GrantCoins = 15000, Label = "コイン 15,000" },
	-- サーバー全体ラック: 買った人のサーバー全員が15分間コイン2倍になる（Steal a Brainrot式）
	ServerLuck = { Id = 0, DurationSeconds = 900, Label = "サーバー全体ラック×2 (15分)" },
}

-- ゾーン定義。奥ほど泡の価値とレア率が高い
Config.Zones = {
	{ Id = "Beach", Name = "ビーチ", UnlockCost = 0, BubbleValue = 1, MaxBubbles = 18, RareBonus = 1.0, Center = Vector3.new(0, 0, 0), Color = Color3.fromRGB(245, 222, 160) },
	{ Id = "Coral", Name = "サンゴ礁", UnlockCost = 500, BubbleValue = 5, MaxBubbles = 18, RareBonus = 1.35, Center = Vector3.new(150, 0, 0), Color = Color3.fromRGB(255, 150, 170) },
	{ Id = "Deep", Name = "深海", UnlockCost = 5000, BubbleValue = 25, MaxBubbles = 18, RareBonus = 1.8, Center = Vector3.new(300, 0, 0), Color = Color3.fromRGB(70, 110, 220) },
}

-- レアリティ階段（確率は全表示する。Weight合計に対する割合がそのまま確率）
-- 「1 in X」表記はクライアントの図鑑にも出す
Config.Rarities = {
	{ Id = "Common", Name = "コモン", Weight = 700, ValueMultiplier = 1, Color = Color3.fromRGB(140, 220, 255) },
	{ Id = "Uncommon", Name = "アンコモン", Weight = 180, ValueMultiplier = 3, Color = Color3.fromRGB(90, 255, 150) },
	{ Id = "Rare", Name = "レア", Weight = 80, ValueMultiplier = 8, Color = Color3.fromRGB(60, 140, 255) },
	{ Id = "Epic", Name = "エピック", Weight = 30, ValueMultiplier = 25, Color = Color3.fromRGB(190, 80, 255) },
	{ Id = "Legendary", Name = "レジェンダリー", Weight = 9, ValueMultiplier = 100, Color = Color3.fromRGB(255, 190, 40) },
	{ Id = "Mythic", Name = "ミシック", Weight = 1, ValueMultiplier = 500, Color = Color3.fromRGB(255, 70, 90) },
}

-- レアリティを抽選する。luckScale は Luckレベル・ゾーン・ラッキーパスの合算倍率
function Config.RollRarity(luckScale: number): any
	local total = 0
	local weights = {}
	for i, rarity in ipairs(Config.Rarities) do
		local w = rarity.Weight
		if i > 1 then
			w = w * luckScale
		end
		weights[i] = w
		total += w
	end
	local roll = math.random() * total
	local acc = 0
	for i, rarity in ipairs(Config.Rarities) do
		acc += weights[i]
		if roll <= acc then
			return rarity
		end
	end
	return Config.Rarities[1]
end

-- 表示用: そのレアリティの出現確率（%）と「1 in X」
function Config.RarityChanceText(rarity: any, luckScale: number): (number, number)
	local total, target = 0, 0
	for i, r in ipairs(Config.Rarities) do
		local w = r.Weight
		if i > 1 then
			w = w * luckScale
		end
		total += w
		if r.Id == rarity.Id then
			target = w
		end
	end
	local pct = target / total * 100
	return pct, math.floor(total / target + 0.5)
end

-- 天候イベント（Grow a Garden式ミューテーション）
-- 通常時間のあとランダムで1つ発生し、その間に生まれた泡の一部が変異する
Config.Weather = {
	NormalSeconds = 240, -- 通常の長さ
	EventSeconds = 90, -- イベントの長さ
	Events = {
		{ Id = "Golden", Name = "黄金の雨", MutationName = "金", MutationChance = 0.3, MutationMultiplier = 20, Color = Color3.fromRGB(255, 200, 60), SkyColor = Color3.fromRGB(255, 230, 170) },
		{ Id = "Rainbow", Name = "虹のシャワー", MutationName = "虹", MutationChance = 0.15, MutationMultiplier = 50, Color = Color3.fromRGB(255, 120, 220), SkyColor = Color3.fromRGB(255, 190, 240) },
		{ Id = "Storm", Name = "泡嵐", MutationName = "嵐", MutationChance = 0.4, MutationMultiplier = 5, Color = Color3.fromRGB(120, 200, 255), SkyColor = Color3.fromRGB(140, 180, 255) },
	},
}

-- 5分回転のフレーバーショップ（Grow a Gardenの在庫回転式）
-- 在庫の間だけ買える一時バフ。レアなフレーバーほど滅多に出ない
Config.Flavors = {
	StockSeconds = 300,
	Items = {
		{ Id = "Mint", Name = "ミント", Weight = 50, Cost = 200, Multiplier = 1.5, DurationSeconds = 600 },
		{ Id = "Berry", Name = "ベリー", Weight = 30, Cost = 600, Multiplier = 2, DurationSeconds = 600 },
		{ Id = "Gold", Name = "ゴールド", Weight = 15, Cost = 2000, Multiplier = 3, DurationSeconds = 600 },
		{ Id = "Rainbow", Name = "レインボー", Weight = 5, Cost = 6000, Multiplier = 5, DurationSeconds = 600 },
	},
}

function Config.RollFlavor(): any
	local total = 0
	for _, item in ipairs(Config.Flavors.Items) do
		total += item.Weight
	end
	local roll = math.random(1, total)
	local acc = 0
	for _, item in ipairs(Config.Flavors.Items) do
		acc += item.Weight
		if roll <= acc then
			return item
		end
	end
	return Config.Flavors.Items[1]
end

function Config.FindFlavor(flavorId: string): any
	for _, item in ipairs(Config.Flavors.Items) do
		if item.Id == flavorId then
			return item
		end
	end
	return nil
end

-- アップグレード定義
Config.Upgrades = {
	Value = { Name = "泡の価値アップ", BaseCost = 100, CostGrowth = 1.8, MaxLevel = 20, Description = "1レベルごとに獲得コイン+100%" },
	Speed = { Name = "移動速度アップ", BaseCost = 50, CostGrowth = 1.6, MaxLevel = 16, Description = "1レベルごとに WalkSpeed +2" },
	Magnet = { Name = "磁石アップ", BaseCost = 150, CostGrowth = 1.9, MaxLevel = 10, Description = "近くの泡を自動回収。1レベルごとに範囲+4" },
	Luck = { Name = "運アップ", BaseCost = 200, CostGrowth = 2.0, MaxLevel = 10, Description = "レア泡が出やすくなる＆クリティカル率UP" },
}

function Config.UpgradeCost(upgradeId: string, currentLevel: number): number
	local def = Config.Upgrades[upgradeId]
	if not def then
		return math.huge
	end
	return math.floor(def.BaseCost * (def.CostGrowth ^ currentLevel))
end

function Config.RebirthCost(rebirths: number): number
	return 10000 * (3 ^ rebirths)
end

-- コンボ: 3秒以内に集め続けると加算。倍率は最大+200%（100コンボ）
Config.Combo = { WindowSeconds = 3, PerCombo = 0.02, MaxCombo = 100 }

-- クリティカル: 基本5%、Luck1レベルごとに+0.3%。倍率5倍
Config.Critical = { BaseChance = 0.05, PerLuckLevel = 0.003, Multiplier = 5 }

-- ミッション階段（累計泡カウンタで自動達成、達成ごとに永久+10%）
Config.Milestones = { 100, 500, 2000, 10000, 50000 }
Config.MilestoneBoostPerTier = 10 -- %

-- コード（更新のたびに実在するコードを出すこと。偽コードは出さない）
Config.Codes = {
	LAUNCH = { Coins = 1000 },
	BUBBLE = { Coins = 300 },
}

-- オフライン報酬（泡ジャー）: 1分あたりの基礎量 × 強化倍率、最大8時間ぶん
Config.Offline = { BasePerMinute = 6, CapSeconds = 8 * 3600, MinSeconds = 600 }

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

function Config.DefaultData()
	return {
		Coins = 0,
		Bubbles = 0,
		Rebirths = 0,
		ValueLevel = 0,
		SpeedLevel = 0,
		MagnetLevel = 0,
		LuckLevel = 0,
		TotalBubbles = 0,
		TotalEarned = 0,
		MilestoneBoost = 0, -- 永久倍率（%）
		LastSeen = 0,
		UnlockedZones = { Beach = true },
		RedeemedCodes = {},
		DiscoveredRarities = {},
	}
end

return Config
