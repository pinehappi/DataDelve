--!strict

export type Theme = {
	padding: { top: number, left: number, bottom: number, right: number },
	font: Font, -- should be monospace
	textSize: number,
	backgroundColor: Color3,
	textColor: Color3,
	disabledTextColor: Color3,
	scrollbarThickness: number,
	scrollbarColor: Color3,

	tokenColors: { [string]: string }, -- should be a hex color

	gutter: {
		backgroundColor: Color3,
		textColor: Color3,
		padding: { left: number, right: number },
	},
}

export type Error = {
	line: number?,
	column: number?,
	message: string,
}

export type TextEditorMethods<Object> = {
	setParent: (Object, parent: Instance) -> (),
	getText: (Object) -> string,
	setText: (Object, text: string) -> (),
	setErrors: (Object, { Error }) -> (),
	setTheme: (Object, Theme) -> (),
	setDisabled: (Object, disabled: boolean) -> (),
	destroy: (Object) -> (),
}

export type TextEditorObject = typeof(setmetatable(
	{} :: {
		-- params:
		--   text: string
		textChanged: RBXScriptSignal,

		-- params:
		--   errors: {Error}
		activeErrorsChanged: RBXScriptSignal,
		activeErrors: { Error },
	},
	{} :: { __index: TextEditorMethods<unknown> }
))

return {}
