-- StudioLiteServer.server.lua
-- Place this Script in ServerScriptService.
-- It owns all persistent build changes so the client never needs external API keys.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local REMOTE_FOLDER_NAME = "StudioLiteRemotes"
local BUILD_FOLDER_NAME = "StudioLiteBuilds"
local DATASTORE_NAME = "StudioLiteBuilds_v1"

local MAX_PARTS_PER_PLAYER = 300
local MAX_POSITION = 2048
local MIN_SIZE = 0.25
local MAX_SIZE = 128
local SAVE_COOLDOWN_SECONDS = 10
local LOAD_COOLDOWN_SECONDS = 5
local MAX_SAVE_BYTES = 2500000

local DEFAULT_SIZE_BY_KIND = {
	Brick = Vector3.new(4, 1, 2),
	Sphere = Vector3.new(4, 4, 4),
	Wedge = Vector3.new(4, 2, 4),
	Cylinder = Vector3.new(4, 4, 4),
}

local ALLOWED_KIND = {
	Brick = true,
	Sphere = true,
	Wedge = true,
	Cylinder = true,
}

local ALLOWED_MATERIAL_NAMES = {
	Plastic = true,
	SmoothPlastic = true,
	Wood = true,
	Concrete = true,
	Metal = true,
	Glass = true,
	Neon = true,
	Brick = true,
	Slate = true,
	Granite = true,
}

local MATERIAL_BY_NAME = {}
for _, material in ipairs(Enum.Material:GetEnumItems()) do
	MATERIAL_BY_NAME[material.Name] = material
end

local remotesFolder = ReplicatedStorage:FindFirstChild(REMOTE_FOLDER_NAME)
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = REMOTE_FOLDER_NAME
	remotesFolder.Parent = ReplicatedStorage
end

local function getRemoteEvent(name)
	local remote = remotesFolder:FindFirstChild(name)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = remotesFolder
	end
	return remote
end

local CreatePartRemote = getRemoteEvent("CreatePart")
local UpdatePartRemote = getRemoteEvent("UpdatePart")
local DeletePartRemote = getRemoteEvent("DeletePart")
local ClearBuildRemote = getRemoteEvent("ClearBuild")
local SaveBuildRemote = getRemoteEvent("SaveBuild")
local LoadBuildRemote = getRemoteEvent("LoadBuild")
local NotifyRemote = getRemoteEvent("Notify")

local buildRoot = Workspace:FindFirstChild(BUILD_FOLDER_NAME)
if not buildRoot then
	buildRoot = Instance.new("Folder")
	buildRoot.Name = BUILD_FOLDER_NAME
	buildRoot.Parent = Workspace
end

local buildStore = DataStoreService:GetDataStore(DATASTORE_NAME)
local cooldowns = {}

local function notify(player, message, success)
	NotifyRemote:FireClient(player, {
		Message = message,
		Success = success == true,
	})
end

local function isFiniteNumber(value)
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function clampNumber(value, minValue, maxValue, fallback)
	if not isFiniteNumber(value) then
		return fallback
	end
	return math.clamp(value, minValue, maxValue)
end

local function clampVector3(value, minValue, maxValue, fallback)
	if typeof(value) ~= "Vector3" then
		return fallback
	end
	return Vector3.new(
		clampNumber(value.X, minValue, maxValue, fallback.X),
		clampNumber(value.Y, minValue, maxValue, fallback.Y),
		clampNumber(value.Z, minValue, maxValue, fallback.Z)
	)
end

local function sanitizeSize(value, fallback)
	return clampVector3(value, MIN_SIZE, MAX_SIZE, fallback)
end

local function sanitizePosition(value, fallback)
	return clampVector3(value, -MAX_POSITION, MAX_POSITION, fallback)
end

local function sanitizeColor(value, fallback)
	if typeof(value) ~= "Color3" then
		return fallback
	end
	return Color3.new(
		clampNumber(value.R, 0, 1, fallback.R),
		clampNumber(value.G, 0, 1, fallback.G),
		clampNumber(value.B, 0, 1, fallback.B)
	)
