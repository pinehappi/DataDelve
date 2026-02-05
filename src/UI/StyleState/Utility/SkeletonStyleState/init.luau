-- Should be used ephemerally

-- Just apply this to any object.
-- Objects in the children that have attribute "SkeletonPlaceholder" will be styled.
-- If they also have "DeleteWithSkeleton" attribute they will be deleted when the skeleton is deleted.

--- Call :animate to animate the skeleton

local TweenService = game:GetService("TweenService")

local StyleStateHelper = require(script.Parent.Parent.StyleStateHelper)

local SkeletonStyleState = {}
SkeletonStyleState.__index = SkeletonStyleState

function SkeletonStyleState.from(theme, object: GuiObject)
	local self = setmetatable({
		theme = theme,
		object = object,

		skeletonPlaceholders = {},

		_destroyed = false,
	}, SkeletonStyleState)

	for _, child in object:GetDescendants() do
		if child:GetAttribute("SkeletonPlaceholder") then
			local gradient = script.Gradient:Clone()
			gradient.Parent = child
			table.insert(self.skeletonPlaceholders, {
				deleteWith = child:GetAttribute("DeleteWithSkeleton"),
				object = child,
				gradient = gradient,
				originalColor = child.BackgroundColor3,
				originalTransparency = child.BackgroundTransparency,
			})
		end
	end

	self:update("instant")
	return self
end

function SkeletonStyleState:animate()
	local start = os.clock()
	while not self._destroyed do
		local delta = os.clock() - start
		local a = delta % 2
		if a <= 0.5 then
			a = 2 * a
		else
			a = 1
		end

		local offset = Vector2.new(2 * (0.5 - a), 0)

		for _, placeholder in self.skeletonPlaceholders do
			placeholder.gradient.Offset = offset
		end

		task.wait()
	end
end

function SkeletonStyleState:update(speed: StyleStateHelper.TransitionSpeed)
	local tweenInfo = StyleStateHelper.getTweenInfoForSpeed(speed)
	for _, placeholder in self.skeletonPlaceholders do
		TweenService:Create(placeholder.object, tweenInfo, {
			BackgroundColor3 = Color3.new(0.5, 0.5, 0.5),
			BackgroundTransparency = 0.5,
		}):Play()
	end
end

function SkeletonStyleState:destroy(completely: boolean)
	if self._destroyed then
		return
	end
	self._destroyed = true

	for _, placeholder in self.skeletonPlaceholders do
		if placeholder.deleteWith then
			placeholder.object:Destroy()
		else
			placeholder.object.BackgroundColor3 = placeholder.originalColor
			placeholder.object.BackgroundTransparency = placeholder.originalTransparency
			placeholder.gradient:Destroy()
		end
	end

	if completely then
		self.object:Destroy()
	end
end

return SkeletonStyleState
