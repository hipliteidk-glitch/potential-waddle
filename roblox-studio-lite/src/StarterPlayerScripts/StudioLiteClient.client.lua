-- StudioLiteClient.client.lua
-- Place this LocalScript in StarterPlayerScripts.
-- It builds the GUI, local grid, selection UX, transform tools, and property editor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = Workspace.CurrentCamera or Workspace:WaitForChild("Camera")

local REMOTE_FOLDER_NAME = "StudioLiteRemotes"
local BUILD_FOLDER_NAME = "StudioLiteBuilds"
local GRID_SIZE = 4
local GRID_EXTENT = 160
local UPDATE_INTERVAL = 0.06

local DEFAULT_SIZE_BY_KIND = {
	Brick = Vector3.new(4, 1, 2),
	Sphere = Vector3.new(4, 4, 4),
	Wedge = Vector3.new(4, 2, 4),
	Cylinder = Vector3.new(4, 4, 4),
}

local MATERIALS = {
	"Plastic",
	"SmoothPlastic",
	"Wood",
	"Concrete",
	"Metal",
	"Glass",
	"Neon",
	"Brick",
	"Slate",
	"Granite",
}

local MATERIAL_BY_NAME = {}
for _, material in ipairs(Enum.Material:GetEnumItems()) do
	MATERIAL_BY_NAME[material.Name] = material
end

local remotesFolder = ReplicatedStorage:WaitForChild(REMOTE_FOLDER_NAME)
local CreatePartRemote = remotesFolder:WaitForChild("CreatePart")
local UpdatePartRemote = remotesFolder:WaitForChild("UpdatePart")
local DeletePartRemote = remotesFolder:WaitForChild("DeletePart")
local ClearBuildRemote = remotesFolder:WaitForChild("ClearBuild")
local SaveBuildRemote = remotesFolder:WaitForChild("SaveBuild")
local LoadBuildRemote = remotesFolder:WaitForChild("LoadBuild")
local NotifyRemote = remotesFolder:WaitForChild("Notify")

local existingGui = playerGui:FindFirstChild("StudioLiteGui")
if existingGui then
	existingGui:Destroy()
end

local existingGrid = Workspace:FindFirstChild("StudioLiteLocalGrid_" .. player.UserId)
if existingGrid then
	existingGrid:Destroy()
end

local currentTool = "Select"
local selectedPart = nil
local gridVisible = true
local dragging = false
local dragMode = nil
local dragStartScreen = Vector2.new(0, 0)
local dragStartWorld = nil
local dragStartCFrame = nil
local dragStartSize = nil
local pendingUpdatePart = nil
local pendingUpdateProperties = nil
local lastUpdateSentAt = 0
local propertyBoxes = {}
local explorerButtons = {}
local statusToken = 0
local explorerConnectionAdded = nil
local explorerConnectionRemoved = nil

local guiObjectsThatBlockWorldInput = {}
local toolButtons = {}

local function make(className, properties, parent)
	local object = Instance.new(className)
	for key, value in pairs(properties or {}) do
		object[key] = value
	end
	object.Parent = parent
	return object
end

local function addCorner(parent, radius)
	return make("UICorner", { CornerRadius = UDim.new(0, radius or 6) }, parent)
end

local function addStroke(parent, color, thickness, transparency)
	return make("UIStroke", {
		Color = color or Color3.fromRGB(70, 70, 80),
		Thickness = thickness or 1,
		Transparency = transparency or 0,
	}, parent)
end

local function addPadding(parent, left, right, top, bottom)
	return make("UIPadding", {
		PaddingLeft = UDim.new(0, left or 0),
		PaddingRight = UDim.new(0, right or 0),
		PaddingTop = UDim.new(0, top or 0),
		PaddingBottom = UDim.new(0, bottom or 0),
	}, parent)
end

local function formatNumber(value)
	return string.format("%.2f", value):gsub("%.00$", "")
end

local function snapNumber(value, increment)
	return math.round(value / increment) * increment
end

local function snapVectorXZ(vector)
	return Vector3.new(
		snapNumber(vector.X, GRID_SIZE),
		vector.Y,
		snapNumber(vector.Z, GRID_SIZE)
	)
end

