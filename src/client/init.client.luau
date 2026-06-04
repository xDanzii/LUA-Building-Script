local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ShapeCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BuildShapeCatalog"))

local localPlayer = Players.LocalPlayer
local camera = workspace.CurrentCamera
local scriptObject = script
local cachedControls = nil
local MODEL_TEMPLATES_FOLDER_NAME = "BuildingModels"

local TOGGLE_KEY = Enum.KeyCode.B

local DEFAULTS = {
	rotateDragSensitivity = 0.65,
	minZoom = 30,
	maxZoom = 180,
	zoomStep = 8,
	curveStart = 55,
	curveEnd = 105,
	topDownPitch = -89,
	normalPitch = -45,
	cameraResponse = 12,
	yawResponse = 14,
	panBaseSpeed = 50,
	panZoomMultiplier = 0.35,
	gridSize = 4,
	gridRadius = 24,
	gridThickness = 0.1,
	gridHeightOffset = 0.04,
	gridColor = Color3.fromRGB(70, 70, 70),
}

local INVERTED_CLOSE_PITCH = 0
local INVERTED_CURVE_POWER = 1.8
local DEBUG_ENABLED = true
local RENDER_DEBUG_INTERVAL = 1.5

local getActiveCamera
local getHumanoid
local logTransformStateSnapshot
local setMoveGizmoVisible
local startMoveHandleExpectation
local updateSelectedTransformUi
local scaleSelectedPart
local getAxisHalfExtentForTransform

local isScriptEnabled = false
local isBuildMode = false
local currentZoom = 80
local targetZoom = 80

local currentYaw = 0
local targetYaw = 0

local focusPoint = Vector3.zero
local previousCameraType = Enum.CameraType.Custom
local previousCameraSubject = nil
local previousCameraMode = Enum.CameraMode.Classic
local previousWalkSpeed = nil
local previousJumpPower = nil
local previousJumpHeight = nil
local previousAutoRotate = nil
local previousMouseBehavior = Enum.MouseBehavior.Default
local inputState = {
	isRightMouseRotating = false,
	lastMousePosition = nil,
}
local UI = {
	settingsButton = nil,
	settingsPanel = nil,
	invertedToggleButton = nil,
	showGridToggleButton = nil,
	snapButton = nil,
	modelsButton = nil,
	modelsPanel = nil,
	modelButtons = {},
	placementIndicator = nil,
	placementPreview = nil,
	selectionHighlight = nil,
	transformMoveGizmoFolder = nil,
	transformRotateHandles = nil,
	transformScaleHandles = nil,
	transformToolGui = nil,
	transformToolPanel = nil,
	moveToolButton = nil,
	rotateToolButton = nil,
	scaleToolButton = nil,
}
local isInvertedCamera = false
local gridFolder = nil
local placedObjectsFolder = nil
local selectedModelName = "Cube"
local isPlacementMode = false
local selectedTransformObject = nil
local copiedTransformObject = nil
local activeTransformTool = "move"
local transformDragState = {
	pivotStart = nil,
	axisVector = nil,
	mode = nil,
	startValue = 0,
	lastValue = 0,
	startMousePosition = nil,
	rotationStartVector = nil,
	rotationStartScreenVector = nil,
	rotationReferenceVector = nil,
	rotationRingSlot = nil,
	isHandleDragging = false,
	lastLogAt = 0,
	activeAxisName = nil,
	activeGizmoName = nil,
	expectationToken = 0,
}
local lastTransformSnapshotKey = nil
local isSnapEnabled = true
local isGridVisible = true
local lastGridCenterKey = nil
local lastRenderDebugAt = 0

local TRANSFORM_ROTATE_STEP = 15
local TRANSFORM_ROTATE_SNAP_STEP = 90
local TRANSFORM_ROTATE_GIZMO_SNAP_THRESHOLD = 12
local TRANSFORM_ROTATE_GIZMO_MAX_DEGREES = 90
local TRANSFORM_MIN_SIZE = 1
local TRANSFORM_DRAG_LOG_INTERVAL = 0.2
local MOVE_GIZMO_AXIS_LENGTH = 5
local MOVE_GIZMO_AXIS_THICKNESS = 0.34
local MOVE_GIZMO_HITBOX_THICKNESS = 1.15
local MOVE_GIZMO_AXIS_GAP = 1.4
local ROTATE_GIZMO_RADIUS = 12.4
local ROTATE_GIZMO_HANDLE_LENGTH = 6.4
local ROTATE_GIZMO_AXIS_THICKNESS = 0.56
local ROTATE_GIZMO_HITBOX_THICKNESS = 2.36
local SCALE_GIZMO_AXIS_LENGTH = 9.6
local SCALE_GIZMO_AXIS_THICKNESS = 0.72
local SCALE_GIZMO_HITBOX_THICKNESS = 2.24
local SCALE_GIZMO_AXIS_GAP = 3.4

local GRID_SIZE = DEFAULTS.gridSize
local GRID_RADIUS = DEFAULTS.gridRadius
local GRID_THICKNESS = DEFAULTS.gridThickness
local GRID_HEIGHT_OFFSET = DEFAULTS.gridHeightOffset
local GRID_COLOR = DEFAULTS.gridColor

local ROTATE_DRAG_SENSITIVITY = DEFAULTS.rotateDragSensitivity
local MIN_ZOOM = DEFAULTS.minZoom
local MAX_ZOOM = DEFAULTS.maxZoom
local ZOOM_STEP = DEFAULTS.zoomStep
local CURVE_START = DEFAULTS.curveStart
local CURVE_END = DEFAULTS.curveEnd
local TOP_DOWN_PITCH = DEFAULTS.topDownPitch
local NORMAL_PITCH = DEFAULTS.normalPitch
local CAMERA_RESPONSE = DEFAULTS.cameraResponse
local YAW_RESPONSE = DEFAULTS.yawResponse
local PAN_BASE_SPEED = DEFAULTS.panBaseSpeed
local PAN_ZOOM_MULTIPLIER = DEFAULTS.panZoomMultiplier

local function getDebugStateSnapshot()
	local activeCamera = getActiveCamera()
	local humanoid = getHumanoid()

	local cameraType = activeCamera and tostring(activeCamera.CameraType) or "nil"
	local cameraMode = tostring(localPlayer.CameraMode)
	local mouseBehavior = tostring(UserInputService.MouseBehavior)
	local walkSpeed = humanoid and tostring(humanoid.WalkSpeed) or "nil"
	local jumpPower = humanoid and tostring(humanoid.JumpPower) or "nil"
	local jumpHeight = humanoid and tostring(humanoid.JumpHeight) or "nil"
	local autoRotate = humanoid and tostring(humanoid.AutoRotate) or "nil"

	return string.format(
		"script=%s build=%s cameraType=%s cameraMode=%s mouse=%s walk=%s jumpPower=%s jumpHeight=%s autoRotate=%s",
		tostring(isScriptEnabled),
		tostring(isBuildMode),
		cameraType,
		cameraMode,
		mouseBehavior,
		walkSpeed,
		jumpPower,
		jumpHeight,
		autoRotate
	)
end

local function debugLog(tag, message)
	if not DEBUG_ENABLED then
		return
	end

	if tag ~= "Transform" then
		return
	end

	print(string.format("[TransformDebug][%.3f] %s", os.clock(), message))
end

local function getNumberAttribute(name, defaultValue)
	local value = scriptObject:GetAttribute(name)
	if typeof(value) == "number" then
		return value
	end

	return defaultValue
end

local function reloadConfigFromAttributes()
	ROTATE_DRAG_SENSITIVITY = getNumberAttribute("RotateDragSensitivity", DEFAULTS.rotateDragSensitivity)
	MIN_ZOOM = getNumberAttribute("MinZoom", DEFAULTS.minZoom)
	MAX_ZOOM = getNumberAttribute("MaxZoom", DEFAULTS.maxZoom)
	ZOOM_STEP = getNumberAttribute("ZoomStep", DEFAULTS.zoomStep)
	CURVE_START = getNumberAttribute("CurveStart", DEFAULTS.curveStart)
	CURVE_END = getNumberAttribute("CurveEnd", DEFAULTS.curveEnd)
	TOP_DOWN_PITCH = getNumberAttribute("TopDownPitch", DEFAULTS.topDownPitch)
	NORMAL_PITCH = getNumberAttribute("NormalPitch", DEFAULTS.normalPitch)
	CAMERA_RESPONSE = getNumberAttribute("CameraResponse", DEFAULTS.cameraResponse)
	YAW_RESPONSE = getNumberAttribute("YawResponse", DEFAULTS.yawResponse)
	PAN_BASE_SPEED = getNumberAttribute("PanBaseSpeed", DEFAULTS.panBaseSpeed)
	PAN_ZOOM_MULTIPLIER = getNumberAttribute("PanZoomMultiplier", DEFAULTS.panZoomMultiplier)
	GRID_SIZE = getNumberAttribute("GridSize", DEFAULTS.gridSize)
	GRID_RADIUS = math.max(1, math.floor(getNumberAttribute("GridRadius", DEFAULTS.gridRadius)))
	GRID_THICKNESS = getNumberAttribute("GridThickness", DEFAULTS.gridThickness)
	GRID_HEIGHT_OFFSET = getNumberAttribute("GridHeightOffset", DEFAULTS.gridHeightOffset)

	if MAX_ZOOM < MIN_ZOOM then
		MAX_ZOOM = MIN_ZOOM
	end

	if CURVE_END <= CURVE_START then
		CURVE_END = CURVE_START + 1
	end

	targetZoom = math.clamp(targetZoom, MIN_ZOOM, MAX_ZOOM)
	currentZoom = math.clamp(currentZoom, MIN_ZOOM, MAX_ZOOM)
end

reloadConfigFromAttributes()

for _, attributeName in {
	"RotateDragSensitivity",
	"MinZoom",
	"MaxZoom",
	"ZoomStep",
	"CurveStart",
	"CurveEnd",
	"TopDownPitch",
	"NormalPitch",
	"CameraResponse",
	"YawResponse",
	"PanBaseSpeed",
	"PanZoomMultiplier",
	"GridSize",
	"GridRadius",
	"GridThickness",
	"GridHeightOffset",
} do
	scriptObject:GetAttributeChangedSignal(attributeName):Connect(reloadConfigFromAttributes)
end

local function lerpExp(current, goal, response, dt)
	local alpha = 1 - math.exp(-response * dt)
	return current + (goal - current) * alpha
end

local function shortestAngleDeltaDegrees(fromDeg, toDeg)
	local delta = (toDeg - fromDeg + 180) % 360 - 180
	return delta
end

local function getRootPart()
	local character = localPlayer.Character
	if not character then
		return nil
	end

	return character:FindFirstChild("HumanoidRootPart")
end

getActiveCamera = function()
	local current = workspace.CurrentCamera
	if current then
		camera = current
	end
	return camera
end

local function getPlayerControls()
	if cachedControls then
		return cachedControls
	end

	local playerScripts = localPlayer:FindFirstChild("PlayerScripts")
	if not playerScripts then
		return nil
	end

	local playerModule = playerScripts:FindFirstChild("PlayerModule")
	if not playerModule then
		return nil
	end

	local ok, controls = pcall(function()
		local module = require(playerModule)
		return module:GetControls()
	end)

	if ok and controls then
		cachedControls = controls
		return controls
	end

	return nil
end

getHumanoid = function()
	local character = localPlayer.Character
	if not character then
		return nil
	end

	return character:FindFirstChildOfClass("Humanoid")
end

local function setControlsEnabled(enabled)
	local controls = getPlayerControls()
	if not controls then
		debugLog("Controls", "Player controls module not available")
		return
	end

	if enabled then
		controls:Enable()
		debugLog("Controls", "Enabled default controls")
	else
		controls:Disable()
		debugLog("Controls", "Disabled default controls")
	end
end

local function setPlacementPreviewVisible(visible)
	if not UI.placementPreview then
		return
	end

	UI.placementPreview.Transparency = visible and 0.55 or 1
	local marker = UI.placementPreview:FindFirstChild("OrientationMarker")
	if marker and marker:IsA("SurfaceGui") then
		marker.Enabled = visible
	end
end

local function restoreNormalGameplayState()
	debugLog("Restore", "Applying normal gameplay camera and controls")

	local activeCamera = getActiveCamera()
	local character = localPlayer.Character or localPlayer.CharacterAdded:Wait()
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid")

	activeCamera.CameraSubject = nil
	activeCamera.CameraSubject = humanoid
	activeCamera.CameraType = previousCameraType or Enum.CameraType.Custom
	localPlayer.CameraMode = previousCameraMode or Enum.CameraMode.Classic

	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	setControlsEnabled(true)
	debugLog("Restore", "Normal gameplay state restored")
end

local function setCharacterBuildLock(enabled)
	local humanoid = getHumanoid()
	if not humanoid then
		local character = localPlayer.Character or localPlayer.CharacterAdded:Wait()
		humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 2)
		if not humanoid then
			debugLog("Lock", "Humanoid missing; cannot change movement lock")
			return
		end
	end

	if enabled then
		debugLog("Lock", "Locking humanoid movement for build mode")

		previousWalkSpeed = humanoid.WalkSpeed
		previousAutoRotate = humanoid.AutoRotate
		previousJumpPower = humanoid.JumpPower
		previousJumpHeight = humanoid.JumpHeight

		humanoid.WalkSpeed = 0
		humanoid.AutoRotate = false

		if humanoid.UseJumpPower then
			humanoid.JumpPower = 0
		else
			humanoid.JumpHeight = 0
		end

		debugLog("Lock", "Humanoid locked")
	else
		debugLog("Lock", "Restoring humanoid movement")

		local restoredWalkSpeed = previousWalkSpeed
		if restoredWalkSpeed == nil or restoredWalkSpeed <= 0 then
			restoredWalkSpeed = 16
		end
		humanoid.WalkSpeed = restoredWalkSpeed
		humanoid.AutoRotate = if previousAutoRotate ~= nil then previousAutoRotate else true

		if humanoid.UseJumpPower then
			local restoredJumpPower = previousJumpPower
			if restoredJumpPower == nil or restoredJumpPower <= 0 then
				restoredJumpPower = 50
			end
			humanoid.JumpPower = restoredJumpPower
		else
			local restoredJumpHeight = previousJumpHeight
			if restoredJumpHeight == nil or restoredJumpHeight <= 0 then
				restoredJumpHeight = 7.2
			end
			humanoid.JumpHeight = restoredJumpHeight
		end

		debugLog("Lock", "Humanoid movement restored")
	end
