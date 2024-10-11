--!strict
-- I will document later. For now, good luck! 🫡

-- Parameters when using HexEditor.new(container, params, dependencies):

-- "fillContainer" makes the hex editor fill up the entire container (UDim2.fromScale(1, 1))
-- "fillContainerY" makes the hex hex editor fill up the Y-axis, but take up only as much space
-- in the X-axis as necessary.
export type EditorSizing = "fillContainer" | "fillContainerY"

export type HexEditorNewParams = {
	container: GuiObject,

	-- Default is "fillContainer".
	sizing: EditorSizing?,

	theme: ThemeData,
	layout: LayoutData,

	-- If you don't provide this, the default ones will be used.
	hotkeys: HotkeyData?,
}

-- Table of dependencies so you can mix and match for your use case.
export type HexEditorDependencies = {
	-- This will be used for hotkeys.
	inputReceiver: GuiObject | UserInputService,

	-- This is optional if you want to have right click functionality.
	forms: HexEditorFormProvider?,
}

export type HexEditorFormProvider = {
	promptContextMenu: (InputObject, options: { string }) -> string?,
	promptFillWith: (InputObject) -> buffer?,
	promptInsertNullBytes: (InputObject) -> number?,
}

-- These options are for the overall layout.
export type LayoutData = {
	columns: number,

	showDecodedText: boolean,

	showHeader: boolean,

	showGutter: boolean,
	gutterColumns: number?,
}

-- For customizing hotkeys.
export type HotkeyAction = "undo" | "redo" | "cycleCursorMode" | "selectAll"
export type HotkeyData = {
	{
		action: HotkeyAction,
		keyCode: Enum.KeyCode,
		modifierKeys: { Enum.ModifierKey }?,
	}
}

-- These options are for cosmetic things.
export type ThemeData = {
	cell: CellThemeData,
	modifiedCell: CellThemeData,
	addCell: CellThemeData,

	headerText: Color3?,
	headerActiveText: Color3,
	headerBackground: Color3?,

	gutterText: Color3?,
	gutterActiveText: Color3,
	gutterBackground: Color3?,

	font: Font,
	textSize: number,

	sectionGap: number,
	cellPadding: number,
	halfCellPadding: number,

	-- Properties to assign to the ScrollingFrame after it is created.
	scrollingFrameProperties: { [string]: unknown }?,
}

export type CellThemeData = {
	background: Color3,
	text: Color3,

	hover: Color3,
	hoverText: Color3,

	select: Color3,
	selectText: Color3,

	cursorActive: Color3,
	cursorActiveText: Color3,

	cursor: Color3,
}

--[[ Implementation ]]

-- TODO: Reduce amount of buffer.copy used while editing (main culprits are deletes and inserts).
--       Maybe have some kind of "virtual edits" and instead of using buffer.readX, have
--       a :_readBufferX(offset) method that accounts for these virtual edits and apply
--       the virtual edits as necessary.

local TextService = game:GetService("TextService")

local MAX_UNDOS = 24

-- Only one can be active at a time, so keep track.
local globalHiddenTextBox: TextBox?

export type HexEditorImplementation = {
	--[==[ Static ]==]
	__index: HexEditorImplementation,

	DEFAULT_HOTKEYS: HotkeyData,

	SELECTION_CONTEXT_MENU_OPTIONS: { string },
	SINGLE_BYTE_CONTEXT_MENU_OPTIONS: { string },
	ADD_CELL_CONTEXT_MENU_OPTIONS: { string },

	isCharacterPrintable: (ascii: number) -> boolean,

	--[==[ Non-static ]==]

	new: (buffer, HexEditorNewParams, HexEditorDependencies) -> HexEditor,

	setBuffer: (HexEditor, buffer) -> (),

	-- Gets the buffer the user sees in the editor. DO NOT MODIFY IT.
	getBuffer: (HexEditor) -> buffer,

	-- Gets the underlying buffer used for editing. DO NOT MODIFY IT!
	getRawBuffer: (HexEditor) -> (buffer, number),

	getCursorOffset: (HexEditor) -> number?,

	setTheme: (HexEditor, ThemeData) -> (),
	setLayout: (HexEditor, LayoutData) -> (),

	undo: (HexEditor) -> (),
	redo: (HexEditor) -> (),

	destroy: (HexEditor) -> (),

	--[==[ Private ]==]

	_setTheme: (HexEditor, ThemeData) -> (),

	-- Hidden text box
	_createHiddenTextBox: (HexEditor) -> (),
	_destroyHiddenTextBox: (HexEditor) -> (),

	-- Cursor stuff
	_cycleCursorMode: (HexEditor) -> (),
	_setCursorState: (HexEditor, offset: number?, view: CursorView, mode: CursorMode?) -> (),
	_incrementCursor: (HexEditor, amount: number?) -> (),

	-- Edits
	_isTyping: (HexEditor) -> boolean,
	_typeCharacter: (HexEditor, string) -> (),
	_finishTyping: (HexEditor) -> (), -- pushes an action (sometimes)
	_cancelTyping: (HexEditor) -> (),

	-- Operations that DON'T push an action
	_insertAt: (HexEditor, offset: number, value: number?) -> (),
	_insertBuffer: (HexEditor, offset: number, buffer: buffer) -> (),

	_deleteAt: (HexEditor, offset: number) -> (),
	_deleteRegion: (HexEditor, offset: number, length: number) -> (),

	_replaceAt: (HexEditor, offset: number, value: number, doNotModifyCount: boolean?) -> (),
	_replaceBuffer: (HexEditor, offset: number, buffer: buffer, modifyIncrement: number?) -> (),

	_growBuffer: (HexEditor, minimumGrow: number) -> (),

	_incrementModifiedCount: (HexEditor, offset: number, amount: number) -> (),
	_bumpModifiedOffsetsAfter: (HexEditor, after: number, amount: number) -> (),

	_setInModal: (HexEditor, inModal: boolean) -> (),

	--- Operations that DO push an action (lets you undo them)
	_insertBufferWithAction: (HexEditor, offset: number, buffer: buffer) -> (),

	_deleteAtCursorWithAction: (HexEditor) -> (),
	_deleteBeforeCursorWithAction: (HexEditor) -> (),
	_deleteSelectionWithAction: (HexEditor, keepCursor: boolean?) -> (),

	_replaceAtWithAction: (HexEditor, offset: number, value: number) -> (),
	_fillPatternWithAction: (HexEditor, offset: number, length: number, fillPattern: buffer) -> (),

	_pushAction: (HexEditor, Action) -> (),

	-- Selection
	_isCellSelected: (HexEditor, offset: number) -> boolean,
	_startSelection: (HexEditor, offset: number, view: CursorView) -> (),
	_updateSelection: (HexEditor, offset: number, view: CursorView) -> (),
	_endSelection: (HexEditor) -> (),
	_setSelection: (HexEditor, anchor: number, offset: number) -> (),
	_clearSelection: (HexEditor) -> (),

	-- UI
	_updateSelectionCellStyles: (HexEditor, anchor: number?, cursor: number?) -> (),
	_updateCursorStyle: (HexEditor, CursorMode?, state: "modified" | "add" | nil) -> (),
	_updateCellStyle: (HexEditor, offset: number, state: ButtonState?) -> (),
	_updateHeaderPosition: (HexEditor) -> (),
	_buildHeader: (HexEditor) -> (),
	_buildRow: (HexEditor, row: number) -> (),
	_rebuildCell: (HexEditor, offset: number, rowFrame: Frame?) -> (),
	_rebuildVisibleRows: (HexEditor, overflow: number, forceAfterOffset: number?) -> (),
	_buildCursor: (HexEditor) -> (),
	_buildGutter: (HexEditor) -> (),
	_buildUi: (HexEditor) -> (),
	_clearUi: (HexEditor) -> (),
}
export type HexEditorFields = {
	--[[ Public ]]
	horizontalSpaceUsed: number,

	-- Access at your own risk.
	scrollingFrame: ScrollingFrame?,

	-- Events

	-- Parameters:
	--	offset: number?
	cursorMoved: RBXScriptSignal,
	_cursorMoved: BindableEvent,

	-- Parameters:
	--	horizontalSpaceUsed: number
	sizeChanged: RBXScriptSignal,
	_sizeChanged: BindableEvent,

	--[[ Private ]]

	_dependencies: HexEditorDependencies,

	_container: GuiObject,
	_sizing: EditorSizing,
	_theme: ThemeData,
	_layout: LayoutData,

	_buffer: buffer,
	_bufferSize: number,

	_cellWidth: number,
	_cellHeight: number,
	_halfCellWidth: number,

	_hiddenTextBox: TextBox?,

	_typed: string,
	_inModal: boolean, -- Used so that hidden text box knows not to deselect

	_modifiedOffsets: { [number]: number? }, -- [offset]: times modified
	_undoList: { Action },
	_undoPosition: number,

	_cursorState: { offset: number?, view: CursorView?, mode: CursorMode },
	_selectionAnchor: number?, -- offset
	_selectionPhase: "mousedown" | "selecting" | nil,

	_headerOffset: number,
	_gutterOffset: number,

	_cursor: Frame?,
	_header: Frame?,
	_cells: { { hex: TextButton, ascii: TextButton? } },
	_rows: { [number]: Frame },

	_connections: { RBXScriptConnection },
}
export type HexEditor = typeof(setmetatable({} :: HexEditorFields, {} :: HexEditorImplementation))

