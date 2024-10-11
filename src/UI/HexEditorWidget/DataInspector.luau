--!strict
-- I will document later. For now, good luck! 🫡

export type DataInspectorSizing = "fillContainer" | "fillContainerY"

export type DataInspectorNewParams = {
	container: GuiObject,
	-- Default is "fillContainer"
	sizing: DataInspectorSizing?,
	theme: ThemeData,
}

export type ThemeData = {
	background: Color3,
	bodyPadding: number,
	editorMargin: number, -- How far from the hex editor to place it

	headerBackground: Color3,
	headerText: Color3,

	keyText: Color3,
	valueText: Color3,
	invalidValueText: Color3,
	keyValuePadding: number,
	rowPadding: number,

	font: Font,
	textSize: number,

	scrollingFrameProperties: { [string]: unknown },
}

--

local TextService = game:GetService("TextService")

local HexEditor = require(script.Parent.HexEditor)

export type DataInspectorImplementation = {
	__index: DataInspectorImplementation,

	new: (HexEditor.HexEditor, DataInspectorNewParams) -> DataInspector,
	setTheme: (DataInspector, ThemeData) -> (),
	destroy: (DataInspector) -> (),

	_setTheme: (DataInspector, ThemeData) -> (),

	_buildHeader: (DataInspector) -> (),
	_buildRow: (DataInspector, rowName: string) -> (),
	_updateRows: (DataInspector) -> (),
	_buildUi: (DataInspector) -> (),
	_updatePosition: (DataInspector) -> (),
	_clearUi: (DataInspector) -> (),
}

export type DataInspectorFields = {
	editor: HexEditor.HexEditor,
	horizontalSpaceUsed: number,

	-- Access at your own risk.
	scrollingFrame: ScrollingFrame?,

	--[[ Private ]]
	_sizing: DataInspectorSizing,
	_theme: ThemeData,

	_container: GuiObject,

	_headerHeight: number,
	_rowHeight: number,
	_keyWidth: number,
	_valueWidth: number,
	_rowsCount: number,

	_header: TextLabel?,
	_rows: { [string]: { frame: Frame, key: TextLabel, value: TextBox } },

	_lastOffset: number?,

	_connections: { RBXScriptConnection },
}

export type DataInspector = typeof(setmetatable({} :: DataInspectorFields, {} :: DataInspectorImplementation))

local DataInspector: DataInspectorImplementation = {} :: DataInspectorImplementation
DataInspector.__index = DataInspector

function DataInspector.new(editor, params)
	local self = setmetatable({}, DataInspector) :: DataInspector
	self._container = params.container
	self._sizing = params.sizing :: DataInspectorSizing
	self:_setTheme(params.theme)

	self.editor = editor
	self.horizontalSpaceUsed = 0

	self._rows = {}

	self:_buildUi()
	self:_updatePosition()

	self._connections = {
		editor.sizeChanged:Connect(function()
			self:_updatePosition()
		end),
		editor.cursorMoved:Connect(function()
			self:_updateRows()
			self._lastOffset = self.editor:getCursorOffset()
		end),
	}

	return self
end

function DataInspector:setTheme(theme)
	self:_setTheme(theme)
	self:_buildUi()
end

function DataInspector:destroy()
	self:_clearUi()
	for _, connection in self._connections do
		connection:Disconnect()
	end
	self._connections = {}
end

function DataInspector:_setTheme(theme)
	self._theme = theme

	local textParams = Instance.new("GetTextBoundsParams")
	textParams.Font = theme.font
	textParams.Size = theme.textSize
	textParams.Text = "1.7976931348623157e+308" -- Largest float64
	textParams.Width = math.huge

	local valueBounds = TextService:GetTextBoundsAsync(textParams)

	textParams.Text = "binary"
	local keyBounds = TextService:GetTextBoundsAsync(textParams)

	self._keyWidth = keyBounds.X
	self._valueWidth = valueBounds.X
	self._rowHeight = valueBounds.Y + theme.rowPadding
	self._headerHeight = valueBounds.Y + 2 * theme.rowPadding
end

function DataInspector:_buildHeader()
	local label = Instance.new("TextLabel")
	label.BorderSizePixel = 0
	label.BackgroundColor3 = self._theme.headerBackground
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = self._theme.headerText
	label.FontFace = Font.new(self._theme.font.Family, Enum.FontWeight.Bold, self._theme.font.Style)
	label.TextSize = self._theme.textSize
	label.Size = UDim2.fromOffset(self.horizontalSpaceUsed, self._headerHeight)
	label.Text = "Data Inspector"
	label.Position = UDim2.fromOffset(self._theme.bodyPadding, 0)
	label.Name = "Header"
	label.Parent = self.scrollingFrame
	self._header = label
end

function DataInspector:_buildRow(rowName: string)
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromOffset(self._keyWidth + self._theme.keyValuePadding + self._valueWidth, self._rowHeight)
	frame.Position = UDim2.fromOffset(self._theme.bodyPadding, self._headerHeight + self._rowHeight * self._rowsCount)
	frame.Name = rowName

	local key = Instance.new("TextLabel")
	key.BackgroundTransparency = 1
	key.Size = UDim2.fromOffset(self._keyWidth, self._rowHeight)
	key.TextColor3 = self._theme.keyText
	key.FontFace = self._theme.font
	key.TextSize = self._theme.textSize
	key.TextXAlignment = Enum.TextXAlignment.Left
	key.Text = rowName
	key.Parent = frame

	local value = Instance.new("TextBox")
	value.BackgroundTransparency = 1
	value.FontFace = self._theme.font
	value.TextXAlignment = Enum.TextXAlignment.Left
	value.TextColor3 = self._theme.invalidValueText
	value.TextEditable = false
	value.TextSize = self._theme.textSize
	value.ClearTextOnFocus = false
	value.Text = "none"
	value.Size = UDim2.fromOffset(self._valueWidth, self._rowHeight)
	value.Position = UDim2.fromOffset(self._keyWidth + self._theme.keyValuePadding, 0)
	value.Parent = frame

	frame.Parent = self.scrollingFrame

	self._rows[rowName] = {
		frame = frame,
		key = key,
		value = value,
	}
	self._rowsCount += 1