end

local function getCurveAlpha(zoomDistance)
	local t = (zoomDistance - CURVE_START) / (CURVE_END - CURVE_START)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function getPanInputVector()
	local x = 0
	local y = 0

	if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then
		x -= 1
	end

	if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then
		x += 1
	end

	if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then
		y += 1
	end

	if UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then
		y -= 1
	end

	local vector = Vector2.new(x, y)
	if vector.Magnitude > 1 then
		vector = vector.Unit
	end

	return vector
end

local function getMouseLocation()
	return UserInputService:GetMouseLocation()
end

local function snapValue(value, step)
	return math.floor(value / step + 0.5) * step
end

local function getPlacementSize()
	return Vector3.new(GRID_SIZE, GRID_SIZE, GRID_SIZE)
end

local function getModelTemplatesFolder()
	local sharedFolder = ReplicatedStorage:FindFirstChild("Shared")
	if not sharedFolder then
		return nil
	end

	local templatesFolder = sharedFolder:FindFirstChild(MODEL_TEMPLATES_FOLDER_NAME)
	if templatesFolder and templatesFolder:IsA("Folder") then
		return templatesFolder
	end

	return nil
end

local function getTemplateModelByName(modelName)
	local templateName = ShapeCatalog.getTemplateName(modelName)
	if typeof(templateName) ~= "string" or templateName == "" then
		return nil
	end

	local templatesFolder = getModelTemplatesFolder()
	if not templatesFolder then
		return nil
	end

	local template = templatesFolder:FindFirstChild(templateName)
	if template and (template:IsA("Model") or template:IsA("BasePart")) then
		return template
	end

	return nil
end

local function getFirstBasePart(root)
	if root:IsA("BasePart") then
		return root
	end

	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end

	return nil
end

local function getBorderSnappedPosition(position)
	local half = GRID_SIZE * 0.5
	local snappedX = math.floor(position.X / GRID_SIZE) * GRID_SIZE + half
	local snappedZ = math.floor(position.Z / GRID_SIZE) * GRID_SIZE + half
	local snappedY = position.Y + half
	return Vector3.new(snappedX, snappedY, snappedZ)
end

local function snapToGridCellCenter(value)
	local half = GRID_SIZE * 0.5
	return math.floor((value - half) / GRID_SIZE + 0.5) * GRID_SIZE + half
end

local function getPlacementOffsetPosition(position, normal)
	local half = GRID_SIZE * 0.5
	return position + normal * half
end

local function getPlacementTarget()
	local mousePosition = getMouseLocation()
	local activeCamera = getActiveCamera()
	local unitRay = activeCamera:ViewportPointToRay(mousePosition.X, mousePosition.Y)
	local rayOrigin = unitRay.Origin
	local rayDirection = unitRay.Direction * 1000

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Blacklist
	params.IgnoreWater = true

	local blacklist = {}
	local character = localPlayer.Character
	if character then
		table.insert(blacklist, character)
	end
	if UI.placementPreview then
		table.insert(blacklist, UI.placementPreview)
	end
	if gridFolder then
		table.insert(blacklist, gridFolder)
	end
	params.FilterDescendantsInstances = blacklist

	local result = workspace:Raycast(rayOrigin, rayDirection, params)
	if not result then
		return nil
	end

	local position = result.Position
	if isSnapEnabled then
		position = getBorderSnappedPosition(position)
	else
		position = getPlacementOffsetPosition(position, result.Normal)
	end

	return position, result.Normal
end

local function updatePlacementIndicatorVisible()
	if not UI.placementIndicator then
		return
	end

	UI.placementIndicator.Visible = isBuildMode and isPlacementMode and ShapeCatalog.isSupported(selectedModelName)
end

local function addOrientationMarker(part)
	if not part then
		return
	end

	local existingMarker = part:FindFirstChild("OrientationMarker")
	if existingMarker then
		existingMarker:Destroy()
	end

	local surfaceGui = Instance.new("SurfaceGui")
	surfaceGui.Name = "OrientationMarker"
	surfaceGui.Face = Enum.NormalId.Front
	surfaceGui.AlwaysOnTop = true
	surfaceGui.LightInfluence = 0
	surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surfaceGui.PixelsPerStud = 40
	surfaceGui.Enabled = isBuildMode
	surfaceGui.Parent = part

	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)
	frame.Parent = surfaceGui

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.Text = "F"
	label.TextColor3 = Color3.fromRGB(30, 30, 30)
	label.TextScaled = true
	label.TextStrokeColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.35
	label.Parent = frame
end

local function setOrientationMarkersVisible(visible)
	if UI.placementPreview then
		local previewMarker = UI.placementPreview:FindFirstChild("OrientationMarker")
		if previewMarker and previewMarker:IsA("SurfaceGui") then
			previewMarker.Enabled = visible
		end
	end

	if not placedObjectsFolder then
		return
	end

	for _, descendant in placedObjectsFolder:GetDescendants() do
		if descendant:IsA("SurfaceGui") and descendant.Name == "OrientationMarker" then
			descendant.Enabled = visible
		end
	end
end

local function updatePlacementPreview(targetPosition)
	if not UI.placementPreview then
		return
	end

	if not targetPosition then
		setPlacementPreviewVisible(false)
		return
	end

	if ShapeCatalog.getTemplateName(selectedModelName) then
		setPlacementPreviewVisible(false)
		return
	end

	setPlacementPreviewVisible(true)
	UI.placementPreview.Shape = ShapeCatalog.getShape(selectedModelName)
	UI.placementPreview.Size = getPlacementSize()
	UI.placementPreview.CFrame = CFrame.new(targetPosition)
end

local function createPlacementPreview()
	if UI.placementPreview then
		UI.placementPreview:Destroy()
	end

	local part = Instance.new("Part")
	part.Name = "PlacementPreview"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.ForceField
	part.Color = Color3.fromRGB(120, 220, 255)
	part.Transparency = 0.55
	part.Shape = ShapeCatalog.getShape(selectedModelName)
	part.Size = getPlacementSize()
	addOrientationMarker(part)
	part.Parent = workspace

	UI.placementPreview = part
end

local function createPlacementIndicator()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local existingGui = playerGui:FindFirstChild("BuildModePlacementGui")
	if existingGui then
		existingGui:Destroy()
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "BuildModePlacementGui"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	UI.placementIndicator = Instance.new("Frame")
	UI.placementIndicator.Name = "PlacementIndicator"
	UI.placementIndicator.AnchorPoint = Vector2.new(0, 0)
	UI.placementIndicator.Size = UDim2.fromOffset(14, 14)
	UI.placementIndicator.BackgroundColor3 = Color3.fromRGB(120, 220, 255)
	UI.placementIndicator.BackgroundTransparency = 0.15
	UI.placementIndicator.BorderSizePixel = 0
	UI.placementIndicator.Visible = false
	UI.placementIndicator.Parent = screenGui

	local indicatorCorner = Instance.new("UICorner")
	indicatorCorner.CornerRadius = UDim.new(1, 0)
	indicatorCorner.Parent = UI.placementIndicator

	local indicatorStroke = Instance.new("UIStroke")
	indicatorStroke.Thickness = 1
	indicatorStroke.Transparency = 0.25
	indicatorStroke.Color = Color3.fromRGB(255, 255, 255)
	indicatorStroke.Parent = UI.placementIndicator
end

local function setPlacementMode(enabled)
	isPlacementMode = enabled
	updatePlacementIndicatorVisible()
	if not enabled then
		setPlacementPreviewVisible(false)
	end
end

local function placeSelectedModel()
	if not (isBuildMode and isPlacementMode and ShapeCatalog.isSupported(selectedModelName)) then
		return
	end

	local targetPosition = getPlacementTarget()
	if not targetPosition then
		return
	end

	local templateModel = getTemplateModelByName(selectedModelName)
	if templateModel then
		local placedTemplate = templateModel:Clone()
		placedTemplate.Name = "Placed" .. selectedModelName:gsub("%s+", "")

		if placedTemplate:IsA("Model") then
			for _, descendant in placedTemplate:GetDescendants() do
				if descendant:IsA("BasePart") then
					descendant.Anchored = true
				end
			end

			placedTemplate:PivotTo(CFrame.new(targetPosition))
			local markerPart = getFirstBasePart(placedTemplate)
			if markerPart then
				addOrientationMarker(markerPart)
			end
		elseif placedTemplate:IsA("BasePart") then
			placedTemplate.Anchored = true
			placedTemplate.CFrame = CFrame.new(targetPosition)
			addOrientationMarker(placedTemplate)
		end

		placedTemplate.Parent = placedObjectsFolder or workspace

		setPlacementMode(false)
		updatePlacementIndicatorVisible()
		if UI.placementPreview then
			setPlacementPreviewVisible(false)
		end

		return
	end

	local placedPart = Instance.new("Part")
	placedPart.Name = "Placed" .. selectedModelName
	placedPart.Anchored = true
	placedPart.Shape = ShapeCatalog.getShape(selectedModelName)
	placedPart.Size = getPlacementSize()
	placedPart.Color = Color3.fromRGB(180, 180, 180)
	placedPart.Material = Enum.Material.SmoothPlastic
	placedPart.CastShadow = true
	placedPart.CFrame = CFrame.new(targetPosition)
	addOrientationMarker(placedPart)
	placedPart.Parent = placedObjectsFolder or workspace

	setPlacementMode(false)
	updatePlacementIndicatorVisible()
	if UI.placementPreview then
		setPlacementPreviewVisible(false)
	end
end

	local function isTransformableObject(instance)
		if not instance then
			return false
		end

		if not (instance:IsA("BasePart") or instance:IsA("Model")) then
			return false
		end

		return placedObjectsFolder ~= nil and instance.Parent == placedObjectsFolder
	end

	local function getTransformRootFromInstance(instance)
		if not instance or not placedObjectsFolder then
			return nil
		end

		local current = instance
		while current and current ~= placedObjectsFolder do
			if isTransformableObject(current) then
				return current
			end

			current = current.Parent
		end

		return nil
	end

	local function getTransformObjectPivot(transformObject)
		if not transformObject then
			return nil
		end

		if transformObject:IsA("BasePart") then
			return transformObject.CFrame
		end

		if transformObject:IsA("Model") then
			return transformObject:GetPivot()
		end

		return nil
	end

	local function setTransformObjectPivot(transformObject, newPivot)
		if not transformObject or not newPivot then
			return
		end

		if transformObject:IsA("BasePart") then
			transformObject.CFrame = newPivot
		elseif transformObject:IsA("Model") then
			transformObject:PivotTo(newPivot)
		end
	end

	local function getTransformObjectSize(transformObject)
		if not transformObject then
			return Vector3.zero
		end

		if transformObject:IsA("BasePart") then
			return transformObject.Size
		end

		if transformObject:IsA("Model") then
			return transformObject:GetExtentsSize()
		end

		return Vector3.zero
	end

	local function scaleModelAlongAxis(model, axis, delta, handleSign)
		local oldExtents = model:GetExtentsSize()
		local oldAxisSize
		if axis == "X" then
			oldAxisSize = oldExtents.X
		elseif axis == "Y" then
			oldAxisSize = oldExtents.Y
		else
			oldAxisSize = oldExtents.Z
		end

		if oldAxisSize <= 0 then
			return
		end

		local newAxisSize = math.max(TRANSFORM_MIN_SIZE, oldAxisSize + delta)
		local ratio = newAxisSize / oldAxisSize
		if math.abs(ratio - 1) <= 0.0001 then
			return
		end

		local pivot = model:GetPivot()
		local axisVector
		if axis == "X" then
			axisVector = pivot.RightVector
		elseif axis == "Y" then
			axisVector = pivot.UpVector
		else
			axisVector = pivot.LookVector
		end
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				local localPosition = pivot:PointToObjectSpace(descendant.Position)
				local newLocalPosition

				if axis == "X" then
					descendant.Size = Vector3.new(math.max(TRANSFORM_MIN_SIZE, descendant.Size.X * ratio), descendant.Size.Y, descendant.Size.Z)
					newLocalPosition = Vector3.new(localPosition.X * ratio, localPosition.Y, localPosition.Z)
				elseif axis == "Y" then
					descendant.Size = Vector3.new(descendant.Size.X, math.max(TRANSFORM_MIN_SIZE, descendant.Size.Y * ratio), descendant.Size.Z)
					newLocalPosition = Vector3.new(localPosition.X, localPosition.Y * ratio, localPosition.Z)
				else
					descendant.Size = Vector3.new(descendant.Size.X, descendant.Size.Y, math.max(TRANSFORM_MIN_SIZE, descendant.Size.Z * ratio))
					newLocalPosition = Vector3.new(localPosition.X, localPosition.Y, localPosition.Z * ratio)
				end

				descendant.CFrame = CFrame.new(pivot:PointToWorldSpace(newLocalPosition)) * descendant.CFrame.Rotation
			end
		end

		local appliedDelta = newAxisSize - oldAxisSize
		local centerShift = axisVector * (appliedDelta * 0.5 * handleSign)
		model:PivotTo(CFrame.new(pivot.Position + centerShift) * pivot.Rotation)
	end

local function updateTransformToolButtonsVisual()
	if not UI.moveToolButton or not UI.rotateToolButton or not UI.scaleToolButton then
		return
	end

	UI.moveToolButton.BackgroundColor3 = activeTransformTool == "move" and Color3.fromRGB(45, 150, 80) or Color3.fromRGB(35, 35, 35)
	UI.rotateToolButton.BackgroundColor3 = activeTransformTool == "rotate" and Color3.fromRGB(45, 150, 80) or Color3.fromRGB(35, 35, 35)
	UI.scaleToolButton.BackgroundColor3 = activeTransformTool == "scale" and Color3.fromRGB(45, 150, 80) or Color3.fromRGB(35, 35, 35)
