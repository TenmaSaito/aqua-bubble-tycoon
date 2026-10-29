-- WorldBuilder.luau (v3)
-- マップをコードで自動生成する。v3では広場の作り込み・ゾーンごとのランドマーク・
-- ランキングボード・表彰台・空島（バブルリフト）・レガシー神殿まで生成する。
-- アセットはすべて基本パーツの組み合わせ（著作権フリー・外部モデル不使用）。

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local WorldBuilder = {}

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

-- 円盤パーツ（シリンダーはX軸方向が長さ。Zに90度倒して平らな円盤にする）
local function makeDisc(parent: Instance, name: string, diameter: number, thickness: number, position: Vector3, color: Color3, material: Enum.Material): Part
	local part = makePart(parent, name, Vector3.new(thickness, diameter, diameter), position, color, material)
	part.Shape = Enum.PartType.Cylinder
	part.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	return part
end

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
	local guiBack = gui:Clone()
	guiBack.Face = Enum.NormalId.Back
	guiBack.Parent = board
end

-- ランキングボード（行ラベル Row1..RowN をサーバーが書き換える）
local function makeBoard(parent: Instance, name: string, position: Vector3, rotY: number, titleText: string, color: Color3)
	local board = makePart(parent, name, Vector3.new(17, 11, 0.5), position, color, Enum.Material.SmoothPlastic)
	board.CFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(rotY), 0)
	board.CanCollide = false
	local gui = Instance.new("SurfaceGui")
	gui.Name = "BoardGui"
	gui.Face = Enum.NormalId.Front
	gui.Parent = board
	local title = Instance.new("TextLabel")
	title.Name = "BoardTitle"
	title.Size = UDim2.new(1, 0, 0.14, 0)
	title.BackgroundTransparency = 1
	title.Text = titleText
	title.TextScaled = true
	title.Font = Enum.Font.GothamBold
	title.TextColor3 = Color3.fromRGB(255, 230, 120)
	title.Parent = gui
	for i = 1, 8 do
		local row = Instance.new("TextLabel")
		row.Name = "Row" .. i
		row.Size = UDim2.new(1, -8, 0.1, 0)
		row.Position = UDim2.new(0, 4, 0.15 + (i - 1) * 0.103, 0)
		row.BackgroundTransparency = 1
		row.Text = ""
		row.TextScaled = true
		row.Font = Enum.Font.GothamBold
		row.TextColor3 = Color3.new(1, 1, 1)
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.Parent = gui
	end
	return board
end

local function makePalm(parent: Instance, position: Vector3)
	local trunk = makePart(parent, "PalmTrunk", Vector3.new(1.2, 9, 1.2), position + Vector3.new(0, 4.5, 0), Color3.fromRGB(140, 100, 60), Enum.Material.Wood)
	trunk.CFrame = CFrame.new(trunk.Position) * CFrame.Angles(math.rad(8), 0, 0)
	for i = 1, 3 do
		local angle = (i / 3) * math.pi * 2
		local leaf = makePart(parent, "PalmLeaf", Vector3.new(7, 1.2, 3), position + Vector3.new(math.cos(angle) * 2.4, 9.4, math.sin(angle) * 2.4), Color3.fromRGB(50, 180, 90), Enum.Material.Grass)
		leaf.Shape = Enum.PartType.Ball
		leaf.CanCollide = false
	end
end

local function makeLamp(parent: Instance, position: Vector3)
	makePart(parent, "LampPost", Vector3.new(0.5, 7, 0.5), position + Vector3.new(0, 3.5, 0), Color3.fromRGB(60, 60, 80), Enum.Material.Metal)
	local bulb = makePart(parent, "LampBulb", Vector3.new(1.4, 1.4, 1.4), position + Vector3.new(0, 7.4, 0), Color3.fromRGB(255, 240, 180), Enum.Material.Neon)
	bulb.Shape = Enum.PartType.Ball
	bulb.CanCollide = false
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 230, 170)
	light.Range = 22
	light.Brightness = 1.2
	light.Parent = bulb
end

