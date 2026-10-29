-- WorldBuilder.luau
-- マップをコードで自動生成するモジュール。
-- Studioで手作業で並べなくても、実行するだけで島・看板・ポータルが生える。
-- アセットはすべて基本パーツの組み合わせ（著作権フリー・外部モデル不使用）。

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local WorldBuilder = {}

-- 汎用パーツ生成ヘルパー
local function makePart(parent: Instance, name: string, size: Vector3, position: Vector3, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- 立て看板（SurfaceGui付き）を作る
local function makeSign(parent: Instance, position: Vector3, text: string, color: Color3)
	local post = makePart(parent, "SignPost", Vector3.new(0.6, 6, 0.6), position + Vector3.new(0, 3, 0), Color3.fromRGB(120, 85, 50), Enum.Material.Wood)
	post.CanCollide = false
	local board = makePart(parent, "SignBoard", Vector3.new(10, 3.4, 0.4), position + Vector3.new(0, 7, 0), color, Enum.Material.SmoothPlastic)
	board.CanCollide = false

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Parent = gui
	-- 裏面にも同じ看板を出す
	local guiBack = gui:Clone()
	guiBack.Face = Enum.NormalId.Back
	guiBack.Parent = board
end

-- ワールド全体を構築し、ポータルの Prompt 一覧を返す
function WorldBuilder.Build(): (Folder, { ProximityPrompt })
	local world = Instance.new("Folder")
	world.Name = "GameWorld"
	world.Parent = workspace

	-- 海（大きな水面ベース）
	local sea = makePart(world, "Sea", Vector3.new(700, 1, 260), Vector3.new(150, -1.2, 0), Color3.fromRGB(40, 140, 220), Enum.Material.SmoothPlastic)
	sea.Transparency = 0.25
	sea.CanCollide = false

	local bubbleFolder = Instance.new("Folder")
	bubbleFolder.Name = "Bubbles"
	bubbleFolder.Parent = world

	local prompts: { ProximityPrompt } = {}

	for index, zone in ipairs(Config.Zones) do
		local zoneFolder = Instance.new("Folder")
		zoneFolder.Name = "Zone_" .. zone.Id
		zoneFolder.Parent = world

		-- 島の地面
		makePart(zoneFolder, "Island", Vector3.new(92, 2, 92), zone.Center + Vector3.new(0, 0, 0), zone.Color, Enum.Material.Sand)

		-- 島の縁（落下防止の低い壁ではなく、目印の枠）
		makePart(zoneFolder, "Rim", Vector3.new(94, 0.6, 2), zone.Center + Vector3.new(0, 1.2, 46), Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic)
		makePart(zoneFolder, "Rim", Vector3.new(94, 0.6, 2), zone.Center + Vector3.new(0, 1.2, -46), Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic)

		-- 装飾: ランダムな岩と貝殻っぽい球（基本パーツのみ）
		for i = 1, 8 do
			local angle = (i / 8) * math.pi * 2 + index
			local decoPos = zone.Center + Vector3.new(math.cos(angle) * 38, 2, math.sin(angle) * 38)
			local rock = makePart(zoneFolder, "Deco", Vector3.new(3, 2, 3), decoPos, Color3.fromRGB(160, 160, 170), Enum.Material.Rock)
			rock.Shape = Enum.PartType.Ball
		end

		-- ゾーン看板
		makeSign(zoneFolder, zone.Center + Vector3.new(0, 1, -40), string.format("%s\n泡の価値: %d", zone.Name, zone.BubbleValue), Color3.fromRGB(30, 120, 200))
	end

	-- スポーン地点（ビーチ中央）
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "MainSpawn"
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.Position = Vector3.new(0, 1.6, 20)
	spawn.Color = Color3.fromRGB(0, 200, 160)
	spawn.Material = Enum.Material.Neon
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Parent = world

	makeSign(world, Vector3.new(0, 1, 32), "Aqua Bubble Tycoon\n泡を集めてコインを稼ごう!", Color3.fromRGB(0, 160, 200))

	-- ポータル置き場（ビーチのスポーン前に3つ並べる）
	for i, zone in ipairs(Config.Zones) do
		local x = (i - 2) * 14
		local pad = makePart(world, "Portal_" .. zone.Id, Vector3.new(9, 0.6, 9), Vector3.new(x, 1.3, 6), Color3.fromRGB(120, 80, 255), Enum.Material.Neon)
		pad.CanCollide = false
		pad:SetAttribute("ZoneId", zone.Id)

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "PortalPrompt"
		prompt.ActionText = zone.UnlockCost > 0 and string.format("解放 %d コイン", zone.UnlockCost) or "移動"
		prompt.ObjectText = zone.Name .. "へ"
		prompt.HoldDuration = 0.4
		prompt.MaxActivationDistance = 12
		prompt.Parent = pad
		table.insert(prompts, prompt)

		makeSign(world, Vector3.new(x, 1, -2), zone.Name, Color3.fromRGB(120, 80, 255))
	end

	-- ショップ案内看板（購入自体は画面右のSHOPボタンから）
	makeSign(world, Vector3.new(22, 1, 20), "SHOPは画面のボタンから\nアップグレードとリバースができるよ", Color3.fromRGB(255, 140, 0))

	return world, prompts
end

return WorldBuilder