local function colorToHex(color)
	local r = math.floor(color.R * 255 + 0.5)
	local g = math.floor(color.G * 255 + 0.5)
	local b = math.floor(color.B * 255 + 0.5)
	return string.format("#%02X%02X%02X", r, g, b)
end

local function hexToColor(text)
	local cleaned = string.gsub(text or "", "#", "")
	cleaned = string.gsub(cleaned, "%s", "")
	if #cleaned == 3 then
		cleaned = cleaned:sub(1, 1) .. cleaned:sub(1, 1)
			.. cleaned:sub(2, 2) .. cleaned:sub(2, 2)
			.. cleaned:sub(3, 3) .. cleaned:sub(3, 3)
	end
	if #cleaned ~= 6 or not cleaned:match("^[%da-fA-F]+$") then
		return nil
	end
	return Color3.fromRGB(
		tonumber(cleaned:sub(1, 2), 16),
		tonumber(cleaned:sub(3, 4), 16),
		tonumber(cleaned:sub(5, 6), 16)
	)
end

local function parseNumber(text, fallback)
	local number = tonumber(text)
	if not number or number ~= number then
		return fallback
	end
	return math.clamp(number, -2048, 2048)
end

local function isStudioLitePart(part)
	return part ~= nil
		and part:IsA("BasePart")
		and typeof(part:GetAttribute("StudioLiteId")) == "string"
		and part:GetAttribute("StudioLiteOwnerUserId") == player.UserId
end

local function getBuildFolder()
	local root = Workspace:FindFirstChild(BUILD_FOLDER_NAME)
	if not root then
		return nil
	end
	return root:FindFirstChild(tostring(player.UserId))
end

local function setStatus(message, success)
	statusToken += 1
	local thisToken = statusToken
	local statusLabel = propertyBoxes.StatusLabel
	if statusLabel then
		statusLabel.Text = message or ""
		statusLabel.TextColor3 = success and Color3.fromRGB(115, 255, 142) or Color3.fromRGB(255, 184, 94)
	end
	task.delay(4, function()
		if statusToken == thisToken and statusLabel then
			statusLabel.Text = "Ready"
			statusLabel.TextColor3 = Color3.fromRGB(190, 190, 200)
		end
	end)
end

local function pointInsideGui(guiObject, point)
	if not guiObject or not guiObject.Visible then
		return false
	end
	local position = guiObject.AbsolutePosition
	local size = guiObject.AbsoluteSize
	return point.X >= position.X
		and point.X <= position.X + size.X
		and point.Y >= position.Y
		and point.Y <= position.Y + size.Y
end

local function isMouseOverStudioLiteGui()
	local point = UserInputService:GetMouseLocation()
	for _, guiObject in ipairs(guiObjectsThatBlockWorldInput) do
		if pointInsideGui(guiObject, point) then
			return true
		end
	end
	return false
end

local function sendUpdate(part, properties, force)
	if not part or not part.Parent then
		return
	end

	if properties.CFrame then
		part.CFrame = properties.CFrame
	end
	if properties.Size then
		part.Size = properties.Size
	end
	if properties.Color then
		part.Color = properties.Color
	end
	if properties.Material then
		local material = MATERIAL_BY_NAME[properties.Material]
		if material then
			part.Material = material
		end
	end
	if properties.Name then
		part.Name = properties.Name
	end

	local now = os.clock()
	if force or now - lastUpdateSentAt >= UPDATE_INTERVAL then
		UpdatePartRemote:FireServer(part, properties)
		lastUpdateSentAt = now
		pendingUpdatePart = nil
		pendingUpdateProperties = nil
	else
		pendingUpdatePart = part
		pendingUpdateProperties = properties
	end
end

RunService.Heartbeat:Connect(function()
	if pendingUpdatePart and pendingUpdateProperties and os.clock() - lastUpdateSentAt >= UPDATE_INTERVAL then
		UpdatePartRemote:FireServer(pendingUpdatePart, pendingUpdateProperties)
		lastUpdateSentAt = os.clock()
		pendingUpdatePart = nil
		pendingUpdateProperties = nil
	end
end)