end

local function sanitizeMaterial(value, fallback)
	if typeof(value) == "EnumItem" and value.EnumType == Enum.Material then
		if ALLOWED_MATERIAL_NAMES[value.Name] then
			return value
		end
	elseif typeof(value) == "string" then
		local enumValue = MATERIAL_BY_NAME[value]
		if enumValue and ALLOWED_MATERIAL_NAMES[enumValue.Name] then
			return enumValue
		end
	end
	return fallback
end

local function sanitizeKind(kind)
	if typeof(kind) == "string" and ALLOWED_KIND[kind] then
		return kind
	end
	return "Brick"
end

local function sanitizeCFrame(value, fallback)
	if typeof(value) ~= "CFrame" then
		return fallback
	end

	local position = sanitizePosition(value.Position, fallback.Position)
	local rx, ry, rz = value:ToOrientation()
	if not isFiniteNumber(rx) or not isFiniteNumber(ry) or not isFiniteNumber(rz) then
		return CFrame.new(position)
	end
	return CFrame.new(position) * CFrame.fromOrientation(rx, ry, rz)
end

local function getPlayerFolder(player)
	local folderName = tostring(player.UserId)
	local folder = buildRoot:FindFirstChild(folderName)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = folderName
		folder:SetAttribute("StudioLiteOwnerUserId", player.UserId)
		folder.Parent = buildRoot
	end
	return folder
end

local function countPlayerParts(player)
	local count = 0
	for _, child in ipairs(getPlayerFolder(player):GetChildren()) do
		if child:IsA("BasePart") then
			count += 1
		end
	end
	return count
end

local function isOwnedStudioLitePart(player, instance)
	return instance ~= nil
		and instance:IsA("BasePart")
		and instance:IsDescendantOf(getPlayerFolder(player))
		and instance:GetAttribute("StudioLiteOwnerUserId") == player.UserId
		and typeof(instance:GetAttribute("StudioLiteId")) == "string"
end

local function makePart(kind)
	local part
	if kind == "Wedge" then
		part = Instance.new("WedgePart")
	else
		part = Instance.new("Part")
		if kind == "Sphere" then
			part.Shape = Enum.PartType.Ball
		elseif kind == "Cylinder" then
			part.Shape = Enum.PartType.Cylinder
		else
			part.Shape = Enum.PartType.Block
		end
	end
	return part
end

local function initializePart(player, kind, payload)
	local part = makePart(kind)
	local id = HttpService:GenerateGUID(false)
	local requestedSize = payload and payload.Size or nil
	local requestedPosition = payload and payload.Position or nil
	local requestedColor = payload and payload.Color or nil
	local requestedMaterial = payload and payload.Material or nil

	part.Name = string.format("%s_%s", kind, string.sub(id, 1, 8))
	part.Anchored = true
	part.CanCollide = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = sanitizeSize(requestedSize, DEFAULT_SIZE_BY_KIND[kind])
	part.Color = sanitizeColor(requestedColor, Color3.fromRGB(196, 40, 28))
	part.Material = sanitizeMaterial(requestedMaterial, Enum.Material.Plastic)

	local position = sanitizePosition(requestedPosition, Vector3.new(0, part.Size.Y / 2, 0))
	if position.Y < part.Size.Y / 2 then
		position = Vector3.new(position.X, part.Size.Y / 2, position.Z)
	end
	part.CFrame = CFrame.new(position)

	part:SetAttribute("StudioLiteId", id)
	part:SetAttribute("StudioLiteKind", kind)
	part:SetAttribute("StudioLiteOwnerUserId", player.UserId)
	part.Parent = getPlayerFolder(player)

	return part
end

