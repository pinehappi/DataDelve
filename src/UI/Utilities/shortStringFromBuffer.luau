--!strict
local MAX_BUFFER_READ_SIZE = 16
return function(buf: buffer)
	local str: string
	if buffer.len(buf) <= MAX_BUFFER_READ_SIZE then
		str = buffer.tostring(buf)
	else
		str = buffer.readstring(buf, 0, MAX_BUFFER_READ_SIZE) .. "..."
	end
	return `<buffer {buffer.len(buf)}:{str}>`
end
