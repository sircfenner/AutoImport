local ScriptEditorService = game:GetService("ScriptEditorService")
local RunService = game:GetService("RunService")

if not RunService:IsEdit() then
	return
end

local Types = require(script.Parent.Types)
local getModules = require(script.Parent.getModules)
local parseScript = require(script.Parent.parseScript)
local moduleServices = require(script.Parent.moduleServices)
local services = require(script.Parent.services)

local CALLBACK_ID = "sircfenner-auto-import"
local PAT_IDENT = `[_%a][_%w]*`

local function isSafeIdentifier(text: string)
	return string.match(text, `^{PAT_IDENT}$`) ~= nil
end

local function getModuleIdentifier(module: ModuleScript)
	local name = module.Name
	if isSafeIdentifier(name) then
		return name
	end

	name = string.gsub(name, "[^_%w]", "")
	if #name == 0 then
		name = "_"
	elseif string.match(string.sub(name, 1, 1), "[^_%a]") then
		name = `_{name}`
	end

	return name
end

local function getModuleProvenance(module: ModuleScript): (Instance, string)
	local root: Instance?
	for _, service in moduleServices do
		if module:IsDescendantOf(service) then
			root = service
			break
		end
	end
	assert(root, "module service not found")

	local path = {}
	local current: Instance = module
	repeat
		local name = current.Name
		local item = `.{name}`
		if not isSafeIdentifier(name) then
			item = string.format("[%q]", name)
		end
		table.insert(path, 1, item)
		current = current.Parent :: Instance -- we know that the instance is rooted
	until current == root

	return root, table.concat(path)
end

local function getRequires(source: string): Types.Requires
	local requires = {}
	for i, line in string.split(source, "\n") do
		local identifier = string.match(line, `^local%s*({PAT_IDENT})%s*=%s*require%s*%b()%s*$`)
		if identifier then
			requires[identifier] = {
				lineNumber = i,
			}
		end
	end
	return requires
end

local function getServiceAcquisitions(source: string): Types.ServiceAcquisitions
	local acquisitions = {}
	for i, line in string.split(source, "\n") do
		local identifier, call = string.match(line, `^local%s*({PAT_IDENT})%s*=%s*game%s*:%s*GetService%s*(%b())%s*$`)
		if identifier and call then
			local name = string.sub(call, 3, -3) -- ("...")
			acquisitions[name] = {
				lineNumber = i,
				identifier = identifier,
			}
		end
	end
	return acquisitions
end

local function isInLongRange(pos: Types.Position, range: Types.Range): boolean
	local p0 = range.start
	local p1 = range["end"]
	if
		pos.line == p0.line
		and pos.character >= p0.character
		and (pos.line < p1.line or pos.character <= p1.character)
	then
		return true -- first-line
	elseif
		pos.line == p1.line
		and pos.character <= p1.character
		and (pos.line > p0.line or pos.character >= p0.character)
	then
		return true -- last-line
	elseif pos.line > p0.line and pos.line < p1.line then
		return true -- mid-lines
	end
	return false
end

local function isInComment(pos: Types.Position, comment: Types.Comment): boolean
	local range = comment.range
	if comment.kind == "simple" then
		return pos.line == range.start.line and pos.character >= range.start.character
	end
	return isInLongRange(pos, range)
end

local function isInString(pos: Types.Position, str: Types.String): boolean
	local range = str.range
	if str.kind == "quoted" then
		local p0 = range.start
		local p1 = range["end"]
		return pos.line == p0.line and pos.character >= p0.character and pos.character <= p1.character
	end
	return isInLongRange(pos, range)
end

local function isNonBlankLine(text: string?)
	return text == nil or string.match(text, "%S") ~= nil
end

