local CollectionService = game:GetService("CollectionService")

local Shared = game.ReplicatedStorage:WaitForChild("Shared")

local GoodSignal = require(Shared.Generic.GoodSignal)
local Observers = require(Shared.Generic.Observers)
local Promise = require(Shared.Generic.Promise)

local BaseClass
for _, inst in CollectionService:GetTagged("BaseClass") do
	if inst:IsDescendantOf(script.Parent) then
		BaseClass = require(inst)
		break
	end
end

local function injectShared(target)
	local function processChildren(parent, dest)
		for _, child in parent:GetChildren() do
			if child:IsA("ModuleScript") then
				dest[child.Name] = require(child)
			elseif child:IsA("Folder") then
				processChildren(child, dest)
			end
		end
	end

	processChildren(Shared, target)
end

local store = {}
local EntityStore = {}

EntityStore.onComponentAdded = GoodSignal.new()
EntityStore.onComponentRemoved = GoodSignal.new()

local Components = script.Parent.Components

local discoveredComponents = {}

local function injectComponents(target)
	for name, classRef in discoveredComponents do
		if target ~= classRef and target[name] == nil then
			target[name] = classRef
		end
	end
end

local function findComponentModule(parent, name)
	for _, child in parent:GetChildren() do
		if child:IsA("ModuleScript") and child.Name == name then
			return child
		end
		local nested = findComponentModule(child, name)
		if nested then
			return nested
		end
	end
	return nil
end

function EntityStore.createEntity(instance)
	store[instance] = {}

	return store[instance]
end

function EntityStore.getComponent(instance, componentTag)
	local entity = store[instance]

	if not entity then
		warn("Unable to find entity for instance (" .. tostring(instance) .. ")")
        return nil
	end

    return entity[componentTag]
end

function EntityStore.findComponent(instance, componentTag)
	local entity = store[instance]
	if not entity then return nil end
	return entity[componentTag]
end

function EntityStore.promiseGetComponent(instance, componentTag)
	return Promise.new(function(resolve, reject, onCancel)
		local entity = store[instance]

		repeat
			task.wait()
			entity = store[instance]
		until (entity and entity[componentTag] ~= nil) or not instance:IsDescendantOf(game)

		if not instance:IsDescendantOf(game) then
			return reject()
		end

		resolve(entity[componentTag])
	end)
end

function EntityStore.addComponent(instance, componentTag, ...)
	local entity = store[instance]

	if entity == nil then
		entity = EntityStore.createEntity(instance)
	end

	if entity[componentTag] then
		return entity, entity[componentTag]
	end

	local module = findComponentModule(Components, componentTag)

	if module == nil then
		error("Unable to find component (" .. componentTag .. ")")
	end

	module = require(module)
	module.EntityStore = EntityStore
	module.BaseClass = BaseClass
	injectShared(module)
	injectComponents(module)

	local component = module.new(instance, ...)
	instance:AddTag(componentTag)

	EntityStore.onComponentAdded:Fire(instance, component)

	entity[component.Tag] = component

	return entity, component
end

function EntityStore.removeComponent(instance, componentTag)
	local entity = store[instance]

	if entity == nil then
		return
	end

	local component = entity[componentTag]

	if component == nil then
		warn("Component (" .. componentTag .. ") does not exist for instance (" .. tostring(instance) .. ")")
		return nil
	end

	if component.trove then
		component.trove:Destroy()
	end

	if component.destroy then
		component:destroy()
	end

	EntityStore.onComponentRemoved:Fire(instance, component)

	instance:RemoveTag(componentTag)

	entity[componentTag] = nil

	if next(entity) == nil then
		EntityStore.removeEntity(instance)
	end

	return entity
end

function EntityStore.removeEntity(instance)
	local entity = store[instance]

	if entity == nil then
		warn("Entity does not exist for instance (" .. tostring(instance) .. ")")
		return nil
	end

	store[instance] = nil

	return true
end

local function collectComponents(folder)
	for _, child in folder:GetChildren() do
		if child:IsA("ModuleScript") then
			local componentClass = require(child)

			if componentClass.Tag == nil then
				error("Class must have a Tag field: " .. child.Name)
			end

			discoveredComponents[componentClass.Tag] = componentClass
		elseif child:IsA("Folder") then
			collectComponents(child)
		end
	end
end

local function setupComponent(folder)
	collectComponents(folder)

	for _, componentClass in discoveredComponents do
		injectShared(componentClass)
		injectComponents(componentClass)
		componentClass.EntityStore = EntityStore
		componentClass.BaseClass = BaseClass
	end

	for _, componentClass in discoveredComponents do
		if componentClass.Start then
			task.spawn(function()
				local ok, err = xpcall(componentClass.Start, debug.traceback)
				if not ok then
					warn(string.format(
						"[EntityStore] Start() errored for component '%s': %s",
						tostring(componentClass.Tag), tostring(err)))
				end
			end)
		end

		Observers.observeTag(componentClass.Tag, function(instance)
			local component = EntityStore.addComponent(instance, componentClass.Tag)

			return function()
				if EntityStore.findComponent(instance, componentClass.Tag) then
					EntityStore.removeComponent(instance, componentClass.Tag)
				end
			end
		end)
	end
end

setupComponent(Components)

return EntityStore