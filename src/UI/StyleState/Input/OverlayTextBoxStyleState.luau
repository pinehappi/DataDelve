--!strict

-- Only works with text box that are not multiline
-- Does not support text boxes with UIPadding that uses Scale

local TextService = game:GetService("TextService")
local Players = game:GetService("Players")

local StyleStateHelper = require(script.Parent.Parent.StyleStateHelper)
local Theme = require(script.Parent.Parent.Parent.Theme)

local TextBoxStyleState = require(script.Parent.TextBoxStyleState)

local OverlayTextBoxStyleState = setmetatable({}, { __index = TextBoxStyleState })
OverlayTextBoxStyleState.__index = OverlayTextBoxStyleState

export type Piece = {
	text: string,
	hg: string?, -- Highlight group. `nil` means do not highlight
}

local function escapeRichText(source: string): string
	return source:gsub("&", "&amp;"):gsub("'", "&apos;"):gsub('"', "&quot;"):gsub("<", "&lt;"):gsub(">", "&gt;")
end

local function getLengthOfText(textBox: TextBox, text: string)
	local params = Instance.new("GetTextBoundsParams")
	params.Text = text
	params.Font = textBox.FontFace
	params.Size = textBox.TextSize
	params.Width = math.huge
	return TextService:GetTextBoundsAsync(params).X
end

local function getLengthToCursor(textBox: TextBox)
	return getLengthOfText(textBox, textBox.Text:sub(1, textBox.CursorPosition - 1))
end

function OverlayTextBoxStyleState.from(theme: Theme.Theme, textBox: TextBox & { UIStroke: UIStroke })
	local self = setmetatable(TextBoxStyleState.from(theme, textBox), OverlayTextBoxStyleState)
	self._highlightColors = nil

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
	self._atEnd = false
	self._pieces = {} :: { Piece }

	self._cursorPositionConnection = textBox:GetPropertyChangedSignal("CursorPosition"):Connect(function()
		if textBox.CursorPosition <= 0 then
			self:_updateShift(0)
			self._atEnd = false
		else
			local startBoundsX = self._lastShift
			local endBoundsX = startBoundsX + (self.textBox.AbsoluteSize.X - paddingX) - 1
			local cursorX = getLengthToCursor(textBox)

			self.overlay.Size = UDim2.new(0, cursorX, 1, 0) -- The RichTextLabel will stop rendering when it is too far away, so make it bigger

			if cursorX < startBoundsX then
				self:_updateShift(cursorX)
				self._atEnd = false
			elseif cursorX > endBoundsX then
				local shifted = cursorX - endBoundsX
				self:_updateShift(startBoundsX + shifted)
				self._atEnd = true
			elseif cursorX < endBoundsX then
				-- User backspaced, have to move back
				-- This will also fire for inserts, so check it actually moved down
				if self._atEnd then
					local lengthX = getLengthOfText(textBox, textBox.Text)
					local shifted = endBoundsX - lengthX
					if shifted > 0 then
						self:_updateShift(startBoundsX - shifted)

						if self._lastShift == 0 then
							self._atEnd = false
						end
					end
				end
			end
		end
	end)

	return self
end

function OverlayTextBoxStyleState:setPieces(pieces: { Piece })
	self._pieces = pieces
	self:_updateOverlayText()
end

function OverlayTextBoxStyleState:setHighlightColors(colors: { [string]: Color3 })
	self._highlightColors = colors
	self:_updateOverlayText()
end

function OverlayTextBoxStyleState:_updateOverlayText()
	local pieces = self._pieces :: { Piece }
	local text = table.create(#pieces)
	for _, piece in pieces do
		if not piece.hg then
			table.insert(text, `<font transparency="1">{escapeRichText(piece.text)}</font>`)
		else
			table.insert(
				text,
				`<font color="#{(self._highlightColors or self.theme.colors.syntaxHighlight)[piece.hg]:ToHex()}">{escapeRichText(
					piece.text
				)}</font>`
			)
		end
	end
	self.overlay.Text = table.concat(text)
end

function OverlayTextBoxStyleState:_updateShift(amount: number)
	amount = math.max(0, amount)
	self._lastShift = amount
	self.overlay.Position = UDim2.fromOffset(-amount, 0)
end

function OverlayTextBoxStyleState:update(speed: StyleStateHelper.TransitionSpeed)
	TextBoxStyleState.update(self, speed)
	StyleStateHelper.tween(self.overlay, StyleStateHelper.getTweenInfoForSpeed(speed), {
		TextTransparency = if self.disabled then 0.75 else 0,
	})
	self:_updateOverlayText(true)
end

function OverlayTextBoxStyleState:destroy(completely: boolean)
	self._cursorPositionConnection:Disconnect()
	TextBoxStyleState.destroy(self, completely)
end

return OverlayTextBoxStyleState