local screenGui = make("ScreenGui", {
	Name = "StudioLiteGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local toolbar = make("Frame", {
	Name = "Toolbar",
	BackgroundColor3 = Color3.fromRGB(30, 31, 38),
	BorderSizePixel = 0,
	Position = UDim2.new(0, 0, 0, 0),
	Size = UDim2.new(1, 0, 0, 54),
}, screenGui)
addPadding(toolbar, 8, 8, 7, 7)
table.insert(guiObjectsThatBlockWorldInput, toolbar)

local toolbarLayout = make("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Left,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 6),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, toolbar)

local function makeButton(parent, text, width, callback)
	local button = make("TextButton", {
		AutoButtonColor = true,
		BackgroundColor3 = Color3.fromRGB(48, 50, 62),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamSemibold,
		Text = text,
		TextColor3 = Color3.fromRGB(245, 245, 250),
		TextSize = 14,
		Size = UDim2.new(0, width or 88, 1, 0),
	}, parent)
	addCorner(button, 6)
	addStroke(button, Color3.fromRGB(78, 80, 94), 1, 0)
	if callback then
		button.MouseButton1Click:Connect(callback)
	end
	return button
end

local title = make("TextLabel", {
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "Studio Lite",
	TextColor3 = Color3.fromRGB(255, 255, 255),
	TextSize = 18,
	TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(0, 128, 1, 0),
	LayoutOrder = 0,
}, toolbar)

local function updateToolButtonStyles()
	for toolName, button in pairs(toolButtons) do
		if toolName == currentTool then
			button.BackgroundColor3 = Color3.fromRGB(61, 112, 255)
		else
			button.BackgroundColor3 = Color3.fromRGB(48, 50, 62)
		end
	end
end

local function setTool(toolName)
	currentTool = toolName
	updateToolButtonStyles()
	setStatus("Tool: " .. toolName, true)
end

for _, toolName in ipairs({ "Select", "Move", "Scale", "Rotate" }) do
	local button = makeButton(toolbar, toolName, 78, function()
		setTool(toolName)
	end)
	button.LayoutOrder = 10
	toolButtons[toolName] = button
end

local spacer = make("Frame", {
	BackgroundTransparency = 1,
	Size = UDim2.new(0, 10, 1, 0),
	LayoutOrder = 20,
}, toolbar)

makeButton(toolbar, "Save", 70, function()
	SaveBuildRemote:FireServer()
	setStatus("Saving...", true)
end).LayoutOrder = 30

makeButton(toolbar, "Load", 70, function()
	LoadBuildRemote:FireServer()
	setStatus("Loading...", true)
end).LayoutOrder = 31

makeButton(toolbar, "Clear", 70, function()
	ClearBuildRemote:FireServer()
	selectedPart = nil
	setStatus("Cleared local selection.", true)
end).LayoutOrder = 32

local gridButton
local function toggleGrid()
	gridVisible = not gridVisible
	local grid = Workspace:FindFirstChild("StudioLiteLocalGrid_" .. player.UserId)
	if grid then
		for _, child in ipairs(grid:GetChildren()) do
			if child:IsA("BasePart") then
				child.Transparency = gridVisible and child:GetAttribute("VisibleTransparency") or 1
			end
		end
	end
	if gridButton then
		gridButton.Text = gridVisible and "Grid: On" or "Grid: Off"
		setStatus(gridButton.Text, true)
	end
end
gridButton = makeButton(toolbar, "Grid: On", 88, toggleGrid)
gridButton.LayoutOrder = 33

local toolbox = make("Frame", {
	Name = "Toolbox",
	BackgroundColor3 = Color3.fromRGB(37, 39, 47),
	BorderSizePixel = 0,
	Position = UDim2.new(0, 0, 0, 54),
	Size = UDim2.new(0, 190, 1, -54),
}, screenGui)
addPadding(toolbox, 10, 10, 10, 10)
addStroke(toolbox, Color3.fromRGB(65, 67, 78), 1, 0)
table.insert(guiObjectsThatBlockWorldInput, toolbox)

make("TextLabel", {
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "Toolbox",
	TextColor3 = Color3.fromRGB(255, 255, 255),
	TextSize = 18,
	TextXAlignment = Enum.TextXAlignment.Left,
	Position = UDim2.new(0, 0, 0, 0),
	Size = UDim2.new(1, 0, 0, 28),
}, toolbox)

local toolboxList = make("Frame", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 0, 0, 38),
	Size = UDim2.new(1, 0, 0, 190),
}, toolbox)
local toolboxLayout = make("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	Padding = UDim.new(0, 8),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, toolboxList)

local function getSpawnPosition(defaultSize)
	camera = Workspace.CurrentCamera or camera
	local inFront = camera.CFrame.Position + camera.CFrame.LookVector * 18
	local snapped = snapVectorXZ(inFront)
	return Vector3.new(snapped.X, defaultSize.Y / 2, snapped.Z)
end

for _, kind in ipairs({ "Brick", "Sphere", "Wedge", "Cylinder" }) do
	makeButton(toolboxList, "+ " .. kind, 160, function()
		local defaultSize = DEFAULT_SIZE_BY_KIND[kind]
		CreatePartRemote:FireServer({
			Kind = kind,
			Size = defaultSize,
			Position = getSpawnPosition(defaultSize),
			Color = Color3.fromRGB(196, 40, 28),
			Material = "Plastic",
		})
		setStatus("Creating " .. kind .. "...", true)
	end).Size = UDim2.new(1, 0, 0, 38)
end

local helpText = make("TextLabel", {
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "Shortcuts:\n1 Select · 2 Move\n3 Scale · 4 Rotate\nQ/E rotate 15°\nDel deletes selected\nG toggles grid",
	TextColor3 = Color3.fromRGB(190, 192, 205),
	TextSize = 13,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Position = UDim2.new(0, 0, 0, 250),
	Size = UDim2.new(1, 0, 0, 150),
}, toolbox)

local propertiesPanel = make("Frame", {
	Name = "Properties",
	BackgroundColor3 = Color3.fromRGB(37, 39, 47),
	BorderSizePixel = 0,
	Position = UDim2.new(1, -320, 0, 54),
	Size = UDim2.new(0, 320, 0, 430),
}, screenGui)
addPadding(propertiesPanel, 10, 10, 10, 10)
addStroke(propertiesPanel, Color3.fromRGB(65, 67, 78), 1, 0)
table.insert(guiObjectsThatBlockWorldInput, propertiesPanel)

make("TextLabel", {
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "Properties",
	TextColor3 = Color3.fromRGB(255, 255, 255),
	TextSize = 18,
	TextXAlignment = Enum.TextXAlignment.Left,
	Position = UDim2.new(0, 0, 0, 0),
	Size = UDim2.new(1, 0, 0, 28),
}, propertiesPanel)

local selectedLabel = make("TextLabel", {
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "No object selected",
	TextColor3 = Color3.fromRGB(190, 192, 205),
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Position = UDim2.new(0, 0, 0, 30),
	Size = UDim2.new(1, 0, 0, 22),
}, propertiesPanel)
propertyBoxes.SelectedLabel = selectedLabel

local function makeField(label, y, defaultText)
	make("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamSemibold,
		Text = label,
		TextColor3 = Color3.fromRGB(220, 222, 230),
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.new(0, 0, 0, y),
		Size = UDim2.new(0, 72, 0, 26),
	}, propertiesPanel)
	local box = make("TextBox", {
		BackgroundColor3 = Color3.fromRGB(27, 28, 35),
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Font = Enum.Font.Gotham,
		Text = defaultText or "",
		TextColor3 = Color3.fromRGB(245, 245, 250),
		PlaceholderColor3 = Color3.fromRGB(130, 132, 145),
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.new(0, 78, 0, y),
		Size = UDim2.new(1, -78, 0, 26),
	}, propertiesPanel)
	addPadding(box, 8, 8, 0, 0)
	addCorner(box, 5)
	return box