local function makeCrystal(parent: Instance, position: Vector3, scale: number, color: Color3)
	local crystal = makePart(parent, "Crystal", Vector3.new(2.2 * scale, 7 * scale, 2.2 * scale), position + Vector3.new(0, 3 * scale, 0), color, Enum.Material.Neon)
	crystal.CFrame = CFrame.new(crystal.Position) * CFrame.Angles(math.rad(16), math.rad(30), math.rad(45))
	crystal.CanCollide = false
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 16
	light.Brightness = 1.4
	light.Parent = crystal
	return crystal
end

function WorldBuilder.Build(): (Folder, { ProximityPrompt }, ProximityPrompt, TextLabel)
	local world = Instance.new("Folder")
	world.Name = "GameWorld"
	world.Parent = workspace

	local sea = makePart(world, "Sea", Vector3.new(760, 1, 300), Vector3.new(150, -1.2, 0), Color3.fromRGB(40, 140, 220), Enum.Material.SmoothPlastic)
	sea.Transparency = 0.25
	sea.CanCollide = false

	local bubbleFolder = Instance.new("Folder")
	bubbleFolder.Name = "Bubbles"
	bubbleFolder.Parent = world

	local statues = Instance.new("Folder")
	statues.Name = "Statues"
	statues.Parent = world

	local prompts: { ProximityPrompt } = {}

	for index, zone in ipairs(Config.Zones) do
		local zoneFolder = Instance.new("Folder")
		zoneFolder.Name = "Zone_" .. zone.Id
		zoneFolder.Parent = world

		makePart(zoneFolder, "Island", Vector3.new(92, 2, 92), zone.Center, zone.Color, Enum.Material.Sand)
		-- 島の内側サークル（色分けされた活動エリア）
		makeDisc(zoneFolder, "Disc", 76, 0.5, zone.Center + Vector3.new(0, 1.1, 0), zone.Color:Lerp(Color3.new(1, 1, 1), 0.18), Enum.Material.SmoothPlastic)

		for i = 1, 8 do
			local angle = (i / 8) * math.pi * 2 + index
			local rock = makePart(zoneFolder, "Deco", Vector3.new(3, 2, 3), zone.Center + Vector3.new(math.cos(angle) * 38, 2, math.sin(angle) * 38), Color3.fromRGB(160, 160, 170), Enum.Material.Rock)
			rock.Shape = Enum.PartType.Ball
		end

		if zone.Id == "Beach" then
			for i = 1, 4 do
				local angle = i * 1.7
				makePalm(zoneFolder, zone.Center + Vector3.new(math.cos(angle) * 34, 1, math.sin(angle) * 34))
			end
		elseif zone.Id == "Coral" then
			-- サンゴの枝と、ランドマークの巨大シェル
			for i = 1, 10 do
				local angle = i * 2.3
				local pos = zone.Center + Vector3.new(math.cos(angle) * 33, 1, math.sin(angle) * 33)
				local coral = makePart(zoneFolder, "CoralBranch", Vector3.new(1.4, math.random(4, 8), 1.4), pos + Vector3.new(0, 3, 0), i % 2 == 0 and Color3.fromRGB(255, 110, 150) or Color3.fromRGB(255, 160, 80), Enum.Material.SmoothPlastic)
				coral.CFrame = CFrame.new(coral.Position) * CFrame.Angles(math.rad(math.random(-18, 18)), 0, math.rad(math.random(-18, 18)))
				coral.CanCollide = false
			end
			local shell = makePart(zoneFolder, "GiantShell", Vector3.new(16, 7, 12), zone.Center + Vector3.new(0, 3, -34), Color3.fromRGB(255, 190, 210), Enum.Material.SmoothPlastic)
			shell.Shape = Enum.PartType.Ball
			local pearl = makePart(zoneFolder, "Pearl", Vector3.new(4.5, 4.5, 4.5), zone.Center + Vector3.new(0, 4, -27), Color3.fromRGB(255, 255, 255), Enum.Material.Neon)
			pearl.Shape = Enum.PartType.Ball
			pearl.CanCollide = false
		elseif zone.Id == "Deep" then
			-- クリスタル群とランドマークの巨大クリスタル
			for i = 1, 8 do
				local angle = i * 2.7
				makeCrystal(zoneFolder, zone.Center + Vector3.new(math.cos(angle) * 34, 1, math.sin(angle) * 34), 0.7, Color3.fromRGB(90, 220, 255))
			end
			makeCrystal(zoneFolder, zone.Center + Vector3.new(0, 1, -34), 2.2, Color3.fromRGB(120, 120, 255))
		end

		makeSign(zoneFolder, zone.Center + Vector3.new(0, 1, -40), string.format("%s\n泡の価値: %d", zone.Name, zone.BubbleValue), Color3.fromRGB(30, 120, 200))
	end

	-- スポーンと広場
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "MainSpawn"
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.Position = Vector3.new(0, 1.6, 20)
	spawn.Color = Color3.fromRGB(0, 200, 160)
	spawn.Material = Enum.Material.Neon
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Parent = world

	makeDisc(world, "Plaza", 52, 0.5, Vector3.new(0, 1.15, 10), Color3.fromRGB(235, 240, 245), Enum.Material.Marble)
	makeSign(world, Vector3.new(0, 1, 32), "Aqua Bubble Tycoon\n泡を集めてコインを稼ごう!", Color3.fromRGB(0, 160, 200))

	for _, lampPos in ipairs({ Vector3.new(-16, 1, -4), Vector3.new(16, 1, -4), Vector3.new(-16, 1, 24), Vector3.new(16, 1, 24), Vector3.new(150, 1, 20), Vector3.new(300, 1, 20) }) do
		makeLamp(world, lampPos)
	end

	-- ポータル（アーチ付き）
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
		-- アーチ
		makePart(world, "ArchPillar", Vector3.new(1, 8, 1), Vector3.new(x - 5, 5, 6), zone.Color, Enum.Material.Marble)
		makePart(world, "ArchPillar", Vector3.new(1, 8, 1), Vector3.new(x + 5, 5, 6), zone.Color, Enum.Material.Marble)
		makePart(world, "ArchTop", Vector3.new(11.5, 1.2, 1.2), Vector3.new(x, 9.4, 6), zone.Color, Enum.Material.Neon)
		makeSign(world, Vector3.new(x, 1, -2), zone.Name, Color3.fromRGB(120, 80, 255))
	end

	makeSign(world, Vector3.new(22, 1, 20), "SHOPは画面のボタンから\nアップグレードとリバースができるよ", Color3.fromRGB(255, 140, 0))

	-- 噴水とランドマーク泡（色はサーバーが状態に合わせて変える）
	local fountain = Instance.new("Folder")
	fountain.Name = "Fountain"
	fountain.Parent = world
	makeDisc(fountain, "Basin", 14, 1.6, Vector3.new(-24, 1.6, 22), Color3.fromRGB(200, 210, 220), Enum.Material.Marble)
	local landmark = makePart(fountain, "LandmarkBubble", Vector3.new(9, 9, 9), Vector3.new(-24, 15, 22), Color3.fromRGB(120, 215, 255), Enum.Material.Glass)
	landmark.Shape = Enum.PartType.Ball
	landmark.Transparency = 0.25
	landmark.CanCollide = false
	local landmarkLight = Instance.new("PointLight")
	landmarkLight.Color = Color3.fromRGB(120, 210, 255)
	landmarkLight.Range = 40
	landmarkLight.Brightness = 2
	landmarkLight.Parent = landmark

	-- フレーバーショップ
	local flavorPad = makePart(world, "FlavorShopPad", Vector3.new(9, 0.6, 9), Vector3.new(-24, 1.3, 6), Color3.fromRGB(255, 110, 180), Enum.Material.Neon)
	flavorPad.CanCollide = false
	local flavorPrompt = Instance.new("ProximityPrompt")
	flavorPrompt.Name = "FlavorPrompt"
	flavorPrompt.ActionText = "買う"
	flavorPrompt.ObjectText = "フレーバー"
	flavorPrompt.HoldDuration = 0.4
	flavorPrompt.MaxActivationDistance = 12
	flavorPrompt.Parent = flavorPad
	local flavorBoard = makePart(world, "FlavorBoard", Vector3.new(12, 4, 0.4), Vector3.new(-24, 8, -2), Color3.fromRGB(255, 110, 180), Enum.Material.SmoothPlastic)
	flavorBoard.CanCollide = false
	local flavorGui = Instance.new("SurfaceGui")
	flavorGui.Face = Enum.NormalId.Front
	flavorGui.Parent = flavorBoard
	local stockLabel = Instance.new("TextLabel")
	stockLabel.Name = "StockLabel"
	stockLabel.Size = UDim2.fromScale(1, 1)
	stockLabel.BackgroundTransparency = 1
	stockLabel.Text = "フレーバーショップ"
	stockLabel.TextScaled = true
	stockLabel.Font = Enum.Font.GothamBold
	stockLabel.TextColor3 = Color3.new(1, 1, 1)
	stockLabel.Parent = flavorGui
	local flavorGuiBack = flavorGui:Clone()
	flavorGuiBack.Face = Enum.NormalId.Back
	flavorGuiBack.Parent = flavorBoard

	-- ランキングボード2枚（このサーバー / 週間グローバル）
	makeBoard(world, "ServerBoard", Vector3.new(30, 7, -8), -35, "🏆 このサーバーの英雄", Color3.fromRGB(40, 60, 120))
	makeBoard(world, "GlobalBoard", Vector3.new(38, 7, 6), -55, "🌍 週間グローバル TOP", Color3.fromRGB(90, 40, 130))

	-- 表彰台（上位3人の像が立つ）
	local podiumColors = { Color3.fromRGB(255, 200, 40), Color3.fromRGB(200, 200, 210), Color3.fromRGB(200, 130, 70) }
	local podiumHeights = { 3.2, 2.2, 1.6 }
	for i = 1, 3 do
		makeDisc(world, "Podium" .. i, 5, podiumHeights[i], Vector3.new(14 + (i - 1) * 6.5, 1 + podiumHeights[i] / 2, 26), podiumColors[i], Enum.Material.Marble)
	end
	makeSign(world, Vector3.new(20, 1, 33), "表彰台\nこのサーバーのTOP3が立つ!", Color3.fromRGB(255, 170, 0))

	-- レガシー神殿（転生アビリティの祠）
	local shrine = Instance.new("Folder")
	shrine.Name = "LegacyShrine"
	shrine.Parent = world
	makeCrystal(shrine, Vector3.new(-34, 1, -16), 1.4, Color3.fromRGB(190, 90, 255))
	makeCrystal(shrine, Vector3.new(-29, 1, -21), 0.9, Color3.fromRGB(255, 90, 220))
	makeSign(shrine, Vector3.new(-31, 1, -10), "レガシー神殿\n転生でポイントを貯めて\n永続アビリティを解放!", Color3.fromRGB(140, 60, 220))

	-- 空島とバブルリフト（縦のランドマーク）
	local liftPad = makePart(world, "BubbleLift", Vector3.new(7, 0.6, 7), Vector3.new(34, 1.3, -20), Color3.fromRGB(0, 220, 255), Enum.Material.Neon)
	liftPad.CanCollide = false
	makeSign(world, Vector3.new(34, 1, -27), "バブルリフト\n乗ると空島へ!", Color3.fromRGB(0, 160, 220))
	local sky = Instance.new("Folder")
	sky.Name = "SkyDeck"
	sky.Parent = world
	makeDisc(sky, "SkyIsland", 30, 2, Vector3.new(34, 44, -20), Color3.fromRGB(240, 248, 255), Enum.Material.SmoothPlastic)
	makeCrystal(sky, Vector3.new(24, 45, -28), 1, Color3.fromRGB(255, 220, 120))
	makeSign(sky, Vector3.new(34, 45, -32), "空島スカイデッキ\n景色が自慢の休憩所", Color3.fromRGB(0, 160, 220))
	local returnPad = makePart(sky, "ReturnPad", Vector3.new(7, 0.6, 7), Vector3.new(34, 45.3, -12), Color3.fromRGB(255, 170, 60), Enum.Material.Neon)
	returnPad.CanCollide = false
	local returnPrompt = Instance.new("ProximityPrompt")
	returnPrompt.Name = "ReturnPrompt"
	returnPrompt.ActionText = "地上へ戻る"
	returnPrompt.ObjectText = "リターン"
	returnPrompt.HoldDuration = 0.3
	returnPrompt.MaxActivationDistance = 10
	returnPrompt.Parent = returnPad

	return world, prompts, flavorPrompt, stockLabel
end

return WorldBuilder