end

local function setActiveTransformTool(toolName)
	activeTransformTool = toolName
	updateTransformToolButtonsVisual()
	debugLog("Transform", string.format("Active tool changed to %s", toolName))

	if toolName == "move" and selectedTransformObject then
		startMoveHandleExpectation("setActiveTransformTool")
	end
end

local function setTransformGizmosEnabled(enabled)
	local showMove = enabled and activeTransformTool == "move"
	local showRotate = enabled and activeTransformTool == "rotate"
	local showScale = enabled and activeTransformTool == "scale"

	setMoveGizmoVisible(showMove)

	if UI.transformRotateHandles then
		UI.transformRotateHandles.Parent = showRotate and workspace or nil
	end

	if UI.transformScaleHandles then
		UI.transformScaleHandles.Parent = showScale and workspace or nil
	end

	logTransformStateSnapshot("setTransformGizmosEnabled")
end

setMoveGizmoVisible = function(visible)
	if UI.transformMoveGizmoFolder then
		UI.transformMoveGizmoFolder.Parent = visible and workspace or nil
	end
end

local function getMoveAxisVectorFromName(axisName, pivot)
	if axisName == "X" then
		return pivot.RightVector
	elseif axisName == "NX" then
		return -pivot.RightVector
	elseif axisName == "Y" then
		return pivot.UpVector
	elseif axisName == "NY" then
		return -pivot.UpVector
	elseif axisName == "Z" then
		return pivot.LookVector
	end

	return -pivot.LookVector
end

local function updateMoveGizmoFromSelected()
	if not UI.transformMoveGizmoFolder or not selectedTransformObject then
		return
	end

	local pivot = getTransformObjectPivot(selectedTransformObject)
	if not pivot then
		return
	end

	for _, part in UI.transformMoveGizmoFolder:GetChildren() do
		if part:IsA("BasePart") then
			local axisName = part:GetAttribute("AxisName")
			if typeof(axisName) == "string" then
				local axis = getMoveAxisVectorFromName(axisName, pivot)
				local axisOffset = getAxisHalfExtentForTransform(selectedTransformObject, axis) + MOVE_GIZMO_AXIS_GAP + MOVE_GIZMO_AXIS_LENGTH * 0.5
				part.CFrame = CFrame.lookAt(pivot.Position + axis * axisOffset, pivot.Position + axis * (axisOffset + 1))
			end
		end
	end
end

local function getPositiveAxisName(axisName)
	if axisName == "NX" then
		return "X"
	elseif axisName == "NY" then
		return "Y"
	elseif axisName == "NZ" then
		return "Z"
	end

	return axisName
end

local function getPrimaryAxisWorldVector(axisName, pivot)
	if axisName == "X" then
		return pivot.RightVector
	elseif axisName == "Y" then
		return pivot.UpVector
	end

	return pivot.LookVector
end

local function getYawPitchDegreesFromRotation(rotation)
	local lookVector = rotation.LookVector
	local pitchDegrees = math.deg(math.asin(math.clamp(lookVector.Y, -1, 1)))
	local yawDegrees = math.deg(math.atan2(-lookVector.X, -lookVector.Z))
	return yawDegrees, pitchDegrees
end

local function buildYawPitchRotation(yawDegrees, pitchDegrees)
	return CFrame.Angles(0, math.rad(yawDegrees), 0) * CFrame.Angles(math.rad(pitchDegrees), 0, 0)
end

local function getPerpendicularAxes(axisUnitVector)
	local helper = math.abs(axisUnitVector.Y) < 0.95 and Vector3.yAxis or Vector3.xAxis
	local tangentA = axisUnitVector:Cross(helper)
	if tangentA.Magnitude <= 0.0001 then
		helper = Vector3.zAxis
		tangentA = axisUnitVector:Cross(helper)
	end

	tangentA = tangentA.Unit
	local tangentB = axisUnitVector:Cross(tangentA).Unit
	return tangentA, tangentB
end

getAxisHalfExtentForTransform = function(transformObject, axisUnitVector)
	if not transformObject then
		return 0
	end

	local basisCFrame
	local size

	if transformObject:IsA("BasePart") then
		basisCFrame = transformObject.CFrame
		size = transformObject.Size
	elseif transformObject:IsA("Model") then
		local boxCFrame, boxSize = transformObject:GetBoundingBox()
		basisCFrame = boxCFrame
		size = boxSize
	else
		return 0
	end

	local axis = axisUnitVector.Unit
	return math.abs(axis:Dot(basisCFrame.RightVector)) * size.X * 0.5
		+ math.abs(axis:Dot(basisCFrame.UpVector)) * size.Y * 0.5
		+ math.abs(axis:Dot(basisCFrame.LookVector)) * size.Z * 0.5
end

local function getTransformMaxHalfExtent(transformObject, pivot)
	if not (transformObject and pivot) then
		return 0
	end

	local hx = getAxisHalfExtentForTransform(transformObject, pivot.RightVector)
	local hy = getAxisHalfExtentForTransform(transformObject, pivot.UpVector)
	local hz = getAxisHalfExtentForTransform(transformObject, pivot.LookVector)
	return math.max(hx, hy, hz)
end

local function updateRotateGizmoFromSelected()
	if not UI.transformRotateHandles or not selectedTransformObject then
		return
	end

	local pivot = getTransformObjectPivot(selectedTransformObject)
	if not pivot then
		return
	end

	local rotateRadius = getTransformMaxHalfExtent(selectedTransformObject, pivot) + ROTATE_GIZMO_RADIUS

	for _, part in UI.transformRotateHandles:GetDescendants() do
		if part:IsA("BasePart") then
			local axisName = part:GetAttribute("AxisName")
			local ringSlot = part:GetAttribute("RingSlot")
			if typeof(axisName) == "string" and typeof(ringSlot) == "number" then
				local axis
				local direction

				if axisName == "Y" then
					axis = pivot.UpVector
					if ringSlot == 1 then
						direction = pivot.RightVector
					elseif ringSlot == 2 then
						direction = -pivot.RightVector
					elseif ringSlot == 3 then
						direction = pivot.LookVector
					else
						direction = -pivot.LookVector
					end
				elseif axisName == "X" then
					axis = pivot.RightVector
					direction = if ringSlot == 1 then pivot.UpVector else -pivot.UpVector
				else
					axis = getPrimaryAxisWorldVector(axisName, pivot)
					direction = if ringSlot == 1 then pivot.LookVector else -pivot.LookVector
				end

				local handlePosition = pivot.Position + direction * rotateRadius
				part.CFrame = CFrame.new(handlePosition) * pivot.Rotation
			end
		end
	end
end

local function updateScaleGizmoFromSelected()
	if not UI.transformScaleHandles or not selectedTransformObject then
		return
	end

	local pivot = getTransformObjectPivot(selectedTransformObject)
	if not pivot then
		return
	end

	for _, part in UI.transformScaleHandles:GetDescendants() do
		if part:IsA("BasePart") then
			local axisName = part:GetAttribute("AxisName")
			if typeof(axisName) == "string" then
				local axis = getMoveAxisVectorFromName(axisName, pivot)
				local axisOffset = getAxisHalfExtentForTransform(selectedTransformObject, axis) + SCALE_GIZMO_AXIS_GAP + SCALE_GIZMO_AXIS_LENGTH * 0.5
				part.CFrame = CFrame.lookAt(pivot.Position + axis * axisOffset, pivot.Position + axis * (axisOffset + 1))
			end
		end
	end
end

local function getMouseRay()
	local mousePosition = getMouseLocation()
	local activeCamera = getActiveCamera()
	local unitRay = activeCamera:ViewportPointToRay(mousePosition.X, mousePosition.Y)
	return unitRay.Origin, unitRay.Direction
end

local function getMousePointOnPlane(planePoint, planeNormal)
	local rayOrigin, rayDirection = getMouseRay()
	local denominator = planeNormal:Dot(rayDirection)
	if math.abs(denominator) < 1e-5 then
		return nil
	end

	local distanceAlongRay = planeNormal:Dot(planePoint - rayOrigin) / denominator
	if distanceAlongRay < 0 then
		return nil
	end

	return rayOrigin + rayDirection * distanceAlongRay
end

local function getProjectedPlaneVector(pointOnPlane, planePoint, planeNormal)
	local offset = pointOnPlane - planePoint
	local projected = offset - planeNormal * offset:Dot(planeNormal)
	if projected.Magnitude <= 1e-5 then
		return nil
	end

	return projected.Unit
end

local function getMouseVectorFromWorldPoint(worldPoint)
	local activeCamera = getActiveCamera()
	local screenPoint, onScreen = activeCamera:WorldToViewportPoint(worldPoint)
	if not onScreen then
		return nil
	end

	local mousePosition = getMouseLocation()
	local vector = Vector2.new(mousePosition.X - screenPoint.X, mousePosition.Y - screenPoint.Y)
	if vector.Magnitude <= 1e-5 then
		return nil
	end

	return vector.Unit
end

local function getSignedScreenAngleDegrees(fromVector, toVector)
	local determinant = fromVector.X * toVector.Y - fromVector.Y * toVector.X
	local dotProduct = math.clamp(fromVector:Dot(toVector), -1, 1)
	return -math.deg(math.atan2(determinant, dotProduct))
end

local function getSignedAngleDegreesAroundAxis(axisUnitVector, fromVector, toVector)
	local sine = axisUnitVector:Dot(fromVector:Cross(toVector))
	local cosine = math.clamp(fromVector:Dot(toVector), -1, 1)
	return math.deg(math.atan2(sine, cosine))
end

local function getClosestAxisParameterToMouse(originOnAxis, axisUnitVector)
	local rayOrigin, rayDirection = getMouseRay()
	local w0 = originOnAxis - rayOrigin
	local u = axisUnitVector
	local v = rayDirection

	local a = u:Dot(u)
	local b = u:Dot(v)
	local c = v:Dot(v)
	local d = u:Dot(w0)
	local e = v:Dot(w0)
	local denom = a * c - b * b

	if math.abs(denom) < 0.000001 then
		return nil
	end

	return (b * e - c * d) / denom
end

local function tryBeginTransformGizmoDrag()
	if not selectedTransformObject then
		debugLog("Transform", "tryBeginTransformGizmoDrag aborted: no selected transform object")
		return false
	end

	local gizmoFolder = nil
	local dragMode = nil
	if activeTransformTool == "move" then
		gizmoFolder = UI.transformMoveGizmoFolder
		dragMode = "move-gizmo"
	elseif activeTransformTool == "rotate" then
		gizmoFolder = UI.transformRotateHandles
		dragMode = "rotate-gizmo"
	elseif activeTransformTool == "scale" then
		gizmoFolder = UI.transformScaleHandles
		dragMode = "scale-gizmo"
	end

	if not (gizmoFolder and gizmoFolder.Parent) then
		debugLog("Transform", string.format("tryBeginTransformGizmoDrag aborted: gizmo folder missing or hidden for tool=%s", tostring(activeTransformTool)))
		return false
	end

	local rayOrigin, rayDirection = getMouseRay()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Whitelist
	params.IgnoreWater = true
	params.FilterDescendantsInstances = { gizmoFolder }

	local result = workspace:Raycast(rayOrigin, rayDirection * 1000, params)
	if not result then
		debugLog("Transform", string.format("tryBeginTransformGizmoDrag raycast miss for tool=%s", tostring(activeTransformTool)))
		return false
	end

	local hitPart = result.Instance
	if not hitPart then
		debugLog("Transform", "tryBeginTransformGizmoDrag aborted: raycast hit had no instance")
		return false
	end

	local axisName = hitPart:GetAttribute("AxisName")
	if typeof(axisName) ~= "string" then
		debugLog("Transform", string.format("tryBeginTransformGizmoDrag aborted: hit part %s missing AxisName attribute", hitPart:GetFullName()))
		return false
	end

	local gizmoName = hitPart:GetAttribute("GizmoName")
	if typeof(gizmoName) ~= "string" then
		gizmoName = hitPart.Name
	end

	local pivot = getTransformObjectPivot(selectedTransformObject)
	if not pivot then
		debugLog("Transform", string.format("tryBeginTransformGizmoDrag aborted: selected transform %s has no pivot", selectedTransformObject:GetFullName()))
		return false
	end

	transformDragState.mode = dragMode
	transformDragState.activeAxisName = axisName
	transformDragState.activeGizmoName = gizmoName
	transformDragState.rotationRingSlot = typeof(hitPart:GetAttribute("RingSlot")) == "number" and hitPart:GetAttribute("RingSlot") or nil
	transformDragState.pivotStart = pivot
	transformDragState.startMousePosition = getMouseLocation()
	transformDragState.isHandleDragging = true
	transformDragState.expectationToken += 1
	debugLog(
		"Transform",
		string.format("Gizmo used gizmo=%s mode=%s axis=%s handle=%s", tostring(gizmoName), tostring(dragMode), tostring(axisName), hitPart:GetFullName())
	)

	if dragMode == "move-gizmo" or dragMode == "scale-gizmo" then
		local axisVector = getMoveAxisVectorFromName(axisName, pivot)
		local initialT = getClosestAxisParameterToMouse(pivot.Position, axisVector)
		if initialT == nil then
			transformDragState.mode = nil
			transformDragState.activeAxisName = nil
			transformDragState.pivotStart = nil
			transformDragState.isHandleDragging = false
			return false
		end

		transformDragState.axisVector = axisVector

		if dragMode == "move-gizmo" then
			transformDragState.startValue = initialT
			transformDragState.lastValue = initialT
		else
			-- For scaling, accumulate total drag distance from the initial grab point.
			transformDragState.startValue = initialT
			transformDragState.lastValue = 0
		end
	else
		local rotateAxis
		local rotationYawDegrees, rotationPitchDegrees = getYawPitchDegreesFromRotation(pivot.Rotation)

		if axisName == "Y" then
			rotateAxis = Vector3.yAxis
			rotationYawDegrees = snapValue(rotationYawDegrees, TRANSFORM_ROTATE_SNAP_STEP)
		elseif axisName == "X" then
			rotateAxis = Vector3.xAxis
			rotationPitchDegrees = snapValue(rotationPitchDegrees, TRANSFORM_ROTATE_SNAP_STEP)
		else
			rotateAxis = Vector3.zAxis
		end

		transformDragState.rotationYawDegrees = rotationYawDegrees
		transformDragState.rotationPitchDegrees = rotationPitchDegrees
		transformDragState.startRotationYawDegrees = rotationYawDegrees
		transformDragState.startRotationPitchDegrees = rotationPitchDegrees

		transformDragState.axisVector = rotateAxis
		transformDragState.rotationStartScreenVector = getMouseVectorFromWorldPoint(pivot.Position)
		if not transformDragState.rotationStartScreenVector then
			transformDragState.mode = nil
			transformDragState.activeAxisName = nil
			transformDragState.axisVector = nil
			transformDragState.pivotStart = nil
			transformDragState.isHandleDragging = false
			return false
		end

		transformDragState.startValue = 0
		transformDragState.lastValue = 0
		debugLog(
			"Transform",
			string.format(
				"Rotate drag initialized axis=%s handle=%s pivot=(%.2f, %.2f, %.2f) axisVector=(%.3f, %.3f, %.3f)",
				tostring(axisName),
				hitPart:GetFullName(),
				pivot.Position.X,
				pivot.Position.Y,
				pivot.Position.Z,
				rotateAxis.X,
				rotateAxis.Y,
				rotateAxis.Z
			)
		)
	end

	debugLog("Transform", string.format("[MovePipeline] Stage 2 handle grabbed axis=%s", axisName))
	logTransformStateSnapshot("MoveGizmoDown")
	return true
