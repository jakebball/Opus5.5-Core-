return {
	GroupId = 0, -- TODO: your group id (group ranks in Roles get admin)

	-- DEBUG: when true AND running in Studio, every player resolves to full permissions
	-- (all admin commands). Studio-gated, so it is a no-op on live servers.
	BlanketEnable = true,

	Roles = {
		[253] = { Name = "Developer",        PermissionLevel = 3 },
		[255] = { Name = "Owner",            PermissionLevel = 3 },
	},

	UserOverrides = {
		-- TODO: [yourUserId] = math.huge,
	},

	-- Admin panel command categories (radio buttons). Order here = tab order.
	-- A category either lists its own Commands by name, or is flagged Default
	-- to catch every command not explicitly assigned elsewhere.
	Categories = {
		{ Name = "Server", Default = true },
		},

	BanDataStoreName = "AdminBans_v1",
	EventDataStoreName = "AdminEvents_v1",
	RateLimitPerMinute = 20,
}
