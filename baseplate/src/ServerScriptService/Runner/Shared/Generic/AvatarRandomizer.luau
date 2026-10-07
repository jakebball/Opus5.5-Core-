local RunService = game:GetService("RunService")
local AvatarEditorService = game:GetService("AvatarEditorService")

local Assets = require(script.Parent.Assets)

local AvatarRandomizer = {}

const IS_SERVER = RunService:IsServer()
const POOL_SIZE = 30
const POOL_FOLDER_NAME = "AvatarRandomizerPool"
const STAGING_FOLDER_NAME = "AvatarRandomizerStaging"
const TEMPLATE_ASSET_PATH = "Models/BaseRig"
const SEARCH_THROTTLE = 0.2
const WARM_BATCH_SIZE = 5
const WARM_FAILURE_LIMIT = 3
const CATALOG_WAIT_TIMEOUT = 20
const NAME_ATTRIBUTE = "FakeName"
const NAME_ATTEMPTS = 25
const NAME_NUMBER_CHANCE = 0.7
const NAME_UNDERSCORE_CHANCE = 0.15

const WARDROBE = {
	{
		field = "Shirt",
		numeric = true,
		chance = 1,
		assetType = Enum.AvatarAssetType.Shirt,
		keywords = { "shirt", "hoodie", "jacket", "tactical", "camo", "streetwear" },
	},
	{
		field = "Pants",
		numeric = true,
		chance = 1,
		assetType = Enum.AvatarAssetType.Pants,
		keywords = { "pants", "jeans", "cargo pants", "joggers", "camo pants" },
	},
	{
		field = "HairAccessory",
		numeric = false,
		chance = 0.9,
		assetType = Enum.AvatarAssetType.HairAccessory,
		keywords = { "hair", "messy hair", "long hair", "curly hair", "buzzcut" },
	},
	{
		field = "HatAccessory",
		numeric = false,
		chance = 0.55,
		assetType = Enum.AvatarAssetType.Hat,
		keywords = { "cap", "helmet", "beanie", "headphones", "bandana" },
	},
	{
		field = "FaceAccessory",
		numeric = false,
		chance = 0.3,
		assetType = Enum.AvatarAssetType.FaceAccessory,
		keywords = { "glasses", "sunglasses", "mask" },
	},
	{
		field = "BackAccessory",
		numeric = false,
		chance = 0.3,
		assetType = Enum.AvatarAssetType.BackAccessory,
		keywords = { "backpack", "wings", "cape" },
	},
}

const SKIN_TONES = {
	Color3.fromRGB(255, 204, 153),
	Color3.fromRGB(245, 225, 200),
	Color3.fromRGB(234, 184, 146),
	Color3.fromRGB(214, 178, 140),
	Color3.fromRGB(204, 142, 105),
	Color3.fromRGB(163, 106, 74),
	Color3.fromRGB(120, 78, 55),
	Color3.fromRGB(80, 52, 38),
}

const NAME_PREFIXES = {
	"Swift", "Dark", "Iron", "Crimson", "Silent", "Rapid", "Frost", "Shadow", "Turbo", "Neon",
	"Rogue", "Blitz", "Savage", "Lunar", "Toxic", "Prime", "Epic", "Wild", "Grim", "Vex",
	"Nova", "Cyber", "Ghost", "Steel", "Atomic", "Rusty", "Sneaky", "Mega", "Hyper", "Zesty",
}

const NAME_NOUNS = {
	"Falcon", "Raptor", "Wolf", "Viper", "Bandit", "Sniper", "Ranger", "Comet", "Reaper", "Panda",
	"Nugget", "Goblin", "Phantom", "Tiger", "Pilot", "Wizard", "Knight", "Racer", "Hunter", "Yeti",
	"Otter", "Muffin", "Sergeant", "Cactus", "Waffle", "Dragon", "Bolt", "Jester", "Titan", "Moose",
}

local catalogPools = {}
local catalogReady = false
local usedNames = {}
local warming = false
local rng = Random.new()

