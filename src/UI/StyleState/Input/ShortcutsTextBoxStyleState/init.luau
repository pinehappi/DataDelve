--!strict

-- This handles "shortcuts text box" which are text box with shortcuts that auto replace special sequences.
-- Only works with text box that are not multiline
-- Does not support text boxes with UIPadding that uses Scale

-- Shortcuts:
--		@username: This will replace @username with the id of the user with that name

-- Use :getText(errorHandler) to get the text instead of textBox.Text
-- Must pass in a function to handle any errors that occur.
-- Errors are non-fatal, but should be reported.

local TextService = game:GetService("TextService")
local Players = game:GetService("Players")

local StyleStateHelper = require(script.Parent.Parent.StyleStateHelper)
local Theme = require(script.Parent.Parent.Parent.Theme)

local TextBoxStyleState = require(script.Parent.TextBoxStyleState)

local parseShortcuts = require(script.parseShortcuts)

local ShortcutsTextBoxStyleState = setmetatable({}, { __index = TextBoxStyleState })
ShortcutsTextBoxStyleState.__index = ShortcutsTextBoxStyleState

local function escapeRichText(source: string): string
	return source:gsub("&", "&amp;"):gsub("'", "&apos;"):gsub('"', "&quot;"):gsub("<", "&lt;"):gsub(">", "&gt;")
end

local function getLengthToCursor(textBox: TextBox)
	local sub = textBox.Text:sub(1, textBox.CursorPosition - 1)
	local params = Instance.new("GetTextBoundsParams")
	params.Text = sub
	params.Font = textBox.FontFace
	params.Size = textBox.TextSize
	params.Width = math.huge
	return TextService:GetTextBoundsAsync(params).X
end

function ShortcutsTextBoxStyleState.from(theme: Theme.Theme, textBox: TextBox & { UIStroke: UIStroke })
	local self = setmetatable(TextBoxStyleState.from(theme, textBox), ShortcutsTextBoxStyleState)

	self.overlay = Instance.new("TextLabel")
	self.overlay.BackgroundTransparency = 1
	self.overlay.TextColor3 = Color3.new(1, 0, 0)
	self.overlay.TextSize = textBox.TextSize
	self.overlay.FontFace = textBox.FontFace
	self.overlay.RichText = true
	self.overlay.TextXAlignment = textBox.TextXAlignment
	self.overlay.TextYAlignment = textBox.TextYAlignment
	self.overlay.Size = UDim2.fromScale(1, 1)
	self.overlay.TextWrapped = false
	self.overlay.Text = textBox.Text
	self.overlay.Parent = textBox

	local paddingX = 0
	do
		local uiPadding = textBox:FindFirstChildOfClass("UIPadding")
		if uiPadding then
			paddingX = uiPadding.PaddingLeft.Offset + uiPadding.PaddingRight.Offset
		end
	end
	self._lastShift = 0
	self._pieces = {} :: parseShortcuts.ShortcutsString

	self._shortcutsConnections = {
		textBox:GetPropertyChangedSignal("Text"):Connect(function()
			self:_updateOverlayText(false)
		end),
		textBox:GetPropertyChangedSignal("CursorPosition"):Connect(function()
			if textBox.CursorPosition <= 0 then
				self:_updateShift(0)
			else
				local boundsX = self._lastShift + (self.textBox.AbsoluteSize.X - paddingX) - 1
				local cursorX = getLengthToCursor(textBox)
				self.overlay.Size = UDim2.new(0, cursorX, 1, 0) -- The RichTextLabel will stop rendering when it is too far away, so make it bigger
				if cursorX < self._lastShift then
					self:_updateShift(cursorX)
				elseif cursorX > boundsX then
					local shifted = cursorX - boundsX
					self:_updateShift(self._lastShift + shifted)
				end
			end
		end),
	}

	return self
end

function ShortcutsTextBoxStyleState:_updateOverlayText(useCachedPieces: boolean)
	local pieces = if useCachedPieces
		then self._pieces :: parseShortcuts.ShortcutsString
		else parseShortcuts(self.textBox.Text)
	local text = table.create(#pieces)
	for _, piece in pieces do
		if piece.type == "normal" then
			table.insert(text, `<font transparency="1">{escapeRichText(piece.content)}</font>`)
		elseif piece.type == "escapedNormal" then
			table.insert(
				text,
				`<font color="#{self.theme.colors.syntaxHighlight.string:ToHex()}">{escapeRichText(piece.content)}</font>`
			)
		elseif piece.type == "mention" then
			table.insert(
				text,
				`<font color="#{self.theme.colors.syntaxHighlight.root:ToHex()}">{escapeRichText(piece.content)}</font>`
			)
		end
	end
	self.overlay.Text = table.concat(text)

	self._pieces = pieces
end

function ShortcutsTextBoxStyleState:_updateShift(amount: number)
	self._lastShift = amount
	self.overlay.Position = UDim2.fromOffset(-amount, 0)
end

function ShortcutsTextBoxStyleState:update(speed: StyleStateHelper.TransitionSpeed)
	TextBoxStyleState.update(self, speed)
	StyleStateHelper.tween(self.overlay, StyleStateHelper.getTweenInfoForSpeed(speed), {
		TextTransparency = if self.disabled then 0.75 else 0,
	})
	self:_updateOverlayText(true)
end

local noop = function(err: string) end

type TextResult = {
	type: "text",
	content: string,
} | {
	type: "error",
	message: string,
}
function ShortcutsTextBoxStyleState:getText(errorHandler: TextBoxStyleState.GetTextErrorHandler?): string
	local errorHandler = errorHandler or noop
	local pieces = self._pieces :: parseShortcuts.ShortcutsString
	local text = table.create(#pieces)

	for _, piece in pieces do
		if piece.type == "normal" then
			table.insert(text, piece.content)
		elseif piece.type == "escapedNormal" then
			table.insert(text, piece.content:sub(2))
		elseif piece.type == "mention" then
			local name: string
			local id = piece.content:sub(2)
			local success, err = pcall(function()
				name = Players:GetUserIdFromNameAsync(id)
			end)

			if not success then
				if err:find("Unknown user") then
					errorHandler(`User not found: {id}`)
				else
					errorHandler(err)
				end
				table.insert(text, piece.content)
			else
				table.insert(text, name)
			end
		end
	end

	return table.concat(text)
end

function ShortcutsTextBoxStyleState:destroy(completely: boolean)
	for _, connection in self._shortcutsConnections do
		connection:Disconnect()
	end
	TextBoxStyleState.destroy(self, completely)
end

return ShortcutsTextBoxStyleState
