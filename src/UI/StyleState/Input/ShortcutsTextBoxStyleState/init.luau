--!strict

-- This handles "shortcuts text box" which are text box with shortcuts that auto replace special sequences.

-- Shortcuts:
--		@username: This will replace @username with the id of the user with that name

-- Use :getText(errorHandler) to get the text instead of textBox.Text
-- Must pass in a function to handle any errors that occur.
-- Errors are non-fatal, but should be reported.

local Players = game:GetService("Players")

local Theme = require(script.Parent.Parent.Parent.Theme)

local TextBoxStyleState = require(script.Parent.TextBoxStyleState)
local OverlayTextBoxStyleState = require(script.Parent.OverlayTextBoxStyleState)

local parseShortcuts = require(script.parseShortcuts)

local ShortcutsTextBoxStyleState = setmetatable({}, { __index = OverlayTextBoxStyleState })
ShortcutsTextBoxStyleState.__index = ShortcutsTextBoxStyleState

function ShortcutsTextBoxStyleState.from(theme: Theme.Theme, textBox: TextBox & { UIStroke: UIStroke })
	local self = setmetatable(OverlayTextBoxStyleState.from(theme, textBox), ShortcutsTextBoxStyleState)

	self._shortcutPieces = {}

	self._textChangedConnection = textBox:GetPropertyChangedSignal("Text"):Connect(function()
		self:_updatePieces()
	end)

	return self
end

function ShortcutsTextBoxStyleState:_updatePieces()
	local shortcutPieces = parseShortcuts(self.textBox.Text)
	self._shortcutPieces = shortcutPieces
	local highlightPieces = table.create(#shortcutPieces)

	for _, piece in shortcutPieces do
		table.insert(highlightPieces, {
			hg = if piece.type == "mention" then "root" elseif piece.type == "escapedNormal" then "string" else nil,
			text = piece.content,
		})
	end

	self:setPieces(highlightPieces)
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
	local pieces = self._shortcutPieces :: parseShortcuts.ShortcutsString
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
	self._textChangedConnection:Disconnect()
	OverlayTextBoxStyleState.destroy(self, completely)
end

return ShortcutsTextBoxStyleState
