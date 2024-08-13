-- Should be used ephemerally

-- Example:
-- ```
-- local styleState = LoadingBarStyleState.from(theme, frame)
-- task.spawn(styleState.animate, styleState)
-- task.wait(5)
-- styleState:destroy()
-- ```

local StyleStateHelper = require(script.Parent.Parent.StyleStateHelper)
local Theme = require(script.Parent.Parent.Parent.Theme)

local LoadingBarStyleState = {}
LoadingBarStyleState.__index = LoadingBarStyleState

-- For convenience
-- Returns a function to delete the loading bar
function LoadingBarStyleState.show(theme, container: Frame): () -> ()
	local loadingBar = LoadingBarStyleState.from(theme, container)
	loadingBar.container.Visible = true
	task.spawn(loadingBar.animate, loadingBar)

	return function()
		loadingBar.container.Visible = false
		loadingBar:destroy()
	end
end

function LoadingBarStyleState.from(theme, container: Frame)
	local self = setmetatable({
		theme = theme,
		container = container,
		fill = script.Fill:Clone(),
	}, LoadingBarStyleState)

	self.fill.Parent = container

	self:update("instant")
	return self
end

function LoadingBarStyleState:update()
	if Theme.getLuminance(self.theme.colors.background) > 0.5 then
		self.container.BackgroundTransparency = 0
		local hue, saturation, value = Theme.getAccentComponents(self.theme.preset, self.theme.accent)
		self.container.BackgroundColor3 = Color3.new(0.6, 0.6, 0.6)
	else
		self.container.BackgroundTransparency = 0.75
		self.container.BackgroundColor3 = self.theme.colors.mainAccent
	end
	self.fill.BackgroundColor3 = self.theme.colors.mainAccent
end

-- destroy completely for animation to end
function LoadingBarStyleState:animate()
	local start = os.clock()
	-- Light theme it's hard to see the bar at first so fast forward so they see it
	if Theme.getLuminance(self.theme.colors.background) > 0.5 then
		start += 0.5
	end

	while self.fill.Parent do
		local delta = os.clock() - start
		local a = 1.5 * delta
		local b = a % 1
		self.fill.Position = UDim2.fromScale(-0.5 + 2 * b, 0)
		task.wait()
	end
end

function LoadingBarStyleState:destroy(completely)
	assert(not completely, "Loading bar should not own the frame that contains the fill.")

	self.fill:Destroy()
	if completely then
		self.frame:Destroy()
	end
end

return LoadingBarStyleState
