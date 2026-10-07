local Enum = {}
local enums = {}
Enum.enums = enums

function Enum.createEnum(enumName, details)
	assert(typeof(enumName) == "string", "bad argument #1 - enums must be created using a string name!")
	assert(typeof(details) == "table", "bad argument #2 - enums must be created using a table!")
	assert(not enums[enumName], ("enum '%s' already exists!"):format(enumName))

	local enum = {}
	local usedNames = {}
	local usedValues = {}
	local usedProperties = {}
	local enumMetaFunctions = {
		getName = function(valueOrProperty)
			valueOrProperty = tostring(valueOrProperty)
			local index = usedValues[valueOrProperty]
			if not index then
				index = usedProperties[valueOrProperty]
			end
			if index then
				return details[index][1]
			end
		end,
		getValue = function(nameOrProperty)
			nameOrProperty = tostring(nameOrProperty)
			local index = usedNames[nameOrProperty]
			if not index then
				index = usedProperties[nameOrProperty]
			end
			if index then
				return details[index][2]
			end
		end,
		getProperty = function(nameOrValue)
			nameOrValue = tostring(nameOrValue)
			local index = usedNames[nameOrValue]
			if not index then
				index = usedValues[nameOrValue]
			end
			if index then
				return details[index][3]
			end
		end
	}
	for i, detail in pairs(details) do
		assert(typeof(detail) == "table", ("bad argument #2.%s - details must only be comprised of tables!"):format(i))
		local name = detail[1]
		assert(typeof(name) == "string", ("bad argument #2.%s.1 - detail name must be a string!"):format(i))
		assert(typeof(not usedNames[name]), ("bad argument #2.%s.1 - the detail name '%s' already exists!"):format(i, name))
		assert(typeof(not enumMetaFunctions[name]), ("bad argument #2.%s.1 - that name is reserved."):format(i, name))
		usedNames[tostring(name)] = i
		local value = detail[2]
		local valueString = tostring(value)
		assert(typeof(not usedValues[valueString]), ("bad argument #2.%s.2 - the detail value '%s' already exists!"):format(i, valueString))
		usedValues[valueString] = i
		local property = detail[3]
		if property then
			assert(typeof(not usedProperties[property]), ("bad argument #2.%s.3 - the detail property '%s' already exists!"):format(i, tostring(property)))
			usedProperties[tostring(property)] = i
		end
		enum[name] = value
		setmetatable(enum, {
			__index = function(_, index)
				return(enumMetaFunctions[index])
			end
		})
	end

	enums[enumName] = enum
	return enum
end

function Enum.getEnums()
	return enums
end

local createEnum = Enum.createEnum
for _, childModule in pairs(script:GetChildren()) do
	if childModule:IsA("ModuleScript") then
		local enumDetail = require(childModule)
		createEnum(childModule.Name, enumDetail)
	end
end

return Enum