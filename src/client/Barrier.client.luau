-- Barrier.client.luau
-- ゾーン結界の表示と当たり判定を、自分の解放状態に合わせて切り替える専用スクリプト。
-- メインのクライアントスクリプトから分離してあるのは、万一メイン側でエラーが起きても
-- 結界だけは必ず機能させるため（キャラクターの物理はクライアント側で計算される）。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local gameWorld = workspace:WaitForChild("GameWorld")

local function refreshBarrier(zone)
	local zoneFolder = gameWorld:WaitForChild("Zone_" .. zone.Id)
	local barrier = zoneFolder:WaitForChild("Barrier_" .. zone.Id)
	local unlocked = player:GetAttribute("Unlocked_" .. zone.Id) == true
	for _, wallPart in ipairs(barrier:GetChildren()) do
		if wallPart:IsA("BasePart") then
			wallPart.CanCollide = not unlocked
			wallPart.Transparency = unlocked and 0.92 or 0.45
		end
	end
end

for _, zone in ipairs(Config.Zones) do
	task.spawn(refreshBarrier, zone)
	player:GetAttributeChangedSignal("Unlocked_" .. zone.Id):Connect(function()
		refreshBarrier(zone)
	end)
end
