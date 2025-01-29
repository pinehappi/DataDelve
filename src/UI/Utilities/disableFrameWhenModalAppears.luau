-- `PopupHelper.modal` creates a frame to block input, but it does not block MouseMovement inputs.
-- To fix that, this utility function will detect when the input blocking frame of `PopupHelper.modal`
-- appears and disable `Interactable` for all the frames you give it. This will prevent MouseMovement
-- inputs from being fired.

-- DRAWBACK: You can only have one layer of MouseMovement input blocking. See right clicking in versions view
--           and how MouseMovement events still fire for the buttons.

-- @param  modalParent  What the modal will be parented too. Used for detecting when it appears.
-- @param  frames  The frames you want to disable MouseMovement events for when a modal appears.
return function(modalParent: Frame, frames: { Frame })
	local blockedInputs = 0

	local function update()
		if blockedInputs == 0 then
			for _, child in frames do
				child.Interactable = true
			end
		else
			for _, child in frames do
				child.Interactable = false
			end
		end
	end

	modalParent.ChildAdded:Connect(function(child)
		if child:IsA("ScrollingFrame") and child.Name == "BlockInput" then
			local clickCapture = child:FindFirstChild("ClickCapture")
			if clickCapture and clickCapture:IsA("TextButton") and clickCapture.Interactable then
				blockedInputs += 1
				update()

				child.Destroying:Connect(function()
					blockedInputs -= 1
					update()
				end)
			end
		end
	end)
end
