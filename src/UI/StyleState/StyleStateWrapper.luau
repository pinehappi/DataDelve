-- Utility class useful for one-off style states.
-- See `UI.createUserCard` for example

local StyleStateHelper = require(script.Parent.StyleStateHelper)

local StyleStateWrapper = {}
StyleStateWrapper.__index = StyleStateWrapper

export type StyleStateWrapperOptions = {
	autoFollowTheme: boolean?, -- default: true
	onThemeChange: (() -> ())?, -- Will only be called if autoFollowTheme is true
}
function StyleStateWrapper.new<
	T --[[: {[string]: StyleState}]]
>(theme, styleStates: T, options: StyleStateWrapperOptions?)
	options = options or {}
	assert(options)

	local self = setmetatable({
		styleStates = styleStates,
		connections = {},
	}, StyleStateWrapper)

	if (options.autoFollowTheme == nil) or options.autoFollowTheme then
		table.insert(
			self.connections,
			theme.colorsChanged:Connect(function()
				self:update("slow")
				if options.onThemeChange then
					options.onThemeChange()
				end
			end)
		)
	end

	return self
end

function StyleStateWrapper:update(speed: StyleStateHelper.TransitionSpeed)
	StyleStateHelper.update(self.styleStates, speed)
end

local function destroy(styleStates, completely: boolean)
	for _, state in styleStates do
		-- Otherwise it's probably a table with stylestates in it
		if state.destroy then
			state:destroy(completely)
		else
			destroy(state, completely)
		end
	end
end

function StyleStateWrapper:destroy(completely: boolean)
	destroy(self.styleStates, completely)
	for _, connection in self.connections do
		connection:Disconnect()
	end
end

return StyleStateWrapper