local function cooldownReady(player, key, seconds)
	local now = os.clock()
	local playerCooldowns = cooldowns[player.UserId]
	if not playerCooldowns then
		playerCooldowns = {}
		cooldowns[player.UserId] = playerCooldowns
	end

	local last = playerCooldowns[key]
	if last and now - last < seconds then
		return false, math.ceil(seconds - (now - last))
	end

	playerCooldowns[key] = now
	return true, 0
end

local function cframeToArray(cframe)
	return { cframe:GetComponents() }
end

local function arrayToCFrame(array, fallback)
	if type(array) ~= "table" then
		return fallback
	end

	local values = {}
	for index = 1, 12 do
		local value = array[index]
		if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
			return fallback
		end
		values[index] = value
	end

	return CFrame.new(table.unpack(values))
end

local function vector3ToArray(vector)
	return { vector.X, vector.Y, vector.Z }
end

local function arrayToVector3(array, fallback)
	if type(array) ~= "table" then
		return fallback
	end

	local x = array[1]
	local y = array[2]
	local z = array[3]
	if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then
		return fallback
	end
	return Vector3.new(x, y, z)
end

local function colorToArray(color)
	return { color.R, color.G, color.B }
end

local function arrayToColor3(array, fallback)
	if type(array) ~= "table" then
		return fallback
	end

	local r = array[1]
	local g = array[2]
	local b = array[3]
	if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
		return fallback
	end
	return Color3.new(r, g, b)
end

local function serializePlayerBuild(player)
	local parts = {}
	for _, child in ipairs(getPlayerFolder(player):GetChildren()) do
		if child:IsA("BasePart") and isOwnedStudioLitePart(player, child) then
			table.insert(parts, {
				Kind = sanitizeKind(child:GetAttribute("StudioLiteKind")),
				Name = child.Name,
				Size = vector3ToArray(child.Size),
				CFrame = cframeToArray(child.CFrame),
				Color = colorToArray(child.Color),
				Material = child.Material.Name,
			})
		end
	end

	return {
		Version = 1,
		SavedAt = os.time(),
		Parts = parts,
	}
end

local function restorePlayerBuild(player, data)
	if type(data) ~= "table" or type(data.Parts) ~= "table" then
		return false, "No saved build found."
	end

	local folder = getPlayerFolder(player)
	folder:ClearAllChildren()

	local restored = 0
	for _, saved in ipairs(data.Parts) do
		if restored >= MAX_PARTS_PER_PLAYER then
			break
		end

		if type(saved) == "table" then
			local kind = sanitizeKind(saved.Kind)
			local part = makePart(kind)
			local id = HttpService:GenerateGUID(false)
			local defaultSize = DEFAULT_SIZE_BY_KIND[kind]

			if type(saved.Name) == "string" and #saved.Name > 0 and #saved.Name <= 50 then
				part.Name = saved.Name
			else
				part.Name = string.format("%s_%s", kind, string.sub(id, 1, 8))
			end
			part.Anchored = true
			part.CanCollide = true
			part.TopSurface = Enum.SurfaceType.Smooth
			part.BottomSurface = Enum.SurfaceType.Smooth
			part.Size = sanitizeSize(arrayToVector3(saved.Size, defaultSize), defaultSize)
			part.CFrame = sanitizeCFrame(arrayToCFrame(saved.CFrame, CFrame.new(0, part.Size.Y / 2, 0)), CFrame.new(0, part.Size.Y / 2, 0))
			part.Color = sanitizeColor(arrayToColor3(saved.Color, Color3.fromRGB(196, 40, 28)), Color3.fromRGB(196, 40, 28))
			part.Material = sanitizeMaterial(saved.Material, Enum.Material.Plastic)
			part:SetAttribute("StudioLiteId", id)
			part:SetAttribute("StudioLiteKind", kind)
			part:SetAttribute("StudioLiteOwnerUserId", player.UserId)
			part.Parent = folder

			restored += 1
		end
	end

	return true, string.format("Loaded %d part(s).", restored)
end