local function serverFolder(folderName)
	local ServerStorage = game:GetService("ServerStorage")
	local folder = ServerStorage:FindFirstChild(folderName)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = folderName
		folder.Parent = ServerStorage
	end
	return folder
end

local function poolFolder()
	return serverFolder(POOL_FOLDER_NAME)
end

local function stagingFolder()
	return serverFolder(STAGING_FOLDER_NAME)
end

local function searchCatalog(keyword, assetType)
	local params = CatalogSearchParams.new()
	params.SearchKeyword = keyword
	params.AssetTypes = { assetType }

	local searched, pages = pcall(function()
		return AvatarEditorService:SearchCatalog(params)
	end)
	if not searched then
		warn("AvatarRandomizer: catalog search failed for '" .. keyword .. "' - " .. tostring(pages))
		return {}
	end

	local paged, page = pcall(function()
		return pages:GetCurrentPage()
	end)
	if not paged then
		return {}
	end

	local ids = {}
	for _, entry in page do
		table.insert(ids, entry.Id)
	end
	return ids
end

local function fetchCatalogPools()
	for _, slot in WARDROBE do
		local ids = {}
		local seen = {}
		for _, keyword in slot.keywords do
			for _, assetId in searchCatalog(keyword, slot.assetType) do
				if not seen[assetId] then
					seen[assetId] = true
					table.insert(ids, assetId)
				end
			end
			task.wait(SEARCH_THROTTLE)
		end
		catalogPools[slot.field] = ids
	end
	catalogReady = true
end

