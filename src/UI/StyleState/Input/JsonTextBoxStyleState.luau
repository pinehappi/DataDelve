--!strict

-- Behavior:
--	- tries to parse as JSON5 (permissible mode)
--	- falls back to JsonHelper dumb parsing if it doesn't look like they're trying to type
--	  in an object/array

-- NOTE: meant to be used transitively! should not be long-lived as the highlight colors are only calculated on initialization.

local Theme = require(script.Parent.Parent.Parent.Theme)
local json5 = require(script.Parent.Parent.Parent.Parent.json5)
local JSONHelper = require(script.Parent.Parent.Parent.Parent.JSONHelper)

local OverlayTextBoxStyleState = require(script.Parent.OverlayTextBoxStyleState)
local getHighlightColors = require(script.Parent.Parent.Parent.Utilities.getHighlightColors)

local JsonTextBoxStyleState = setmetatable({}, { __index = OverlayTextBoxStyleState })
JsonTextBoxStyleState.__index = JsonTextBoxStyleState

export type JsonTextBoxStyleStateFromOptions = {
	-- Default is false. Whether or not to respsect the users highlight colors setting.
	useDefaultTheme: boolean?,
}
function JsonTextBoxStyleState.from(
	theme: Theme.Theme,
	textBox: TextBox & { UIStroke: UIStroke },
	options: JsonTextBoxStyleStateFromOptions
)
	options = options or {}
	assert(options, "???")

	local self = setmetatable(OverlayTextBoxStyleState.from(theme, textBox), JsonTextBoxStyleState)

	self._cachedValue = nil
	self._cachedParseFailed = false
	self._cachedIsArray = false

	self._textChangedConnection = textBox:GetPropertyChangedSignal("Text"):Connect(function()
		self:_updatePieces()
	end)

	local highlightColors = getHighlightColors(theme, if options.useDefaultTheme then "forceDefault" else nil)
	self:setHighlightColors(highlightColors)
	if not options.useDefaultTheme then
		self:overrideBackgroundColor(highlightColors.background)
		self:overrideTextColor(highlightColors.plain)
	end
	self:update("instant")

	return self
end

-- Second return is if it is an array
function JsonTextBoxStyleState:getJson(): (json5.Json, boolean)
	if self._cachedParseFailed then
		local valueType, parsedValue = JSONHelper.parseInputString(self.textBox.Text)
		return parsedValue, (valueType == "array")
	else
		return self._cachedValue, self._cachedIsArray
	end
end

function JsonTextBoxStyleState:_updatePiecesDumbMode()
	local source = self.textBox.Text
	local valueType, parsedValue = JSONHelper.parseInputString(source)
	local piece = { {
		text = source,
		hg = valueType,
	} }
	self._cachedValue = parsedValue
	self._cachedParseFailed = false
	self._cachedIsArray = (valueType == "array")

	self:setPieces(piece)
end

local DECODE_OPTIONS: json5.DecodeOptions = {
	mode = "permissive",
	collectTokens = true,
}
local STRING_FALLBACK_REGEX = [=[^%s*["']]=]
function JsonTextBoxStyleState:_updatePieces()
	local source = self.textBox.Text
	if JSONHelper.looksDumb(source) then
		self:_updatePiecesDumbMode()
	else
		local pieces = table.create(8)

		local result = json5.decode(source, DECODE_OPTIONS)
		local errorSpots = {}
		if result.kind == "failure" then
			if source:match(STRING_FALLBACK_REGEX) then
				self:_updatePiecesDumbMode()
				return
			end

			for _, err in result.errors do
				if err.token then
					errorSpots[err.token.start] = true
				end
				if (err :: any).openingToken then
					errorSpots[(err :: any).openingToken.start] = true
				end
			end
			self._cachedValue = nil :: json5.Json
			self._cachedParseFailed = true
		elseif result.kind == "success" then
			self._cachedValue = result.json
			self._cachedParseFailed = false
			self._cachedIsArray = result.isArray
		end

		local start = os.clock()
		for _, token in result.tokens :: { json5.Token } do
			table.insert(pieces, {
				text = json5.getTokenContent(source, token),
				hg = if errorSpots[token.start] then "error" else JSONHelper.highlightGroups[token.kind],
			})
		end

		self:setPieces(pieces)
	end
end

function JsonTextBoxStyleState:destroy(completely: boolean)
	self._textChangedConnection:Disconnect()
	OverlayTextBoxStyleState.destroy(self, completely)
end

return JsonTextBoxStyleState