end

local function getTransformBottomOffsetForGround(transformObject)
	if not transformObject then
		return 0
	end

	if transformObject:IsA("Model") then
		local _, boundingSize = transformObject:GetBoundingBox()
		return boundingSize.Y * 0.5
	end

	local part = transformObject
	local worldHalfHeight =
		math.abs(part.CFrame.RightVector.Y) * part.Size.X * 0.5
		+ math.abs(part.CFrame.UpVector.Y) * part.Size.Y * 0.5
		+ math.abs(part.CFrame.LookVector.Y) * part.Size.Z * 0.5

	return worldHalfHeight
end

local function getGroundYForTransformMove(x, z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Blacklist
	params.IgnoreWater = true

	local blacklist = {}
	local character = localPlayer.Character
	if character then
		table.insert(blacklist, character)
	end
	if UI.placementPreview then
		table.insert(blacklist, UI.placementPreview)
	end
	if gridFolder then
		table.insert(blacklist, gridFolder)
	end
	if UI.transformMoveGizmoFolder then
		table.insert(blacklist, UI.transformMoveGizmoFolder)
	end
	if UI.transformRotateHandles then
		table.insert(blacklist, UI.transformRotateHandles)
	end
	if UI.transformScaleHandles then
		table.insert(blacklist, UI.transformScaleHandles)
	end
	if selectedTransformObject then
		table.insert(blacklist, selectedTransformObject)
	end
	params.FilterDescendantsInstances = blacklist

	local rayOrigin = Vector3.new(x, 2000, z)
	local rayDirection = Vector3.new(0, -4000, 0)
	local result = workspace:Raycast(rayOrigin, rayDirection, params)
	if result then
		return result.Position.Y
	end

	return 0
end

local function clampPivotToGround(position, transformObject)
	local groundY = getGroundYForTransformMove(position.X, position.Z)
	local minPivotY = groundY + getTransformBottomOffsetForGround(transformObject)

	if position.Y < minPivotY then
		return Vector3.new(position.X, minPivotY, position.Z)
	end

	return position
end

local function updateMoveGizmoDrag()
	if transformDragState.mode ~= "move-gizmo" or not selectedTransformObject or not transformDragState.pivotStart or not transformDragState.axisVector then
		return
	end

	local currentT = getClosestAxisParameterToMouse(transformDragState.pivotStart.Position, transformDragState.axisVector)
	if currentT == nil then
		return
	end

	local delta = currentT - transformDragState.lastValue
	if math.abs(delta) < 0.0005 then
		return
	end

	transformDragState.lastValue = currentT
	local newPivot = transformDragState.pivotStart + transformDragState.axisVector * (currentT - transformDragState.startValue)
	local newPosition = newPivot.Position

	if isSnapEnabled then
		newPosition = Vector3.new(
			snapToGridCellCenter(newPosition.X),
			newPosition.Y,
			snapToGridCellCenter(newPosition.Z)
		)
	end

	newPosition = clampPivotToGround(newPosition, selectedTransformObject)
	newPivot = CFrame.new(newPosition) * newPivot.Rotation

	setTransformObjectPivot(selectedTransformObject, newPivot)
	updateSelectedTransformUi()

	local now = os.clock()
	if now - transformDragState.lastLogAt >= TRANSFORM_DRAG_LOG_INTERVAL then
		transformDragState.lastLogAt = now
		debugLog("Transform", string.format("[MovePipeline] Stage 3 dragging axis=%s t=%.3f", tostring(transformDragState.activeAxisName), currentT))
	end
end

local function updateScaleGizmoDrag()
	if transformDragState.mode ~= "scale-gizmo" or not selectedTransformObject or not transformDragState.pivotStart or not transformDragState.axisVector then
		return
	end

	local currentT = getClosestAxisParameterToMouse(transformDragState.pivotStart.Position, transformDragState.axisVector)
	if currentT == nil then
		return
	end

	local totalDelta = currentT - transformDragState.startValue
	local targetDelta = isSnapEnabled and snapValue(totalDelta, GRID_SIZE) or totalDelta
	local delta = targetDelta - transformDragState.lastValue
	if math.abs(delta) < 0.0001 then
		return
	end

	transformDragState.lastValue = targetDelta
	local axis = getPositiveAxisName(transformDragState.activeAxisName)
	scaleSelectedPart(axis, delta)

	local now = os.clock()
	if now - transformDragState.lastLogAt >= TRANSFORM_DRAG_LOG_INTERVAL then
		transformDragState.lastLogAt = now
			debugLog("Transform", string.format("%s used: axis=%s raw=%.3f snapped=%.3f delta=%.3f", tostring(transformDragState.activeGizmoName), tostring(axis), totalDelta, targetDelta, delta))
	end
end

local function updateRotateGizmoDrag()
	if transformDragState.mode ~= "rotate-gizmo" or not selectedTransformObject or not transformDragState.pivotStart or not transformDragState.axisVector then
		debugLog(
			"Transform",
			string.format(
				"updateRotateGizmoDrag skipped mode=%s selected=%s pivot=%s axis=%s",
				tostring(transformDragState.mode),
				tostring(selectedTransformObject ~= nil),
				tostring(transformDragState.pivotStart ~= nil),
				tostring(transformDragState.axisVector ~= nil)
			)
		)
		return
	end

	if not transformDragState.rotationStartScreenVector then
		return
	end

	local currentVector = getMouseVectorFromWorldPoint(transformDragState.pivotStart.Position)
	if not currentVector then
		return
	end

	local totalDegrees = getSignedScreenAngleDegrees(transformDragState.rotationStartScreenVector, currentVector)
	totalDegrees = math.clamp(totalDegrees, -TRANSFORM_ROTATE_GIZMO_MAX_DEGREES, TRANSFORM_ROTATE_GIZMO_MAX_DEGREES)

	if isSnapEnabled then
		local snappedDegrees = snapValue(totalDegrees, TRANSFORM_ROTATE_SNAP_STEP)
		if math.abs(totalDegrees - snappedDegrees) <= TRANSFORM_ROTATE_GIZMO_SNAP_THRESHOLD then
			totalDegrees = snappedDegrees
		end
	end

	if math.abs(totalDegrees - transformDragState.lastValue) < 0.0001 then
		debugLog("Transform", string.format("Rotate skipped: totalDegrees %.2f unchanged from last %.2f", totalDegrees, transformDragState.lastValue))
		return
	end

	transformDragState.lastValue = totalDegrees
	if transformDragState.activeAxisName == "Y" then
		transformDragState.rotationYawDegrees = transformDragState.startRotationYawDegrees + totalDegrees
	elseif transformDragState.activeAxisName == "X" then
		transformDragState.rotationPitchDegrees = transformDragState.startRotationPitchDegrees + totalDegrees
	end

	local rotation = buildYawPitchRotation(transformDragState.rotationYawDegrees, transformDragState.rotationPitchDegrees)
	local newPivot = CFrame.new(transformDragState.pivotStart.Position) * rotation
	debugLog(
		"Transform",
		string.format(
			"Rotate apply axis=(%.3f, %.3f, %.3f) degrees=%.2f rotation=%s",
			transformDragState.axisVector.X,
			transformDragState.axisVector.Y,
			transformDragState.axisVector.Z,
			totalDegrees,
			tostring(rotation)
		)
	)
	setTransformObjectPivot(selectedTransformObject, newPivot)
	updateSelectedTransformUi()

	local appliedPivot = getTransformObjectPivot(selectedTransformObject)
	if appliedPivot then
		debugLog(
			"Transform",
			string.format(
				"Rotate applied pivot pos=(%.2f, %.2f, %.2f) look=(%.3f, %.3f, %.3f) right=(%.3f, %.3f, %.3f)",
				appliedPivot.Position.X,
				appliedPivot.Position.Y,
				appliedPivot.Position.Z,
				appliedPivot.LookVector.X,
				appliedPivot.LookVector.Y,
				appliedPivot.LookVector.Z,
				appliedPivot.RightVector.X,
				appliedPivot.RightVector.Y,
				appliedPivot.RightVector.Z
			)
		)
	end

	local now = os.clock()
	if now - transformDragState.lastLogAt >= TRANSFORM_DRAG_LOG_INTERVAL then
		transformDragState.lastLogAt = now
		debugLog("Transform", string.format("Rotate gizmo dragging axis=%s degrees=%.2f", tostring(transformDragState.activeAxisName), totalDegrees))
	end
end

local function getMouseDeltaFromTrackedPosition()
	local currentMousePosition = getMouseLocation()
	if not inputState.lastMousePosition then
		inputState.lastMousePosition = currentMousePosition
		return Vector2.zero
	end

	local delta = currentMousePosition - inputState.lastMousePosition
	inputState.lastMousePosition = currentMousePosition
	return delta
end

local function endTransformGizmoDrag()
	if transformDragState.mode ~= "move-gizmo" and transformDragState.mode ~= "rotate-gizmo" and transformDragState.mode ~= "scale-gizmo" then
		return
	end

	transformDragState.mode = nil
	transformDragState.activeAxisName = nil
	transformDragState.axisVector = nil
	transformDragState.pivotStart = nil
	transformDragState.rotationYawDegrees = nil
	transformDragState.rotationPitchDegrees = nil
	transformDragState.startRotationYawDegrees = nil
	transformDragState.startRotationPitchDegrees = nil
	transformDragState.startMousePosition = nil
	transformDragState.startValue = 0
	transformDragState.lastValue = 0
	transformDragState.isHandleDragging = false
	transformDragState.rotationStartVector = nil
	transformDragState.rotationStartScreenVector = nil
	transformDragState.rotationReferenceVector = nil
	transformDragState.rotationRingSlot = nil
	transformDragState.activeGizmoName = nil

	debugLog("Transform", "[TransformPipeline] Released active gizmo handle.")
	logTransformStateSnapshot("TransformGizmoUp")
end

logTransformStateSnapshot = function(context, force)
	local selectedName = selectedTransformObject and selectedTransformObject.Name or "nil"
	local selectedClass = selectedTransformObject and selectedTransformObject.ClassName or "nil"
	local moveVisible = tostring(UI.transformMoveGizmoFolder ~= nil and UI.transformMoveGizmoFolder.Parent ~= nil)
	local rotateVisible = tostring(UI.transformRotateHandles ~= nil and UI.transformRotateHandles.Parent ~= nil)
	local scaleVisible = tostring(UI.transformScaleHandles ~= nil and UI.transformScaleHandles.Parent ~= nil)
	local panelVisible = UI.transformToolGui and tostring(UI.transformToolGui.Enabled) or "nil"
	local snapshotKey = string.format(
		"selected=%s class=%s tool=%s panel=%s move=%s rotate=%s scale=%s dragging=%s mode=%s",
		selectedName,
		selectedClass,
		activeTransformTool,
		panelVisible,
		moveVisible,
		rotateVisible,
		scaleVisible,
		tostring(transformDragState.isHandleDragging),
		tostring(transformDragState.mode)
	)

	if not force and snapshotKey == lastTransformSnapshotKey then
		return
	end

	lastTransformSnapshotKey = snapshotKey

	debugLog(
		"Transform",
		string.format(
			"[%s] %s",
			context,
			snapshotKey
		)
	)
end

startMoveHandleExpectation = function(reason)
	transformDragState.expectationToken += 1
	local token = transformDragState.expectationToken

	debugLog("Transform", string.format("[MovePipeline] Stage 1 selected (%s). Waiting for move-gizmo grab...", reason))

	task.delay(0.9, function()
		if transformDragState.expectationToken ~= token then
			return
		end

		if not isBuildMode then
			return
		end

		if not selectedTransformObject then
			return
		end

		if activeTransformTool ~= "move" then
			return
		end

		if transformDragState.isHandleDragging then
			return
		end

		if not (UI.transformMoveGizmoFolder and UI.transformMoveGizmoFolder.Parent) then
			debugLog("Transform", "[MovePipeline] Warning: move tool active but move handles are not visible.")
			return
		end

		debugLog("Transform", "[MovePipeline] Warning: selected and move gizmo visible, but no grab raycast hit occurred.")
		debugLog("Transform", "[MovePipeline] This usually means the click missed gizmo parts or query filtering blocked them.")
	end)
end

updateSelectedTransformUi = function()
	if not selectedTransformObject then
		if UI.selectionHighlight then
			UI.selectionHighlight.Adornee = nil
			UI.selectionHighlight.Enabled = false
		end

		setMoveGizmoVisible(false)
		if UI.transformRotateHandles then
			UI.transformRotateHandles.Parent = nil
		end

		if UI.transformScaleHandles then
			UI.transformScaleHandles.Parent = nil
		end

		setTransformGizmosEnabled(false)
		return
	end

	if UI.selectionHighlight then
		UI.selectionHighlight.Adornee = selectedTransformObject
		UI.selectionHighlight.Enabled = true
	end

	updateMoveGizmoFromSelected()
	updateRotateGizmoFromSelected()
	updateScaleGizmoFromSelected()

	setTransformGizmosEnabled(true)
end

local function clearTransformSelection()
	selectedTransformObject = nil
	transformDragState.expectationToken += 1
	transformDragState.mode = nil
	transformDragState.activeAxisName = nil
	transformDragState.pivotStart = nil
	transformDragState.axisVector = nil
	transformDragState.startValue = 0
	transformDragState.isHandleDragging = false
	transformDragState.lastValue = 0
	updateSelectedTransformUi()
end

local function selectTransformObject(transformObject)
	if not isTransformableObject(transformObject) then
		debugLog("Transform", "selectTransformObject rejected: not transformable")
		return false
	end

	selectedTransformObject = transformObject
	updateSelectedTransformUi()
	debugLog("Transform", "Selected placed object")
	logTransformStateSnapshot("selectTransformObject")

	if activeTransformTool == "move" then
		startMoveHandleExpectation("selectTransformObject")
	end

	return true
end

local function getTransformTargetFromMouse()
	local mousePosition = getMouseLocation()
	local activeCamera = getActiveCamera()
	local unitRay = activeCamera:ViewportPointToRay(mousePosition.X, mousePosition.Y)
	local rayOrigin = unitRay.Origin
	local rayDirection = unitRay.Direction * 1000

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Blacklist
	params.IgnoreWater = true

	local blacklist = {}
	local character = localPlayer.Character
	if character then
		table.insert(blacklist, character)
	end
	if UI.placementPreview then
		table.insert(blacklist, UI.placementPreview)
	end
	if gridFolder then
		table.insert(blacklist, gridFolder)
	end
	if UI.transformMoveGizmoFolder then
		table.insert(blacklist, UI.transformMoveGizmoFolder)
	end
	if UI.transformRotateHandles then
		table.insert(blacklist, UI.transformRotateHandles)
	end
	if UI.transformScaleHandles then
		table.insert(blacklist, UI.transformScaleHandles)
	end
	params.FilterDescendantsInstances = blacklist

	local result = workspace:Raycast(rayOrigin, rayDirection, params)
	if not result then
		debugLog("Transform", "getTransformTargetFromMouse: raycast miss")
		return nil
	end

	local root = getTransformRootFromInstance(result.Instance)
	debugLog(
		"Transform",
		string.format(
			"getTransformTargetFromMouse: hit=%s root=%s",
			result.Instance and result.Instance:GetFullName() or "nil",
			root and root:GetFullName() or "nil"
		)
	)

	return root
end

scaleSelectedPart = function(axis, delta)
	debugLog("Transform", string.format("scaleSelectedPart gizmo=%s axis=%s delta=%d selected=%s", tostring(transformDragState.activeGizmoName), axis, delta, tostring(selectedTransformObject ~= nil)))

	local gizmoName = tostring(transformDragState.activeGizmoName or "")
	local handleSign = string.find(gizmoName, "Minus", 1, true) and -1 or 1
	local adjustedDelta = delta

	if not selectedTransformObject then
		debugLog("Transform", "scaleSelectedPart bailing: no selected part")
		return
	end

	if selectedTransformObject:IsA("Model") then
		scaleModelAlongAxis(selectedTransformObject, axis, adjustedDelta, handleSign)
		updateSelectedTransformUi()
		debugLog("Transform", string.format("Scaled %s axis=%s by %d", tostring(transformDragState.activeGizmoName), axis, adjustedDelta))
		return
	end

	local part = selectedTransformObject
	local size = part.Size
	local oldAxisSize
	local newAxisSize
	local axisVector
	local shape = part.Shape

	if shape == Enum.PartType.Ball then
		oldAxisSize = math.max(size.X, size.Y, size.Z)
		newAxisSize = math.max(TRANSFORM_MIN_SIZE, oldAxisSize + adjustedDelta)
		part.Size = Vector3.new(newAxisSize, newAxisSize, newAxisSize)

		if axis == "X" then
			axisVector = part.CFrame.RightVector
		elseif axis == "Y" then
			axisVector = part.CFrame.UpVector
		else
			axisVector = part.CFrame.LookVector
		end

		local appliedDelta = newAxisSize - oldAxisSize
		part.CFrame = part.CFrame + axisVector * (appliedDelta * 0.5 * handleSign)
		updateSelectedTransformUi()
		debugLog("Transform", string.format("Scaled %s axis=%s by %d", tostring(transformDragState.activeGizmoName), axis, adjustedDelta))
		return
	end

	if shape == Enum.PartType.Cylinder then
		if axis == "X" then
			oldAxisSize = size.X
			newAxisSize = math.max(TRANSFORM_MIN_SIZE, oldAxisSize + adjustedDelta)
			part.Size = Vector3.new(newAxisSize, size.Y, size.Z)
			axisVector = part.CFrame.RightVector
		else
			oldAxisSize = (size.Y + size.Z) * 0.5
			newAxisSize = math.max(TRANSFORM_MIN_SIZE, oldAxisSize + adjustedDelta)
			part.Size = Vector3.new(size.X, newAxisSize, newAxisSize)
			axisVector = axis == "Y" and part.CFrame.UpVector or part.CFrame.LookVector
		end

		local appliedDelta = newAxisSize - oldAxisSize
		part.CFrame = part.CFrame + axisVector * (appliedDelta * 0.5 * handleSign)
		updateSelectedTransformUi()
		debugLog("Transform", string.format("Scaled %s axis=%s by %d", tostring(transformDragState.activeGizmoName), axis, adjustedDelta))
		return
	end

	if axis == "X" then
		oldAxisSize = size.X
		newAxisSize = math.max(TRANSFORM_MIN_SIZE, oldAxisSize + adjustedDelta)
		part.Size = Vector3.new(newAxisSize, size.Y, size.Z)
		axisVector = part.CFrame.RightVector
	elseif axis == "Y" then
		oldAxisSize = size.Y
		newAxisSize = math.max(TRANSFORM_MIN_SIZE, oldAxisSize + adjustedDelta)
		part.Size = Vector3.new(size.X, newAxisSize, size.Z)
		axisVector = part.CFrame.UpVector
	else
		oldAxisSize = size.Z
		newAxisSize = math.max(TRANSFORM_MIN_SIZE, oldAxisSize + adjustedDelta)
		part.Size = Vector3.new(size.X, size.Y, newAxisSize)
		axisVector = part.CFrame.LookVector
	end

	local appliedDelta = newAxisSize - oldAxisSize
	part.CFrame = part.CFrame + axisVector * (appliedDelta * 0.5 * handleSign)

	updateSelectedTransformUi()
	debugLog("Transform", string.format("Scaled %s axis=%s by %d", tostring(transformDragState.activeGizmoName), axis, adjustedDelta))
end

local function copySelectedPart()
	debugLog("Transform", string.format("copySelectedPart called selected=%s", tostring(selectedTransformObject ~= nil)))

	if not selectedTransformObject then
		debugLog("Transform", "copySelectedPart bailing: no selected part")
		return
	end

	copiedTransformObject = selectedTransformObject:Clone()
	copiedTransformObject.Parent = nil
	debugLog("Transform", "Copied selected part")
end

local function deleteSelectedTransformObject()
	if not selectedTransformObject then
		return
	end

	local target = selectedTransformObject
	if not isTransformableObject(target) then
		return
	end

	if transformDragState.isHandleDragging then
		endTransformGizmoDrag()
	end

	local deletedName = target.Name
	clearTransformSelection()
	target:Destroy()
	debugLog("Transform", string.format("Deleted selected object: %s", deletedName))
end

local function getPasteTargetPosition(copiedSize)
	local mousePosition = getMouseLocation()
	local activeCamera = getActiveCamera()
	local unitRay = activeCamera:ViewportPointToRay(mousePosition.X, mousePosition.Y)
	local rayOrigin = unitRay.Origin
	local rayDirection = unitRay.Direction * 1000

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Blacklist
	params.IgnoreWater = true

	local blacklist = {}
	local character = localPlayer.Character
	if character then
		table.insert(blacklist, character)
	end
	if UI.placementPreview then
		table.insert(blacklist, UI.placementPreview)
	end
	if gridFolder then
		table.insert(blacklist, gridFolder)
	end
	params.FilterDescendantsInstances = blacklist

	local result = workspace:Raycast(rayOrigin, rayDirection, params)
	if not result then
		return nil
	end

	local halfHeight = copiedSize.Y * 0.5
	if isSnapEnabled then
		local x = math.floor(result.Position.X / GRID_SIZE) * GRID_SIZE + GRID_SIZE * 0.5
		local z = math.floor(result.Position.Z / GRID_SIZE) * GRID_SIZE + GRID_SIZE * 0.5
		local y = result.Position.Y + halfHeight
		return Vector3.new(x, y, z)
	end

	return result.Position + result.Normal * halfHeight
end

local function pasteCopiedPart()
	debugLog("Transform", string.format("pasteCopiedPart called copied=%s", tostring(copiedTransformObject ~= nil)))

	if not copiedTransformObject then
		debugLog("Transform", "pasteCopiedPart bailing: no copied part")
		return
	end

	local clone = copiedTransformObject:Clone()
	local targetPosition = getPasteTargetPosition(getTransformObjectSize(clone))
	if targetPosition then
		if clone:IsA("BasePart") then
			clone.CFrame = CFrame.new(targetPosition) * copiedTransformObject.CFrame.Rotation
		elseif clone:IsA("Model") then
			clone:PivotTo(CFrame.new(targetPosition) * copiedTransformObject:GetPivot().Rotation)
		end
	else
		local oldPivot = getTransformObjectPivot(copiedTransformObject)
		if oldPivot then
			setTransformObjectPivot(clone, oldPivot * CFrame.new(GRID_SIZE, 0, 0))
		end
	end
	clone.Parent = placedObjectsFolder or workspace
	selectTransformObject(clone)
	debugLog("Transform", "Pasted copied part")
end

local function createTransformUI()
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local existingToolGui = playerGui:FindFirstChild("TransformToolGui")
	if existingToolGui then
		existingToolGui:Destroy()
	end

	UI.transformToolGui = Instance.new("ScreenGui")
	UI.transformToolGui.Name = "TransformToolGui"
	UI.transformToolGui.ResetOnSpawn = false
	UI.transformToolGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	UI.transformToolGui.Enabled = false
	UI.transformToolGui.Parent = playerGui

	UI.transformToolPanel = Instance.new("Frame")
	UI.transformToolPanel.Name = "TransformToolPanel"
	UI.transformToolPanel.AnchorPoint = Vector2.new(0.5, 1)
	UI.transformToolPanel.Position = UDim2.new(0.5, 0, 1, -22)
	UI.transformToolPanel.Size = UDim2.fromOffset(318, 44)
	UI.transformToolPanel.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
	UI.transformToolPanel.BackgroundTransparency = 0.15
	UI.transformToolPanel.BorderSizePixel = 0
	UI.transformToolPanel.Parent = UI.transformToolGui

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 10)
	panelCorner.Parent = UI.transformToolPanel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Thickness = 1
	panelStroke.Transparency = 0.35
	panelStroke.Color = Color3.fromRGB(255, 255, 255)
	panelStroke.Parent = UI.transformToolPanel

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.Parent = UI.transformToolPanel

	local function createModeButton(name, label)
		local button = Instance.new("TextButton")
		button.Name = name
		button.Size = UDim2.fromOffset(92, 30)
		button.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
		button.BackgroundTransparency = 0.05
		button.Text = label
		button.TextColor3 = Color3.fromRGB(255, 255, 255)
		button.TextScaled = false
		button.TextSize = 14
		button.TextXAlignment = Enum.TextXAlignment.Center
		button.TextYAlignment = Enum.TextYAlignment.Center
		button.Font = Enum.Font.GothamBold
		button.AutoButtonColor = true
		button.Parent = UI.transformToolPanel

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = button

		return button
	end

	UI.moveToolButton = createModeButton("MoveButton", "MOVE")
	UI.rotateToolButton = createModeButton("RotateButton", "ROTATE")
	UI.scaleToolButton = createModeButton("ScaleButton", "SCALE")

	UI.moveToolButton.Activated:Connect(function()
		setActiveTransformTool("move")
		updateSelectedTransformUi()
		if selectedTransformObject then
			startMoveHandleExpectation("MoveButton")
		end
	end)

	UI.rotateToolButton.Activated:Connect(function()
		setActiveTransformTool("rotate")
		updateSelectedTransformUi()
	end)

	UI.scaleToolButton.Activated:Connect(function()
		setActiveTransformTool("scale")
		updateSelectedTransformUi()
	end)

	setActiveTransformTool(activeTransformTool)

	UI.selectionHighlight = Instance.new("Highlight")
	UI.selectionHighlight.Name = "TransformSelectionHighlight"
	UI.selectionHighlight.Enabled = false
	UI.selectionHighlight.FillTransparency = 1
	UI.selectionHighlight.OutlineTransparency = 0
	UI.selectionHighlight.OutlineColor = Color3.fromRGB(120, 220, 255)
	UI.selectionHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	UI.selectionHighlight.Parent = workspace

	UI.transformMoveGizmoFolder = Instance.new("Folder")
	UI.transformMoveGizmoFolder.Name = "TransformMoveGizmo"
	UI.transformMoveGizmoFolder.Parent = nil

	local function createAxisGizmoPartSet(parentFolder, name, axisName, color, length, visualThickness, hitboxThickness, visualShape, visualSize)
		local visiblePart = Instance.new("Part")
		visiblePart.Name = name
		visiblePart.Anchored = true
		visiblePart.CanCollide = false
		visiblePart.CanTouch = false
		visiblePart.CanQuery = false
		visiblePart.CastShadow = false
		visiblePart.Material = Enum.Material.Neon
		visiblePart.Color = color
		visiblePart.Transparency = 0.15
		visiblePart.Shape = visualShape or Enum.PartType.Block
		visiblePart.Size = visualSize or Vector3.new(visualThickness, visualThickness, length)
		visiblePart:SetAttribute("AxisName", axisName)
		visiblePart:SetAttribute("GizmoName", name)
		visiblePart.Parent = parentFolder

		local hitboxPart = Instance.new("Part")
		hitboxPart.Name = name .. "Hitbox"
		hitboxPart.Anchored = true
		hitboxPart.CanCollide = false
		hitboxPart.CanTouch = false
		hitboxPart.CanQuery = true
		hitboxPart.CastShadow = false
		hitboxPart.Material = Enum.Material.SmoothPlastic
		hitboxPart.Color = color
		hitboxPart.Transparency = 1
		hitboxPart.Size = Vector3.new(hitboxThickness, hitboxThickness, length)
		hitboxPart:SetAttribute("AxisName", axisName)
		hitboxPart:SetAttribute("GizmoName", name)
		hitboxPart.Parent = parentFolder

		return visiblePart, hitboxPart
	end

	createAxisGizmoPartSet(UI.transformMoveGizmoFolder, "MoveXPlus", "X", Color3.fromRGB(235, 70, 70), MOVE_GIZMO_AXIS_LENGTH, MOVE_GIZMO_AXIS_THICKNESS, MOVE_GIZMO_HITBOX_THICKNESS)
	createAxisGizmoPartSet(UI.transformMoveGizmoFolder, "MoveXMinus", "NX", Color3.fromRGB(170, 55, 55), MOVE_GIZMO_AXIS_LENGTH, MOVE_GIZMO_AXIS_THICKNESS, MOVE_GIZMO_HITBOX_THICKNESS)
	createAxisGizmoPartSet(UI.transformMoveGizmoFolder, "MoveYPlus", "Y", Color3.fromRGB(70, 220, 95), MOVE_GIZMO_AXIS_LENGTH, MOVE_GIZMO_AXIS_THICKNESS, MOVE_GIZMO_HITBOX_THICKNESS)
	createAxisGizmoPartSet(UI.transformMoveGizmoFolder, "MoveYMinus", "NY", Color3.fromRGB(55, 160, 70), MOVE_GIZMO_AXIS_LENGTH, MOVE_GIZMO_AXIS_THICKNESS, MOVE_GIZMO_HITBOX_THICKNESS)
	createAxisGizmoPartSet(UI.transformMoveGizmoFolder, "MoveZPlus", "Z", Color3.fromRGB(70, 145, 240), MOVE_GIZMO_AXIS_LENGTH, MOVE_GIZMO_AXIS_THICKNESS, MOVE_GIZMO_HITBOX_THICKNESS)
	createAxisGizmoPartSet(UI.transformMoveGizmoFolder, "MoveZMinus", "NZ", Color3.fromRGB(55, 105, 180), MOVE_GIZMO_AXIS_LENGTH, MOVE_GIZMO_AXIS_THICKNESS, MOVE_GIZMO_HITBOX_THICKNESS)

	UI.transformRotateHandles = Instance.new("Folder")
	UI.transformRotateHandles.Name = "TransformRotateGizmo"
	UI.transformRotateHandles.Parent = nil

	UI.transformScaleHandles = Instance.new("Folder")
	UI.transformScaleHandles.Name = "TransformScaleGizmo"
	UI.transformScaleHandles.Parent = nil

	local rotateSphereSize = Vector3.new(ROTATE_GIZMO_AXIS_THICKNESS * 2.5, ROTATE_GIZMO_AXIS_THICKNESS * 2.5, ROTATE_GIZMO_AXIS_THICKNESS * 2.5)
	local rotateYSlot1Visible, rotateYSlot1Hitbox = createAxisGizmoPartSet(UI.transformRotateHandles, "RotateYSlot1", "Y", Color3.fromRGB(70, 145, 240), ROTATE_GIZMO_HANDLE_LENGTH, ROTATE_GIZMO_AXIS_THICKNESS, ROTATE_GIZMO_HITBOX_THICKNESS, Enum.PartType.Ball, rotateSphereSize)
	local rotateYSlot2Visible, rotateYSlot2Hitbox = createAxisGizmoPartSet(UI.transformRotateHandles, "RotateYSlot2", "Y", Color3.fromRGB(70, 145, 240), ROTATE_GIZMO_HANDLE_LENGTH, ROTATE_GIZMO_AXIS_THICKNESS, ROTATE_GIZMO_HITBOX_THICKNESS, Enum.PartType.Ball, rotateSphereSize)
	local rotateYSlot3Visible, rotateYSlot3Hitbox = createAxisGizmoPartSet(UI.transformRotateHandles, "RotateYSlot3", "Y", Color3.fromRGB(70, 145, 240), ROTATE_GIZMO_HANDLE_LENGTH, ROTATE_GIZMO_AXIS_THICKNESS, ROTATE_GIZMO_HITBOX_THICKNESS, Enum.PartType.Ball, rotateSphereSize)
	local rotateYSlot4Visible, rotateYSlot4Hitbox = createAxisGizmoPartSet(UI.transformRotateHandles, "RotateYSlot4", "Y", Color3.fromRGB(70, 145, 240), ROTATE_GIZMO_HANDLE_LENGTH, ROTATE_GIZMO_AXIS_THICKNESS, ROTATE_GIZMO_HITBOX_THICKNESS, Enum.PartType.Ball, rotateSphereSize)
	local rotateXSlot1Visible, rotateXSlot1Hitbox = createAxisGizmoPartSet(UI.transformRotateHandles, "RotateXSlot1", "X", Color3.fromRGB(235, 70, 70), ROTATE_GIZMO_HANDLE_LENGTH, ROTATE_GIZMO_AXIS_THICKNESS, ROTATE_GIZMO_HITBOX_THICKNESS, Enum.PartType.Ball, rotateSphereSize)
	local rotateXSlot2Visible, rotateXSlot2Hitbox = createAxisGizmoPartSet(UI.transformRotateHandles, "RotateXSlot2", "X", Color3.fromRGB(235, 70, 70), ROTATE_GIZMO_HANDLE_LENGTH, ROTATE_GIZMO_AXIS_THICKNESS, ROTATE_GIZMO_HITBOX_THICKNESS, Enum.PartType.Ball, rotateSphereSize)

	rotateYSlot1Visible:SetAttribute("RingSlot", 1)
	rotateYSlot1Hitbox:SetAttribute("RingSlot", 1)
	rotateYSlot2Visible:SetAttribute("RingSlot", 2)
	rotateYSlot2Hitbox:SetAttribute("RingSlot", 2)
	rotateYSlot3Visible:SetAttribute("RingSlot", 3)
	rotateYSlot3Hitbox:SetAttribute("RingSlot", 3)
	rotateYSlot4Visible:SetAttribute("RingSlot", 4)
	rotateYSlot4Hitbox:SetAttribute("RingSlot", 4)
	rotateXSlot1Visible:SetAttribute("RingSlot", 1)
	rotateXSlot1Hitbox:SetAttribute("RingSlot", 1)
	rotateXSlot2Visible:SetAttribute("RingSlot", 2)
	rotateXSlot2Hitbox:SetAttribute("RingSlot", 2)

	createAxisGizmoPartSet(UI.transformScaleHandles, "ScaleXPlus", "X", Color3.fromRGB(255, 155, 155), SCALE_GIZMO_AXIS_LENGTH, SCALE_GIZMO_AXIS_THICKNESS, SCALE_GIZMO_HITBOX_THICKNESS, Enum.PartType.Block, Vector3.new(SCALE_GIZMO_AXIS_THICKNESS * 1.5, SCALE_GIZMO_AXIS_THICKNESS * 1.5, SCALE_GIZMO_AXIS_THICKNESS * 1.5))
	createAxisGizmoPartSet(UI.transformScaleHandles, "ScaleXMinus", "NX", Color3.fromRGB(200, 110, 110), SCALE_GIZMO_AXIS_LENGTH, SCALE_GIZMO_AXIS_THICKNESS, SCALE_GIZMO_HITBOX_THICKNESS, Enum.PartType.Block, Vector3.new(SCALE_GIZMO_AXIS_THICKNESS * 1.5, SCALE_GIZMO_AXIS_THICKNESS * 1.5, SCALE_GIZMO_AXIS_THICKNESS * 1.5))
	createAxisGizmoPartSet(UI.transformScaleHandles, "ScaleYPlus", "Y", Color3.fromRGB(150, 255, 170), SCALE_GIZMO_AXIS_LENGTH, SCALE_GIZMO_AXIS_THICKNESS, SCALE_GIZMO_HITBOX_THICKNESS, Enum.PartType.Block, Vector3.new(SCALE_GIZMO_AXIS_THICKNESS * 1.5, SCALE_GIZMO_AXIS_THICKNESS * 1.5, SCALE_GIZMO_AXIS_THICKNESS * 1.5))
	createAxisGizmoPartSet(UI.transformScaleHandles, "ScaleYMinus", "NY", Color3.fromRGB(115, 205, 130), SCALE_GIZMO_AXIS_LENGTH, SCALE_GIZMO_AXIS_THICKNESS, SCALE_GIZMO_HITBOX_THICKNESS, Enum.PartType.Block, Vector3.new(SCALE_GIZMO_AXIS_THICKNESS * 1.5, SCALE_GIZMO_AXIS_THICKNESS * 1.5, SCALE_GIZMO_AXIS_THICKNESS * 1.5))
	createAxisGizmoPartSet(UI.transformScaleHandles, "ScaleZPlus", "Z", Color3.fromRGB(155, 200, 255), SCALE_GIZMO_AXIS_LENGTH, SCALE_GIZMO_AXIS_THICKNESS, SCALE_GIZMO_HITBOX_THICKNESS, Enum.PartType.Block, Vector3.new(SCALE_GIZMO_AXIS_THICKNESS * 1.5, SCALE_GIZMO_AXIS_THICKNESS * 1.5, SCALE_GIZMO_AXIS_THICKNESS * 1.5))
	createAxisGizmoPartSet(UI.transformScaleHandles, "ScaleZMinus", "NZ", Color3.fromRGB(115, 150, 205), SCALE_GIZMO_AXIS_LENGTH, SCALE_GIZMO_AXIS_THICKNESS, SCALE_GIZMO_HITBOX_THICKNESS, Enum.PartType.Block, Vector3.new(SCALE_GIZMO_AXIS_THICKNESS * 1.5, SCALE_GIZMO_AXIS_THICKNESS * 1.5, SCALE_GIZMO_AXIS_THICKNESS * 1.5))

	updateSelectedTransformUi()
