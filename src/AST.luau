--!optimize 2
-- https://github.com/luau-lang/luau/blob/master/Ast/src/Lexer.cpp

local Types = require("./Types")

local function isNewline(ch: string)
	return ch == "\n"
end

local function isSpace(ch: string)
	return ch == " " or ch == "\t" or ch == "\r" or ch == "\n" or ch == "\v" or ch == "\f"
end

local function makeRange(start: Types.Position, finish: Types.Position): Types.Range
	return {
		["start"] = start,
		["end"] = finish,
	}
end

local function isInLongRange(pos: Types.Position, range: Types.Range): boolean
	local p0 = range["start"]
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
		local p0 = range["start"]
		local p1 = range["end"]
		return pos.line == p0.line and pos.character >= p0.character and pos.character <= p1.character
	end
	return isInLongRange(pos, range)
end

local function parse(source: string): {
	comments: { Types.Comment },
	strings: { Types.String },
}
	local length = #source
	local offset = 1

	local line = 1
	local lineOffset = 1

	local isHeaderBlock = true
	local braceStack: { string } = {} -- "normal", "interp"

	local function position(): Types.Position
		return {
			line = line,
			character = offset - lineOffset + 1,
		}
	end

	local function peekCh()
		return string.sub(source, offset, offset)
	end

	local function consume()
		if isNewline(peekCh()) then
			line += 1
			lineOffset = offset + 1 -- as if we already incremented offset
		end
		offset += 1
	end

	local function skipLongSeparator()
		local start = peekCh()
		local count = 0
		offset += 1 -- always [ or ]
		while peekCh() == "=" do
			count += 1
			offset += 1
		end
		return if start == peekCh() then count else -count - 1
	end

	local function readLongComment(start: Types.Position, sep: number): Types.Comment
		consume() -- second [

		while offset <= length do
			if peekCh() == "]" then
				if skipLongSeparator() == sep then
					local finish = position()
					consume() -- second ]
					return {
						kind = "long",
						range = makeRange(start, finish), -- includes final ]
						header = false,
					}
				end
			else
				consume()
			end
		end

		return { -- broken/unfinished comment
			kind = "long",
			range = makeRange(start, position()),
			header = false,
		}
	end

	local function readComment(): Types.Comment
		local start = position()
		offset += 2 -- two opening dashes

		if peekCh() == "[" then
			local sep = skipLongSeparator()
			if sep >= 0 then
				return readLongComment(start, sep)
			end
		end

		while offset < length and not isNewline(peekCh()) do
			offset += 1
		end

		return {
			kind = "simple",
			range = makeRange(start, position()), -- includes newline/eof
			header = false,
		}
	end

	local function readLongString(start: Types.Position, sep: number): Types.String
		consume() -- second [

		while offset <= length do
			if peekCh() == "]" then
				if skipLongSeparator() == sep then
					local finish = position()
					consume() -- second ]
					return {
						kind = "long",
						range = makeRange(start, finish), -- includes final ]
					}
				end
			else
				consume()
			end
		end

		return { -- broken/unfinished string
			kind = "long",
			range = makeRange(start, position()),
		}
	end

	local function skipBackslashInString()
		consume()
		local escch = peekCh()
		if escch == "z" then
			consume()
			while isSpace(peekCh()) do
				consume()
			end
		elseif escch ~= "" then
			consume()
		end
	end

	local function readQuotedString(): Types.String
		local start = position()
		local delim = peekCh()
		consume() -- delim

		while peekCh() ~= delim do
			local ch = peekCh()
			if ch == "" or ch == "\n" then
				return {
					kind = "quoted",
					range = makeRange(start, position()), -- includes newline/eof
				}
			elseif ch == "\\" then
				skipBackslashInString()
			else
				consume()
			end
		end

		local finish = position()
		consume() -- delim

		return {
			kind = "quoted",
			range = makeRange(start, finish), -- includes closing delim
		}
	end

	local function readInterpSection(start: Types.Position, startOffset: number): Types.String
		while peekCh() ~= "`" do
			local ch = peekCh()
			if ch == "" or ch == "\n" then
				return { -- broken interp
					kind = "interp",
					range = makeRange(start, position()),
				}
			elseif ch == "\\" then
				if string.sub(source, offset + 1, offset + 2) == "u{" then
					offset += 3 -- \u{
				else
					skipBackslashInString()
				end
			elseif ch == "{" then
				table.insert(braceStack, "interp")
				local finish = position()
				consume()
				if peekCh() == "{" then
					local doubleBraceFinish = position()
					consume()
					return {
						kind = "interp",
						range = makeRange(start, doubleBraceFinish), -- broken double brace
					}
				end
				return {
					kind = "interp", -- section
					range = makeRange(start, finish),
				}
			else
				consume()
			end
		end

		local finish = position()
		consume() -- closing `

		return {
			kind = "interp",
			range = makeRange(start, finish),
		}
	end

	local function readInterpBegin(): Types.String
		local start = position()
		local startOffset = offset
		consume()
		return readInterpSection(start, startOffset)
	end

	local comments = {}
	local strings = {}

	while true do
		while isSpace(peekCh()) do
			consume()
		end
		if offset > length then
			break
		end

		if string.sub(source, offset, offset + 1) == "--" then
			local comment = readComment()
			comment.header = isHeaderBlock
			table.insert(comments, comment)
			continue
		end

		-- non-comment lexeme
		isHeaderBlock = false

		if peekCh() == '"' or peekCh() == "'" then
			table.insert(strings, readQuotedString())
		elseif peekCh() == "[" then
			local start = position()
			local sep = skipLongSeparator()
			if sep >= 0 then
				table.insert(strings, readLongString(start, sep))
			elseif sep < -1 then
				local finish = position()
				table.insert(strings, { -- e.g. a lone [==
					kind = "long",
					range = makeRange(start, {
						line = finish.line,
						character = finish.character - 1,
					}),
				})
				consume()
			else
				consume()
			end
		elseif peekCh() == "`" then
			table.insert(strings, readInterpBegin())
		elseif peekCh() == "{" then
			consume()
			if #braceStack > 0 then
				table.insert(braceStack, "normal")
			end
		elseif peekCh() == "}" then
			local start = position()
			local startOffset = offset
			consume()
			local braceStackTop = table.remove(braceStack)
			if braceStackTop == "interp" then
				table.insert(strings, readInterpSection(start, startOffset))
			end
		else
			consume()
		end
	end

	return {
		comments = comments,
		strings = strings,
	}
end

return {
	parse = parse,
	isInComment = isInComment,
	isInString = isInString,
}
