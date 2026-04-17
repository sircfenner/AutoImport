local targetRoots: { Instance } = {
	game:GetService("Workspace"),
	game:GetService("ReplicatedFirst"),
	game:GetService("ReplicatedStorage"),
	game:GetService("ServerScriptService"),
	game:GetService("ServerStorage"),
	game:GetService("StarterGui"),
	game:GetService("StarterPack"),
	game:GetService("StarterPlayer"),
}

local serverDirectories: { Instance } = {
	game:GetService("ServerScriptService"),
	game:GetService("ServerStorage"),
}

local clientDirectories: { Instance } = {
	game:GetService("StarterPlayer"),
	game:GetService("StarterGui"),
	game:GetService("StarterPack"),
}

local excludedRootNames = {
	"_Index", -- wally
	"node_modules", -- npm
}

type Context = "server" | "shared" | "client"

local function getContext(container: LuaSourceContainer): Context
	if container:IsA("LocalScript") then -- do this check first because localscript inherits script
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

local function isImportable(module: ModuleScript)
	local parent = module.Parent
	while parent and parent ~= game do
		if parent:IsA("Folder") and table.find(excludedRootNames, parent.Name) then
			return false
		end
		parent = parent.Parent
	end
	return true
end

local function create()
	local latestModules: { ModuleScript } = {}
	local cacheValid = false

	local function invalidateCache()
		cacheValid = false
	end

	local function getAll()
		local modules = {}
		for _, root in targetRoots do
			for _, module in root:QueryDescendants("ModuleScript") do
				if isImportable(module) then
					table.insert(modules, module)
				end
			end
		end

		return modules
	end

	local function getAccessible(origin: LuaSourceContainer): { ModuleScript }
		if not cacheValid then
			latestModules = getAll()
			cacheValid = true
		end

		local modules = {}
		for _, module in latestModules do
			if canAccess(origin, module) then
				table.insert(modules, module)
			end
		end

		return modules
	end

	local addedConnection = game.DescendantAdded:Connect(invalidateCache)
	local removedConnection = game.DescendantRemoving:Connect(invalidateCache)

	local function destroy()
		table.clear(latestModules)
		addedConnection:Disconnect()
		removedConnection:Disconnect()
	end

	return {
		getAccessible = getAccessible,
		destroy = destroy,
	}
end

return {
	create = create,
}