end

local function updateSnapButtonVisual()
	if not UI.snapButton then
		return
	end

	UI.snapButton.Text = isSnapEnabled and "SNAP ON" or "SNAP OFF"
	UI.snapButton.BackgroundColor3 = isSnapEnabled and Color3.fromRGB(45, 150, 80) or Color3.fromRGB(110, 40, 40)
end

local function updateGridVisibility()
	if gridFolder then
		gridFolder.Parent = isBuildMode and isGridVisible and workspace or nil
	end
end

local function updateModelsButtonVisual()
	if not UI.modelsButton then
		return
	end

	UI.modelsButton.Text = "MODEL"
	UI.modelsButton.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
end

local function updateShowGridButtonVisual()
	if not UI.showGridToggleButton then
		return
	end

	if isGridVisible then
		UI.showGridToggleButton.Text = "ON"
		UI.showGridToggleButton.BackgroundColor3 = Color3.fromRGB(45, 150, 80)
	else
		UI.showGridToggleButton.Text = "OFF"
		UI.showGridToggleButton.BackgroundColor3 = Color3.fromRGB(110, 40, 40)
	end
end

local function clearGrid()
	if gridFolder then
		gridFolder:ClearAllChildren()
	end
end

local function rebuildGrid(centerPosition)
	if not gridFolder then
		return
	end

	clearGrid()

	local baseY = centerPosition.Y + GRID_HEIGHT_OFFSET
	local half = GRID_RADIUS
	local lineColor = Color3.fromRGB(100, 100, 100)

	for x = -half, half do
		local line = Instance.new("Part")
		line.Name = "GridLineX"
		line.Anchored = true
		line.CanCollide = false
		line.CanQuery = false
		line.CanTouch = false
		line.CastShadow = false
		line.Material = Enum.Material.SmoothPlastic
		line.Color = GRID_COLOR
		line.Transparency = 0.55
		line.Size = Vector3.new(GRID_THICKNESS, GRID_THICKNESS, half * 2 * GRID_SIZE)
		line.CFrame = CFrame.new(centerPosition.X + (x * GRID_SIZE), baseY, centerPosition.Z)
		line.Parent = gridFolder
	end

	for z = -half, half do
		local line = Instance.new("Part")
		line.Name = "GridLineZ"
		line.Anchored = true
		line.CanCollide = false
		line.CanQuery = false
		line.CanTouch = false
		line.CastShadow = false
		line.Material = Enum.Material.SmoothPlastic
		line.Color = GRID_COLOR
		line.Transparency = 0.55
		line.Size = Vector3.new(half * 2 * GRID_SIZE, GRID_THICKNESS, GRID_THICKNESS)
		line.CFrame = CFrame.new(centerPosition.X, baseY, centerPosition.Z + (z * GRID_SIZE))
		line.Parent = gridFolder
	end
