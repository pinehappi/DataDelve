--!strict

-- Makes sure a TextBox matches a validator.

return function(textBoxStyleState, validators: { (string) -> (boolean, string?) })
	textBoxStyleState.textBox:GetPropertyChangedSignal("Text"):Connect(function()
		if textBoxStyleState.textBox.Text == "" then
			textBoxStyleState:setError(nil :: string?):update("veryFast")
			return
		end

		local valid, err = true, nil
		for _, validator in validators do
			valid, err = validator(textBoxStyleState:getText())
			if not valid then
				break
			end
		end

		textBoxStyleState:setError(err):update("veryFast")
	end)
end
