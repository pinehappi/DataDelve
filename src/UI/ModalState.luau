--!strict

-- Keeps track if the UI has a modal or not.

type ModalStateImplementation = {
	__index: ModalStateImplementation,

	new: () -> ModalState,

	push: (ModalState) -> (),
	pop: (ModalState) -> (),
	wrap: <T>(ModalState, action: () -> T) -> T,

	pushId: (ModalState, id: string) -> (),
	popId: (ModalState, id: string) -> (),

	_update: (ModalState) -> (),
}

type ModalStateFields = {
	isInside: boolean,
	_count: number,
	_ids: { [string]: boolean },
}

export type ModalState = typeof(setmetatable({} :: ModalStateFields, {} :: ModalStateImplementation))

local ModalState: ModalStateImplementation = {} :: ModalStateImplementation
ModalState.__index = ModalState

function ModalState.new()
	return setmetatable({
		isInside = false,
		_count = 0,
		_ids = {},
	}, ModalState)
end

function ModalState:_update()
	self.isInside = (self._count > 0) or (not not next(self._ids))
end

function ModalState:push()
	self._count += 1
	self:_update()
end

function ModalState:pop()
	self._count -= 1
	self:_update()
end

function ModalState:pushId(id)
	self._ids[id] = true
	self:_update()
end

function ModalState:popId(id)
	self._ids[id] = nil
	self:_update()
end

function ModalState:wrap<T>(action)
	self:push()
	local result = action() :: any
	self:pop()
	return result
end

return ModalState