type InsertAction = {
	type: "insert",
	offset: number,
	value: number,
}
type ReplaceAction = {
	type: "replace",
	offset: number,
	value: number,
	originalValue: number?,
}
type DeleteAction = {
	type: "delete",
	offset: number,
	originalValue: number,
	wasBehind: boolean, -- If the deletion was behind the cursor (in that case move up one when undoing)
}
type RegionDeleteAction = {
	type: "regionDelete",
	offset: number,
	buffer: buffer,
}
type RegionReplaceAction = {
	type: "regionReplace",
	offset: number,
	originalBuffer: buffer,
	buffer: buffer,
}
type RegionInsertAction = {
	type: "regionInsert",
	offset: number,
	buffer: buffer,
}
type Action = InsertAction | ReplaceAction | DeleteAction | RegionDeleteAction | RegionReplaceAction | RegionInsertAction

type Selection = { anchor: number, cursor: number }

type CursorView = "hex" | "ascii"
type CursorMode = "insert" | "replace"

local HexEditor: HexEditorImplementation = {} :: HexEditorImplementation
HexEditor.__index = HexEditor

HexEditor.DEFAULT_HOTKEYS = {
	{
		action = "undo",
		keyCode = Enum.KeyCode.Z,
		modifierKeys = { Enum.ModifierKey.Ctrl },
	},
	{
		action = "redo",
		keyCode = Enum.KeyCode.Y,
		modifierKeys = { Enum.ModifierKey.Ctrl },
	},
	{
		action = "redo",
		keyCode = Enum.KeyCode.Z,
		modifierKeys = { Enum.ModifierKey.Ctrl, Enum.ModifierKey.Shift },
	},
	{
		action = "cycleCursorMode",
		keyCode = Enum.KeyCode.Insert,
	},
	{
		action = "selectAll",
		keyCode = Enum.KeyCode.A,
		modifierKeys = { Enum.ModifierKey.Ctrl },
	},
}

HexEditor.SELECTION_CONTEXT_MENU_OPTIONS = table.freeze({
	"Fill Selection",
	"Delete Selection",
	"Insert Null Bytes",
	"Select All",
})

HexEditor.SINGLE_BYTE_CONTEXT_MENU_OPTIONS = table.freeze({
	"Insert Null Bytes",
	"Delete Byte",
	"Select All",
})

HexEditor.ADD_CELL_CONTEXT_MENU_OPTIONS = table.freeze({
	"Insert Null Bytes",
	"Select All",
})

function HexEditor.new(b: buffer, params: HexEditorNewParams, dependencies: HexEditorDependencies)
	local self: HexEditor = (setmetatable({}, HexEditor) :: any) :: HexEditor

	-- Events
	self._cursorMoved = Instance.new("BindableEvent")
	self.cursorMoved = self._cursorMoved.Event

	self._sizeChanged = Instance.new("BindableEvent")
	self.sizeChanged = self._sizeChanged.Event

	-- Fields

	self._dependencies = table.freeze(dependencies)
	self._sizing = params.sizing :: EditorSizing

	self._buffer = b
	self._bufferSize = buffer.len(b)

	self._modifiedOffsets = {}

	self._typed = ""
	self._inModal = false

	self._undoList = {}
	self._undoPosition = 0

	self._cursorState = { offset = nil, view = nil, mode = "replace" }
	self._selectionAnchor = nil
	self._selectionPhase = nil

	self._headerOffset = 0
	self._gutterOffset = 0

	self._rows = {}
	self._cells = {}

	self._container = params.container

	self._layout = params.layout
	self:_setTheme(params.theme)

	self:_buildUi()

	local hotkeys = params.hotkeys or HexEditor.DEFAULT_HOTKEYS
	self._connections = {
		(self._dependencies.inputReceiver.InputBegan :: any):Connect(function(input: InputObject)
			if self._inModal then
				return
			end

			for _, hotkey in hotkeys do
				if input.KeyCode == hotkey.keyCode then
					local run = true
					for _, modifierKey in Enum.ModifierKey:GetEnumItems() do
						if
							input:IsModifierKeyDown(modifierKey)
							~= (not not table.find(hotkey.modifierKeys or {}, modifierKey))
						then
							run = false
							break
						end
					end

					if run then
						if hotkey.action == "undo" then
							self:undo()
						elseif hotkey.action == "redo" then
							self:redo()
						elseif hotkey.action == "cycleCursorMode" then
							if self._cursorState.offset then
								self:_cycleCursorMode()
							end
						elseif hotkey.action == "selectAll" then
							self:_setSelection(0, self._bufferSize - 1)
						end
					end
				end
			end
		end),
	}

	return self
end

--[==[ Public ]==]

function HexEditor:setBuffer(b)
	self._buffer = b
	self._bufferSize = buffer.len(b)
	self:_rebuildVisibleRows(0, 0)
end

function HexEditor:getBuffer()
	if self._bufferSize < buffer.len(self._buffer) then
		local copy = buffer.create(self._bufferSize)
		buffer.copy(copy, 0, self._buffer, 0, self._bufferSize)
		return copy
	else
		return self._buffer
	end
end

function HexEditor:getRawBuffer()
	return self._buffer, self._bufferSize
end

function HexEditor:getCursorOffset()
	return self._cursorState.offset
end

function HexEditor:setTheme(theme)
	self:_setTheme(theme)
	self:_buildUi()
end

function HexEditor:setLayout(layout)
	self._layout = layout
	self:_buildUi()
end

