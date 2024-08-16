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
				- container.UIPadding.PaddingRight.Offset
				- container.UIPadding.PaddingLeft.Offset
			)
		local y = anchorRelativeToParent.Y
			* (
				container.AbsoluteSize.Y
				- container.UIPadding.PaddingTop.Offset
				- container.UIPadding.PaddingBottom.Offset
			)
		object.Position = UDim2.fromOffset(x, y) + extraOffset
	end

	object.AnchorPoint = anchorRelativeToParent

	updatePosition()
	container:GetPropertyChangedSignal("AbsoluteSize"):Connect(updatePosition)
end
