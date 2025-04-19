--!strict
return function(object: GuiObject): boolean
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
