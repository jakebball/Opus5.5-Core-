// Edits applied to baseplate/src after every `node maintainer/baseplate.js source`, so a re-extract never loses them.
// Each patch must change its file; a patch that matches nothing fails the run, because the source moved under it.
const replaceOnce = (text, from, to, label) => {
  if (!text.includes(from)) throw new Error(`${label}: expected text not found`);
  return text.replace(from, to);
};

module.exports = [
  {
    name: "GoodSignal connections can go in a Trove (Connection.Destroy aliases Disconnect)",
    file: "ServerScriptService/Runner/Shared/Generic/GoodSignal.luau",
    apply: (text) => replaceOnce(text, "\nsetmetatable(Connection, {", "\nConnection.Destroy = Connection.Disconnect\n\nsetmetatable(Connection, {", "GoodSignal"),
  },
  {
    name: "client Zone releases its zone and signals when the instance goes away",
    file: "StarterPlayerScripts/Runner/Components/Generic/Zone.luau",
    apply: (text) => replaceOnce(text, "function ZoneComponent:destroy()\nend", "function ZoneComponent:destroy()\n\tself.trove:Destroy()\n\tself.onPlayerEntered:DisconnectAll()\n\tself.onPlayerExited:DisconnectAll()\nend", "Zone"),
  },
  {
    name: "profile template without any game's fields",
    file: "ServerScriptService/Runner/Shared/getConfig/Profile.luau",
    apply: () => `local RunService = game:GetService("RunService")

return {
	ProfileVersion = 1,
	UseMockstore = RunService:IsStudio(),
	DataTemplate = {
		Currencies = {
			Coins = 0,
		},
		Inventory = {},
		HotbarGuids = {},
		EquippedItems = {},
		TotalXp = 0,
		LastSeen = 0,
		OnboardingComplete = false,
		SeasonPass = {
			Season = 1,
			Xp = 0,
			Claimed = { Free = {}, Premium = {}, Group = {} },
		},
		Quests = {},
	},
}
`,
  },
  {
    name: "no game-currency formatter in NumberUtils",
    file: "ServerScriptService/Runner/Shared/Generic/NumberUtils.luau",
    apply: (text) => text.replace(/function NumberUtils\.Gold\(amount\)\n[\s\S]*?\nend\n\n/, ""),
  },
  {
    name: "no products from an earlier game",
    file: "ServerScriptService/Runner/Shared/getConfig/Monetization.luau",
    apply: () => `return {
	DeveloperProducts = {},
	Gamepasses = {},
}
`,
  },
  {
    name: "admin config without a real group or user",
    file: "ServerScriptService/AdminSystem/Config.luau",
    apply: (text) => {
      let out = replaceOnce(text, /GroupId = \d+,/.exec(text)?.[0] || "GroupId =", "GroupId = 0, -- TODO: your group id (group ranks in Roles get admin)", "Config GroupId");
      out = out.replace(/UserOverrides = \{[\s\S]*?\n\t\},/, "UserOverrides = {\n\t\t-- TODO: [yourUserId] = math.huge,\n\t},");
      out = out.replace(/\t\{ Name = "Global", Commands = \{[\s\S]*?\} \},\n/, "");
      return out;
    },
  },
];
