return function(scrollingFrame: ScrollingFrame, shadow: Frame)
	scrollingFrame:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		shadow.Visible = scrollingFrame.CanvasPosition.Y > 10
	end)
end
