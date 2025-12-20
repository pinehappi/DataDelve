--!strict

local Settings = require(script.Parent.Parent.Parent.Settings)
local Theme = require(script.Parent.Parent.Theme)
local UIMessages = require(script.Parent.Parent.UIMessages)

local json5 = require(script.Parent.Parent.Parent.json5)
local JSONHelper = require(script.Parent.Parent.Parent.JSONHelper)

local Types = require(script.Parent.Types)
local EditorTypes = require(script.Types)

local CodeEditor = require(script.CodeEditor)
local DumbEditor = require(script.DumbEditor)

local getHighlightColors = require(script.Parent.Parent.Utilities.getHighlightColors)

-- after this many characters, switch from the CodeEditor to the DumbEditor
local CODE_EDITOR_CUTOFF = 20_000
local MAX_TEXTBOX_CHARACTERS = 200_000

export type CodeViewerFields = {
	_dirtyChanged: BindableEvent,
	dirtyChanged: RBXScriptSignal,

	isDirty: boolean,

	_idLookedUp: BindableEvent,
	idLookedUp: RBXScriptSignal,

	_container: typeof(script.Container),
	_editor: EditorTypes.TextEditorObject?,
	_theme: Theme.Theme,
	_connections: { RBXScriptConnection },
	_cachedData: unknown,
}

export type CodeViewerImplementation = {
	__index: CodeViewerImplementation,
	new: (Theme.Theme, UIMessages.UIMessages, GuiObject, Types.NewOptions) -> CodeViewer,

	getHistoryCapability: (CodeViewer) -> Types.HistoryCapability?,
	getKeyInfoCapability: (CodeViewer) -> Types.KeyInfoCapability?,

	getValue: (CodeViewer) -> Types.GetValueResult,
	setDisabled: (CodeViewer, disabled: boolean) -> (),
	undirty: (CodeViewer) -> (),

	_updateTheme: (CodeViewer) -> (),
	_updateTextEditorFrom: (CodeViewer, data: unknown) -> (),

	destroy: (CodeViewer) -> (),
}

type CodeViewer = typeof(setmetatable({} :: CodeViewerFields, {} :: CodeViewerImplementation))

local CodeViewer: CodeViewerImplementation = {} :: CodeViewerImplementation
CodeViewer.__index = CodeViewer

local function getCodeEditorTheme(theme: Theme.Theme): EditorTypes.Theme
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

