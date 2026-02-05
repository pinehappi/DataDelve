--!strict

local TextService = game:GetService("TextService")
local Types = require(script.Parent.Types)

export type NewOptions = {
	theme: Types.Theme,
	doLex: (source: string) -> {Token},
}

export type Token = {
	kind: string,
	start: number,
	length: number,
}

type CodeEditorObject = Types.TextEditorObject & {
	_textChanged: BindableEvent,
	_activeErrorsChanged: BindableEvent,
	
	_frame: ScrollingFrame,
	_theme: Types.Theme,
	_textBox: TextBox,
	_textBoxPadding: UIPadding,
	_overlay: TextLabel,
	_gutter: TextLabel,
	_gutterPadding: UIPadding,
	_errorFrameContainer: Folder,
	_errorFrames: {Frame},
	_singleCharacterBounds: Vector2,
	_lastLineCount: number,
	_errors: {Types.Error},
	_errorLookups: {[number]: {Types.Error}},
	_disabled: boolean,
	_connections: {RBXScriptConnection},
	_doLex: (source: string) -> {Token},
}

local function getSingleCharacterBounds(theme: Types.Theme)
	local params = Instance.new("GetTextBoundsParams")
	params.Font = theme.font
	params.Text = "a"
	params.Size = theme.textSize

	local bounds = TextService:GetTextBoundsAsync(params)
	return bounds
end

local function escapeRichText(text: string): string
	return text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub("\"", "&quot;"):gsub("'", "&apos;")
end

local function updateHighlights(self: CodeEditorObject)
	local overlayText = table.create(16)
	local source = self._textBox.Text
	local tokens = self._doLex(source)

	for _, t in tokens do
		local color = self._theme.tokenColors[t.kind]
		if color then
			table.insert(overlayText,
				"<font color=\"" .. color .. "\">"
					.. escapeRichText(source:sub(t.start, t.start + t.length - 1))
					.. "</font>"
			)
		else
			table.insert(overlayText,
				"<font transparency=\"1\">"
					.. escapeRichText(source:sub(t.start, t.start + t.length - 1))
					.. "</font>"
			)
		end
	end

	self._overlay.Text = table.concat(overlayText)
end

local function updateTheme(self: CodeEditorObject)
	self._singleCharacterBounds = getSingleCharacterBounds(self._theme)

	self._frame.BackgroundColor3 = self._theme.backgroundColor
	self._frame.ScrollBarThickness = self._theme.scrollbarThickness
	self._frame.ScrollBarImageColor3 = self._theme.scrollbarColor
	self._frame.ScrollBarThickness = self._theme.scrollbarThickness

	self._textBox.FontFace = self._theme.font
	self._textBox.TextSize = self._theme.textSize
	self._textBox.TextColor3 = self._theme.textColor
	if self._disabled then
		self._textBox.TextColor3 = self._theme.disabledTextColor
	end

	self._overlay.FontFace = self._theme.font
	self._overlay.TextSize = self._theme.textSize
	self._overlay.Visible = not self._disabled

	self._textBoxPadding.PaddingTop = UDim.new(0, self._theme.padding.top)
	self._textBoxPadding.PaddingBottom = UDim.new(0, self._theme.padding.bottom)
	self._textBoxPadding.PaddingLeft = UDim.new(0, self._theme.padding.left)
	self._textBoxPadding.PaddingRight = UDim.new(0, self._theme.padding.right)

	self._gutter.BackgroundColor3 = self._theme.gutter.backgroundColor
	self._gutter.TextColor3 = self._theme.gutter.textColor
	self._gutter.FontFace = self._theme.font
	self._gutter.TextSize = self._theme.textSize

	self._gutterPadding.PaddingTop = UDim.new(0, self._theme.padding.top)
	self._gutterPadding.PaddingBottom = UDim.new(0, self._theme.padding.bottom)
	self._gutterPadding.PaddingLeft = UDim.new(0, self._theme.gutter.padding.left)
	self._gutterPadding.PaddingRight = UDim.new(0, self._theme.gutter.padding.right)

	updateHighlights(self)
	self:setErrors(self._errors)
end

local function countLines(text: string, upto: number?): number
	if upto then
		local _, replacements = text:sub(1, upto - 1):gsub("\n", "\n")
		return replacements + 1
	else
		local _, replacements = text:gsub("\n", "\n")
		return replacements + 1
	end
end

local function getTopAndBottomLinesInView(self: CodeEditorObject)
	local bottomLine = math.ceil(self._frame.CanvasPosition.Y / self._singleCharacterBounds.Y) 
	local topLine = math.floor((self._frame.CanvasPosition.Y + self._frame.AbsoluteSize.Y) / self._singleCharacterBounds.Y) - 1
	return bottomLine, topLine
end