end

export type RowStrategy = {
	requiredBytes: number,
	func: (buffer: buffer, offset: number) -> unknown,
}
local rowStrategies: { [string]: RowStrategy } = {
	["ascii"] = {
		requiredBytes = 1,
		func = function(b, offset)
			return string.char(buffer.readu8(b, offset))
		end,
	},
	["utf-8"] = {
		requiredBytes = 1,
		func = function(b, offset)
			local count = math.min(4, buffer.len(b) - offset)
			local s = buffer.readstring(b, offset, count)
			local start, finish = s:find(utf8.charpattern)
			if start and finish then
				return `{s:sub(start, finish)} ({finish - start + 1} {finish > start and "bytes" or "byte"})`
			else
				return nil
			end
		end,
	},
	["binary"] = {
		requiredBytes = 1,
		func = function(b, offset)
			local n = buffer.readu8(b, offset)
			local s = {}

			for i = 7, 0, -1 do
				if bit32.band(bit32.lshift(0b1, i), n) == 0 then
					table.insert(s, "0")
				else
					table.insert(s, "1")
				end
			end

			return table.concat(s, "")
		end,
	},
	["i8"] = {
		requiredBytes = 1,
		func = buffer.readi8,
	},
	["u8"] = {
		requiredBytes = 1,
		func = buffer.readu8,
	},
	["i16"] = {
		requiredBytes = 2,
		func = buffer.readi16,
	},
	["u16"] = {
		requiredBytes = 2,
		func = buffer.readu16,
	},
	["i32"] = {
		requiredBytes = 4,
		func = buffer.readi32,
	},
	["u32"] = {
		requiredBytes = 4,
		func = buffer.readu32,
	},
	["f32"] = {
		requiredBytes = 4,
		func = buffer.readf32,
	},
	["f64"] = {
		requiredBytes = 8,
		func = buffer.readf64,
	},
}
function DataInspector:_updateRows()
	local b, bSize = self.editor:getRawBuffer()
	local offset = self.editor:getCursorOffset() or self._lastOffset
	local remaining = 0
	if offset then
		remaining = bSize - offset
	end

	for rowName, row in self._rows do
		local strategy = rowStrategies[rowName]

		local result = if offset and remaining > strategy.requiredBytes then tostring(strategy.func(b, offset)) else nil

		if result == nil then
			row.value.Text = "none"
			row.value.TextColor3 = self._theme.invalidValueText
		else
			row.value.Text = result
			row.value.TextColor3 = self._theme.valueText
		end
	end
end

function DataInspector:_buildUi()
	self:_clearUi()

	local scrollingFrame = Instance.new("ScrollingFrame")
	self.scrollingFrame = scrollingFrame
	scrollingFrame.BackgroundColor3 = self._theme.background
	scrollingFrame.BorderSizePixel = 0
	scrollingFrame.Size = UDim2.fromScale(1, 1)
	scrollingFrame.Parent = self._container

	self.horizontalSpaceUsed = 2 * self._theme.bodyPadding
		+ self._keyWidth
		+ self._theme.keyValuePadding
		+ self._valueWidth

	if self._sizing == "fillContainerY" then
		local sizeConstraint = Instance.new("UISizeConstraint")
		sizeConstraint.MaxSize = Vector2.new(self.horizontalSpaceUsed, math.huge)
		sizeConstraint.Parent = scrollingFrame
	end

	self:_buildHeader()

	self:_buildRow("ascii")
	self:_buildRow("utf-8")
	self:_buildRow("binary")
	self:_buildRow("i8")
	self:_buildRow("u8")
	self:_buildRow("i16")
	self:_buildRow("u16")
	self:_buildRow("i32")
	self:_buildRow("u32")
	self:_buildRow("f32")
	self:_buildRow("f64")

	scrollingFrame.CanvasSize = UDim2.fromOffset(0, self._headerHeight + self._rowHeight * self._rowsCount)

	local scrollingFrameProperties = self._theme.scrollingFrameProperties
	if scrollingFrameProperties then
		for property, value in scrollingFrameProperties do
			(scrollingFrame :: any)[property] = value
		end
	end

	self:_updateRows()
end

function DataInspector:_updatePosition()
	if self.editor.scrollingFrame and self.scrollingFrame then
		self.scrollingFrame.Position = self.editor.scrollingFrame.Position
			+ UDim2.fromOffset(self.editor.horizontalSpaceUsed + self._theme.editorMargin, 0)
	end
end

function DataInspector:_clearUi()
	local header = self._header
	if header then
		header:Destroy()
		self._header = nil
	end

	for _, row in self._rows do
		row.frame:Destroy()
	end
	self._rowsCount = 0
	self._rows = {}

	local scrollingFrame = self.scrollingFrame
	if scrollingFrame then
		scrollingFrame:Destroy()
		self.scrollingFrame = nil
	end
end

return DataInspector