local function enhanceErrorMessage(message: string): string
	return message
		:gsub("doubleQuotedString", [["]])
		:gsub("leftCurlyBracket", "'{'")
		:gsub("leftSquareBracket", "'['")
		:gsub("rightCurlyBracket", "'}'")
		:gsub("rightSquareBracket", "']'")
		:gsub("singleQuotedString", [[']])
		:gsub("colon", "':'")
		:gsub("equals", "'='")
		:gsub("comma", "','")
end

local function collectDecodeErrors(result: json5.DecodeResult): { EditorTypes.Error }
	local errors = {}
	if result.kind == "failure" then
		for _, err in result.errors do
			if err.token then
				table.insert(errors, {
					line = err.token.startLine,
					column = err.token.startColumn,
					message = err.message or (err.token :: json5.ErrorToken).message,
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
	return errors
end

local function formatError(err: EditorTypes.Error): string
	if err.line then
		return `[line {err.line} col {err.column}] {err.message}`
	else
		return err.message
	end
end

function CodeViewer.new(
	theme: Theme.Theme,
	uiMessages: UIMessages.UIMessages,
	container: GuiObject,
	options: Types.NewOptions
)
	local self = setmetatable({}, CodeViewer)
	self._theme = theme

	self._container = script.Container:Clone()
	self._container.Parent = container

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

	self:_updateTheme()

	self:_updateTextEditorFrom(options.data)

	return self
end

function CodeViewer:getHistoryCapability()
	return nil
end

function CodeViewer:getKeyInfoCapability()
	return nil
end

function CodeViewer:getValue()
	if not self._editor then
		return { kind = "success", value = self._cachedData, hasNil = false }
	end

	local text = self._editor:getText()
	local result = json5.decode(text, {
		mode = "permissive",
		doesRecover = false,
	})

	if result.kind == "failure" then
		local errors = collectDecodeErrors(result)
		if #result.errors == 1 then
			return {
				kind = "failure",
				message = enhanceErrorMessage(formatError(errors[1])),
			}
		else
			local lineSet = {}
			for _, err in errors do
				lineSet[err.line] = true
			end

			local lines = {}
			for line in lineSet do
				table.insert(lines, line)
			end

			table.sort(lines)

			return {
				kind = "failure",
				message = `Errors on lines {table.concat(lines, ", ", 1, #lines - 1)} and {lines[#lines]}`,
			}
		end
	else
		return {
			kind = "success",
			value = result.json,
			hasNil = false, -- TODO: detect if the user put any nils
		}
	end
end

function CodeViewer:setDisabled(disabled: boolean)
	if self._editor then
		self._editor:setDisabled(disabled)
	end
end

function CodeViewer:undirty()
	-- always dirty, do nothing
end

function CodeViewer:_updateTheme()
	if self._editor then
		self._editor:setTheme(getCodeEditorTheme(self._theme))
	end

	self._container.Error.BackgroundColor3 = self._theme.colors.message.background
	self._container.Error.UIStroke.Color = self._theme.colors.message.outline
	self._container.Error.TextLabel.TextColor3 = self._theme.colors.message.text
	self._container.Error.ImageLabel.ImageColor3 = self._theme.colors.error
	self._container.Error.ImageLabel.Image = self._theme.icons.error
end

function CodeViewer:_updateTextEditorFrom(data: unknown)
	if self._editor then
		self._editor:destroy()
	end

	local editorTheme = getCodeEditorTheme(self._theme)
	local text: string
	local success, err = pcall(function()
		self._cachedData = data
		text = json5.encode(data :: any, {
			mode = "readable",
			tab = "\t",
		})
	end)

	self._container.Error.Visible = false
	self._container.Error.Size = UDim2.fromScale(1, 0)
	self._container.Error.AutomaticSize = Enum.AutomaticSize.Y
	self._container.Error.UIListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	self._container.Error.TextLabel.UIFlexItem.FlexMode = Enum.UIFlexMode.Fill
	self._container.EditorContainer.Visible = true

	local isTooLarge = text and #text > MAX_TEXTBOX_CHARACTERS
	if (not success) or isTooLarge then
		self._container.Error.Visible = true
		self._container.Error.Size = UDim2.fromScale(1, 1)
		self._container.Error.AutomaticSize = Enum.AutomaticSize.None
		self._container.Error.UIListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		self._container.Error.TextLabel.UIFlexItem.FlexMode = Enum.UIFlexMode.None
		self._container.EditorContainer.Visible = false

		self._container.Error.TextLabel.Text = if isTooLarge
			then "Data is too large. Use the tree view mode."
			elseif
				typeof(err) == "string" and err:match("unexpected type buffer")
			then "Buffers are not supported. Use the tree view mode."
			else `There was an error. Try using the tree view mode. Error: {err}`

		self._editor = nil
	elseif #text > CODE_EDITOR_CUTOFF then
		local editor = DumbEditor({
			theme = editorTheme,
		})

		editor:setText(text)

		self._container.Error.Visible = true
		self._container.Error.TextLabel.Text = "Editor features disabled due to large size of data."

		self._editor = editor
	else
		local editor = CodeEditor({
			doLex = function(source: string)
				return json5.lex(source, {
					mode = "strict",
				}) :: any
			end,
			theme = editorTheme,
		})

		local lastTextChange = 0
		local analysisThread: thread?
		editor.textChanged:Connect(function()
			lastTextChange = os.clock()
			if not analysisThread then
				analysisThread = task.spawn(function()
					while os.clock() - lastTextChange <= 1 do
						task.wait()
					end

					local result = json5.decode(editor:getText(), {
						mode = "permissive",
						doesRecover = false,
					})

					local errors = collectDecodeErrors(result)

					editor:setErrors(errors)
					analysisThread = nil
				end)
			end
		end)

		editor.activeErrorsChanged:Connect(function(errors: { EditorTypes.Error })
			if #errors == 0 then
				self._container.Error.Visible = false
			else
				local text = {}
				for _, err in errors do
					table.insert(text, formatError(err))
				end

				self._container.Error.Visible = true
				self._container.Error.TextLabel.Text = enhanceErrorMessage(table.concat(text, " and "))
			end
		end)

		editor:setText(text)

		self._editor = editor
	end

	if self._editor then
		self._editor:setParent(self._container.EditorContainer)
	end
end

function CodeViewer:destroy()
	for _, connection in self._connections do
		connection:Disconnect()
	end

	if self._editor then
		self._editor:destroy()
		self._editor = nil
	end

	self._container:Destroy()

	self._dirtyChanged:Destroy()
	self._idLookedUp:Destroy()
end

return CodeViewer
