local HttpService = game:GetService("HttpService")
local ScriptEditorService = game:GetService("ScriptEditorService")
local ReflectionService = game:GetService("ReflectionService")

local AST = require("@self/AST")
local Types = require("@self/Types")

local ModulesWatcher = require("@self/ModulesWatcher")

local CALLBACK_ID = "sircfenner-auto-import-2"
local TEMPLATE_STR = string.gsub(HttpService:GenerateGUID(false), "%-", "")

local PAT_IDENT = `[_%a][_%w]*`

local watcher = ModulesWatcher.create()

local serviceNames = {}
for _, class in ReflectionService:GetClasses() do
	if class.Permits.GetService then
		table.insert(serviceNames, class.Name)
	end
end

local excludePreceding = {
	"local",
	"export",
	"type",
	"function",
}

local commonEscapes = {
	[string.byte("\t")] = "\\t",
	[string.byte("\n")] = "\\n",
}

local function getSafeInstanceName(name: string): string?
	if #name == 0 then
		return nil
	elseif name == "." or name == ".." then
		return nil
	elseif string.find(name, "/") or string.find(name, "\\") then
		return nil
	elseif string.find(name, '"') then
		return nil
	end

	local out = {}
	for i = 1, #name do
		local b = string.byte(name, i)
		if b < 32 or b > 126 then
			out[i] = commonEscapes[b] or `\\{b}`
		else
			out[i] = string.char(b)
		end
	end

	return table.concat(out)
end

local function getSafeIdentifier(name: string)
	if not string.match(name, `^{PAT_IDENT}$`) then
		name = string.gsub(name, "[^_%w]", "")
		if #name == 0 then
			name = "_"
		elseif string.match(string.sub(name, 1, 1), "[^_%a]") then
			name = `_{name}`
		end
	end
	return name
end

local function getRequirePath(origin: Instance, target: ModuleScript): (string, boolean)
	local chunks = {}
	local terminate: Instance
	if target:IsDescendantOf(origin) then -- descendant
		table.insert(chunks, "@self")
		terminate = origin
	elseif target.Parent == origin.Parent then -- sibling
		table.insert(chunks, ".")
		terminate = assert(origin.Parent)
	else
		table.insert(chunks, "@game") -- absolute
		terminate = game
	end
	local current: Instance = target
	local valid = true
	repeat
		local name = getSafeInstanceName(current.Name)
		if not name then
			valid = false
			table.insert(chunks, 2, current.Name)
		else
			table.insert(chunks, 2, name)
		end
		current = assert(current.Parent)
	until current == terminate
	return table.concat(chunks, "/"), valid
end

type FileRequires = { [string]: { line: number } }
local function getRequires(source: string): FileRequires
	local records = {}
	for i, line in string.split(source, "\n") do
		local ident = string.match(line, `^local%s*({PAT_IDENT})%s*=%s*require%s*%b()%s*$`)
		if ident then
			records[ident] = {
				line = i,
			}
		end
	end
	return records
end

type FileServiceGets = { [string]: { line: number } }
local function getServiceGets(source: string): FileServiceGets
	local records = {}
	for i, line in string.split(source, "\n") do
		local identifier, call = string.match(line, `^local%s*({PAT_IDENT})%s*=%s*game%s*:%s*GetService%s*(%b())%s*$`)
		if identifier and call then
			local name = string.sub(call, 3, -3) -- ("...")
			records[name] = {
				line = i,
			}
		end
	end
	return records
end

local function getClosestAncestorPair(inst0: Instance, inst1: Instance): Instance
	local current = inst0
	while not current:IsAncestorOf(inst1) do
		current = assert(current.Parent)
	end
	return current
end

local function getClosestAncestor(insts: { Instance }): Instance
	local ancestor = getClosestAncestorPair(insts[1], insts[2])
	for i = 3, #insts do
		ancestor = getClosestAncestorPair(ancestor, insts[i])
	end
	return ancestor
end

local function findAncestorChild(ancestor: Instance, leaf: Instance): Instance
	local current = leaf
	while current.Parent ~= ancestor do
		current = assert(current.Parent)
	end
	return current
end

local function buildName(module: ModuleScript, prefix: { Instance }): string
	if #prefix == 0 then
		return module.Name
	end

	local items = { prefix[1].Name }
	local last = prefix[1]

	for i = 2, #prefix do
		local item = prefix[i]
		if item.Parent ~= last then
			table.insert(items, "...")
		end
		table.insert(items, item.Name)
		last = item
	end

	return `{module.Name} ({table.concat(items, "/")})`
