--!strict

local Theme = require(script.Parent.Parent.Theme)
local Types = require(script.Parent.Types)

local HexEditor = require(script.HexEditor)
local DataInspector = require(script.DataInspector)
local FormProvider = require(script.FormProvider)

export type HexImplementation = {
	__index: HexImplementation,
	from: (buf: buffer, container: Frame, options: Types.BufferViewerFromOptions) -> Hex,
	setValue: (Hex, buf: buffer) -> (),
	getValue: (Hex) -> buffer,
	destroy: (Hex) -> (),

	undo: (Hex) -> (),
	redo: (Hex) -> (),
	canUndo: (Hex) -> boolean,
	canRedo: (Hex) -> boolean,
}

export type HexFields = {
	historyChanged: RBXScriptSignal,

	_container: Frame,
	_editor: HexEditor.HexEditor,
	_dataInspector: DataInspector.DataInspector,
}

export type Hex = typeof(setmetatable({} :: HexFields, {} :: HexImplementation))

local Hex: HexImplementation = {} :: HexImplementation
Hex.__index = Hex

local function generateCellTheme(theme: Theme.Theme, accent: Color3?): HexEditor.CellThemeData
	local mainBackground = if accent
		then accent:Lerp(theme.colors.background, math.min(0.8, 2 * theme.colors.button.transparent.hover))
		else theme.colors.background

	local accent = accent or theme.colors.mainAccent

	local hoverTransparency = math.min(0.75, 1.5 * theme.colors.button.transparent.select)
	local selectTransparency = math.min(0.6, 1.25 * theme.colors.button.transparent.select)

	local hoverBackground = accent:Lerp(theme.colors.background, hoverTransparency)

	local trueSelectBackground = theme.colors.mainAccent:Lerp(theme.colors.background, selectTransparency)
	local selectBackground = accent:Lerp(theme.colors.background, selectTransparency)
	local finalSelectBackground = selectBackground:Lerp(trueSelectBackground, 0.5)

	local cursorBackground =
		accent:Lerp(theme.colors.background, math.min(0.5, 0.75 * theme.colors.button.transparent.select))

	return {
		background = mainBackground,
		text = Theme.improveContrast(theme.colors.text, mainBackground),

		hover = hoverBackground,
		hoverText = Theme.improveContrast(theme.colors.text, hoverBackground),

		select = finalSelectBackground,
		selectText = Theme.improveContrast(theme.colors.text, finalSelectBackground),

		cursorActive = cursorBackground,
		cursorActiveText = Theme.improveContrast(theme.colors.text, cursorBackground),

		cursor = accent,
	}
end

-- Generates themes for hex editor and data inspector
local function generateThemes(theme: Theme.Theme): (HexEditor.ThemeData, DataInspector.ThemeData)
	local accentHue, accentSaturation, accentValue = theme.colors.mainAccent:ToHSV()
	local hoverAccent = Color3.fromHSV((accentHue + 0.525) % 1, accentSaturation, accentValue)
	local addAccent = Color3.fromHSV((accentHue + 0.7) % 1, accentSaturation, accentValue)

	local hexEditorTheme = {
		cell = generateCellTheme(theme),
		modifiedCell = generateCellTheme(theme, hoverAccent),
		addCell = generateCellTheme(theme, addAccent),

		headerText = theme.colors.disabledText,
		headerActiveText = theme.colors.text,
		headerBackground = theme.colors.background,

		gutterText = theme.colors.disabledText,
		gutterActiveText = theme.colors.text,
		gutterBackground = theme.colors.background,

		font = Font.fromEnum(Enum.Font.Code),
		textSize = 14,

		sectionGap = 12,
		cellPadding = 4,
		halfCellPadding = 0,

		scrollingFrameProperties = {
			ScrollBarThickness = 8,
			ScrollBarImageColor3 = Color3.new(0.5, 0.5, 0.5),
		},
	}

	local dataInspectorTheme = {
		background = theme.colors.background,
		bodyPadding = 4,
		editorMargin = 12,

		headerBackground = theme.colors.background,
		headerText = theme.colors.disabledText,

		keyText = theme.colors.text,
		valueText = theme.colors.text,
		invalidValueText = theme.colors.disabledText,
		keyValuePadding = 24,
		rowPadding = 4,

		font = Font.fromEnum(Enum.Font.Code),
		textSize = 14,

		scrollingFrameProperties = {
			ScrollBarThickness = 8,
			ScrollBarImageColor3 = Color3.new(0.5, 0.5, 0.5),
		},
	}

	return hexEditorTheme, dataInspectorTheme
end

function Hex.from(buf: buffer, container: Frame, options: Types.BufferViewerFromOptions)
	local self = setmetatable({}, Hex)
	self._theme = options.theme

	self._container = container

	local hexEditorTheme, dataInpsectorTheme = generateThemes(options.theme)
	self._editor = HexEditor.new(buf, {
		container = self._container,
		sizing = "fillContainerY",
		theme = hexEditorTheme,
		layout = {
			columns = 16,
			showHeader = true,
			showGutter = true,
			showDecodedText = true,
			gutterColumns = 6,
		},
	}, {
		inputReceiver = options.inputReceiver,
		forms = FormProvider.generate(self._theme, hexEditorTheme, options.inputReceiver, options.widget),
	})

	self._dataInspector = DataInspector.new(self._editor, {
		container = self._container,
		sizing = "fillContainerY",
		theme = dataInpsectorTheme,
	})

	self.historyChanged = self._editor.historyChanged

	return self
end

function Hex.setValue(self: Hex, buf: buffer)
	self._editor:setBuffer(buf)
end

function Hex.getValue(self: Hex): buffer
	local got, size = self._editor:getRawBuffer()
	local copy = buffer.create(size)
	buffer.copy(copy, 0, got, 0, size)
	return copy
end

function Hex.canUndo(self: Hex)
	return self._editor:canUndo()
end

function Hex.canRedo(self: Hex)
	return self._editor:canRedo()
end

function Hex.redo(self: Hex)
	return self._editor:redo()
end

function Hex.undo(self: Hex)
	return self._editor:undo()
end

function Hex.destroy(self: Hex)
	self._editor:destroy()
	self._dataInspector:destroy()
end

return Hex
