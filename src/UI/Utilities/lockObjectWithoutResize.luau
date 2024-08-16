-- Sets the position of an object without triggering AutomaticSize resizing.
-- Assumes UIPadding only has offset padding.
return function(
	object: GuiObject,
	container: GuiObject & { UIPadding: UIPadding? },
	anchorRelativeToParent: Vector2,
	extraOffset: UDim2
)
	local uiPadding = container:FindFirstChildOfClass("UIPadding")
	local function updatePosition()
		local x = anchorRelativeToParent.X
			* (
				container.AbsoluteSize.X
				- uiPadding.PaddingRight.Offset
				- uiPadding.PaddingLeft.Offset
			)
		local y = anchorRelativeToParent.Y
			* (
				container.AbsoluteSize.Y
				- uiPadding.PaddingTop.Offset
				- uiPadding.PaddingBottom.Offset
			)
		object.Position = UDim2.fromOffset(x, y) + extraOffset
	end

	object.AnchorPoint = anchorRelativeToParent

	updatePosition()
	container:GetPropertyChangedSignal("AbsoluteSize"):Connect(updatePosition)
end