local function pickId(field)
	local ids = catalogPools[field]
	if not ids or #ids == 0 then
		return nil
	end
	return ids[rng:NextInteger(1, #ids)]
end

local function prepareClone(template)
	local clone = template:Clone()
	clone:SetAttribute("ComponentRemoteId", nil)
	for _, tag in clone:GetTags() do
		clone:RemoveTag(tag)
	end
	for _, descendant in clone:GetDescendants() do
		descendant:SetAttribute("ComponentRemoteId", nil)
		for _, tag in descendant:GetTags() do
			descendant:RemoveTag(tag)
		end
	end
	return clone
end

local function stripWardrobe(rig)
	for _, child in rig:GetChildren() do
		if child:IsA("Accessory") or child:IsA("Shirt") or child:IsA("Pants")
			or child:IsA("ShirtGraphic") or child:IsA("BodyColors") then
			child:Destroy()
		end
	end
end

local function buildDescription(supportsScaling)
	local description = Instance.new("HumanoidDescription")

	local skin = SKIN_TONES[rng:NextInteger(1, #SKIN_TONES)]
	description.HeadColor = skin
	description.TorsoColor = skin
	description.LeftArmColor = skin
	description.RightArmColor = skin
	description.LeftLegColor = skin
	description.RightLegColor = skin

	for _, slot in WARDROBE do
		if rng:NextNumber() <= slot.chance then
			local assetId = pickId(slot.field)
			if assetId then
				description[slot.field] = if slot.numeric then assetId else tostring(assetId)
			end
		end
	end

	if supportsScaling then
		description.HeightScale = rng:NextNumber(0.94, 1.06)
		description.WidthScale = rng:NextNumber(0.9, 1.08)
		description.HeadScale = rng:NextNumber(0.92, 1.06)
		description.DepthScale = rng:NextNumber(0.92, 1.06)
		description.BodyTypeScale = rng:NextNumber(0, 0.6)
		description.ProportionScale = rng:NextNumber(0, 1)
	end

	return description
end

local function awaitCatalog()
	if catalogReady then
		return true
	end
	local deadline = os.clock() + CATALOG_WAIT_TIMEOUT
	while not catalogReady and os.clock() < deadline do
		task.wait(0.1)
	end
	return catalogReady
end

function AvatarRandomizer.randomName()
	for attempt = 1, NAME_ATTEMPTS do
		local prefix = NAME_PREFIXES[rng:NextInteger(1, #NAME_PREFIXES)]
		local noun = NAME_NOUNS[rng:NextInteger(1, #NAME_NOUNS)]
		local separator = if rng:NextNumber() < NAME_UNDERSCORE_CHANCE then "_" else ""
		local candidate = prefix .. separator .. noun
		if rng:NextNumber() < NAME_NUMBER_CHANCE then
			candidate ..= tostring(rng:NextInteger(1, 9999))
		end
		if not usedNames[candidate] then
			usedNames[candidate] = true
			return candidate
		end
	end

	local fallback = NAME_NOUNS[rng:NextInteger(1, #NAME_NOUNS)] .. tostring(rng:NextInteger(10000, 999999))
	usedNames[fallback] = true
	return fallback
end

function AvatarRandomizer.dress(rig)
	if not rig or not rig:IsA("Model") then
		warn("AvatarRandomizer.dress expected a Model, got " .. tostring(rig))
		return nil
	end

	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn("AvatarRandomizer.dress: '" .. rig.Name .. "' has no Humanoid")
		return nil
	end

	awaitCatalog()
	stripWardrobe(rig)

	local detached = rig.Parent == nil
	if detached and IS_SERVER then
		rig.Parent = stagingFolder()
	end

	local description = buildDescription(humanoid.RigType == Enum.HumanoidRigType.R15)
	local applied, applyError = pcall(function()
		humanoid:ApplyDescription(description)
	end)

	if detached and rig.Parent then
		rig.Parent = nil
	end

	if not applied then
		warn("AvatarRandomizer.dress: ApplyDescription failed on '" .. rig.Name .. "' - " .. tostring(applyError))
		return nil
	end

	local fakeName = AvatarRandomizer.randomName()
	rig:SetAttribute(NAME_ATTRIBUTE, fakeName)
	return fakeName
end

function AvatarRandomizer.warm(count)
	if not IS_SERVER or warming then
		return
	end
	warming = true

	if not awaitCatalog() then
		warn("AvatarRandomizer: catalog pools never loaded - pool warm aborted")
		warming = false
		return
	end

	local template = Assets.Get(TEMPLATE_ASSET_PATH)
	if not template then
		warn("AvatarRandomizer: no template at Assets/" .. TEMPLATE_ASSET_PATH .. " - pool disabled")
		warming = false
		return
	end

	local folder = poolFolder()
	local target = count or POOL_SIZE
	local failures = 0

	while #folder:GetChildren() < target and failures < WARM_FAILURE_LIMIT do
		local before = #folder:GetChildren()
		local batchSize = math.min(WARM_BATCH_SIZE, target - before)
		local finished = 0

		for index = 1, batchSize do
			task.spawn(function()
				local built, buildError = pcall(function()
					local rig = prepareClone(template)
					if AvatarRandomizer.dress(rig) then
						rig.Parent = folder
					else
						rig:Destroy()
					end
				end)
				if not built then
					warn("AvatarRandomizer: warm build failed - " .. tostring(buildError))
				end
				finished += 1
			end)
		end

		while finished < batchSize do
			task.wait()
		end

		if #folder:GetChildren() <= before then
			failures += 1
		else
			failures = 0
		end
	end

	warming = false
end

function AvatarRandomizer.take()
	if not IS_SERVER then
		return nil, nil
	end

	local folder = poolFolder()
	local rig = folder:FindFirstChildOfClass("Model")
	if rig then
		rig.Parent = nil
		task.spawn(AvatarRandomizer.warm)
		return rig, rig:GetAttribute(NAME_ATTRIBUTE)
	end

	local template = Assets.Get(TEMPLATE_ASSET_PATH)
	if not template then
		warn("AvatarRandomizer.take: pool empty and no template at Assets/" .. TEMPLATE_ASSET_PATH)
		return nil, nil
	end

	local fresh = prepareClone(template)
	local fakeName = AvatarRandomizer.dress(fresh)
	task.spawn(AvatarRandomizer.warm)
	return fresh, fakeName
end

function AvatarRandomizer.poolCount()
	if not IS_SERVER then
		return 0
	end
	return #poolFolder():GetChildren()
end

function AvatarRandomizer.ready()
	return catalogReady
end

if IS_SERVER then
	task.spawn(fetchCatalogPools)
end

return AvatarRandomizer