function HexEditor:undo()
	if self._undoPosition == 0 then
		return
	end

	if self:_isTyping() then
		self:_cancelTyping()
	end

	local action = self._undoList[self._undoPosition]
	self._undoPosition -= 1

	if action.type == "insert" then
		self:_deleteAt(action.offset)
	elseif action.type == "delete" then
		self:_insertAt(action.offset, action.originalValue)
	elseif action.type == "replace" then
		self:_incrementModifiedCount(action.offset, -1)
		if action.originalValue then
			self:_replaceAt(action.offset, action.originalValue, true)
		else
			-- It was inserted at the end
			self:_deleteAt(action.offset)
		end
	elseif action.type == "regionInsert" then
		self:_deleteRegion(action.offset, buffer.len(action.buffer))
	elseif action.type == "regionDelete" then
		self:_insertBuffer(action.offset, action.buffer)
		self:_setSelection(action.offset, action.offset + buffer.len(action.buffer) - 1)
		return
	elseif action.type == "regionReplace" then
		self:_replaceBuffer(action.offset, action.originalBuffer, -1)
		self:_setSelection(action.offset, action.offset + buffer.len(action.originalBuffer) - 1)
		return
	end

	if self._selectionAnchor then
		self:_clearSelection()
	end
	self:_setCursorState(action.offset, self._cursorState.view :: CursorView)
	if (action :: any).wasBehind then
		self:_incrementCursor()
	end
end

function HexEditor:redo()
	if self._undoPosition >= #self._undoList then
		return
	end

	if self:_isTyping() then
		self:_cancelTyping()
	end

	self._undoPosition += 1
	local action = self._undoList[self._undoPosition]

	if action.type == "insert" then
		self:_insertAt(action.offset, action.value)
	elseif action.type == "delete" then
		self:_deleteAt(action.offset)
	elseif action.type == "replace" then
		self:_replaceAt(action.offset, action.value)
	elseif action.type == "regionInsert" then
		self:_insertBuffer(action.offset, action.buffer)
		self:_setSelection(action.offset, action.offset + buffer.len(action.buffer) - 1)
		return
	elseif action.type == "regionDelete" then
		self:_deleteRegion(action.offset, buffer.len(action.buffer))
	elseif action.type == "regionReplace" then
		self:_replaceBuffer(action.offset, action.buffer)
		self:_setSelection(action.offset, action.offset + buffer.len(action.buffer) - 1)
		return
	end

	if self._selectionAnchor then
		self:_clearSelection()
	end
	self:_setCursorState(action.offset, self._cursorState.view :: CursorView)
	if action.type == "insert" then
		self:_incrementCursor()
	end
end

function HexEditor:destroy()
	self:_destroyHiddenTextBox()
	self:_clearUi()

	for _, connection in self._connections do
		connection:Disconnect()
	end
end

--[==[ Private ]==]

function HexEditor:_setTheme(theme)
	self._theme = theme

	-- Cell stuff

	local textParams = Instance.new("GetTextBoundsParams")
	textParams.Font = theme.font
	textParams.Size = theme.textSize
	textParams.Text = "FF"
	textParams.Width = math.huge
	local bounds = TextService:GetTextBoundsAsync(textParams)
	textParams.Text = "W"
	local halfBounds = TextService:GetTextBoundsAsync(textParams)

	self._cellWidth = bounds.X + 2 * self._theme.cellPadding
	self._cellHeight = bounds.Y + 2 * self._theme.cellPadding
	self._halfCellWidth = halfBounds.X + 2 * self._theme.halfCellPadding

	if self._layout.showGutter then
		assert(self._layout.gutterColumns)

		textParams.Text = string.rep("F", self._layout.gutterColumns)
		local gutterBounds = TextService:GetTextBoundsAsync(textParams)
		-- Add some cell padding is so it doesn't touch the left
		self._gutterOffset = gutterBounds.X + self._theme.sectionGap + 2 * self._theme.cellPadding
	else
		self._gutterOffset = 0
	end
end