local function getCurrentLine(self: CodeEditorObject): number?
	if self._textBox.CursorPosition <= 0 then
		return
	end

	return countLines(self._textBox.Text, self._textBox.CursorPosition)
end

local function updateGutter(self: CodeEditorObject)
	local lines = table.create(self._lastLineCount)
	for i = 1, math.min(10, self._lastLineCount) do
		lines[i] = "  " .. i
	end
	for i = 10, self._lastLineCount do
		lines[i] = tostring(i)
	end
	self._gutter.Text = table.concat(lines, "\n")
end

local function updateGutterIfNecessary(self: CodeEditorObject)
	local count = countLines(self._textBox.Text)
	if self._lastLineCount ~= count then
		self._lastLineCount = count
		updateGutter(self)
	else
		self._lastLineCount = count
	end
end

local function updateActiveErrors(self: CodeEditorObject, currentLine: number)
	local errors = self._errorLookups[currentLine]
	if errors then
		self.activeErrors = table.clone(errors)

		-- insert all errors with no location
		for _, v in self._errors do
			if not v.line then
				table.insert(self.activeErrors, v)
			end
		end

		self._activeErrorsChanged:Fire(errors)
	else
		self.activeErrors = {}
		self._activeErrorsChanged:Fire({})
	end
end

local CodeEditorMethods: Types.TextEditorMethods<CodeEditorObject> = {} :: Types.TextEditorMethods<CodeEditorObject>
local mt = {__index = CodeEditorMethods :: any}

function CodeEditorMethods.setParent(self: CodeEditorObject, parent: Instance)
	self._frame.Parent = parent
end

function CodeEditorMethods.getText(self: CodeEditorObject): string
	return self._textBox.Text
end

function CodeEditorMethods.setText(self: CodeEditorObject, text: string)
	self._textBox.Text = text
end

function CodeEditorMethods.setErrors(self: CodeEditorObject, errors: {Types.Error})
	self._errors = errors
	self._errorLookups = {}
	
	local unusedErrorFrames = self._errorFrames
	local usedErrorFrames = {}
	
	for _, err in errors do
		if not err.line then
			continue
		end
		
		if self._errorLookups[err.line] then
			table.insert(self._errorLookups[err.line], err)
		else
			self._errorLookups[err.line] = {err}
		end
	end
	
	for line, errors in self._errorLookups do
		local errorFrame = table.remove(unusedErrorFrames) or Instance.new("Frame")
		errorFrame.Size = UDim2.new(1, 0, 0, self._singleCharacterBounds.Y)
		errorFrame.Position = UDim2.fromOffset(0, ((errors[1].line :: number) - 1) * self._singleCharacterBounds.Y + self._theme.padding.top)
		errorFrame.BorderSizePixel = 0
		errorFrame.BackgroundTransparency = 0.6
		errorFrame.BackgroundColor3 = Color3.fromHex(self._theme.tokenColors.error)
		errorFrame.ZIndex = -1
		errorFrame.Visible = true
		errorFrame.Parent = self._errorFrameContainer

		table.insert(usedErrorFrames, errorFrame)
	end
	
	self._errorFrames = usedErrorFrames
	for _, v in unusedErrorFrames do
		v:Destroy()
	end
	
	local currentLine = getCurrentLine(self)
	if currentLine then
		updateActiveErrors(self, currentLine)
	end
end

function CodeEditorMethods.setTheme(self: CodeEditorObject, theme: Types.Theme)
	self._theme = theme
	updateTheme(self)
end

function CodeEditorMethods.setDisabled(self: CodeEditorObject, disabled: boolean)
	self._textBox.TextEditable = not disabled
	self._disabled = disabled
	updateTheme(self)
end

function CodeEditorMethods:destroy()
	for _, c in self._connections do
		c:Disconnect()
	end
	
	self._textChanged:Destroy()
	self._activeErrorsChanged:Destroy()
	
	self._frame:Destroy()
end

