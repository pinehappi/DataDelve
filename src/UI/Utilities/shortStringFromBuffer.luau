--!strict
local MAX_BUFFER_READ_SIZE = 16
return function(buf: buffer)
	return `<buffer {buffer.len(buf)}>`
end