function HexEditor:_setCursorState(offset, view, mode)
	if self:_isTyping() then
		self:_finishTyping()
	end

	local lastOffset = nil
	if offset ~= self._cursorState.offset and self._cursorState.offset then
		lastOffset = self._cursorState.offset

		local header = self._header
		if header then
			local cell = header:FindFirstChild(tostring(lastOffset % self._layout.columns)) :: TextLabel
			if cell then
				cell.TextColor3 = self._theme.headerText or self._theme.cell.text
			end
		end
		local row = self._rows[lastOffset // self._layout.columns]
		if row then
			local gutterText = row:FindFirstChild("Gutter") :: TextLabel
			if gutterText then
				gutterText.TextColor3 = self._theme.gutterText or self._theme.cell.text
			end
		end
	end

	if offset then
		if not self._cursor then
			self:_buildCursor()
		end
		if not self._hiddenTextBox then
			self:_createHiddenTextBox()
		end

		self._cursorState = { offset = offset, view = view, mode = mode or self._cursorState.mode } :: any

		local cursor = self._cursor :: Frame
		if self._cursorState.view == "hex" then
			cursor.Position = UDim2.fromOffset(
				self._gutterOffset + offset % self._layout.columns * self._cellWidth,
				self._headerOffset + (offset // self._layout.columns + 1) * self._cellHeight
			)
		elseif self._cursorState.view == "ascii" then
			cursor.Position = UDim2.fromOffset(
				self._gutterOffset
					+ self._cellWidth * self._layout.columns
					+ self._theme.sectionGap
					+ offset % self._layout.columns * self._halfCellWidth,
				self._headerOffset + (offset // self._layout.columns + 1) * self._cellHeight
			)
		end

		-- Make sure cursor always in view
		local scrollingFrame = self.scrollingFrame
		if scrollingFrame then
			local relativeCellOffset = self._headerOffset
				+ (offset // self._layout.columns) * self._cellHeight
				- scrollingFrame.CanvasPosition.Y
				- self._cellHeight
			if relativeCellOffset < 0 then
				scrollingFrame.CanvasPosition = scrollingFrame.CanvasPosition + Vector2.new(0, relativeCellOffset)
			else
				relativeCellOffset += 2 * self._cellHeight
				if relativeCellOffset > scrollingFrame.AbsoluteWindowSize.Y then
					scrollingFrame.CanvasPosition = scrollingFrame.CanvasPosition
						+ Vector2.new(0, relativeCellOffset - scrollingFrame.AbsoluteWindowSize.Y)
				end
			end
		end

		self:_updateCellStyle(offset)

		self:_updateCursorStyle()

		local header = self._header
		if header then
			local cell = header:FindFirstChild(tostring(offset % self._layout.columns)) :: TextLabel
			if cell then
				cell.TextColor3 = self._theme.headerActiveText or self._theme.headerText or self._theme.cell.text
			end
		end
		local row = self._rows[offset // self._layout.columns]
		if row then
			local gutterText = row:FindFirstChild("Gutter") :: TextLabel
			if gutterText then
				gutterText.TextColor3 = self._theme.gutterActiveText or self._theme.gutterText or self._theme.cell.text
			end
		end
	else
		if self._cursor then
			self._cursor:Destroy()
			self._cursor = nil
		end
		if self._hiddenTextBox then
			self:_destroyHiddenTextBox()
		end
		self:_clearSelection()

		self._cursorState.offset = nil
		self._cursorState.view = nil
	end

	self:_updateCellStyle(lastOffset)

	if lastOffset ~= self._cursorState.offset then
		self._cursorMoved:Fire(self._cursorState.offset)
	end
end

function HexEditor:_incrementCursor(amount)
	assert(self._cursorState.offset)

	if self._selectionAnchor then
		self:_clearSelection()
	end

	local offset = self._cursorState.offset + (amount or 1)
	self:_setCursorState(math.clamp(offset, 0, self._bufferSize), self._cursorState.view :: CursorView)
end

function HexEditor:_createHiddenTextBox()
	if self._inModal then
		return
	end
	if self._hiddenTextBox then
		self:_destroyHiddenTextBox()
	end
	if globalHiddenTextBox then
		globalHiddenTextBox:Destroy()
		globalHiddenTextBox = nil
	end

	local hiddenTextBox = Instance.new("TextBox")
	hiddenTextBox.TextSize = 0
	hiddenTextBox.TextTransparency = 1
	hiddenTextBox.BackgroundTransparency = 1
	hiddenTextBox.Size = UDim2.fromOffset(0, 0)
	hiddenTextBox.ClearTextOnFocus = false
	hiddenTextBox.Position = UDim2.fromOffset(-5000, -5000)
	hiddenTextBox.Name = "HiddenTextBox"
	hiddenTextBox.ZIndex = 100
	hiddenTextBox.Parent = self._container

	hiddenTextBox.Size = UDim2.fromOffset(100, 50)
	self._hiddenTextBox = hiddenTextBox
	globalHiddenTextBox = hiddenTextBox

	local function resetText()
		hiddenTextBox.Text = "abc\nac\nabc"
		hiddenTextBox:CaptureFocus()
		hiddenTextBox.SelectionStart = -1
		hiddenTextBox.CursorPosition = 6
	end

	local function tryRegisterType()
		if
			hiddenTextBox.Text ~= "abc\nac\nabc"
			and #hiddenTextBox.Text == 11
			and hiddenTextBox.Text:sub(1, 5) == "abc\na"
			and hiddenTextBox.Text:sub(7, 11) == "c\nabc"
		then
			local inserted = hiddenTextBox.Text:sub(6, 6)

			-- Vim shortcuts only work in hex view because the characters don't register
			if self._cursorState.view == "hex" then
				if inserted == "j" then
					self:_incrementCursor(self._layout.columns)
				elseif inserted == "k" then
					self:_incrementCursor(-self._layout.columns)
				elseif inserted == "h" then
					self:_incrementCursor(-1)
				elseif inserted == "l" then
					self:_incrementCursor(1)
				elseif inserted == "$" then
					local rowEnd = math.min(
						self._bufferSize - 1,
						self._layout.columns * math.ceil(((self._cursorState.offset or 0) + 1) / self._layout.columns)
							- 1
					)
					self:_setCursorState(rowEnd, self._cursorState.view)
				elseif inserted == "^" then
					local rowStart = math.max(
						0,
						self._layout.columns * math.floor((self._cursorState.offset or 0) / self._layout.columns)
					)
					self:_setCursorState(rowStart, self._cursorState.view)
				-- "g" to easy to press, "gg" too much work to implement, so I decide that "S" will work (for start)
				elseif inserted == "S" then
					self:_setCursorState(0, self._cursorState.view)
				elseif inserted == "G" then
					self:_setCursorState(self._bufferSize - 1, self._cursorState.view)
				end
			end

			self:_typeCharacter(inserted)
			resetText()
		elseif hiddenTextBox.Text == "abc\nc\nabc" then
			if self._selectionAnchor then
				self:_deleteSelectionWithAction(true)
			else
				self:_deleteBeforeCursorWithAction()
			end
			resetText()
		else
			resetText()
		end
	end

	hiddenTextBox:GetPropertyChangedSignal("SelectionStart"):Connect(function()
		if hiddenTextBox:IsFocused() then
			resetText()
		end
	end)

	hiddenTextBox:GetPropertyChangedSignal("CursorPosition"):Connect(function()
		if hiddenTextBox:IsFocused() then
			-- If SignalBehavior is immediate, text changes will trigger cursor position behavior the text itself changes.
			-- So we have to add task.defer unfortunately

			task.defer(function()
				if #hiddenTextBox.Text == 10 then
					if hiddenTextBox.CursorPosition == 5 then
						self:_incrementCursor(-1)
					elseif hiddenTextBox.CursorPosition == 2 then
						self:_incrementCursor(-self._layout.columns)
					elseif hiddenTextBox.CursorPosition == 7 then
						self:_incrementCursor(1)
					elseif hiddenTextBox.CursorPosition == 9 then
						self:_incrementCursor(self._layout.columns)
					end
					resetText()
				end
			end)
		end
	end)

	hiddenTextBox:GetPropertyChangedSignal("Text"):Connect(function()
		if #hiddenTextBox.Text == 11 then
			tryRegisterType()
		elseif #hiddenTextBox.Text == 9 then
			if hiddenTextBox.Text == "abc\na\nabc" then
				if self:_isTyping() then
					self:_cancelTyping()
					resetText()
				else
					if self._selectionAnchor then
						self:_deleteSelectionWithAction(true)
					else
						self:_deleteAtCursorWithAction()
					end
					resetText()
				end
			elseif hiddenTextBox.Text == "abc\nc\nabc" then
				if self:_isTyping() then
					self:_cancelTyping()
					resetText()
				else
					if self._selectionAnchor then
						self:_deleteSelectionWithAction(true)
					else
						self:_deleteBeforeCursorWithAction()
					end
					resetText()
				end
			end
		else
			resetText()
		end
	end)

	local recursions = 0
	hiddenTextBox.FocusLost:Connect(function(entered: boolean, input)
		if entered then
			self:_finishTyping()
			self:_setCursorState(self._cursorState.offset, self._cursorState.view :: CursorView) -- To update the color
			resetText()
		else
			if self:_isTyping() then
				self:_cancelTyping()
			end

			-- Don't delete the selection/cursor since the modal puts the editor in the background.
			if self._inModal then
				return
			end

			-- If it is pressing within the editor, do not deselect so .Activated is fired and the cursor mode is cycled
			local scrollingFrame = self.scrollingFrame
			if
				input
				and scrollingFrame
				and (input.UserInputType == Enum.UserInputType.MouseButton1)
				and (scrollingFrame.AbsolutePosition.Y + self._headerOffset <= input.Position.Y)
				and (input.Position.Y <= scrollingFrame.AbsolutePosition.Y + scrollingFrame.AbsoluteSize.Y)
				and (
					( -- In the hex portion
						(
							input.Position.X
							<= scrollingFrame.AbsolutePosition.X
								+ self._gutterOffset
								+ self._cellWidth * self._layout.columns
						) and (scrollingFrame.AbsolutePosition.X + self._gutterOffset <= input.Position.X)
					)
					or ( -- In the text portion
						self._layout.showDecodedText
						and (
							(
								scrollingFrame.AbsolutePosition.X
									+ self._gutterOffset
									+ self._cellWidth * self._layout.columns
									+ self._theme.sectionGap
								<= input.Position.X
							)
							and (
								input.Position.X
								<= scrollingFrame.AbsolutePosition.X
									+ self._gutterOffset
									+ (self._cellWidth + self._halfCellWidth) * self._layout.columns
									+ self._theme.sectionGap
							)
						)
					)
				)
			then
				resetText()
			else
				self:_setCursorState(nil, self._cursorState.view :: CursorView)
			end
		end
	end)

	resetText()
end

function HexEditor:_destroyHiddenTextBox()
	if self._hiddenTextBox then
		self._hiddenTextBox:Destroy()
		if self._hiddenTextBox == globalHiddenTextBox then
			globalHiddenTextBox = nil
		end
		self._hiddenTextBox = nil
	end
end

function HexEditor:_isTyping()
	return #self._typed > 0
end

local function isHex(character: string): boolean
	local ascii = string.byte(character)
	return (0x30 <= ascii and ascii <= 0x39) or (0x41 <= ascii and ascii <= 0x46) or (0x61 <= ascii and ascii <= 0x66)
end

function HexEditor:_typeCharacter(character: string)
	assert(#character == 1)
	assert(self._cursorState.offset)

	self:_clearSelection()

	if self._cursorState.view == "hex" then
		if not isHex(character) then
			return
		end

		character = character:upper()

		if #self._typed >= 2 then
			self:_incrementCursor()
			self._typed = ""
		elseif #self._typed == 1 then
			self._typed ..= character
			self:_finishTyping()
			self:_incrementCursor()
		else
			if self._cursorState.mode == "replace" then
				self._typed = character
				local cell = self._cells[self._cursorState.offset]
				if cell then
					cell.hex.Text = self._typed .. "_"
				end
			elseif self._cursorState.mode == "insert" then
				self:_insertAt(self._cursorState.offset)
				self._typed = character

				local cell = self._cells[self._cursorState.offset]
				if cell then
					cell.hex.Text = self._typed .. "_"
					self:_updateCursorStyle(self._cursorState.mode, "modified")

					-- Move it to the middle so it looks like ur typing
					local cursor = self._cursor
					if cursor then
						cursor.Position += UDim2.fromOffset(self._cellWidth / 2, 0)
					end
				end
			end
		end
	elseif self._cursorState.view == "ascii" then
		self._typed = character
		if self._cursorState.mode == "replace" then
			self:_finishTyping()
			self:_incrementCursor()
		elseif self._cursorState.mode == "insert" then
			self:_insertAt(self._cursorState.offset)
			self:_finishTyping()
			self:_incrementCursor()
		end
	end
end

function HexEditor:_finishTyping()
	assert(self._cursorState.offset)

	if self:_isTyping() then
		local value = (
			if self._cursorState.view == "hex" then tonumber(self._typed, 16) else string.byte(self._typed)
		) :: number

		if self._cursorState.mode == "insert" then
			self:_replaceAt(self._cursorState.offset, value)
			self:_pushAction({
				type = "insert",
				offset = self._cursorState.offset,
				value = value,
			})
		else
			self:_replaceAtWithAction(self._cursorState.offset, value)
		end

		self._typed = ""
	end
end

function HexEditor:_cancelTyping()
	if self._cursorState.offset then
		if self._cursorState.mode == "insert" and self:_isTyping() then
			self._typed = ""
			self:_deleteAt(self._cursorState.offset)
			self:_setCursorState(self._cursorState.offset, self._cursorState.view :: CursorView) -- Reset the cursor visually
		else
			self._typed = ""
			self:_rebuildCell(self._cursorState.offset)
		end
	end
end

function HexEditor:_insertAt(offset: number, value: number?)
	if buffer.len(self._buffer) <= self._bufferSize then
		self:_growBuffer(1)
	end

	local temp = buffer.create(self._bufferSize - offset)
	buffer.copy(temp, 0, self._buffer, offset, buffer.len(temp))
	buffer.copy(self._buffer, offset + 1, temp)
	buffer.writeu8(self._buffer, offset, value or 0)
	self:_bumpModifiedOffsetsAfter(offset - 1, 1)
	self:_incrementModifiedCount(offset, 1)
	self._bufferSize += 1

	self:_rebuildVisibleRows(0, offset)
end

function HexEditor:_insertBuffer(offset, b)
	if self._bufferSize + buffer.len(b) >= buffer.len(self._buffer) then
		self:_growBuffer((self._bufferSize + buffer.len(b)) - buffer.len(self._buffer))
	end

	local temp = buffer.create(self._bufferSize - offset)
	buffer.copy(temp, 0, self._buffer, offset, buffer.len(temp))
	buffer.copy(self._buffer, offset + buffer.len(b), temp)
	buffer.copy(self._buffer, offset, b)
	self:_bumpModifiedOffsetsAfter(offset - 1, buffer.len(b))
	for i = offset, offset + buffer.len(b) - 1 do
		self:_incrementModifiedCount(i, 1)
	end
	self._bufferSize += buffer.len(b)

	self:_rebuildVisibleRows(0, offset)

	self:_updateCursorStyle()
end

function HexEditor:_deleteAt(offset: number)
	if offset < self._bufferSize - 1 then
		buffer.copy(self._buffer, offset, self._buffer, offset + 1)
	end

	self._bufferSize -= 1
	self._modifiedOffsets[offset] = nil
	self:_bumpModifiedOffsetsAfter(offset, -1)

	if self._cursorState.offset and self._cursorState.offset > offset then
		self:_setCursorState(self._cursorState.offset - 1, self._cursorState.view :: CursorView)
	end

	self:_rebuildVisibleRows(0, offset)
end

function HexEditor:_deleteRegion(offset: number, length: number)
	if offset + length < self._bufferSize - 1 then
		buffer.copy(self._buffer, offset, self._buffer, offset + length)
	end

	self._bufferSize -= length
	for offset = offset, offset + length - 1 do
		self._modifiedOffsets[offset] = nil
	end
	self:_bumpModifiedOffsetsAfter(offset, -length)
	self:_rebuildVisibleRows(0, offset)
end

function HexEditor:_replaceAt(offset, value, doNotModifyCount)
	if offset >= buffer.len(self._buffer) then
		self:_growBuffer(1)
	end

	buffer.writeu8(self._buffer, offset, value)
	if not doNotModifyCount then
		self:_incrementModifiedCount(offset, 1)
	end

	if offset == self._bufferSize then
		self._bufferSize += 1
		self:_rebuildVisibleRows(0, offset)
	else
		self:_rebuildCell(offset)
	end
end

function HexEditor:_replaceBuffer(offset, b, modifyIncrement)
	if offset + buffer.len(b) >= buffer.len(self._buffer) then
		self:_growBuffer((offset + buffer.len(b)) - buffer.len(self._buffer))
	end

	local modifyIncrement = modifyIncrement or 1

	buffer.copy(self._buffer, offset, b)

	for i = offset, offset + buffer.len(b) - 1 do
		self:_incrementModifiedCount(i, modifyIncrement)
		self:_rebuildCell(i)
	end

	-- The cursor may have been inside the replaced region
	self:_updateCursorStyle()
end

-- METHODS THAT PUSH ACTIONS

function HexEditor:_insertBufferWithAction(offset: number, b: buffer)
	self:_insertBuffer(offset, b)
	self:_rebuildVisibleRows(0, offset)
	self:_pushAction({
		type = "regionInsert",
		offset = offset,
		buffer = b,
	})

	self:_setSelection(offset, offset + buffer.len(b) - 1)
end

function HexEditor:_deleteAtCursorWithAction()
	assert(self._cursorState.offset)
	if self._cursorState.offset >= self._bufferSize then
		return
	end
	local originalValue = buffer.readu8(self._buffer, self._cursorState.offset)
	self:_deleteAt(self._cursorState.offset)
	self:_pushAction({
		type = "delete",
		offset = self._cursorState.offset, -- delete at move the cursor so we dont have to account for the -1
		originalValue = originalValue,
		wasBehind = false,
	})
end

function HexEditor:_deleteBeforeCursorWithAction()
	assert(self._cursorState.offset)
	if self._cursorState.offset <= 0 or self._cursorState.offset > self._bufferSize then
		return
	end
	local originalValue = buffer.readu8(self._buffer, self._cursorState.offset - 1)
	self:_deleteAt(self._cursorState.offset - 1)
	self:_pushAction({
		type = "delete",
		offset = self._cursorState.offset,
		originalValue = originalValue,
		wasBehind = true,
	})
end

function HexEditor:_deleteSelectionWithAction(keepCursor)
	if not self._selectionAnchor then
		return
	end
	if not self._cursorState.offset then
		return
	end
	if self._cursorState.offset == self._selectionAnchor then
		return
	end

	local start = math.min(self._selectionAnchor, self._cursorState.offset)
	local finish = math.max(self._selectionAnchor, self._cursorState.offset)

	-- Add 1 because the selection is inclusive
	local deletedAmount = finish - start + 1
	local deletedBuffer = buffer.create(deletedAmount)
	buffer.copy(deletedBuffer, 0, self._buffer, start, deletedAmount)

	self:_deleteRegion(start, deletedAmount)

	self:_clearSelection()
	self:_setCursorState(if keepCursor then start else nil, self._cursorState.view :: CursorView)
	self:_rebuildVisibleRows(0, start)

	self:_pushAction({
		type = "regionDelete",
		buffer = deletedBuffer,
		offset = start,
	})
end

function HexEditor:_replaceAtWithAction(offset, value)
	local originalValue = nil
	if self._bufferSize > offset then
		originalValue = buffer.readu8(self._buffer, offset)
	end
	self:_replaceAt(offset, value)
	self:_pushAction({
		type = "replace",
		offset = offset,
		originalValue = originalValue,
		value = value,
	})
end

function HexEditor:_fillPatternWithAction(offset, length, pattern)
	local originalBuffer = buffer.create(length)
	buffer.copy(originalBuffer, 0, self._buffer, offset, length)

	local fillBuffer = buffer.create(length)
	for i = 1, math.ceil(length / buffer.len(pattern)) do
		local start = buffer.len(pattern) * (i - 1)
		local count = math.min(buffer.len(pattern), length - start)

		buffer.copy(fillBuffer, start, pattern, 0, count)
	end

	self:_replaceBuffer(offset, fillBuffer)

	self:_pushAction({
		type = "regionReplace",
		offset = offset,
		originalBuffer = originalBuffer,
		buffer = fillBuffer,
	})
end

function HexEditor:_growBuffer(minimumGrow: number?)
	local size: number
	if buffer.len(self._buffer) < 1024 then
		size = buffer.len(self._buffer) * 2 + (minimumGrow or 0)
	else
		size = buffer.len(self._buffer) + 256 + (minimumGrow or 0)
	end
	if size < 64 then
		size = 64
	end

	local newBuffer = buffer.create(size)
	buffer.copy(newBuffer, 0, self._buffer)
	self._buffer = newBuffer
end

function HexEditor:_incrementModifiedCount(offset: number, amount: number)
	local new: number? = (self._modifiedOffsets[offset] or 0) + amount
	if new <= 0 then
		new = nil
	end
	self._modifiedOffsets[offset] = new
end

function HexEditor:_bumpModifiedOffsetsAfter(after: number, amount: number)
	local newModifiedOffsets = {}
	for k, v in self._modifiedOffsets do
		newModifiedOffsets[k + (if k > after then amount else 0)] = v
	end
	self._modifiedOffsets = newModifiedOffsets
end

function HexEditor:_pushAction(action)
	if self._undoPosition < #self._undoList then
		for i = 1, #self._undoList - self._undoPosition do
			table.remove(self._undoList)
		end
	end

	if #self._undoList >= MAX_UNDOS then
		table.remove(self._undoList, 1)
	end

	table.insert(self._undoList, action)
	self._undoPosition += 1
end

--[[ Selection ]]

function HexEditor:_isCellSelected(offset)
	if self._selectionAnchor then
		return math.min(self._selectionAnchor, self._cursorState.offset or math.huge) <= offset
			and offset <= math.max(self._selectionAnchor, self._cursorState.offset or -math.huge)
	end
	return false
end

function HexEditor:_updateSelectionCellStyles(anchor, cursor)
	local scrollingFrame = self.scrollingFrame
	local selectionAnchor = anchor or self._selectionAnchor
	local cursorOffset = cursor or self._cursorState.offset
	if selectionAnchor ~= cursorOffset and selectionAnchor and cursorOffset and scrollingFrame then
		local start = math.max(
			self._layout.columns * (math.floor(scrollingFrame.CanvasPosition.Y / self._cellHeight) - 1),
			math.min(cursorOffset, selectionAnchor)
		)
		local finish = math.min(
			self._layout.columns
				* (
					math.ceil(
						(scrollingFrame.CanvasPosition.Y + scrollingFrame.AbsoluteWindowSize.Y) / self._cellHeight
					) + 1
				),
			math.max(cursorOffset, selectionAnchor)
		)
		for offset = start, finish do
			self:_updateCellStyle(offset)
		end
	end
end

function HexEditor:_startSelection(offset, view)
	if self._selectionAnchor then
		self:_clearSelection()
	end

	self._selectionAnchor = offset
	self._selectionPhase = "selecting"
	self:_setCursorState(offset, view :: CursorView)

	self:_updateSelectionCellStyles()
end

function HexEditor:_updateSelection(offset, view)
	if self._selectionAnchor and self._cursorState.offset and (self._selectionPhase == "selecting") then
		local lastCursor = self._cursorState
		self:_setCursorState(offset, view :: CursorView)

		if lastCursor.offset then
			if
				math.abs(lastCursor.offset - self._selectionAnchor)
				> math.abs(self._cursorState.offset - self._selectionAnchor)
			then
				for offset = self._cursorState.offset, lastCursor.offset, math.sign(lastCursor.offset - self._cursorState.offset) do
					self:_updateCellStyle(offset)
				end
			end
		end

		self:_updateSelectionCellStyles()
	end
end

function HexEditor:_endSelection()
	if self._selectionAnchor == self._cursorState.offset then
		self:_clearSelection()
	end
	self._selectionPhase = nil
end

function HexEditor:_setSelection(anchor, cursor)
	if self._selectionAnchor then
		self:_clearSelection()
	end

	if anchor == cursor then
		return
	end

	self:_startSelection(anchor, self._cursorState.view :: CursorView)
	self:_updateSelection(cursor, self._cursorState.view :: CursorView)
	self:_endSelection()
end

function HexEditor:_clearSelection()
	if not self._selectionAnchor then
		return
	end

	local cursor = self._cursorState.offset
	local anchor = self._selectionAnchor
	self._selectionAnchor = nil

	if cursor and anchor and cursor ~= anchor then
		self:_updateSelectionCellStyles(cursor, anchor)
	end
end

--[[ UI ]]

function HexEditor:_setInModal(inModal: boolean)
	self._inModal = inModal

	if not inModal then
		if (not self._hiddenTextBox) and self._cursorState.offset then
			self:_createHiddenTextBox()
		end
	else
		self:_destroyHiddenTextBox()
	end
end

type ButtonState = "default" | "hover"

function HexEditor:_updateCellStyle(offset, state)
	local cellThemeData = if offset == self._bufferSize
		then self._theme.addCell
		elseif self._modifiedOffsets[offset] then self._theme.modifiedCell
		else self._theme.cell

	local cells = self._cells[offset]

	if cells then
		local selected = self:_isCellSelected(offset)

		local backgroundColor = if self._cursorState.offset == offset
			then cellThemeData.cursorActive
			elseif selected then cellThemeData.select
			elseif state == "hover" then cellThemeData.hover
			elseif state == "select" then cellThemeData.select
			else cellThemeData.background
		local textColor = if self._cursorState.offset == offset
			then cellThemeData.cursorActiveText
			elseif selected then cellThemeData.selectText
			elseif state == "hover" then cellThemeData.hoverText
			elseif state == "select" then cellThemeData.selectText
			else self._theme.cell.text

		cells.hex.BackgroundColor3 = backgroundColor
		cells.hex.TextColor3 = textColor
		cells.hex.FontFace = self._theme.font
		cells.hex.TextSize = self._theme.textSize

		if cells.ascii then
			cells.ascii.BackgroundColor3 = backgroundColor
			cells.ascii.TextColor3 = textColor
			cells.ascii.FontFace = self._theme.font
			cells.ascii.TextSize = self._theme.textSize
		end
	end
end

function HexEditor.isCharacterPrintable(asciiCode: number): boolean
	if 0 <= asciiCode and asciiCode <= 31 then
		return false
	elseif asciiCode >= 127 then
		return false
	else
		return true
	end
end

function HexEditor:_updateHeaderPosition()
	assert(self._header)
	assert(self.scrollingFrame)

	self._header.Position = UDim2.fromOffset(0, self.scrollingFrame.CanvasPosition.Y)
end

function HexEditor:_buildHeader()
	assert(not self._header)

	local header = Instance.new("Frame")
	header.BorderSizePixel = 0
	header.BackgroundColor3 = self._theme.headerBackground or self._theme.cell.background
	header.Size = UDim2.fromOffset(
		2 * self._theme.sectionGap + (self._cellWidth + self._halfCellWidth) * self._layout.columns + self._gutterOffset,
		self._cellHeight
	)
	header.ZIndex = 3
	header.Name = "Header"
	header.Parent = self.scrollingFrame

	for i = 0, self._layout.columns - 1 do
		local cell = Instance.new("TextLabel")
		cell.BackgroundTransparency = 1
		cell.TextColor3 = self._theme.headerText or self._theme.cell.text
		cell.TextSize = self._theme.textSize
		cell.FontFace = Font.new(self._theme.font.Family, Enum.FontWeight.Bold, self._theme.font.Style)
		cell.Position = UDim2.fromOffset(self._gutterOffset + i * self._cellWidth, 0)
		cell.Size = UDim2.fromOffset(self._cellWidth, self._cellHeight)
		cell.Text = string.format("%02X", i)
		cell.Name = tostring(i)
		cell.Parent = header
	end

	if self._layout.showDecodedText then
		local decodedText = Instance.new("TextLabel")
		decodedText.BackgroundTransparency = 1
		decodedText.TextColor3 = self._theme.headerText or self._theme.cell.text
		decodedText.TextSize = self._theme.textSize
		decodedText.FontFace = Font.new(self._theme.font.Family, Enum.FontWeight.Bold, self._theme.font.Style)
		decodedText.Position =
			UDim2.fromOffset(self._gutterOffset + self._theme.sectionGap + self._layout.columns * self._cellWidth, 0)
		decodedText.Size = UDim2.new(1, 0, 0, self._cellHeight)
		decodedText.Text = "Decoded Text"
		decodedText.TextXAlignment = Enum.TextXAlignment.Left
		decodedText.Parent = header
	end

	self._header = header
	self._headerOffset = self._cellHeight
	self:_updateHeaderPosition()
end

function HexEditor:_buildRow(row: number)
	local rowOffset = self._layout.columns * row
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromOffset(self._cellWidth * self._layout.columns, self._cellHeight)
	frame.Position = UDim2.fromOffset(0, self._headerOffset + row * self._cellHeight)
	frame.Name = tostring(row)

	if self._layout.showGutter then
		local gutterText = Instance.new("TextLabel")
		gutterText.BackgroundColor3 = self._theme.gutterBackground or self._theme.cell.background
		gutterText.BorderSizePixel = 0
		gutterText.TextColor3 = self._theme.gutterText or self._theme.cell.text
		gutterText.TextSize = self._theme.textSize
		gutterText.FontFace = Font.new(self._theme.font.Family, Enum.FontWeight.Bold, self._theme.font.Style)
		gutterText.Position = UDim2.fromOffset(0, 0)
		gutterText.Size = UDim2.fromOffset(self._gutterOffset - self._theme.sectionGap, self._cellHeight)
		gutterText.Text = string.format("%0" .. tostring(self._layout.gutterColumns) .. "X", row * self._layout.columns)
		gutterText.Name = "Gutter"
		gutterText.Parent = frame
	end

	for i = 0, self._layout.columns - 1 do
		local offset = rowOffset + i
		if offset > self._bufferSize then
			break
		end

		self:_rebuildCell(offset, frame)
	end

	frame.Parent = self.scrollingFrame
	self._rows[row] = frame
end

function HexEditor:_rebuildCell(offset, frame)
	local row = offset // self._layout.columns
	if not frame then
		frame = self._rows[row]
	end

	local previousCell = self._cells[offset]
	if previousCell then
		previousCell.hex:Destroy()
		if previousCell.ascii then
			previousCell.ascii:Destroy()
		end
	end

	if frame then
		local column = offset % self._layout.columns
		-- A cell will be rebuilt when it is modified so we don't have to worry about updating this

		local cell = Instance.new("TextButton")
		cell.BorderSizePixel = 0
		cell.AutoButtonColor = false
		cell.Position = UDim2.fromOffset(self._gutterOffset + column * self._cellWidth, 0)
		cell.Size = UDim2.fromOffset(self._cellWidth, self._cellHeight)
		cell.Parent = frame

		local asciiCell

		if self._layout.showDecodedText then
			asciiCell = cell:Clone()
			asciiCell.Position = UDim2.fromOffset(
				self._gutterOffset
					+ column * self._halfCellWidth
					+ self._cellWidth * self._layout.columns
					+ self._theme.sectionGap,
				0
			)
			asciiCell.Size = UDim2.fromOffset(self._halfCellWidth, self._cellHeight)
			asciiCell.Parent = frame
		end

		local isAddCell = offset == self._bufferSize
		if isAddCell then
			cell.Text = "+"
			if asciiCell then
				asciiCell.Text = "+"
			end
		else
			local asciiCode = buffer.readu8(self._buffer, offset)
			cell.Text = ("%02X"):format(asciiCode)
			if asciiCell then
				asciiCell.Text = if HexEditor.isCharacterPrintable(asciiCode) then string.char(asciiCode) else "·"
			end
		end

		local function generateInputBegan(view: CursorView)
			return function(input: InputObject)
				if input.UserInputType == Enum.UserInputType.MouseMovement then
					if (self._selectionPhase == "mousedown") and self._cursorState.offset and not isAddCell then
						self:_startSelection(self._cursorState.offset, self._cursorState.view :: CursorView)
						self:_updateSelection(offset, view)
					elseif (self._selectionPhase == "selecting") and not isAddCell then
						self:_updateSelection(offset, view)
					elseif self._cursorState.offset ~= offset then
						self:_updateCellStyle(offset, "hover")
					end
				elseif input.UserInputType == Enum.UserInputType.MouseButton1 and not isAddCell then
					if self._selectionPhase == nil then
						self._selectionPhase = "mousedown"

						local previousState = self._cursorState
						self:_clearSelection()
						self:_setCursorState(offset, view)

						local connection: RBXScriptConnection
						connection = input:GetPropertyChangedSignal("UserInputState"):Connect(function()
							if
								not (
									input.UserInputState == Enum.UserInputState.Begin
									or input.UserInputState == Enum.UserInputState.Change
								)
							then
								if self._selectionPhase == "mousedown" then
									if previousState.offset == offset and self._cursorState.view == view then
										self:_cycleCursorMode()
									end
									self._selectionPhase = nil
								end

								self:_endSelection()
								connection:Disconnect()
							end
						end)
					end
				end
			end
		end

		local function generateInputEnded(view: CursorView)
			return function(input: InputObject)
				if input.UserInputType == Enum.UserInputType.MouseMovement then
					if self._cursorState.offset ~= offset then
						self:_updateCellStyle(offset, "default")
					end
				elseif (input.UserInputType == Enum.UserInputType.MouseButton2) and self._dependencies.forms then
					self:_setInModal(true)

					-- Keep a copy of these because they could change in between prompting the user
					local selectionAnchor = self._selectionAnchor
					local cursorOffset = self._cursorState.offset

					local action: string?
					if self:_isCellSelected(offset) then
						action =
							self._dependencies.forms.promptContextMenu(input, HexEditor.SELECTION_CONTEXT_MENU_OPTIONS)
					else
						self:_clearSelection()
						self:_setCursorState(offset, view)
						action = self._dependencies.forms.promptContextMenu(
							input,
							if isAddCell
								then HexEditor.ADD_CELL_CONTEXT_MENU_OPTIONS
								else HexEditor.SINGLE_BYTE_CONTEXT_MENU_OPTIONS
						)
					end

					if action == "Delete Byte" then
						self:_deleteAtCursorWithAction()
					elseif action == "Insert Null Bytes" then
						-- So the user sees where it will insert
						if self._selectionAnchor then
							self:_clearSelection()
							self:_setCursorState(offset, self._cursorState.view :: CursorView)
						end

						local amount = self._dependencies.forms.promptInsertNullBytes(input)
						if amount then
							self:_insertBufferWithAction(offset, buffer.create(amount))
						end
					elseif action == "Fill Selection" then
						local fillPattern = self._dependencies.forms.promptFillWith(input)
						if fillPattern and (buffer.len(fillPattern) > 0) and selectionAnchor and cursorOffset then
							local from = math.min(selectionAnchor, cursorOffset)
							local to = math.max(selectionAnchor, cursorOffset)
							self:_fillPatternWithAction(from, to - from + 1, fillPattern)
						end
					elseif action == "Delete Selection" then
						self:_deleteSelectionWithAction()
					elseif action == "Select All" then
						self:_setSelection(0, self._bufferSize - 1)
					elseif action == "Select None" then
						self:_clearSelection()
					elseif action ~= nil then
						warn(`Unexpected action: {action}`)
					end

					self:_setInModal(false)
				end
			end
		end

		cell.InputBegan:Connect(generateInputBegan("hex"))
		cell.InputEnded:Connect(generateInputEnded("hex"))

		if isAddCell then
			cell.Activated:Connect(function()
				if self._cursorState.offset == offset and self._cursorState.view == "hex" then
					self:_cycleCursorMode()
				else
					self:_clearSelection()
					self:_setCursorState(offset, "hex")
				end
			end)
		end

		if asciiCell then
			asciiCell.InputBegan:Connect(generateInputBegan("ascii"))
			asciiCell.InputEnded:Connect(generateInputEnded("ascii"))

			if isAddCell then
				asciiCell.Activated:Connect(function()
					if self._cursorState.offset == offset and self._cursorState.view == "ascii" then
						self:_cycleCursorMode()
					else
						self:_clearSelection()
						self:_setCursorState(offset, "ascii")
					end
				end)
			end
		end

		self._cells[offset] = { hex = cell, ascii = asciiCell }
		self:_updateCellStyle(offset)
	end
end

function HexEditor:_rebuildVisibleRows(overflow, forceAfterOffset)
	local scrollingFrame = self.scrollingFrame
	if scrollingFrame then
		local totalRows = math.ceil((self._bufferSize + 1) / self._layout.columns)
		scrollingFrame.CanvasSize =
			UDim2.fromOffset(0, self._headerOffset + self._cellHeight * totalRows + scrollingFrame.ScrollBarThickness)

		local min = math.max(
			math.floor((scrollingFrame.CanvasPosition.Y + (if overflow < 0 then overflow else 0)) / self._cellHeight)
				- 1,
			0
		)
		local max = math.min(
			math.ceil(
				(
					scrollingFrame.CanvasPosition.Y
					+ (if overflow > 0 then overflow else 0)
					+ scrollingFrame.AbsoluteWindowSize.Y
				) / self._cellHeight
			) + 1,
			totalRows - 1
		)

		for index, row in self._rows do
			if index < min or index > max then
				row:Destroy()
				self._rows[index] = nil
			end
		end

		local forceAfterRow = if forceAfterOffset then forceAfterOffset // self._layout.columns else math.huge

		for i = min, max do
			if not self._rows[i] then
				self:_buildRow(i)
			elseif i >= forceAfterRow then
				self._rows[i]:Destroy()
				self:_buildRow(i)
			end
		end
	end
end

function HexEditor:_cycleCursorMode()
	if self:_isTyping() then
		self:_finishTyping()
	end

	local mode: CursorMode
	if self._cursorState.mode == "insert" then
		mode = "replace"
	else
		mode = "insert"
	end
	self:_setCursorState(self._cursorState.offset, self._cursorState.view :: CursorView, mode)
end

function HexEditor:_updateCursorStyle(mode, state)
	local mode = mode or self._cursorState.mode
	local state = state
		or (
			if self._cursorState.offset == self._bufferSize
				then "add"
				elseif self._modifiedOffsets[self._cursorState.offset or -1] then "modified"
				else nil
		)
	local cursor = self._cursor
	if cursor then
		if state == "add" then
			cursor.BackgroundColor3 = self._theme.addCell.cursor
		elseif state == "modified" then
			cursor.BackgroundColor3 = self._theme.modifiedCell.cursor
		else
			cursor.BackgroundColor3 = self._theme.cell.cursor
		end

		if mode == "insert" then
			if self._cursorState.view == "hex" then
				cursor.Size = UDim2.fromOffset(2, self._cellHeight)
			else
				cursor.Size = UDim2.fromOffset(1, self._cellHeight)
			end
		elseif mode == "replace" then
			cursor.Size =
				UDim2.fromOffset(if self._cursorState.view == "hex" then self._cellWidth else self._halfCellWidth, 2)
		end
	end
end

function HexEditor:_buildCursor()
	local cursor = Instance.new("Frame")
	self._cursor = cursor
	cursor.BorderSizePixel = 0
	cursor.AnchorPoint = Vector2.new(0, 1)
	cursor.ZIndex = 2
	cursor.Parent = self.scrollingFrame

	self:_updateCursorStyle(self._cursorState.mode)

	-- Blinking
	task.spawn(function()
		while cursor.Parent do
			task.wait(0.5)
			if self._inModal then
				cursor.Visible = false
			else
				cursor.Visible = not cursor.Visible
			end
		end
	end)
end

function HexEditor:_buildUi()
	self:_clearUi()

	local scrollingFrame = Instance.new("ScrollingFrame")
	self.scrollingFrame = scrollingFrame
	scrollingFrame.BorderSizePixel = 0
	scrollingFrame.BackgroundColor3 = self._theme.cell.background
	scrollingFrame.Size = UDim2.fromScale(1, 1)

	scrollingFrame.Parent = self._container
	scrollingFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_rebuildVisibleRows(0)
	end)
	local lastPosition = scrollingFrame.CanvasPosition
	scrollingFrame:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		local delta = scrollingFrame.CanvasPosition - lastPosition
		local overflow = 0
		if math.abs(delta.Y) < 200 then
			overflow = 1.25 * delta.Y
		end

		if self._header then
			self:_updateHeaderPosition()
		end

		self:_rebuildVisibleRows(overflow)
		lastPosition = scrollingFrame.CanvasPosition
	end)

	local scrollingFrameProperties = self._theme.scrollingFrameProperties
	if scrollingFrameProperties then
		for property, value in scrollingFrameProperties do
			(scrollingFrame :: any)[property] = value
		end
	end

	if self._layout.showHeader then
		self:_buildHeader()
	end

	self:_rebuildVisibleRows(0)

	self.horizontalSpaceUsed = self._gutterOffset
		+ self._cellWidth * self._layout.columns
		+ (if self._layout.showDecodedText
			then self._halfCellWidth * self._layout.columns + self._theme.sectionGap
			else 0)
		+ scrollingFrame.ScrollBarThickness
		+ 6

	if self._sizing == "fillContainerY" then
		local sizeConstraint = Instance.new("UISizeConstraint")
		sizeConstraint.MaxSize = Vector2.new(self.horizontalSpaceUsed, math.huge)
		sizeConstraint.Parent = scrollingFrame
	end

	self._sizeChanged:Fire(self.horizontalSpaceUsed)
end

function HexEditor:_clearUi()
	if self._cursor then
		self._cursor:Destroy()
		self._cursor = nil
	end

	for _, cell in self._cells do
		cell.hex:Destroy()
		if cell.ascii then
			cell.ascii:Destroy()
		end
	end
	self._cells = {}

	for _, row in self._rows do
		row:Destroy()
	end
	self._rows = {}

	if self._header then
		self._header:Destroy()
		self._headerOffset = 0
		self._header = nil
	end

	if self.scrollingFrame then
		self.scrollingFrame:Destroy()
		self.scrollingFrame = nil
	end

	if self._hiddenTextBox then
		self:_destroyHiddenTextBox()
	end

	self.horizontalSpaceUsed = 0
end

return table.freeze(HexEditor)
