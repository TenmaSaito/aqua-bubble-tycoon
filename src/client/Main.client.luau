-- Main.client.luau
-- 画面UI（所持金表示・SHOPパネル・通知）をコードで生成する。
-- 購入の確定はすべてサーバー側。ここは表示と「要求を送る」だけ。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local purchaseUpgradeRemote = remotes:WaitForChild("PurchaseUpgrade")
local requestRebirthRemote = remotes:WaitForChild("RequestRebirth")
local notifyRemote = remotes:WaitForChild("Notify")

local leaderstats = player:WaitForChild("leaderstats")
local stats = player:WaitForChild("Stats")

local gui = Instance.new("ScreenGui")
gui.Name = "AquaHud"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

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
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label
	return label
end

-- 上部バー
local coinsLabel = makeLabel(gui, UDim2.new(0, 210, 0, 40), UDim2.new(0, 12, 0, 10), "Coins: 0", 20)
local bubblesLabel = makeLabel(gui, UDim2.new(0, 170, 0, 40), UDim2.new(0, 232, 0, 10), "Bubbles: 0", 20)
local rebirthLabel = makeLabel(gui, UDim2.new(0, 170, 0, 40), UDim2.new(0, 412, 0, 10), "Rebirth: 0", 20)

local function refreshTopBar()
	coinsLabel.Text = "Coins: " .. leaderstats.Coins.Value
	bubblesLabel.Text = "Bubbles: " .. leaderstats.Bubbles.Value
	rebirthLabel.Text = "Rebirth: " .. leaderstats.Rebirths.Value
end
leaderstats.Coins.Changed:Connect(refreshTopBar)
leaderstats.Bubbles.Changed:Connect(refreshTopBar)
leaderstats.Rebirths.Changed:Connect(refreshTopBar)
refreshTopBar()

-- 通知トースト
local toast = makeLabel(gui, UDim2.new(0, 520, 0, 44), UDim2.new(0.5, -260, 0, 62), "", 18)
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

-- SHOPボタン
local shopButton = Instance.new("TextButton")
shopButton.Size = UDim2.new(0, 130, 0, 52)
shopButton.Position = UDim2.new(1, -142, 0, 10)
shopButton.BackgroundColor3 = Color3.fromRGB(255, 140, 0)
shopButton.TextColor3 = Color3.new(1, 1, 1)
shopButton.Font = Enum.Font.GothamBold
shopButton.TextSize = 22
shopButton.Text = "SHOP"
shopButton.Parent = gui
local shopCorner = Instance.new("UICorner")
shopCorner.CornerRadius = UDim.new(0, 10)
shopCorner.Parent = shopButton

-- SHOPパネル
local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, 460, 0, 620)
panel.Position = UDim2.new(0.5, -230, 0.5, -310)
panel.BackgroundColor3 = Color3.fromRGB(12, 45, 80)
panel.BackgroundTransparency = 0.08
panel.Visible = false
panel.Parent = gui
local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 12)
panelCorner.Parent = panel

local title = makeLabel(panel, UDim2.new(1, -20, 0, 40), UDim2.new(0, 10, 0, 8), "SHOP - アップグレード", 20)
title.BackgroundTransparency = 1

shopButton.MouseButton1Click:Connect(function()
	panel.Visible = not panel.Visible
end)

-- アップグレード行を作る（レベルとコストは自動で追従する）
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
	local buyCorner = Instance.new("UICorner")
	buyCorner.CornerRadius = UDim.new(0, 8)
	buyCorner.Parent = buy

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
local rebirthCorner = Instance.new("UICorner")
rebirthCorner.CornerRadius = UDim.new(0, 8)
rebirthCorner.Parent = rebirthBuy

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

-- 課金行（ゲームパス / 開発者製品）。ID未設定の間は押せない表示にする
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
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = buy
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
makePurchaseRow("開発者製品: " .. Config.Products.CoinsSmall.Label, Config.Products.CoinsSmall.Id, function()
	MarketplaceService:PromptProductPurchase(player, Config.Products.CoinsSmall.Id)
end)
makePurchaseRow("開発者製品: " .. Config.Products.CoinsLarge.Label, Config.Products.CoinsLarge.Id, function()
	MarketplaceService:PromptProductPurchase(player, Config.Products.CoinsLarge.Id)
end)
