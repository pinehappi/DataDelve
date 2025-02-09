--!strict

export type Transaction = () -> ()

export type TransactorImplementation = {
	__index: TransactorImplementation,

	new: () -> Transactor,

	destroy: (Transactor) -> (),
	transact: (Transactor, Transaction) -> boolean,
}

export type TransactorFields = {
	locked: boolean,
	lockedChanged: RBXScriptSignal,
	_lockedChanged: BindableEvent,
}

export type Transactor = typeof(setmetatable({} :: TransactorFields, {} :: TransactorImplementation))

local Transactor = {} :: TransactorImplementation
Transactor.__index = Transactor

function Transactor.new()
	local self = setmetatable({}, Transactor)

	self.locked = false
	self._lockedChanged = Instance.new("BindableEvent")
	self.lockedChanged = self._lockedChanged.Event :: RBXScriptSignal

	return self
end

function Transactor:destroy()
	self._lockedChanged:Destroy()
end

function Transactor:transact(transaction): boolean
	if self.locked then
		warn("Transaction failed. Already doing one.", debug.traceback())
		return false
	end

	self.locked = true
	self._lockedChanged:Fire(self.locked)

	transaction()

	-- Wait a bit in case of race conditions...
	task.wait(0)
	self.locked = false
	self._lockedChanged:Fire(self.locked)

	return true
end

return Transactor