local callback: Types.AutocompleteCallback = function(request, response)
	local origin = request.textDocument
	if origin.script == nil or origin.document == nil or origin.document:IsCommandBar() then
		return response
	end

	local position = request.position
	local slice = origin.document:GetText(1, 1, position.line, position.character)

	local trigger = string.match(slice, `{PAT_IDENT}$`)
	if not trigger then
		return response
	end

	local priorPos = -#trigger - 1
	local priorChar = string.sub(slice, priorPos, priorPos)
	if priorChar == "." or priorChar == ":" then
		return response -- probably an index or method call
	elseif string.sub(slice, priorPos - 6, priorPos) == "local " then
		return response -- probably a variable declaration
	end

	-- we dont have to parse the whole file, just the slice
	-- parser can handle a long comment/string being cut short by the slice (error tolerance)
	-- get lexemes from slice (before we removed trigger) as we need to look at it
	local lexemes = parseScript(slice)

	for _, comment in lexemes.comments do
		if isInComment(position, comment) then
			return response
		end
	end
	for _, str in lexemes.strings do
		if isInString(position, str) then
			return response
		end
	end

	local patch = origin.document:GetText(1, 1, position.line, position.character - #trigger)
	local patchRange = {
		start = { line = 1, character = 1 },
		["end"] = position,
	}

	local lines = string.split(patch, "\n")

	local lastCommentLine = 0
	for _, comment in lexemes.comments do
		if comment.header == true then
			lastCommentLine = comment.range["end"].line
		end
	end

	local requires = getRequires(patch)
	local acquires = getServiceAcquisitions(patch)

	-- if no header comments, write at line 1
	-- otherwise, write at the first line after the last header comment
	local writeLine = lastCommentLine + 1

	-- if we are writing after a comment, ensure there is a blank line after the comment before we (would) write
	if lastCommentLine > 0 then
		local nextLine = lines[writeLine]
		if isNonBlankLine(nextLine) or writeLine == #lines then
			table.insert(lines, writeLine, "")
			for _, item in requires do -- shift requires & services up one
				item.lineNumber += 1
			end
			for _, item in acquires do
				item.lineNumber += 1
			end
		end
		writeLine += 1 -- go to the next line regardless
	end

	-- if any existing service acquires, place line after the last of them
	for _, entry in acquires do
		writeLine = math.max(writeLine, entry.lineNumber + 1)
	end

	-- ensure there is a space after any service we would insert
	do
		local nextLine = lines[writeLine]
		if isNonBlankLine(nextLine) or writeLine == #lines then
			table.insert(lines, writeLine, "")
			for _, item in requires do -- shift requires & services up one
				item.lineNumber += 1
			end
			for _, item in acquires do
				item.lineNumber += 1
			end
		end
		-- but don't increment writeline
	end

	local items = table.clone(response.items)

	for _, module in getModules(origin.script) do
		local identifier = getModuleIdentifier(module)
		if requires[identifier] then
			continue
		end

		local newLines = table.clone(lines)
		local newWriteLine = writeLine
		local shiftImportLinesBy = 0

		local service, path = getModuleProvenance(module)

		local serviceIdentifier = service.Name
		if acquires[serviceIdentifier] then
			-- already have a reference to this service; update variable
			serviceIdentifier = acquires[serviceIdentifier].identifier
		else
			-- need to insert a reference to the service
			local acquireSource = `local {serviceIdentifier} = game:GetService("{serviceIdentifier}")`
			table.insert(newLines, newWriteLine, acquireSource)
			newWriteLine += 1
			shiftImportLinesBy += 1
		end
		newWriteLine += 1 -- known blank line

		local requirePath = `{serviceIdentifier}{path}`
		for _, entry in requires do
			local useLineNumber = entry.lineNumber + shiftImportLinesBy + 1
			newWriteLine = math.max(newWriteLine, useLineNumber)
		end

		local requireSource = `local {identifier} = require({requirePath})`
		table.insert(newLines, newWriteLine, requireSource)

		local finalLine = newWriteLine + 1
		if isNonBlankLine(lines[finalLine]) or finalLine == #newLines then
			table.insert(newLines, newWriteLine + 1, "")
		end

		table.insert(items, {
			label = module.Name,
			kind = Enum.CompletionItemKind.Snippet,
			documentation = { value = "Auto-require" },
			detail = module:GetFullName(),
			textEdit = {
				newText = table.concat(newLines, "\n") .. identifier,
				replace = patchRange,
			},
		})
	end

	-- NB: does nothing with pluginonly currently

	for _, service in services do
		local identifier = service.name
		if acquires[identifier] then
			continue
		end

		local newLines = table.clone(lines)
		local acquireSource = `local {identifier} = game:GetService("{identifier}")`
		table.insert(newLines, writeLine, acquireSource)

		local nextLine = newLines[writeLine + 1]
		if isNonBlankLine(nextLine) or writeLine + 1 == #newLines then
			table.insert(newLines, writeLine + 1, "")
		end

		table.insert(items, {
			label = identifier,
			kind = Enum.CompletionItemKind.Snippet,
			documentation = { value = "Auto-service" },
			learnMoreLink = `https://create.roblox.com/docs/reference/engine/classes/{identifier}`,
			textEdit = {
				newText = table.concat(newLines, "\n") .. identifier,
				replace = patchRange,
			},
		})
	end

	return {
		items = items,
	}
end

ScriptEditorService:RegisterAutocompleteCallback(CALLBACK_ID, 1, callback)

plugin.Unloading:Connect(function()
	ScriptEditorService:DeregisterAutocompleteCallback(CALLBACK_ID)
end)