end

local function getGridGroundYAt(centerX, centerZ)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Blacklist
	params.IgnoreWater = true

	local blacklist = {}
	local character = localPlayer.Character
	if character then
		table.insert(blacklist, character)
	end
	if UI.placementPreview then
		table.insert(blacklist, UI.placementPreview)
	end
	if gridFolder then
		table.insert(blacklist, gridFolder)
	end
	if placedObjectsFolder then
		table.insert(blacklist, placedObjectsFolder)
	end
	params.FilterDescendantsInstances = blacklist

	local rayOrigin = Vector3.new(centerX, 2000, centerZ)
	local rayDirection = Vector3.new(0, -4000, 0)
	local result = workspace:Raycast(rayOrigin, rayDirection, params)
	if result then
		return result.Position.Y
	end

	return 0
end

local function updateGridForFocus(focusPosition)
	if not isGridVisible or not gridFolder then
		return
	end

	local centerX = math.floor(focusPosition.X / GRID_SIZE + 0.5) * GRID_SIZE
	local centerZ = math.floor(focusPosition.Z / GRID_SIZE + 0.5) * GRID_SIZE
	local centerKey = tostring(centerX) .. ":" .. tostring(centerZ)

	if centerKey == lastGridCenterKey then
		return
	end

	lastGridCenterKey = centerKey
	local groundY = getGridGroundYAt(centerX, centerZ)
	rebuildGrid(Vector3.new(centerX, groundY, centerZ))
