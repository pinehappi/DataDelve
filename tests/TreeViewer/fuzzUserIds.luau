--!strict

return function()
	local ids = {}
	for i = 1, math.random(0, 100) do
		table.insert(ids, math.random(1, 10_000_000))
	end
	return ids
end
