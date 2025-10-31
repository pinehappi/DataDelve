--!strict

local Settings = require(script.Parent.Parent.Parent.Settings)
local Theme = require(script.Parent.Parent.Theme)
local UIMessages = require(script.Parent.Parent.UIMessages)

local json5 = require(script.Parent.Parent.Parent.json5)
local JSONHelper = require(script.Parent.Parent.Parent.JSONHelper)

local Types = require(script.Parent.Types)

local CodeEditor = require(script.CodeEditor)

local getHighlightColors = require(script.Parent.Parent.Utilities.getHighlightColors)

export type CodeViewerFields = {
	isHistoryCapable: false,
	isKeyInfoCapable: false,

	_dirtyChanged: BindableEvent,
	dirtyChanged: RBXScriptSignal,

	isDirty: boolean,

	_idLookedUp: BindableEvent,
	idLookedUp: RBXScriptSignal,

	_container: typeof(script.Container),
	_editor: CodeEditor.CodeEditor,
	_theme: Theme.Theme,
	_connections: { RBXScriptConnection },
}

export type CodeViewerImplementation = {
	__index: CodeViewerImplementation,
	new: (Theme.Theme, UIMessages.UIMessages, GuiObject, Types.NewOptions) -> CodeViewer,

	getValue: (CodeViewer) -> Types.GetValueResult,
	setDisabled: (CodeViewer, disabled: boolean) -> (),
	undirty: (CodeViewer) -> (),

	_updateTheme: (CodeViewer) -> (),

	destroy: (CodeViewer) -> (),
}

type CodeViewer = typeof(setmetatable({} :: CodeViewerFields, {} :: CodeViewerImplementation))

local CodeViewer: CodeViewerImplementation = {} :: CodeViewerImplementation
CodeViewer.__index = CodeViewer

local function getCodeEditorTheme(theme: Theme.Theme): CodeEditor.Theme
	local highlightColors = getHighlightColors(theme)
	local tokenColors = {}

	for token, group in JSONHelper.highlightGroups do
		if group ~= "plain" then
			tokenColors[token] = "#" .. highlightColors[group]:ToHex()
		end
	end

	return {
		padding = { top = 2, left = 2, bottom = 2, right = 2 },
		textColor = highlightColors.plain,
		disabledTextColor = highlightColors.disabled,
		backgroundColor = highlightColors.background,
		font = Font.fromEnum(Enum.Font.Code),
		textSize = 15,
		scrollbarThickness = 6,
		scrollbarColor = highlightColors.scrollbar,
		gutter = {
			padding = { left = 2, right = 8 },
			backgroundColor = highlightColors.background,
			textColor = highlightColors.disabled,
		},
		tokenColors = tokenColors,
	}
end

function CodeViewer.new(
	theme: Theme.Theme,
	uiMessages: UIMessages.UIMessages,
	container: GuiObject,
	options: Types.NewOptions
)
	local self = setmetatable({}, CodeViewer)
	self.isHistoryCapable = false :: any
	self.isKeyInfoCapable = false :: any

	self._theme = theme

	self._container = script.Container:Clone()
	self._container.Parent = container

	self._editor = CodeEditor.new({
		doLex = function(source: string)
			return json5.lex(source, {
				mode = "strict",
			}) :: any
		end,
		theme = getCodeEditorTheme(theme),
	})

	-- events
	self._dirtyChanged = Instance.new("BindableEvent")
	self.dirtyChanged = self._dirtyChanged.Event :: any

	self._idLookedUp = Instance.new("BindableEvent")
	self.idLookedUp = self._idLookedUp.Event :: any

	self.isDirty = true -- always dirty

	self._connections = {
		theme.colorsChanged:Connect(function()
			self:_updateTheme()
		end),
		Settings.changed:Connect(function(name)
			if name == "highlightColors" then
				self:_updateTheme()
			end
		end),
	}

	-- setup the editor
	local lastTextChange = 0
	local analysisThread: thread?
	self._editor.textChanged:Connect(function()
		lastTextChange = os.clock()
		if not analysisThread then
			analysisThread = task.spawn(function()
				while os.clock() - lastTextChange <= 1 do
					task.wait()
				end

				local result = json5.decode(self._editor:getText(), {
					mode = "permissive",
				})

				local errors = {}
				if result.kind == "failure" then
					for _, err in result.errors do
						if err.token then
							table.insert(errors, {
								line = err.token.startLine,
								column = err.token.startColumn,
								message = err.message,
							})
						else
							table.insert(
								errors,
								{
									message = err.message,
								} :: any
							)
						end
					end
				end

				self._editor:setErrors(errors)
				analysisThread = nil
			end)
		end
	end)

	self._editor.activeErrorsChanged:Connect(function(errors: { CodeEditor.Error })
		if #errors == 0 then
			self._container.Error.Visible = false
		else
			local text = {}
			for _, err in errors do
				if err.line then
					table.insert(text, `[line {err.line} col {err.column}] {err.message}`)
				else
					table.insert(text, err.message)
				end
			end
			self._container.Error.Visible = true
			self._container.Error.TextLabel.Text = table.concat(text, " and ")
		end
	end)

	self._editor:setText(json5.encode(options.data, {
		mode = "readable",
		tabSize = 2,
	}))

	self:_updateTheme()
	self._editor:setParent(self._container.EditorContainer)

	return self
end

function CodeViewer:getValue()
	local text = self._editor:getText()
	local result = json5.decode(text, {
		mode = "permissive",
	})

	if result.kind == "failure" then
		return {
			kind = "failure",
			message = "Failed to parse.",
		}
	else
		return {
			kind = "success",
			value = result.json,
			hasNil = false, -- TODO: detect if the user put any nils
		}
	end
end

function CodeViewer:setDisabled(disabled: boolean)
	self._editor:setDisabled(disabled)
end

function CodeViewer:undirty()
	-- always dirty, do nothing
end

function CodeViewer:_updateTheme()
	self._editor:setTheme(getCodeEditorTheme(self._theme))
	self._container.Error.BackgroundColor3 = self._theme.colors.message.background
	self._container.Error.UIStroke.Color = self._theme.colors.message.outline
	self._container.Error.TextLabel.TextColor3 = self._theme.colors.error
	self._container.Error.ImageLabel.ImageColor3 = self._theme.colors.error
	self._container.Error.ImageLabel.Image = self._theme.icons.error
end

function CodeViewer:destroy()
	for _, connection in self._connections do
		connection:Disconnect()
	end

	self._editor:destroy()
	self._editor = nil :: any

	self._container:Destroy()

	self._dirtyChanged:Destroy()
	self._idLookedUp:Destroy()
end

return CodeViewer