end

local function updatePlacementCursor()
	if not UI.placementIndicator then
		return
	end

	if not (isBuildMode and isPlacementMode and ShapeCatalog.isSupported(selectedModelName)) then
		UI.placementIndicator.Visible = false
		return
	end

	UI.placementIndicator.Visible = true
	local mousePosition = getMouseLocation()
	UI.placementIndicator.Position = UDim2.fromOffset(mousePosition.X + 6, mousePosition.Y + 6)
end

local function updateModelPickerVisual()
	if not UI.modelButtons then
		return
	end

	for modelName, button in UI.modelButtons do
		if modelName == selectedModelName then
			button.BackgroundColor3 = Color3.fromRGB(60, 150, 95)
		else
			button.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
		end
	end
end

local function createGridFolder()
	local existing = workspace:FindFirstChild("BuildModeGrid")
	if existing then
		existing:Destroy()
	end

	gridFolder = Instance.new("Folder")
	gridFolder.Name = "BuildModeGrid"
	gridFolder.Parent = nil
end

local function createPlacedObjectsFolder()
	local existing = workspace:FindFirstChild("BuildPlacedObjects")
	if existing then
		existing:Destroy()
	end

	placedObjectsFolder = Instance.new("Folder")
	placedObjectsFolder.Name = "BuildPlacedObjects"
	placedObjectsFolder.Parent = workspace
end

local function addCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius
	corner.Parent = parent
	return corner
end

local function addStroke(parent, thickness, transparency, color)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness
	stroke.Transparency = transparency
	stroke.Color = color
	stroke.Parent = parent
	return stroke
end

local function createSettingsLabel(parent, name, text, position, size, isTitle)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = position
	label.Size = size
	label.Font = isTitle and Enum.Font.GothamBold or Enum.Font.Gotham
	label.TextSize = isTitle and 22 or 16
	label.TextWrapped = not isTitle
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = isTitle and Enum.TextYAlignment.Center or Enum.TextYAlignment.Top
	label.TextColor3 = isTitle and Color3.fromRGB(245, 245, 245) or Color3.fromRGB(205, 205, 205)
	label.Text = text
	label.Parent = parent
	return label
end

local function createSettingsToggleRow(parent, labelName, labelText, labelY, toggleName, toggleY)
	local label = Instance.new("TextLabel")
	label.Name = labelName
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0, 1)
	label.Position = UDim2.new(0, 16, 1, labelY)
	label.Size = UDim2.fromOffset(220, 28)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 16
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Color3.fromRGB(235, 235, 235)
	label.Text = labelText
	label.Parent = parent

	local toggle = Instance.new("TextButton")
	toggle.Name = toggleName
	toggle.AnchorPoint = Vector2.new(1, 1)
	toggle.Position = UDim2.new(1, -16, 1, toggleY)
	toggle.Size = UDim2.fromOffset(96, 30)
	toggle.Font = Enum.Font.GothamBold
	toggle.TextSize = 14
	toggle.TextColor3 = Color3.fromRGB(255, 255, 255)
	toggle.AutoButtonColor = true
	toggle.Parent = parent

	addCorner(toggle, UDim.new(0, 8))
	return toggle
end

local function createSettingsUI()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local existingGui = playerGui:FindFirstChild("BuildModeSettingsGui")
	if existingGui then
		existingGui:Destroy()
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "BuildModeSettingsGui"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	UI.settingsButton = Instance.new("TextButton")
	UI.settingsButton.Name = "SettingsButton"
	UI.settingsButton.AnchorPoint = Vector2.new(1, 1)
	UI.settingsButton.Position = UDim2.new(1, -20, 1, -20)
	UI.settingsButton.Size = UDim2.fromOffset(48, 48)
	UI.settingsButton.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	UI.settingsButton.BackgroundTransparency = 0.25
	UI.settingsButton.Text = "⚙"
	UI.settingsButton.TextColor3 = Color3.fromRGB(240, 240, 240)
	UI.settingsButton.TextScaled = false
	UI.settingsButton.TextSize = 28
	UI.settingsButton.TextXAlignment = Enum.TextXAlignment.Center
	UI.settingsButton.TextYAlignment = Enum.TextYAlignment.Center
	UI.settingsButton.Font = Enum.Font.GothamBold
	UI.settingsButton.AutoButtonColor = true
	UI.settingsButton.Visible = false
	UI.settingsButton.Parent = screenGui
	addCorner(UI.settingsButton, UDim.new(1, 0))
	addStroke(UI.settingsButton, 1, 0.3, Color3.fromRGB(255, 255, 255))

	UI.settingsPanel = Instance.new("Frame")
	UI.settingsPanel.Name = "SettingsPanel"
	UI.settingsPanel.AnchorPoint = Vector2.new(0.5, 0.5)
	UI.settingsPanel.Position = UDim2.fromScale(0.5, 0.5)
	UI.settingsPanel.Size = UDim2.fromOffset(420, 260)
	UI.settingsPanel.BackgroundColor3 = Color3.fromRGB(12, 12, 12)
	UI.settingsPanel.BackgroundTransparency = 0.25
	UI.settingsPanel.Visible = false
	UI.settingsPanel.Parent = screenGui
	addCorner(UI.settingsPanel, UDim.new(0, 12))
	addStroke(UI.settingsPanel, 1, 0.5, Color3.fromRGB(255, 255, 255))

	createSettingsLabel(UI.settingsPanel, "Title", "Build Settings", UDim2.fromOffset(16, 12), UDim2.new(1, -32, 0, 28), true)
	createSettingsLabel(UI.settingsPanel, "Subtitle", "Camera settings", UDim2.fromOffset(16, 48), UDim2.new(1, -32, 0, 24), false)

	UI.showGridToggleButton = createSettingsToggleRow(UI.settingsPanel, "ShowGridLabel", "Show Grid", -62, "ShowGridToggle", -62)

	updateShowGridButtonVisual()

	UI.showGridToggleButton.Activated:Connect(function()
		if not isBuildMode then
			return
		end

		isGridVisible = not isGridVisible
		updateShowGridButtonVisual()
		updateGridVisibility()
	end)

	UI.invertedToggleButton = createSettingsToggleRow(UI.settingsPanel, "InvertedLabel", "Main camera profile", -20, "InvertedToggle", -20)

	local function refreshInvertedToggleVisual()
		if not UI.invertedToggleButton then
			return
		end

		if isInvertedCamera then
			UI.invertedToggleButton.Text = "ON"
			UI.invertedToggleButton.BackgroundColor3 = Color3.fromRGB(45, 150, 80)
		else
			UI.invertedToggleButton.Text = "OFF"
			UI.invertedToggleButton.BackgroundColor3 = Color3.fromRGB(110, 40, 40)
		end
	end

	refreshInvertedToggleVisual()

	UI.invertedToggleButton.Activated:Connect(function()
		if not isBuildMode then
			return
		end

		isInvertedCamera = not isInvertedCamera
		refreshInvertedToggleVisual()
	end)

	UI.settingsButton.Activated:Connect(function()
		if not isBuildMode then
			return
		end

		UI.settingsPanel.Visible = not UI.settingsPanel.Visible
	end)
end

local function createBuildButton(parent, name, position, backgroundColor)
	local button = Instance.new("TextButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(1, 1)
	button.Position = position
	button.Size = UDim2.fromOffset(62, 48)
	button.BackgroundColor3 = backgroundColor
	button.BackgroundTransparency = 0.1
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.TextScaled = false
	button.TextSize = 16
	button.TextXAlignment = Enum.TextXAlignment.Center
	button.TextYAlignment = Enum.TextYAlignment.Center
	button.Font = Enum.Font.GothamBold
	button.Visible = false
	button.Parent = parent
	addCorner(button, UDim.new(0, 10))
	addStroke(button, 1, 0.3, Color3.fromRGB(255, 255, 255))
	return button
end

local function createModelsPanel(parent)
	local panel = Instance.new("Frame")
	panel.Name = "ModelsPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(680, 860)
	panel.BackgroundColor3 = Color3.fromRGB(12, 12, 12)
	panel.BackgroundTransparency = 0.25
	panel.Visible = false
	panel.Parent = parent
	addCorner(panel, UDim.new(0, 12))
	addStroke(panel, 1, 0.5, Color3.fromRGB(255, 255, 255))

	local GRID_COLUMNS = 4
	local GRID_VISIBLE_ROWS = 5
	local GRID_PADDING = 8
	local GRID_CELL_WIDTH = 152
	local GRID_CELL_HEIGHT = 122

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(16, 12)
	title.Size = UDim2.new(1, -32, 0, 28)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 22
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(245, 245, 245)
	title.Text = "Build Models"
	title.Parent = panel

	local gridHeight = GRID_VISIBLE_ROWS * GRID_CELL_HEIGHT + (GRID_VISIBLE_ROWS - 1) * GRID_PADDING

	local modelGrid = Instance.new("ScrollingFrame")
	modelGrid.Name = "ModelGrid"
	modelGrid.Position = UDim2.fromOffset(16, 52)
	modelGrid.Size = UDim2.new(1, -32, 0, gridHeight)
	modelGrid.BackgroundTransparency = 1
	modelGrid.BorderSizePixel = 0
	modelGrid.ScrollBarImageColor3 = Color3.fromRGB(180, 180, 180)
	modelGrid.ScrollBarThickness = 8
	modelGrid.CanvasSize = UDim2.fromOffset(0, 0)
	modelGrid.AutomaticCanvasSize = Enum.AutomaticSize.None
	modelGrid.ScrollingDirection = Enum.ScrollingDirection.Y
	modelGrid.Parent = panel

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromOffset(GRID_CELL_WIDTH, GRID_CELL_HEIGHT)
	gridLayout.CellPadding = UDim2.fromOffset(GRID_PADDING, GRID_PADDING)
	gridLayout.FillDirection = Enum.FillDirection.Horizontal
	gridLayout.FillDirectionMaxCells = GRID_COLUMNS
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	gridLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	gridLayout.Parent = modelGrid

	gridLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		modelGrid.CanvasSize = UDim2.fromOffset(0, math.max(gridHeight, gridLayout.AbsoluteContentSize.Y))
	end)

	UI.modelButtons = {}

	local function createModelButton(modelDefinition)
		local modelName = modelDefinition.name
		local button = Instance.new("TextButton")
		button.Name = modelName .. "Button"
		button.Size = UDim2.fromOffset(GRID_CELL_WIDTH, GRID_CELL_HEIGHT)
		button.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
		button.BackgroundTransparency = 0.1
		button.TextColor3 = Color3.fromRGB(255, 255, 255)
		button.Text = ""
		button.TextTransparency = 1
		button.Font = Enum.Font.GothamBold
		button.Parent = modelGrid
		addCorner(button, UDim.new(0, 10))
		addStroke(button, 1, 0.3, Color3.fromRGB(255, 255, 255))

		local viewport = Instance.new("ViewportFrame")
		viewport.Name = modelName .. "Preview"
		viewport.BackgroundTransparency = 1
		viewport.BorderSizePixel = 0
		viewport.Position = UDim2.fromOffset(10, 10)
		viewport.Size = UDim2.new(1, -20, 1, -20)
		viewport.Ambient = Color3.fromRGB(235, 235, 235)
		viewport.LightDirection = Vector3.new(-0.3, -1, -0.6)
		viewport.Parent = button

		local worldModel = Instance.new("WorldModel")
		worldModel.Parent = viewport

		local previewCamera = Instance.new("Camera")
		previewCamera.FieldOfView = 30
		previewCamera.CFrame = CFrame.new(Vector3.new(3.7, 2.7, 3.7), Vector3.new(0, 0, 0))
		previewCamera.Parent = viewport
		viewport.CurrentCamera = previewCamera

		local templateModel = getTemplateModelByName(modelName)
		if templateModel then
			local previewTemplate = templateModel:Clone()
			previewTemplate.Parent = worldModel

			for _, descendant in previewTemplate:GetDescendants() do
				if descendant:IsA("BasePart") then
					descendant.Anchored = true
					descendant.CanCollide = false
					descendant.CanTouch = false
					descendant.CanQuery = false
				end
			end

			if previewTemplate:IsA("Model") then
				local orientation = modelDefinition.previewOrientation or Vector3.new(18, 35, 0)
				previewTemplate:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(math.rad(orientation.X), math.rad(orientation.Y), math.rad(orientation.Z)))
				local boxCFrame, boxSize = previewTemplate:GetBoundingBox()
				local radius = math.max(boxSize.X, boxSize.Y, boxSize.Z) * 0.6
				local distance = radius / math.tan(math.rad(previewCamera.FieldOfView * 0.5)) + radius
				previewCamera.CFrame = CFrame.new(boxCFrame.Position + Vector3.new(distance * 0.8, distance * 0.55, distance * 0.8), boxCFrame.Position)
			elseif previewTemplate:IsA("BasePart") then
				previewTemplate.Orientation = modelDefinition.previewOrientation or Vector3.new(18, 35, 0)
			end
		else
			local previewPart = Instance.new("Part")
			previewPart.Name = modelName
			previewPart.Anchored = true
			previewPart.Shape = modelDefinition.shape
			previewPart.Size = Vector3.new(2, 2, 2)
			previewPart.Material = Enum.Material.SmoothPlastic
			previewPart.Color = Color3.fromRGB(230, 234, 242)
			previewPart.Orientation = modelDefinition.previewOrientation
			previewPart.TopSurface = Enum.SurfaceType.Smooth
			previewPart.BottomSurface = Enum.SurfaceType.Smooth
			previewPart.Parent = worldModel
		end

		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 0)
		label.Position = UDim2.new(0.5, 0, 1, 4)
		label.Size = UDim2.fromOffset(132, 18)
		label.Font = Enum.Font.GothamSemibold
		label.TextSize = 12
		label.TextColor3 = Color3.fromRGB(220, 220, 220)
		label.TextWrapped = true
		label.Text = modelName
		label.Parent = button

		button.Activated:Connect(function()
			if not isBuildMode then
				return
			end

			selectedModelName = modelName
			updateModelPickerVisual()
			setPlacementMode(true)
			UI.modelsPanel.Visible = false
		end)

		UI.modelButtons[modelName] = button
	end

	for index, modelName in ShapeCatalog.Order do
		local modelDefinition = ShapeCatalog.getDefinition(modelName)
		if modelDefinition then
			createModelButton(modelDefinition)
		end
	end

	modelGrid.CanvasSize = UDim2.fromOffset(0, math.max(gridHeight, gridLayout.AbsoluteContentSize.Y))

	local description = Instance.new("TextLabel")
	description.BackgroundTransparency = 1
	description.Position = UDim2.fromOffset(16, 52 + gridHeight + 16)
	description.Size = UDim2.new(1, -32, 0, 120)
	description.Font = Enum.Font.Gotham
	description.TextSize = 14
	description.TextWrapped = true
	description.TextXAlignment = Enum.TextXAlignment.Left
	description.TextYAlignment = Enum.TextYAlignment.Top
	description.TextColor3 = Color3.fromRGB(205, 205, 205)
	description.Text = "Select a shape to place. Cube, sphere, and cylinder all use the same snap and transform workflow."
	description.Parent = panel

	return panel
