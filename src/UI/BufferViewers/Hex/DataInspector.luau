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
	lightValueText: Color3,
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

	addRow: (DataInspector, RowInfo) -> (),

	destroy: (DataInspector) -> (),

	--[[ Private ]]

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
	_rowFramesCount: number,

	_header: TextLabel?,
	_rowFrames: { [string]: { frame: Frame, key: TextLabel, value: TextBox } },

	_lastOffset: number?,
	_rowInfos: { RowInfo },

	_connections: { RBXScriptConnection },
}

export type DataInspector = typeof(setmetatable({} :: DataInspectorFields, {} :: DataInspectorImplementation))

type RowInfo = { name: string, strategy: RowStrategy }
export type RowStrategy = {
	requiredBytes: number,
	func: (buffer: buffer, offset: number) -> { text: string, isLight: boolean } | string | number | nil,
}

local SPECIAL_ASCII = {
	[string.byte("\0")] = "\\0",
	[string.byte("\n")] = "\\n",
	[string.byte("\r")] = "\\r",
	[string.byte("\t")] = "\\t",
	[string.byte("\v")] = "\\v",
	[string.byte("\a")] = "\\a",
	[string.byte("\b")] = "\\b",
	[string.byte("\f")] = "\\f",
}

local builtInRows: { RowInfo } = {
	{
		name = "ascii",
		strategy = {
			requiredBytes = 1,
			func = function(b, offset)
				local ascii = buffer.readu8(b, offset)
				if ascii > 127 then
					return nil
				elseif HexEditor.isCharacterPrintable(ascii) then
					return string.char(ascii)
				elseif SPECIAL_ASCII[ascii] then
					return { text = SPECIAL_ASCII[ascii], isLight = true }
				else
					return { text = "non-printable", isLight = true }
				end
			end,
		},
	},
	{
		name = "utf-8",
		strategy = {
			requiredBytes = 1,
			func = function(b, offset)
				local count = math.min(4, buffer.len(b) - offset)
				local s: string
				for i = count, 0, -1 do
					if i == 0 then
						return nil
					end

					s = buffer.readstring(b, offset, count)
					if utf8.len(s) then
						break
					end
				end

				local start, finish = s:find(utf8.charpattern)
				if start and finish then
					return `{s:sub(start, finish)} ({finish - start + 1} {finish > start and "bytes" or "byte"})`
				else
					return nil
				end
			end,
		},
	},
	{
		name = "binary",
		strategy = {
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
	},
	{
		name = "i8",
		strategy = {
			requiredBytes = 1,
			func = buffer.readi8,
		},
	},
	{
		name = "u8",
		strategy = {
			requiredBytes = 1,
			func = buffer.readu8,
		},
	},
	{
		name = "i16",
		strategy = {
			requiredBytes = 2,
			func = buffer.readi16,
		},
	},
	{
		name = "u16",
		strategy = {
			requiredBytes = 2,
			func = buffer.readu16,
		},
	},
	{
		name = "i32",
		strategy = {
			requiredBytes = 4,
			func = buffer.readi32,
		},
	},
	{
		name = "u32",
		strategy = {
			requiredBytes = 4,
			func = buffer.readu32,
		},
	},
	{
		name = "f32",
		strategy = {
			requiredBytes = 4,
			func = buffer.readf32,
		},
	},
	{
		name = "f64",
		strategy = {
			requiredBytes = 8,
			func = buffer.readf64,
		},
	},
}

local DataInspector: DataInspectorImplementation = {} :: DataInspectorImplementation
DataInspector.__index = DataInspector

function DataInspector.new(editor, params)
	local self = setmetatable({}, DataInspector) :: DataInspector
	self._container = params.container
	self._sizing = params.sizing :: DataInspectorSizing
	self:_setTheme(params.theme)

	self.editor = editor
	self.horizontalSpaceUsed = 0

	self._rowFrames = {}

	self._rowInfos = table.clone(builtInRows)

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

function DataInspector:addRow(rowInfo: RowInfo)
	for _, info in self._rowInfos do
		if info.name == rowInfo.name then
			error(`Duplicate row name: {rowInfo.name}`)
		end
	end

	table.insert(self._rowInfos, rowInfo)
	self:_buildRow(rowInfo.name)
	self:_updateRows()
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
	frame.Position =
		UDim2.fromOffset(self._theme.bodyPadding, self._headerHeight + self._rowHeight * self._rowFramesCount)
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
	value.TextColor3 = self._theme.lightValueText
	value.TextEditable = false
	value.TextSize = self._theme.textSize
	value.ClearTextOnFocus = false
	value.Text = "none"
	value.Size = UDim2.fromOffset(self._valueWidth, self._rowHeight)
	value.Position = UDim2.fromOffset(self._keyWidth + self._theme.keyValuePadding, 0)
	value.Parent = frame

	frame.Parent = self.scrollingFrame

	self._rowFrames[rowName] = {
		frame = frame,
		key = key,
		value = value,
	}
	self._rowFramesCount += 1
end

function DataInspector:_updateRows()
	local b, bSize = self.editor:getRawBuffer()
	local offset = self.editor:getCursorOffset() or self._lastOffset
	local remaining = 0
	if offset then
		remaining = bSize - offset + 1
	end

	for _, row in self._rowInfos do
		local strategy = row.strategy
		local frame = self._rowFrames[row.name]

		local result = if offset and remaining > strategy.requiredBytes then strategy.func(b, offset) else nil

		if result == nil then
			frame.value.Text = "none"
			frame.value.TextColor3 = self._theme.lightValueText
		elseif typeof(result) == "table" then
			frame.value.Text = result.text
			frame.value.TextColor3 = if result.isLight
				then self._theme.lightValueText
				else self._theme.valueText
		else
			frame.value.Text = tostring(result)
			frame.value.TextColor3 = self._theme.valueText
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

	for _, row in self._rowInfos do
		self:_buildRow(row.name)
	end

	scrollingFrame.CanvasSize = UDim2.fromOffset(0, self._headerHeight + self._rowHeight * self._rowFramesCount)

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

	for _, row in self._rowFrames do
		row.frame:Destroy()
	end
	self._rowFramesCount = 0
	self._rowFrames = {}

	local scrollingFrame = self.scrollingFrame
	if scrollingFrame then
		scrollingFrame:Destroy()
		self.scrollingFrame = nil
	end
end

return DataInspector
