--!strict

-- Editor with missing no highlighting or error capabilties.

local Types = require(script.Parent.Types)

export type NewOptions = {
	theme: Types.Theme,
}

export type DumbEditorObject = Types.TextEditorObject & {
	_textChanged: BindableEvent,
	_activeErrorsChanged: BindableEvent,
	
	_frame: ScrollingFrame,
	_theme: Types.Theme,
	_textBox: TextBox,
	_textBoxPadding: UIPadding,
	
	_connections: {RBXScriptConnection},
	
	_disabled: boolean,
}

local DumbEditorMethods: Types.TextEditorMethods<DumbEditorObject> = {} :: Types.TextEditorMethods<DumbEditorObject>
local mt = {__index = DumbEditorMethods :: any}

local function updateTheme(self: DumbEditorObject)
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

	self._textBoxPadding.PaddingTop = UDim.new(0, self._theme.padding.top)
	self._textBoxPadding.PaddingBottom = UDim.new(0, self._theme.padding.bottom)
	self._textBoxPadding.PaddingLeft = UDim.new(0, self._theme.padding.left)
	self._textBoxPadding.PaddingRight = UDim.new(0, self._theme.padding.right)
end

function DumbEditorMethods:setParent(parent: Instance)
	self._frame.Parent = parent
end

function DumbEditorMethods:getText(): string
	return self._textBox.Text
end

function DumbEditorMethods:setText(text: string)
	self._textBox.Text = text
end

function DumbEditorMethods:setDisabled(disabled: boolean)
	self._textBox.TextEditable = not disabled
	self._disabled = disabled
	updateTheme(self)
end

function DumbEditorMethods:setErrors(errors)
	-- stub, don't do anything, dumb editor doesn't support this
end

function DumbEditorMethods:destroy()
	for _, c in self._connections do
		c:Disconnect()
	end

	self._textChanged:Destroy()
	self._activeErrorsChanged:Destroy()
	self._frame:Destroy()
end

return function(options: NewOptions): Types.TextEditorObject
	local self: DumbEditorObject = setmetatable({}, mt) :: DumbEditorObject
	
	self._theme = options.theme
	
	self._frame = Instance.new("ScrollingFrame")
	self._frame.Size = UDim2.fromScale(1, 1)
	self._frame.VerticalScrollBarInset = Enum.ScrollBarInset.Always
	self._frame.HorizontalScrollBarInset = Enum.ScrollBarInset.None
	self._frame.BorderSizePixel = 0
	self._frame.CanvasSize = UDim2.fromOffset(0, 0)
	self._frame.AutomaticCanvasSize = Enum.AutomaticSize.XY

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
	
	self._textBoxPadding = Instance.new("UIPadding")
	self._textBoxPadding.Parent = self._textBox
	
	-- stub, don't actually use this
	self.activeErrors = {}
	self._activeErrorsChanged = Instance.new("BindableEvent")
	self.activeErrorsChanged = self._activeErrorsChanged.Event :: RBXScriptSignal
	
	self._textChanged = Instance.new("BindableEvent")
	self.textChanged = self._textChanged.Event :: RBXScriptSignal
	
	self._disabled = false
	
	self._connections = {
		self._textBox:GetPropertyChangedSignal("Text"):Connect(function()
			self._textChanged:Fire(self._textBox.Text)
		end),
	}
	
	updateTheme(self)
	
	return self
end