end

local nameBox = makeField("Name", 60, "")
propertyBoxes.Name = nameBox

local function makeTriple(label, y)
	make("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamSemibold,
		Text = label,
		TextColor3 = Color3.fromRGB(220, 222, 230),
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.new(0, 0, 0, y),
		Size = UDim2.new(0, 72, 0, 26),
	}, propertiesPanel)

	local boxes = {}
	for index, axis in ipairs({ "X", "Y", "Z" }) do
		local box = make("TextBox", {
			BackgroundColor3 = Color3.fromRGB(27, 28, 35),
			BorderSizePixel = 0,
			ClearTextOnFocus = false,
			Font = Enum.Font.Gotham,
			Text = "0",
			TextColor3 = Color3.fromRGB(245, 245, 250),
			PlaceholderText = axis,
			PlaceholderColor3 = Color3.fromRGB(130, 132, 145),
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.new(0, 78 + (index - 1) * 78, 0, y),
			Size = UDim2.new(0, 70, 0, 26),
		}, propertiesPanel)
		addPadding(box, 6, 6, 0, 0)
		addCorner(box, 5)
		boxes[axis] = box
	end
	return boxes
end

local positionBoxes = makeTriple("Position", 96)
local sizeBoxes = makeTriple("Size", 132)
propertyBoxes.Position = positionBoxes
propertyBoxes.Size = sizeBoxes

