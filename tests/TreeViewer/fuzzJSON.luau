--!strict

-- Actions to generate random JSON+buffer-acceptable value
type Action = (depth: number) -> any

local MAX_DEPTH = 10

local actions: { Action }

local stringAction: Action = function()
	local s = table.create(12)
	while true do
		local got = math.random()
		if got < 0.3 then
			break
		else
			table.insert(s, string.char(math.random(0x21, 0x7E)))
		end
	end
	return table.concat(s)
end

actions = {
	stringAction,
	-- buffer
	function()
		local b = buffer.create(math.random(0, 10))
		for i = 1, buffer.len(b) do
			buffer.writeu8(b, i - 1, math.random(0, 2 ^ 8 - 1))
		end
		return b
	end,
	-- boolean
	function()
		return math.random() >= 0.5
	end,
	-- number
	function()
		return math.random()
	end,
	-- array
	function(depth)
		if depth > 2 * MAX_DEPTH then
			return 1
		elseif depth > MAX_DEPTH then
			return actions[math.random(1, #actions)](depth + 1)
		end

		local len = math.random(0, 5)
		local array = table.create(len)

		for i = 1, len do
			array[i] = actions[math.random(1, #actions)](depth + 1)
		end

		return array
	end,
	-- object
	function(depth)
		if depth > 2 * MAX_DEPTH then
			return 1
		elseif depth > MAX_DEPTH then
			return actions[math.random(1, #actions)](depth + 1)
		end

		local len = math.random(0, 5)
		local object = {}

		for i = 1, math.random(0, 10) do
			object[stringAction(depth)] = actions[math.random(1, #actions)](depth + 1)
		end

		return object
	end,
}

return function(maxDepth: number?)
	return actions[math.random(1, #actions)](MAX_DEPTH - (maxDepth or MAX_DEPTH))
end