return function(options: NewOptions): Types.TextEditorObject
	local self: CodeEditorObject = setmetatable({}, mt) :: CodeEditorObject

	self._frame = Instance.new("ScrollingFrame")
	self._frame.Size = UDim2.fromScale(1, 1)
	self._frame.VerticalScrollBarInset = Enum.ScrollBarInset.Always
	self._frame.HorizontalScrollBarInset = Enum.ScrollBarInset.None
	self._frame.BorderSizePixel = 0
	self._frame.CanvasSize = UDim2.fromOffset(0, 0)
	self._frame.AutomaticCanvasSize = Enum.AutomaticSize.XY

	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Horizontal
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = self._frame

	self._textBox = Instance.new("TextBox")
	self._textBox.BackgroundTransparency = 1
	self._textBox.TextXAlignment = Enum.TextXAlignment.Left
	self._textBox.TextYAlignment = Enum.TextYAlignment.Top
	self._textBox.ClearTextOnFocus = false
	self._textBox.MultiLine = true
	self._textBox.Size = UDim2.fromScale(0, 1)
	self._textBox.AutomaticSize = Enum.AutomaticSize.XY
	self._textBox.LayoutOrder = 1
	self._textBox.Text = ""
	self._textBox.Parent = self._frame

	self._overlay = Instance.new("TextLabel")
	self._overlay.Size = UDim2.fromScale(1, 1)
	self._overlay.BackgroundTransparency = 1
	self._overlay.RichText = true
	self._overlay.TextXAlignment = Enum.TextXAlignment.Left
	self._overlay.TextYAlignment = Enum.TextYAlignment.Top
	self._overlay.Text = ""
	self._overlay.Parent = self._textBox

	local flex = Instance.new("UIFlexItem")
	flex.FlexMode = Enum.UIFlexMode.Grow
	flex.Parent = self._textBox

	self._textBoxPadding = Instance.new("UIPadding")
	self._textBoxPadding.Parent = self._textBox

	self._gutter = Instance.new("TextLabel")
	self._gutter.RichText = true
	self._gutter.AutomaticSize = Enum.AutomaticSize.X
	self._gutter.Size = UDim2.fromScale(0, 1)
	self._gutter.BorderSizePixel = 0
	self._gutter.LayoutOrder = 0
	self._gutter.TextXAlignment = Enum.TextXAlignment.Right
	self._gutter.TextYAlignment = Enum.TextYAlignment.Top
	self._gutter.Parent = self._frame

	self._gutterPadding = Instance.new("UIPadding")
	self._gutterPadding.Parent = self._gutter

	self._errorFrameContainer = Instance.new("Folder")
	self._errorFrameContainer.Parent = self._frame

	self._theme = options.theme
	self._singleCharacterBounds = Vector2.new(0, 0)
	self._lastLineCount = -1

	self.activeErrors = {}
	self._activeErrorsChanged = Instance.new("BindableEvent")
	self.activeErrorsChanged = self._activeErrorsChanged.Event :: RBXScriptSignal
	self._errors = {}
	self._errorLookups = {}
	self._errorFrames = {} :: {Frame}
	self._disabled = false

	self._doLex = options.doLex

	self._textChanged = Instance.new("BindableEvent")
	self.textChanged = self._textChanged.Event :: RBXScriptSignal

	local lastTextSize = 0
	self._connections = {
		self._textBox:GetPropertyChangedSignal("Text"):Connect(function()
			-- hide any errors since they might no longer be valid
			for _, v in self._errorFrames do
				v.Visible = false
			end

			-- auto-indent if necessary
			if self._textBox.CursorPosition > 0 and #self._textBox.Text > lastTextSize then
				local addedCharacter = self._textBox.Text:sub(self._textBox.CursorPosition - 1, self._textBox.CursorPosition - 1)
				if addedCharacter == "\n" then
					local currentLine = getCurrentLine(self)
					if currentLine then
						local lastLine = self._textBox.Text:split("\n")[currentLine - 1]
						if lastLine then
							local indent = lastLine:match("^[\t ]*") or ""
							if #indent > 0 then
								self._textBox.Text =
									self._textBox.Text:sub(1, self._textBox.CursorPosition - 2)
									.. "\n"
									.. indent
									.. self._textBox.Text:sub(self._textBox.CursorPosition)
								self._textBox.CursorPosition += #indent
								lastTextSize = #self._textBox.Text
								return
							end
						end
					end
				end
			end

			lastTextSize = #self._textBox.Text

			updateGutterIfNecessary(self)
			updateHighlights(self)

			self._textChanged:Fire(self._textBox.Text)
		end),
		self._textBox:GetPropertyChangedSignal("CursorPosition"):Connect(function()
			local currentLine = getCurrentLine(self)
			if currentLine then
				-- scroll the cursor into view
				local bottomLine, topLine = getTopAndBottomLinesInView(self)
				if currentLine < bottomLine then
					self._frame.CanvasPosition = Vector2.new(self._frame.CanvasPosition.X, (currentLine - 1) * self._singleCharacterBounds.Y)
				elseif currentLine > topLine then
					local heightLines = math.floor(self._frame.AbsoluteSize.Y / self._singleCharacterBounds.Y)
					self._frame.CanvasPosition = Vector2.new(self._frame.CanvasPosition.X, (currentLine - heightLines + 1) * self._singleCharacterBounds.Y)
				end

				-- update active errors
				updateActiveErrors(self, currentLine)
			end
		end),
		self._frame:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(function()
			-- UDim2.fromScale(1, 0) doesn't work for whatever reason
			self._gutter.Size = UDim2.fromOffset(0, self._frame.AbsoluteCanvasSize.Y)
		end)
	}

	updateTheme(self)
	updateGutterIfNecessary(self)

	return self
end