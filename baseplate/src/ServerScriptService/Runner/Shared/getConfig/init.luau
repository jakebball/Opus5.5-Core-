return function()
	local config = {}

	for _,v in script:GetDescendants() do
		if v:IsA("ModuleScript") then
			config[v.Name] = require(v)
		end
	end

	return config
end