end

local function createBuildUI()
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local existingGui = playerGui:FindFirstChild("BuildModeExtrasGui")
	if existingGui then
		existingGui:Destroy()
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "BuildModeExtrasGui"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	UI.snapButton = createBuildButton(screenGui, "SnapButton", UDim2.new(1, -76, 1, -20), Color3.fromRGB(45, 150, 80))
	UI.modelsButton = createBuildButton(screenGui, "ModelsButton", UDim2.new(1, -148, 1, -20), Color3.fromRGB(35, 35, 35))
	UI.modelsPanel = createModelsPanel(screenGui)

	updateSnapButtonVisual()
	updateModelsButtonVisual()
	updateModelPickerVisual()

	UI.snapButton.Activated:Connect(function()
		if not isBuildMode then
			return
		end

		isSnapEnabled = not isSnapEnabled
		updateSnapButtonVisual()
	end)

	UI.modelsButton.Activated:Connect(function()
		if not isBuildMode then
			return
		end

		UI.modelsPanel.Visible = not UI.modelsPanel.Visible
	end)

end

createSettingsUI()
createBuildUI()
createTransformUI()
createGridFolder()
createPlacedObjectsFolder()
createPlacementIndicator()
createPlacementPreview()

local function setBuildMode(enabled)
	debugLog("Mode", string.format("setBuildMode requested enabled=%s", tostring(enabled)))

	if enabled == isBuildMode then
		debugLog("Mode", "setBuildMode ignored because requested state already active")
		return
	end

	isBuildMode = enabled

	if isBuildMode then
		debugLog("Mode", "Entering build mode")

		local activeCamera = getActiveCamera()
		previousCameraType = activeCamera.CameraType
		previousCameraSubject = activeCamera.CameraSubject
		previousCameraMode = localPlayer.CameraMode
		previousMouseBehavior = UserInputService.MouseBehavior
		activeCamera.CameraType = Enum.CameraType.Scriptable
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		inputState.lastMousePosition = nil
		setCharacterBuildLock(true)
		setControlsEnabled(false)

		local rootPart = getRootPart()
		if rootPart then
			focusPoint = rootPart.Position
		end

		if UI.settingsButton then
			UI.settingsButton.Visible = true
		end

		if UI.transformToolGui then
			UI.transformToolGui.Enabled = true
		end

		if UI.snapButton then
			UI.snapButton.Visible = true
		end

		if UI.modelsButton then
			UI.modelsButton.Visible = true
		end

		updatePlacementIndicatorVisible()
		setOrientationMarkersVisible(true)
		updatePlacementCursor()
		updateGridVisibility()
		debugLog("Mode", "Build mode enabled and camera switched to scriptable")

		print("[BuildMode] Enabled")
	else
		debugLog("Mode", "Exiting build mode")

		inputState.isRightMouseRotating = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		transformDragState.mode = nil
		transformDragState.activeAxisName = nil
		transformDragState.startValue = 0
		transformDragState.lastValue = 0
		transformDragState.isHandleDragging = false
		clearTransformSelection()

		if UI.settingsPanel then
			UI.settingsPanel.Visible = false
		end

		if UI.settingsButton then
			UI.settingsButton.Visible = false
		end

		if UI.snapButton then
			UI.snapButton.Visible = false
		end

		if UI.modelsButton then
			UI.modelsButton.Visible = false
		end

		if UI.modelsPanel then
			UI.modelsPanel.Visible = false
		end

		if UI.transformToolGui then
			UI.transformToolGui.Enabled = false
		end

		setPlacementMode(false)
		setOrientationMarkersVisible(false)

		updateGridVisibility()
		setCharacterBuildLock(false)
		setControlsEnabled(true)
		restoreNormalGameplayState()

		-- Re-apply once on next frame for a clean handoff to default camera.
		task.defer(restoreNormalGameplayState)
		debugLog("Mode", "Build mode disabled and gameplay restored")

		print("[BuildMode] Disabled")
	end
end

local function forceDisableBuildState()
	debugLog("ForceDisable", "Forcing full cleanup without relying on build-mode transition")

	isBuildMode = false
	inputState.isRightMouseRotating = false
	transformDragState.mode = nil
	transformDragState.activeAxisName = nil
	transformDragState.startValue = 0
	transformDragState.lastValue = 0
	transformDragState.isHandleDragging = false
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default

	if UI.settingsPanel then
		UI.settingsPanel.Visible = false
	end

	if UI.settingsButton then
		UI.settingsButton.Visible = false
	end

	if UI.snapButton then
		UI.snapButton.Visible = false
	end

	if UI.modelsButton then
		UI.modelsButton.Visible = false
	end

	if UI.modelsPanel then
		UI.modelsPanel.Visible = false
	end

	setPlacementMode(false)
	updateGridVisibility()
	setCharacterBuildLock(false)
	setControlsEnabled(true)
	restoreNormalGameplayState()
	task.defer(restoreNormalGameplayState)

	debugLog("ForceDisable", "Forced cleanup complete")
end

local function setScriptEnabled(enabled)
	debugLog("ScriptToggle", string.format("setScriptEnabled requested enabled=%s", tostring(enabled)))

	if enabled == isScriptEnabled then
		debugLog("ScriptToggle", "Ignored because script enable state already matches request")
		return
	end

	isScriptEnabled = enabled
	if isScriptEnabled then
		setBuildMode(true)
	else
		if isBuildMode then
			setBuildMode(false)
		else
			forceDisableBuildState()
		end
	end

	debugLog("ScriptToggle", "Script toggle request applied")

	if isScriptEnabled then
		print("[BuildMode] Script Enabled")
	else
		print("[BuildMode] Script Disabled")
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if input.KeyCode == TOGGLE_KEY then
		debugLog("Input", string.format("Toggle key pressed gameProcessed=%s focusedTextBox=%s", tostring(gameProcessed), tostring(UserInputService:GetFocusedTextBox() ~= nil)))

		if not UserInputService:GetFocusedTextBox() then
			setScriptEnabled(not isScriptEnabled)
		end
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton2 and isBuildMode then
		inputState.isRightMouseRotating = true
		inputState.lastMousePosition = getMouseLocation()
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		debugLog("Input", "Right mouse drag rotation started")
		return
	end

	if input.KeyCode == Enum.KeyCode.V then
		local isCtrlDown = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
		if isCtrlDown and not UserInputService:GetFocusedTextBox() then
			debugLog("Input", "Ctrl+V paste requested")
			if isBuildMode then
				pasteCopiedPart()
			end
			return
		end
	end

	if input.KeyCode == Enum.KeyCode.C then
		local isCtrlDown = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
		if isCtrlDown and not UserInputService:GetFocusedTextBox() then
			if isBuildMode then
				copySelectedPart()
			end
			return
		end
	end

	if input.KeyCode == Enum.KeyCode.Delete and not UserInputService:GetFocusedTextBox() then
		if isBuildMode then
			deleteSelectedTransformObject()
		end
		return
	end

	if input.KeyCode == Enum.KeyCode.F6 and not UserInputService:GetFocusedTextBox() then
		logTransformStateSnapshot("F6", true)
		return
	end

	if gameProcessed then
		return
	end

	if not isBuildMode then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		debugLog("Input", "Left click world interaction")

		if transformDragState.isHandleDragging then
			return
		end

		if isPlacementMode then
			placeSelectedModel()
		else
			if selectedTransformObject and tryBeginTransformGizmoDrag() then
				return
			end

			local targetObject = getTransformTargetFromMouse()
			if targetObject then
				selectTransformObject(targetObject)
			end
		end
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if not isBuildMode then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 and transformDragState.isHandleDragging then
		endTransformGizmoDrag()
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		inputState.isRightMouseRotating = false
		inputState.lastMousePosition = nil
		UserInputService.MouseBehavior = previousMouseBehavior
		debugLog("Input", "Right mouse drag rotation ended")
	end
end)

UserInputService.InputChanged:Connect(function(input, gameProcessed)
	if not isBuildMode then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseWheel then
		targetZoom = math.clamp(targetZoom - input.Position.Z * ZOOM_STEP, MIN_ZOOM, MAX_ZOOM)
		debugLog("Input", string.format("Mouse wheel zoom updated targetZoom=%.2f", targetZoom))
	elseif input.UserInputType == Enum.UserInputType.MouseMovement and transformDragState.mode == "move-gizmo" and transformDragState.isHandleDragging then
		updateMoveGizmoDrag()
	elseif input.UserInputType == Enum.UserInputType.MouseMovement and transformDragState.mode == "scale-gizmo" and transformDragState.isHandleDragging then
		updateScaleGizmoDrag()
	elseif input.UserInputType == Enum.UserInputType.MouseMovement and transformDragState.mode == "rotate-gizmo" and transformDragState.isHandleDragging then
		local mouseDelta = getMouseDeltaFromTrackedPosition()
		debugLog("Transform", string.format("Rotate tracked mouse delta=(%.2f, %.2f)", mouseDelta.X, mouseDelta.Y))
		updateRotateGizmoDrag(mouseDelta)
	end
end)

RunService.RenderStepped:Connect(function(dt)
	if not isBuildMode then
		return
	end

	currentZoom = lerpExp(currentZoom, targetZoom, CAMERA_RESPONSE, dt)

	if inputState.isRightMouseRotating then
		local mouseDelta = UserInputService:GetMouseDelta()
		targetYaw -= mouseDelta.X * ROTATE_DRAG_SENSITIVITY
		debugLog("Input", string.format("Right mouse rotate held delta=(%.2f, %.2f) targetYaw=%.2f", mouseDelta.X, mouseDelta.Y, targetYaw))
	end

	local yawDelta = shortestAngleDeltaDegrees(currentYaw, targetYaw)
	currentYaw = currentYaw + yawDelta * (1 - math.exp(-YAW_RESPONSE * dt))

	local panInput = getPanInputVector()
	if panInput.Magnitude > 0 then
		local yawFrame = CFrame.Angles(0, math.rad(currentYaw), 0)
		local flatForward = Vector3.new(yawFrame.LookVector.X, 0, yawFrame.LookVector.Z)
		local flatRight = Vector3.new(yawFrame.RightVector.X, 0, yawFrame.RightVector.Z)

		local panSpeed = PAN_BASE_SPEED + currentZoom * PAN_ZOOM_MULTIPLIER
		local worldMove = (flatRight * panInput.X + flatForward * panInput.Y) * panSpeed * dt
		focusPoint += worldMove
	end

	local blend = getCurveAlpha(currentZoom)
	local pitch
	if isInvertedCamera then
		pitch = TOP_DOWN_PITCH + (NORMAL_PITCH - TOP_DOWN_PITCH) * blend
	else
		local invertedBlend = 1 - blend
		local easedInvertedBlend = invertedBlend ^ INVERTED_CURVE_POWER
		pitch = TOP_DOWN_PITCH + (INVERTED_CLOSE_PITCH - TOP_DOWN_PITCH) * easedInvertedBlend
	end


	local orbitRotation = CFrame.Angles(0, math.rad(currentYaw), 0) * CFrame.Angles(math.rad(pitch), 0, 0)
	local activeCamera = getActiveCamera()
	activeCamera.CFrame = CFrame.new(focusPoint) * orbitRotation * CFrame.new(0, 0, currentZoom)
	activeCamera.Focus = CFrame.new(focusPoint)

	if isBuildMode and isGridVisible then
		if not gridFolder.Parent then
			gridFolder.Parent = workspace
		end
		updateGridForFocus(focusPoint)
	else
		if gridFolder.Parent then
			gridFolder.Parent = nil
		end
		lastGridCenterKey = nil
	end

	updatePlacementCursor()

	if UI.placementPreview and isBuildMode and isPlacementMode and ShapeCatalog.isSupported(selectedModelName) then
		local targetPosition = getPlacementTarget()
		updatePlacementPreview(targetPosition)
	elseif UI.placementPreview then
		setPlacementPreviewVisible(false)
	end

	if selectedTransformObject and not selectedTransformObject.Parent then
		clearTransformSelection()
	elseif selectedTransformObject then
		updateSelectedTransformUi()
	end

	local now = os.clock()
	if DEBUG_ENABLED and now - lastRenderDebugAt >= RENDER_DEBUG_INTERVAL then
		lastRenderDebugAt = now
		debugLog(
			"Render",
			string.format(
				"zoom=%.2f targetZoom=%.2f yaw=%.2f targetYaw=%.2f focus=(%.1f, %.1f, %.1f)",
				currentZoom,
				targetZoom,
				currentYaw,
				targetYaw,
				focusPoint.X,
				focusPoint.Y,
				focusPoint.Z
			)
		)
	end
end)