CreatePartRemote.OnServerEvent:Connect(function(player, payload)
	if type(payload) ~= "table" then
		return
	end

	if countPlayerParts(player) >= MAX_PARTS_PER_PLAYER then
		notify(player, string.format("Part limit reached (%d).", MAX_PARTS_PER_PLAYER), false)
		return
	end

	local kind = sanitizeKind(payload.Kind)
	local part = initializePart(player, kind, payload)
	notify(player, string.format("Created %s.", part.Name), true)
end)

UpdatePartRemote.OnServerEvent:Connect(function(player, part, properties)
	if not isOwnedStudioLitePart(player, part) or type(properties) ~= "table" then
		return
	end

	if properties.Size ~= nil then
		part.Size = sanitizeSize(properties.Size, part.Size)
	end

	if properties.CFrame ~= nil then
		part.CFrame = sanitizeCFrame(properties.CFrame, part.CFrame)
	elseif properties.Position ~= nil then
		local rx, ry, rz = part.CFrame:ToOrientation()
		part.CFrame = CFrame.new(sanitizePosition(properties.Position, part.Position)) * CFrame.fromOrientation(rx, ry, rz)
	end

	if properties.Color ~= nil then
		part.Color = sanitizeColor(properties.Color, part.Color)
	end

	if properties.Material ~= nil then
		part.Material = sanitizeMaterial(properties.Material, part.Material)
	end

	if typeof(properties.Name) == "string" then
		local cleanName = string.gsub(properties.Name, "[^%w_%-%s]", "")
		if #cleanName >= 1 and #cleanName <= 50 then
			part.Name = cleanName
		end
	end
end)

DeletePartRemote.OnServerEvent:Connect(function(player, part)
	if isOwnedStudioLitePart(player, part) then
		local name = part.Name
		part:Destroy()
		notify(player, string.format("Deleted %s.", name), true)
	end
end)

ClearBuildRemote.OnServerEvent:Connect(function(player)
	getPlayerFolder(player):ClearAllChildren()
	notify(player, "Cleared your Studio Lite build.", true)
end)

SaveBuildRemote.OnServerEvent:Connect(function(player)
	local ready, remaining = cooldownReady(player, "Save", SAVE_COOLDOWN_SECONDS)
	if not ready then
		notify(player, string.format("Please wait %d second(s) before saving again.", remaining), false)
		return
	end

	local data = serializePlayerBuild(player)
	local encoded = HttpService:JSONEncode(data)
	if #encoded > MAX_SAVE_BYTES then
		notify(player, "Build is too large to save. Delete some parts first.", false)
		return
	end

	local ok, err = pcall(function()
		buildStore:SetAsync("player_" .. player.UserId, data)
	end)

	if ok then
		notify(player, string.format("Saved %d part(s).", #data.Parts), true)
	else
		warn("Studio Lite save failed for", player, err)
		notify(player, "Save failed. In Studio, enable API Services for DataStores.", false)
	end
end)

LoadBuildRemote.OnServerEvent:Connect(function(player)
	local ready, remaining = cooldownReady(player, "Load", LOAD_COOLDOWN_SECONDS)
	if not ready then
		notify(player, string.format("Please wait %d second(s) before loading again.", remaining), false)
		return
	end

	local ok, dataOrErr = pcall(function()
		return buildStore:GetAsync("player_" .. player.UserId)
	end)

	if not ok then
		warn("Studio Lite load failed for", player, dataOrErr)
		notify(player, "Load failed. In Studio, enable API Services for DataStores.", false)
		return
	end

	local restored, message = restorePlayerBuild(player, dataOrErr)
	notify(player, message, restored)
end)

Players.PlayerAdded:Connect(function(player)
	getPlayerFolder(player)
end)

Players.PlayerRemoving:Connect(function(player)
	cooldowns[player.UserId] = nil
end)

for _, player in ipairs(Players:GetPlayers()) do
	getPlayerFolder(player)
end