local colorBox = makeField("Color", 168, "#C4281C")
propertyBoxes.Color = colorBox

make("TextLabel", {
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamSemibold,
	Text = "Material",
	TextColor3 = Color3.fromRGB(220, 222, 230),
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Left,
	Position = UDim2.new(0, 0, 0, 204),
	Size = UDim2.new(0, 72, 0, 26),
}, propertiesPanel)

local materialButton
materialButton = makeButton(propertiesPanel, "Plastic", 0, function()
	local currentIndex = table.find(MATERIALS, materialButton.Text) or 1
	local nextIndex = currentIndex + 1
	if nextIndex > #MATERIALS then
		nextIndex = 1
	end
	materialButton.Text = MATERIALS[nextIndex]
end)
materialButton.Position = UDim2.new(0, 78, 0, 204)
materialButton.Size = UDim2.new(1, -78, 0, 26)
materialButton.TextXAlignment = Enum.TextXAlignment.Left
addPadding(materialButton, 8, 8, 0, 0)
propertyBoxes.Material = materialButton

local applyButton = makeButton(propertiesPanel, "Apply Properties", 0, nil)
applyButton.Position = UDim2.new(0, 0, 0, 248)
applyButton.Size = UDim2.new(1, 0, 0, 34)

local deleteButton = makeButton(propertiesPanel, "Delete Selected", 0, nil)
deleteButton.BackgroundColor3 = Color3.fromRGB(132, 48, 48)
deleteButton.Position = UDim2.new(0, 0, 0, 290)
deleteButton.Size = UDim2.new(1, 0, 0, 34)

local statusLabel = make("TextLabel", {
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "Ready",
	TextColor3 = Color3.fromRGB(190, 190, 200),
	TextSize = 13,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Position = UDim2.new(0, 0, 0, 340),
	Size = UDim2.new(1, 0, 0, 70),
}, propertiesPanel)
propertyBoxes.StatusLabel = statusLabel

local explorerPanel = make("Frame", {
	Name = "Explorer",
	BackgroundColor3 = Color3.fromRGB(37, 39, 47),
	BorderSizePixel = 0,
	Position = UDim2.new(1, -320, 0, 494),
	Size = UDim2.new(0, 320, 1, -494),
}, screenGui)
addPadding(explorerPanel, 10, 10, 10, 10)
addStroke(explorerPanel, Color3.fromRGB(65, 67, 78), 1, 0)
table.insert(guiObjectsThatBlockWorldInput, explorerPanel)

make("TextLabel", {
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "Explorer",
	TextColor3 = Color3.fromRGB(255, 255, 255),
	TextSize = 18,
	TextXAlignment = Enum.TextXAlignment.Left,
	Position = UDim2.new(0, 0, 0, 0),
	Size = UDim2.new(1, 0, 0, 28),
}, explorerPanel)

local explorerScroll = make("ScrollingFrame", {
	BackgroundColor3 = Color3.fromRGB(27, 28, 35),
	BorderSizePixel = 0,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	ScrollBarThickness = 6,
	Position = UDim2.new(0, 0, 0, 38),
	Size = UDim2.new(1, 0, 1, -38),
}, explorerPanel)
addCorner(explorerScroll, 5)
local explorerLayout = make("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	Padding = UDim.new(0, 4),
	SortOrder = Enum.SortOrder.Name,
}, explorerScroll)
addPadding(explorerScroll, 6, 6, 6, 6)

