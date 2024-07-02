export type Requires = { [string]: { lineNumber: number } }

export type ServiceAcquisitions = { [string]: { lineNumber: number, identifier: string } }

export type Comment = {
	kind: "simple" | "long",
	range: Range,
	header: boolean,
	text: string,
}

export type String = {
	kind: "quoted" | "long" | "interp",
	range: Range,
	text: string,
}

export type Position = {
	line: number,
	character: number,
}

export type Range = {
	start: Position,
	["end"]: Position,
}

export type AutocompleteRequest = {
	position: Position,
	textDocument: {
		document: ScriptDocument?,
		script: LuaSourceContainer?,
	},
}

export type AutocompleteResponseItem = {
	label: string,
	kind: Enum.CompletionItemKind?,
	tags: { Enum.CompletionItemTag }?,
	detail: string?,
	documentation: {
		value: string,
	}?,
	overloads: number?,
	learnMoreLink: string?,
	codeSample: string?,
	preselect: boolean?,
	textEdit: {
		newText: string,
		replace: Range,
	}?,
}

export type AutocompleteResponse = {
	items: { AutocompleteResponseItem },
}

export type AutocompleteCallback = (
	request: AutocompleteRequest,
	response: AutocompleteResponse
) -> AutocompleteResponse

return {}
