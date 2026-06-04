local BuildShapeCatalog = {}

local DEFAULT_SHAPE = Enum.PartType.Block
local DEFAULT_PREVIEW_ORIENTATION = Vector3.new(18, 35, 0)
local TEMPLATE_FOLDER_NAME = "BuildingModels"

local ORDER = {}
local DEFINITIONS = {}

-- Manual entries for primitive/native part types.
-- Add only non-template shapes here.
local CATALOG_ENTRIES = {
	{ name = "Cube", shape = Enum.PartType.Block, previewOrientation = Vector3.new(18, 35, 0) },
	{ name = "Sphere", shape = Enum.PartType.Ball, previewOrientation = Vector3.new(0, 35, 0) },
	{ name = "Cylinder", shape = Enum.PartType.Cylinder, previewOrientation = Vector3.new(90, 35, 0) },
}

-- Optional per-template overrides for discovered models.
-- Key is model name in Shared/BuildingModels.
local TEMPLATE_OVERRIDES = {
	["Classic Rock"] = {
		previewOrientation = Vector3.new(12, 35, 0),
	},
}

local function register(entry, allowReplace)
	if typeof(entry) ~= "table" then
		error("BuildShapeCatalog entry must be a table")
	end

	local name = entry.name
	if typeof(name) ~= "string" or name == "" then
		error("BuildShapeCatalog entry is missing a valid name")
	end

	if DEFINITIONS[name] and not allowReplace then
		error("BuildShapeCatalog has duplicate model name: " .. name)
	end

	local definition = {
		name = name,
		shape = entry.shape or DEFAULT_SHAPE,
		templateName = entry.templateName,
		previewOrientation = entry.previewOrientation or DEFAULT_PREVIEW_ORIENTATION,
	}

	if DEFINITIONS[name] then
		DEFINITIONS[name] = definition
		return
	end

	DEFINITIONS[name] = definition
	table.insert(ORDER, name)
end

for _, entry in CATALOG_ENTRIES do
	register(entry)
end

local function registerTemplateEntriesFromFolder()
	local replicatedStorage = game:GetService("ReplicatedStorage")
	local sharedFolder = replicatedStorage:FindFirstChild("Shared")
	if not sharedFolder then
		return
	end

	local templatesFolder = sharedFolder:FindFirstChild(TEMPLATE_FOLDER_NAME)
	if not templatesFolder or not templatesFolder:IsA("Folder") then
		return
	end

	local discoveredNames = {}
	for _, child in templatesFolder:GetChildren() do
		if child:IsA("Model") or child:IsA("BasePart") then
			table.insert(discoveredNames, child.Name)
		end
	end

	table.sort(discoveredNames)

	for _, name in discoveredNames do
		local override = TEMPLATE_OVERRIDES[name] or {}
		register({
			name = name,
			templateName = name,
			previewOrientation = override.previewOrientation,
		}, true)
	end
end

registerTemplateEntriesFromFolder()

function BuildShapeCatalog.isSupported(modelName)
	return DEFINITIONS[modelName] ~= nil
end

function BuildShapeCatalog.getShape(modelName)
	local definition = DEFINITIONS[modelName]
	if definition then
		return definition.shape
	end

	return DEFAULT_SHAPE
end

function BuildShapeCatalog.getDefinition(modelName)
	return DEFINITIONS[modelName]
end

function BuildShapeCatalog.getTemplateName(modelName)
	local definition = DEFINITIONS[modelName]
	if definition then
		return definition.templateName
	end

	return nil
end

BuildShapeCatalog.Order = ORDER

return BuildShapeCatalog
