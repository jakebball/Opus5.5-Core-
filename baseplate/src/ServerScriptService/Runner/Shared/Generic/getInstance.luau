--!strict

local function getInstance<T>(instance: Instance, ...: string): T
	for _, childName in ipairs({ ... }) do
		local child = instance:FindFirstChild(childName)
		assert(child, string.format("%s is not a child of %s", childName, instance:GetFullName()))
		instance = child
	end

	return (instance :: any) :: T
end

return getInstance