--!strict

-- Makes it so when you press tab, it switches between the TextBoxes.

local function checkTrulyVisible(object: GuiObject): boolean
	local current: any = object
	while current do
		if (not current) or not current.Visible then
			return false
		end

		current = current.Parent
		if current:IsA("LayerCollector") then
			break
		elseif not current:IsA("GuiObject") then
			return false
		end
	end
	return true
end

return function(textBoxes: { TextBox })
	local currentSelected = nil
	local currentConnection: RBXScriptConnection? = nil

	for i, textBox in textBoxes do
		-- Don't need to track when it's unfocused since they can't tab at that point anyways
		textBox.Focused:Connect(function()
			currentSelected = i

			if currentConnection then
				currentConnection:Disconnect()
			end

			local lastText = textBox.Text
			-- NOTE:
			--   Will create a neglible memory leak that won't accumulate.
			--   I would say it's an acceptable trade-off for code simplicity.
			currentConnection = textBox:GetPropertyChangedSignal("Text"):Connect(function()
				-- NOTE:
				--   does not completely handle the case where a user pastes something that ends in a tab
				--   and replaces the exact amount of text such that (#lastText + 1 == #textBox.Text) is true
				if
					(textBox.Text:sub(textBox.CursorPosition - 1, textBox.CursorPosition - 1) == "\t")
					and (#lastText + 1 == #textBox.Text)
				then
					local canSwitch = false
					for i = 1, #textBoxes - 1 do
						currentSelected = (currentSelected % #textBoxes) + 1
						if checkTrulyVisible(textBoxes[currentSelected]) then
							canSwitch = true
							break
						end
					end

					if not canSwitch then
						return
					end

					-- Switch!

					textBox.Text = lastText
					lastText = textBox.Text
					textBoxes[currentSelected]:CaptureFocus()
				else
					lastText = textBox.Text
				end
			end)
		end)
	end
end