local selectionBox = make("SelectionBox", {
	Name = "StudioLiteSelectionBox",
	Color3 = Color3.fromRGB(61, 112, 255),
	LineThickness = 0.045,
	SurfaceTransparency = 0.86,
	Visible = false,
}, screenGui)

local function refreshProperties()
	if not selectedPart or not selectedPart.Parent then
		selectedPart = nil
		selectionBox.Adornee = nil
		selectionBox.Visible = false
		selectedLabel.Text = "No object selected"
		nameBox.Text = ""
		for _, boxes in ipairs({ positionBoxes, sizeBoxes }) do
			boxes.X.Text = ""
			boxes.Y.Text = ""
			boxes.Z.Text = ""
		end
		colorBox.Text = ""
		materialButton.Text = "Plastic"
		return
	end

	selectionBox.Adornee = selectedPart
	selectionBox.Visible = true
	selectedLabel.Text = tostring(selectedPart:GetAttribute("StudioLiteKind") or "Part") .. "  ·  " .. selectedPart.Name
	nameBox.Text = selectedPart.Name
	positionBoxes.X.Text = formatNumber(selectedPart.Position.X)
	positionBoxes.Y.Text = formatNumber(selectedPart.Position.Y)
	positionBoxes.Z.Text = formatNumber(selectedPart.Position.Z)
	sizeBoxes.X.Text = formatNumber(selectedPart.Size.X)
	sizeBoxes.Y.Text = formatNumber(selectedPart.Size.Y)
	sizeBoxes.Z.Text = formatNumber(selectedPart.Size.Z)
	colorBox.Text = colorToHex(selectedPart.Color)
	materialButton.Text = selectedPart.Material.Name
end

local function selectPart(part)
	if isStudioLitePart(part) then
		selectedPart = part
		refreshProperties()
		setStatus("Selected " .. part.Name, true)
	else
		selectedPart = nil
		refreshProperties()
	end
end

