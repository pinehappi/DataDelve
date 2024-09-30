-- When a ScrollingFrame named Block Input with a TextButton child named ClickCapture is added to the frame,
-- set Interactable false for all the frames.

-- Brittle, but prevents inputs like MouseMovement from passing through the modal.

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
