--!strict

local plugin = script:FindFirstAncestorOfClass("Plugin")

local HexEditor = require(script.HexEditor)
local DataInspector = require(script.DataInspector)
local FormProvider = require(script.FormProvider)

local Theme = require(script.Parent.Theme)

local Assets = script.Parent.Assets
local StyleState = script.Parent.StyleState
local StyleStateWrapper = require(StyleState.StyleStateWrapper)
local BackgroundStyleState = require(StyleState.BackgroundStyleState)
local ButtonStyleState = require(StyleState.ButtonStyleState)

local WIDGET_INFO = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Float, -- Widget will be initialized in floating panel
	true, -- Widget will be initially enabled
	true, -- Override the previous enabled state
	832, -- Default width of the floating window
	300, -- Default height of the floating window
	400, -- Minimum width of the floating window
	150 -- Minimum height of the floating window
)

local HexEditorWidget = {}
HexEditorWidget.__index = HexEditorWidget

-- There can only be one open
local globalHexEditorWidget: any

function HexEditorWidget.new(id: string, theme: Theme.Theme, b: buffer)
	if globalHexEditorWidget then
		globalHexEditorWidget:destroy()
		globalHexEditorWidget = nil
	end

	local self = setmetatable({}, HexEditorWidget)
	self.dead = false
	self.id = id

	self.theme = theme
	self.widget = plugin:CreateDockWidgetPluginGui(id, WIDGET_INFO) :: PluginGui & typeof(Assets.HexEditorWidget)
	self.widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	self.widget.Title = tostring(b)
	self.widget.Name = "DataDelve HexEditor"

	-- Set up UI

	for _, item in Assets.HexEditorWidget:GetChildren() do
		item:Clone().Parent = self.widget
	end
	self.wrapper = StyleStateWrapper.new(theme, {
		background = BackgroundStyleState.from(theme, self.widget.Background),
		undo = ButtonStyleState.from(theme, self.widget.Content.LeftTop.Undo, { style = "dormant" }),
		redo = ButtonStyleState.from(theme, self.widget.Content.LeftTop.Redo, { style = "dormant" }),

		commit = ButtonStyleState.from(theme, self.widget.Content.RightTop.Commit, { style = "primary" }),
		cancel = ButtonStyleState.from(theme, self.widget.Content.RightTop.Cancel, { style = "secondary" }),
	})

	local hexEditorTheme, dataInpsectorTheme = HexEditorWidget.generateThemes(theme)
	self.editor = HexEditor.new(b, {
		container = self.widget.Content.EditorContainer,
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
		inputReceiver = self.widget.InputReceiver,
		forms = FormProvider.generate(theme, hexEditorTheme, self.widget.InputReceiver, self.widget),
	})

	self.dataInspector = DataInspector.new(self.editor, {
		container = self.widget.Content.EditorContainer,
		sizing = "fillContainerY",
		theme = dataInpsectorTheme,
	})

	-- Events

	-- Parameters:
	--	submitted: boolean
	--		If the user submitted or cancelled. True is submitted.
	-- NOTE: this is fired with false when the widget is destroyed
	self._interacted = Instance.new("BindableEvent")
	self.interacted = self._interacted.Event

	-- UI Events

	do
		local selfAny = self :: any
		selfAny:_updateUndoRedoButtons()
		selfAny.editor.historyChanged:Connect(function()
			selfAny:_updateUndoRedoButtons()
		end)
	end

	self.wrapper.styleStates.undo.button.Activated:Connect(function()
		self.editor:undo()
	end)
	self.wrapper.styleStates.redo.button.Activated:Connect(function()
		self.editor:redo()
	end)
	self.wrapper.styleStates.cancel.button.Activated:Connect(function()
		self._interacted:Fire(false)
	end)
	self.wrapper.styleStates.commit.button.Activated:Connect(function()
		self._interacted:Fire(true)
	end)

	self.widget.Destroying:Connect(function()
		(self :: any):destroy()
	end)
	self.widget:GetPropertyChangedSignal("Enabled"):Connect(function()
		if not self.widget.Enabled then
			(self :: any):destroy()
		end
	end)

	globalHexEditorWidget = self
	return self
end

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
function HexEditorWidget.generateThemes(theme: Theme.Theme): (HexEditor.ThemeData, DataInspector.ThemeData)
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

function HexEditorWidget:_updateUndoRedoButtons(speed: string?)
	self.wrapper.styleStates.undo:setDisabled(not self.editor:canUndo()):update(speed)
	self.wrapper.styleStates.redo:setDisabled(not self.editor:canRedo()):update(speed)
end

function HexEditorWidget:destroy()
	if self.dead then
		return
	end
	self.dead = true

	self._interacted:Fire(false)

	self.wrapper:destroy(true)
	self.editor:destroy()
	self.dataInspector:destroy()
	self.widget:Destroy()
end

export type HexEditorWidget = typeof(HexEditorWidget.new("hey", {} :: any, buffer.create(0)))
return HexEditorWidget