local function refreshExplorer()
	for _, button in ipairs(explorerButtons) do
		button:Destroy()
	end
	explorerButtons = {}

	local folder = getBuildFolder()
	if not folder then
		explorerScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
		return
	end

	local parts = {}
	for _, child in ipairs(folder:GetChildren()) do
		if isStudioLitePart(child) then
			table.insert(parts, child)
		end
	end
	table.sort(parts, function(a, b)
		return a.Name < b.Name
	end)

	for _, part in ipairs(parts) do
		local button = make("TextButton", {
			Name = part.Name,
			AutoButtonColor = true,
			BackgroundColor3 = part == selectedPart and Color3.fromRGB(61, 112, 255) or Color3.fromRGB(42, 44, 54),
			BorderSizePixel = 0,
			Font = Enum.Font.Gotham,
			Text = string.format("%s  [%s]", part.Name, part:GetAttribute("StudioLiteKind") or "Part"),
			TextColor3 = Color3.fromRGB(245, 245, 250),
			TextSize = 13,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -4, 0, 30),
		}, explorerScroll)
		addPadding(button, 8, 8, 0, 0)
		addCorner(button, 4)
		button.MouseButton1Click:Connect(function()
			selectPart(part)
			refreshExplorer()
		end)
		table.insert(explorerButtons, button)
	end

	explorerScroll.CanvasSize = UDim2.new(0, 0, 0, #parts * 34 + 12)
end

local function hookExplorerFolder()
	if explorerConnectionAdded then
		explorerConnectionAdded:Disconnect()
		explorerConnectionAdded = nil
	end
	if explorerConnectionRemoved then
		explorerConnectionRemoved:Disconnect()
		explorerConnectionRemoved = nil
	end

	local folder = getBuildFolder()
	if folder then
		explorerConnectionAdded = folder.ChildAdded:Connect(function()
			task.defer(refreshExplorer)
		end)
		explorerConnectionRemoved = folder.ChildRemoved:Connect(function()
			task.defer(refreshExplorer)
		end)
	end
	refreshExplorer()
end

local buildRoot = Workspace:WaitForChild(BUILD_FOLDER_NAME, 10)
if buildRoot then
	buildRoot.ChildAdded:Connect(function(child)
		if child.Name == tostring(player.UserId) then
			hookExplorerFolder()
		end
	end)
end
hookExplorerFolder()

applyButton.MouseButton1Click:Connect(function()
	if not selectedPart then
		setStatus("Select an object first.", false)
		return
	end

	local position = Vector3.new(
		parseNumber(positionBoxes.X.Text, selectedPart.Position.X),
		parseNumber(positionBoxes.Y.Text, selectedPart.Position.Y),
		parseNumber(positionBoxes.Z.Text, selectedPart.Position.Z)
	)
	local size = Vector3.new(
		math.clamp(parseNumber(sizeBoxes.X.Text, selectedPart.Size.X), 0.25, 128),
		math.clamp(parseNumber(sizeBoxes.Y.Text, selectedPart.Size.Y), 0.25, 128),
		math.clamp(parseNumber(sizeBoxes.Z.Text, selectedPart.Size.Z), 0.25, 128)
	)
	local color = hexToColor(colorBox.Text) or selectedPart.Color
	local rx, ry, rz = selectedPart.CFrame:ToOrientation()
	local cframe = CFrame.new(position) * CFrame.fromOrientation(rx, ry, rz)

	sendUpdate(selectedPart, {
		Name = nameBox.Text,
		Size = size,
		CFrame = cframe,
		Color = color,
		Material = materialButton.Text,
	}, true)
	refreshProperties()
	refreshExplorer()
	setStatus("Properties applied.", true)
end)

deleteButton.MouseButton1Click:Connect(function()
	if selectedPart then
		DeletePartRemote:FireServer(selectedPart)
		selectedPart = nil
		refreshProperties()
		refreshExplorer()
	else
		setStatus("Nothing selected.", false)
	end
end)

local function createGrid()
	local folder = Instance.new("Folder")
	folder.Name = "StudioLiteLocalGrid_" .. player.UserId
	folder.Parent = Workspace

	for coordinate = -GRID_EXTENT, GRID_EXTENT, GRID_SIZE do
		local isAxis = coordinate == 0
		local transparency = isAxis and 0.35 or 0.78
		local color = isAxis and Color3.fromRGB(90, 145, 255) or Color3.fromRGB(130, 135, 145)

		local xLine = Instance.new("Part")
		xLine.Name = "GridLineX"
		xLine.Anchored = true
		xLine.CanCollide = false
		xLine.CanTouch = false
		xLine.CanQuery = false
		xLine.Locked = true
		xLine.Material = Enum.Material.Neon
		xLine.Color = color
		xLine.Transparency = transparency
		xLine.Size = Vector3.new(GRID_EXTENT * 2, 0.025, 0.025)
		xLine.Position = Vector3.new(0, 0.02, coordinate)
		xLine:SetAttribute("VisibleTransparency", transparency)
		xLine.Parent = folder

		local zLine = Instance.new("Part")
		zLine.Name = "GridLineZ"
		zLine.Anchored = true
		zLine.CanCollide = false
		zLine.CanTouch = false
		zLine.CanQuery = false
		zLine.Locked = true
		zLine.Material = Enum.Material.Neon
		zLine.Color = color
		zLine.Transparency = transparency
		zLine.Size = Vector3.new(0.025, 0.025, GRID_EXTENT * 2)
		zLine.Position = Vector3.new(coordinate, 0.021, 0)
		zLine:SetAttribute("VisibleTransparency", transparency)
		zLine.Parent = folder
	end
end
createGrid()

local function mouseToPlaneY(y)
	camera = Workspace.CurrentCamera or camera
	local location = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(location.X, location.Y)
	if math.abs(ray.Direction.Y) < 0.001 then
		return nil
	end
	local distance = (y - ray.Origin.Y) / ray.Direction.Y
	if distance < 0 then
		return nil
	end
	return ray.Origin + ray.Direction * distance
end

local function beginDrag(mode)
	if not selectedPart then
		return
	end
	dragging = true
	dragMode = mode
	dragStartScreen = Vector2.new(UserInputService:GetMouseLocation().X, UserInputService:GetMouseLocation().Y)
	dragStartWorld = mouseToPlaneY(selectedPart.Position.Y) or selectedPart.Position
	dragStartCFrame = selectedPart.CFrame
	dragStartSize = selectedPart.Size
end

local function endDrag()
	if dragging and selectedPart and pendingUpdateProperties then
		sendUpdate(selectedPart, pendingUpdateProperties, true)
	end
	dragging = false
	dragMode = nil
	dragStartWorld = nil
	dragStartCFrame = nil
	dragStartSize = nil
	refreshProperties()
	refreshExplorer()
end

local function applyDrag()
	if not dragging or not selectedPart or not dragStartCFrame or not dragStartSize then
		return
	end

	local mouseLocation = UserInputService:GetMouseLocation()
	if dragMode == "Move" then
		local currentWorld = mouseToPlaneY(dragStartCFrame.Position.Y)
		if not currentWorld or not dragStartWorld then
			return
		end
		local delta = currentWorld - dragStartWorld
		local targetPosition = dragStartCFrame.Position + Vector3.new(delta.X, 0, delta.Z)
		targetPosition = snapVectorXZ(targetPosition)
		local rx, ry, rz = dragStartCFrame:ToOrientation()
		sendUpdate(selectedPart, {
			CFrame = CFrame.new(targetPosition) * CFrame.fromOrientation(rx, ry, rz),
		}, false)
	elseif dragMode == "Scale" then
		local deltaPixels = (mouseLocation.X - dragStartScreen.X) - (mouseLocation.Y - dragStartScreen.Y)
		local deltaStuds = snapNumber(deltaPixels / 40, 0.25)
		local newSize = Vector3.new(
			math.clamp(dragStartSize.X + deltaStuds, 0.25, 128),
			math.clamp(dragStartSize.Y + deltaStuds, 0.25, 128),
			math.clamp(dragStartSize.Z + deltaStuds, 0.25, 128)
		)
		sendUpdate(selectedPart, { Size = newSize }, false)
	elseif dragMode == "Rotate" then
		local degrees = snapNumber((mouseLocation.X - dragStartScreen.X) * 0.5, 15)
		sendUpdate(selectedPart, {
			CFrame = dragStartCFrame * CFrame.Angles(0, math.rad(degrees), 0),
		}, false)
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if isMouseOverStudioLiteGui() then
			return
		end

		local mouse = player:GetMouse()
		local target = mouse.Target
		if isStudioLitePart(target) then
			selectPart(target)
			refreshExplorer()
			if currentTool == "Move" or currentTool == "Scale" or currentTool == "Rotate" then
				beginDrag(currentTool)
			end
		elseif currentTool == "Select" then
			selectPart(nil)
			refreshExplorer()
		end
		return
	end

	if input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end

	if input.KeyCode == Enum.KeyCode.One then
		setTool("Select")
	elseif input.KeyCode == Enum.KeyCode.Two then
		setTool("Move")
	elseif input.KeyCode == Enum.KeyCode.Three then
		setTool("Scale")
	elseif input.KeyCode == Enum.KeyCode.Four then
		setTool("Rotate")
	elseif input.KeyCode == Enum.KeyCode.G then
		toggleGrid()
	elseif input.KeyCode == Enum.KeyCode.Delete or input.KeyCode == Enum.KeyCode.Backspace then
		if selectedPart then
			DeletePartRemote:FireServer(selectedPart)
			selectedPart = nil
			refreshProperties()
			refreshExplorer()
		end
	elseif input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.E then
		if selectedPart then
			local direction = input.KeyCode == Enum.KeyCode.E and 1 or -1
			sendUpdate(selectedPart, {
				CFrame = selectedPart.CFrame * CFrame.Angles(0, math.rad(15 * direction), 0),
			}, true)
			refreshProperties()
		end
	elseif input.KeyCode == Enum.KeyCode.S and UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
		SaveBuildRemote:FireServer()
	elseif input.KeyCode == Enum.KeyCode.L and UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
		LoadBuildRemote:FireServer()
	end
end)

UserInputService.InputChanged:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		applyDrag()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		endDrag()
	end
end)

NotifyRemote.OnClientEvent:Connect(function(payload)
	if type(payload) == "table" then
		setStatus(payload.Message or "", payload.Success)
	else
		setStatus(tostring(payload), true)
	end
end)

RunService.RenderStepped:Connect(function()
	if selectedPart and not selectedPart.Parent then
		selectedPart = nil
		refreshProperties()
		refreshExplorer()
	end
end)

updateToolButtonStyles()
refreshProperties()
refreshExplorer()
setStatus("Studio Lite loaded. Use the Toolbox to spawn parts.", true)