end

local function disambiguateModuleNames(
	name: string,
	modules: { ModuleScript },
	prefix: { Instance }
): { [ModuleScript]: string }
	local instances = (modules :: any) :: { Instance } -- need a readonly type for `modules`
	local ancestor = getClosestAncestor(instances)

	local out = {}
	local groups = {}
	local basePrefix = table.clone(prefix)

	for _, module in modules do
		if module == ancestor then
			out[module] = buildName(module, prefix)
			table.insert(basePrefix, module)
		else
			local child = findAncestorChild(ancestor, module)
			if not groups[child] then
				groups[child] = {}
			end
			table.insert(groups[child], module)
		end
	end

	for child, list in groups do
		local newPrefix = table.clone(basePrefix)
		if not (#list == 1 and list[1] == child) then
			table.insert(newPrefix, child)
		end

		if #list == 1 then
			local module = list[1]
			out[module] = buildName(module, newPrefix)
		else
			for module, name in disambiguateModuleNames(name, list, newPrefix) do
				out[module] = name
			end
		end
	end

	return out
end

local function computeServiceNewTextTemplate(
	source: string,
	position: Types.Position,
	serviceGets: FileServiceGets,
	comments: { Types.Comment }
): string
	local lastHeaderCommentLine = nil
	for _, comment in comments do
		if comment.header then
			lastHeaderCommentLine = comment.range["end"].line
		end
	end

	local lastServiceGetLine = nil
	for _, record in serviceGets do
		lastServiceGetLine = math.max(lastServiceGetLine or 0, record.line)
	end

	local lines = string.split(source, "\n")
	local writeLine = 1
	if lastServiceGetLine then
		writeLine = lastServiceGetLine + 1
	elseif lastHeaderCommentLine then
		writeLine = lastHeaderCommentLine + 1
	end

	local spaceBefore = writeLine - 1 == lastHeaderCommentLine
	local spaceAfter = lines[writeLine] ~= nil and #lines[writeLine] > 0
	if spaceBefore then
		table.insert(lines, writeLine, "")
		writeLine += 1
	end
	table.insert(lines, writeLine, TEMPLATE_STR)
	if spaceAfter then
		table.insert(lines, writeLine + 1, "")
	end

	return table.concat(lines, "\n")
end

local function computeRequireNewTextTemplate(
	source: string,
	position: Types.Position,
	serviceGets: FileServiceGets,
	requires: FileRequires,
	comments: { Types.Comment }
): string
	local lastHeaderCommentLine = nil
	for _, comment in comments do
		if comment.header then
			lastHeaderCommentLine = comment.range["end"].line
		end
	end

	local lastServiceGetLine = nil
	for _, record in serviceGets do
		lastServiceGetLine = math.max(lastServiceGetLine or 0, record.line)
	end

	local lastRequireLine = nil
	for _, record in requires do
		lastRequireLine = math.max(lastRequireLine or 0, record.line)
	end

	local lines = string.split(source, "\n")
	local writeLine = 1
	if lastRequireLine then
		writeLine = lastRequireLine + 1
	elseif lastServiceGetLine then
		writeLine = lastServiceGetLine + 1
	elseif lastHeaderCommentLine then
		writeLine = lastHeaderCommentLine + 1
	end

	local spaceBefore = writeLine - 1 == lastHeaderCommentLine or writeLine - 1 == lastServiceGetLine
	local spaceAfter = lines[writeLine] ~= nil and #lines[writeLine] > 0
	if spaceBefore then
		table.insert(lines, writeLine, "")
		writeLine += 1
	end
	table.insert(lines, writeLine, TEMPLATE_STR)
	if spaceAfter then
		table.insert(lines, writeLine + 1, "")
	end

	return table.concat(lines, "\n")
end

local function lenientMatch(str0: string, str1: string)
	local cmp0 = string.lower(str0)
	local cmp1 = string.lower(str1)
	return (string.find(cmp0, cmp1, 1, true) or string.find(cmp1, cmp0, 1, true)) ~= nil
end

local function substitute(source: string, match: string, replacement: string)
	local i, j = string.find(source, match, 1, true)
	assert(i and j)
	return `{string.sub(source, 1, i - 1)}{replacement}{string.sub(source, j + 1)}`
end

local callback: Types.AutocompleteCallback = function(request, response)
	local origin = request.textDocument
	if origin.script == nil or origin.document == nil or origin.document:IsCommandBar() then
		return response
	end

	local position = request.position
	local source = origin.document:GetText(1, 1, position.line, position.character)

	local trigger = string.match(source, `{PAT_IDENT}$`)
	if not trigger then
		return response
	end

	local priorPos = -#trigger - 1
	local priorChar = string.sub(source, priorPos, priorPos)
	if priorChar == "." or priorChar == ":" then
		return response -- probably an index or method call
	elseif priorChar == " " then
		for _, excluded in excludePreceding do
			local before = string.sub(source, priorPos - #excluded, priorPos - 1)
			if before == excluded then
				return response
			end
		end
	end

	local lexemes = AST.parse(source)
	for _, comment in lexemes.comments do
		if AST.isInComment(position, comment) then
			return response
		end
	end
	for _, str in lexemes.strings do
		if AST.isInString(position, str) then
			return response
		end
	end

	local items = table.clone(response.items)
	local sourceNoTrigger = string.sub(source, 1, priorPos)
	local positionNoTrigger = {
		line = position.line,
		character = position.character - #trigger - 1,
	}

	-- services
	local serviceGets = getServiceGets(source)
	local serviceNewTextTemplate =
		computeServiceNewTextTemplate(sourceNoTrigger, positionNoTrigger, serviceGets, lexemes.comments)
	for _, serviceName in serviceNames do
		if serviceGets[serviceName] then
			continue
		elseif not lenientMatch(trigger, serviceName) then
			continue
		end

		local acquireLine = `local {serviceName} = game:GetService("{serviceName}")`
		local newText = substitute(serviceNewTextTemplate, TEMPLATE_STR, acquireLine)
		newText = `{newText}{serviceName}`

		table.insert(items, {
			label = serviceName,
			kind = Enum.CompletionItemKind.Snippet,
			detail = `➡️ game:GetService("{serviceName}")`,
			documentation = {
				value = "Inserts a <code>GetService</code> at the top of the script.",
			},
			learnMoreLink = `https://create.roblox.com/docs/reference/engine/classes/{serviceName}`,
			textEdit = {
				newText = newText,
				replace = {
					start = { line = 1, character = 1 },
					["end"] = position,
				},
			},
		})
	end

	-- requires
	local modules = watcher.getAccessible(origin.script)
	local requires = getRequires(source)
	local requireNewTextTemplate =
		computeRequireNewTextTemplate(sourceNoTrigger, positionNoTrigger, serviceGets, requires, lexemes.comments)

	local modulesByName = {}
	for _, module in modules do
		local name = module.Name
		if not modulesByName[name] then
			modulesByName[name] = {}
		end
		table.insert(modulesByName[name], module)
	end

	local moduleLabels = {}
	for name, list in modulesByName do
		if #list == 1 then
			moduleLabels[list[1]] = name
		else
			for module, label in disambiguateModuleNames(name, list, {}) do
				moduleLabels[module] = label
			end
		end
	end

	for _, module in modules do
		local identifier = getSafeIdentifier(module.Name)
		if requires[identifier] then
			continue
		elseif not lenientMatch(trigger, identifier) then
			continue
		end

		local item = {
			label = moduleLabels[module],
			kind = Enum.CompletionItemKind.Snippet,
		}

		local requirePath, isValidPath = getRequirePath(origin.script, module)
		if not isValidPath then
			item.tags = { Enum.CompletionItemTag.Deprecated }
			item.documentation = { value = `Invalid module name or path: <code>{requirePath}</code>` }
			item.textEdit = {
				replace = { start = position, ["end"] = position },
				newText = "",
			}
		else
			local acquireLine = `local {identifier} = require("{requirePath}")`
			local newText = substitute(requireNewTextTemplate, TEMPLATE_STR, acquireLine)
			newText = `{newText}{identifier}`

			item.detail = `➡️ require("{requirePath}")`
			item.documentation = { value = "Inserts a <code>require</code> at the top of the script." }
			item.textEdit = {
				newText = newText,
				replace = {
					start = { line = 1, character = 1 },
					["end"] = position,
				},
			}
		end

		table.insert(items, item)
	end

	return {
		items = items,
	}
end

ScriptEditorService:RegisterAutocompleteCallback(CALLBACK_ID, 1, callback)

plugin.Unloading:Connect(function()
	ScriptEditorService:DeregisterAutocompleteCallback(CALLBACK_ID)
	watcher.destroy()
end)
