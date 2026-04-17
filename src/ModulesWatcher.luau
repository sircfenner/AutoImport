local moduleServices = require(script.Parent.moduleServices)

local excludedRoots = {
	"_Index", -- wally
	"node_modules", -- npm/yarn
}

local function isImportable(module: ModuleScript)
	local parent = module.Parent
	while parent and parent ~= game do
		if parent:IsA("Folder") and table.find(excludedRoots, parent.Name) then
			return false
		end
		parent = parent.Parent
	end

	return true
end

type Context = "server" | "shared" | "client"

local serverDirectories = {
	game:GetService("ServerScriptService"),
	game:GetService("ServerStorage"),
}

local clientDirectories = {
	game:GetService("StarterPlayer"),
	game:GetService("StarterGui"),
	game:GetService("StarterPack"),
}

local function getContext(container: LuaSourceContainer): Context
	if container:IsA("LocalScript") then -- do this check first as localscript inherits script
		return "client"
	elseif container:IsA("Script") then
		if container.RunContext == Enum.RunContext.Client then
			return "client"
		end
		return "server"
	end
	for _, dir in serverDirectories do
		if container:IsDescendantOf(dir) then
			return "server"
		end
	end
	for _, dir in clientDirectories do
		if container:IsDescendantOf(dir) then
			return "client"
		end
	end
	return "shared"
end

local function canAccess(origin: LuaSourceContainer, target: ModuleScript)
	if origin == target then
		return false
	end

	local originContext = getContext(origin)
	local targetContext = getContext(target)
	if originContext == "server" then
		return targetContext == "server" or targetContext == "shared"
	elseif originContext == "client" then
		return targetContext == "client" or targetContext == "shared"
	end

	return true
end

local latestModules: { ModuleScript } = {}

local function getModules(origin: LuaSourceContainer): { ModuleScript }
	local modules = {}
	for _, module in latestModules do
		if canAccess(origin, module) then
			table.insert(modules, module)
		end
	end

	return modules
end

for _, service in moduleServices do
	for _, inst in service:GetDescendants() do
		if inst:IsA("ModuleScript") and isImportable(inst) then
			table.insert(latestModules, inst)
		end
	end
	service.DescendantAdded:Connect(function(inst)
		if inst:IsA("ModuleScript") and isImportable(inst) then
			table.insert(latestModules, inst)
		end
	end)
	service.DescendantRemoving:Connect(function(inst)
		local index = table.find(latestModules, inst)
		if index ~= nil then
			table.remove(latestModules, index)
		end
	end)
end

return getModules
