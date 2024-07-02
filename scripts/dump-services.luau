local fs = require("@lune/fs")
local net = require("@lune/net")
local serde = require("@lune/serde")

print("Fetching client version...")

local versionRes = net.request("https://clientsettings.roblox.com/v2/client-version/WindowsStudio64")
local version = serde.decode("json", versionRes.body).clientVersionUpload

print("Fetching api dump...")

local dumpRes = net.request(`https://setup.rbxcdn.com/{version}-API-Dump.json`)
local dump = serde.decode("json", dumpRes.body)

print("Processing api dump...")

local nameIndexMap = {}
for i, class in dump.Classes do
	nameIndexMap[class.Name] = i
end

local function testSecurity(security)
	return security == "None" or security == "PluginSecurity"
end

local function getAllNonInstanceMembers(className)
	local members = {}
	while className and className ~= "Instance" do
		local class = dump.Classes[nameIndexMap[className]]
		for _, member in class.Members do
			table.insert(members, member)
		end
		className = class.Superclass
	end
	return members
end

local blacklist = {
	"VoiceChatInternal", -- not for use
	"RomarkService", -- locked
	"CommerceService", -- not enabled
	"HttpRbxApiService", -- only RequestLimitedAsync, which is not enabled
	"Studio", -- acquired via settings()
	"RenderSettings", -- as above (NB: other subsettings aren't even tagged as services)
}

local whitelist = {
	"ServerScriptService",
	"ServerStorage",
	"ReplicatedStorage",
	"StarterGui",
	"StarterPack",
	"StarterPlayer",
}

local pluginOnlyOverride = {
	["ServerScriptService"] = false,
	["ServerStorage"] = false,
	["ReplicatedStorage"] = false,
	["StarterPlayer"] = false,
	["StarterPack"] = false,
	["CoreGui"] = true,
	["Selection"] = true,
}

local services = {}

for _, class in dump.Classes do
	if table.find(blacklist, class.Name) then
		continue
	end

	local tags = class.Tags
	if not tags then
		continue
	elseif not table.find(tags, "Service") then
		continue
	elseif table.find(tags, "Deprecated") then
		continue
	end

	local anyValidSecurity = false
	local pluginOnly = true

	for _, member in getAllNonInstanceMembers(class.Name) do
		if member.Tags and table.find(member.Tags, "Deprecated") then
			continue
		end

		local lowestSecurity
		if member.Type == "Property" then
			local readSecurity = member.Security.Read
			local writeSecurity = member.Security.Write
			if testSecurity(readSecurity) or testSecurity(writeSecurity) then
				if readSecurity == writeSecurity then
					lowestSecurity = readSecurity
				else
					-- if they are not the same, one must be None
					lowestSecurity = "None"
				end
			end
		else
			if testSecurity(member.Security) then
				lowestSecurity = member.Security
			end
		end
		if lowestSecurity ~= nil then
			anyValidSecurity = true
		end
		if lowestSecurity == "None" then
			pluginOnly = false
		end
	end

	local name = class.Name
	if pluginOnlyOverride[name] ~= nil then
		anyValidSecurity = true
		pluginOnly = pluginOnlyOverride[name]
	end

	if anyValidSecurity or table.find(whitelist, name) then
		table.insert(services, {
			name = name,
			pluginOnly = pluginOnly,
		})
	end
end

fs.writeFile("services.json", serde.encode("json", services))
