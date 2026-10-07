return {
	SampleWindow = 1,
	HistorySamples = 60,

	Access = {
		AdminSystemName = "AdminSystem",
		MinPermissionLevel = 1,
		StudioAlwaysAllowed = true,
	},

	Region = {
		LookupUrl = "http://ip-api.com/json/",
		Unknown = "Unknown",
		StudioSuffix = " (Studio)",
	},

	Thresholds = {
		PingGood = 90,
		PingBad = 160,
		ServerFpsGood = 55,
		ServerFpsBad = 40,
		HeartbeatGoodMs = 20,
		HeartbeatBadMs = 35,
	},
}
