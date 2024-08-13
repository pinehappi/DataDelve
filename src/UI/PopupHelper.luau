-- Helps with popup stuff
--	`clamp` clamps an object so it doesn't go out of bounds of a container
--	`attach` attach an object to another object so it moves with that object
--	`modal` turns an object into a modal so it blocks input from other objects
-- `attach` and `modal` return objects that should be destroyed once they are done with (using `:destroy()`).

local globalTheme = require(script.Parent.Theme).global
local PopupHelper = {}

--// Clamp

export type ClampOptions = {
	tryPivot: boolean?, -- Pivot will try to pivot the object about its top-left anchor first before clamping.
	boundaryDistance: number?,
}
-- Clamps a GuiObject to container
function PopupHelper.clamp(object: GuiObject, container: GuiBase2d, options: ClampOptions?)
	options = options or {}
	options.boundaryDistance = options.boundaryDistance or 10

	if options.tryPivot then
		if object.AbsolutePosition.X + object.AbsoluteSize.X > container.AbsoluteSize.X then
			if object.AbsolutePosition.X - object.AbsoluteSize.X > 0 then
				object.Position -= UDim2.fromOffset(object.AbsoluteSize.X, 0)
			end
		end
		if object.AbsolutePosition.Y + object.AbsoluteSize.Y > container.AbsoluteSize.Y then
			if object.AbsolutePosition.Y - object.AbsoluteSize.Y > 0 then
				object.Position -= UDim2.fromOffset(0, object.AbsoluteSize.Y)
			end
		end
	end

	local maxX = container.AbsoluteSize.X - 2 * options.boundaryDistance
	if
		(object.AbsoluteSize.X >= maxX)
		and (object.AutomaticSize == Enum.AutomaticSize.X or object.AutomaticSize == Enum.AutomaticSize.XY)
	then
		if object.AutomaticSize == Enum.AutomaticSize.X then
			object.AutomaticSize = Enum.AutomaticSize.None
		else
			object.AutomaticSize = Enum.AutomaticSize.Y
		end
		object.Size = UDim2.new(0, maxX, object.Size.Y.Scale, object.Size.Y.Offset)
	end

	local leftDistance = (object.AbsolutePosition.X - container.AbsolutePosition.X)
	local rightDistance = container.AbsoluteSize.X - (object.AbsolutePosition.X + object.AbsoluteSize.X)

	local topDistance = (object.AbsolutePosition.Y - container.AbsolutePosition.Y)
	local bottomDistance = container.AbsoluteSize.Y - (object.AbsolutePosition.Y + object.AbsoluteSize.Y)

	object.Position += UDim2.fromOffset(
		math.max(0, options.boundaryDistance - leftDistance) - math.max(0, options.boundaryDistance - rightDistance),
		math.max(0, options.boundaryDistance - topDistance) - math.max(0, options.boundaryDistance - bottomDistance)
	)
end

--// Bind

local Attachment = {}
Attachment.__index = Attachment

function Attachment:updatePosition()
	if self.options.onChange then
		if self.options.onChange(self.options, self.object, self.target) == "manual" then
			return
		end
	end

	local position = self.target.AbsolutePosition
		+ self.target.AbsoluteSize * self.options.anchor
		+ 2 * (self.options.anchor - Vector2.new(0.5, 0.5)) * self.options.offset

	self.object.Position = UDim2.fromOffset(position.X, position.Y)
end

function Attachment:destroy(completely: boolean)
	for _, connection in self._connections do
		connection:Disconnect()
	end
	if completely then
		self.object:Destroy()
	end
	self.object = nil
	self.target = nil
end

--
export type AttachOptions = {
	anchor: Vector2, -- Position relative to what it is being attached to
	offset: Vector2,

	-- Callback called every time the attachment has to change positions
	-- Can be used to dynamically change the attachment (as with SelectStyleState)
	-- If it returns "manual", then the the attachment will not change the position of the object
	onChange: ((AttachOptions, object: GuiObject, target: GuiObject) -> "manual"?)?,
}

-- Makes an object always move with a target object at a certain offset
-- Assumes that UDim2.fromOffset(0, 0) will place the object at the top-left corner of the gui
-- Options are required
function PopupHelper.attach(object: GuiObject, target: GuiObject, options: AttachOptions)
	local attachment = setmetatable({
		object = object,
		target = target,

		options = options,
		_connections = {},
	}, Attachment)

	attachment:updatePosition()

	table.insert(
		attachment._connections,
		target:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
			attachment:updatePosition()
		end)
	)
	table.insert(
		attachment._connections,
		target:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			attachment:updatePosition()
		end)
	)

	return attachment
end

--// Modal

local Modal = {}
Modal.__index = Modal

function Modal:destroy()
	self.blockInputFrame:Destroy()
	self._cancelled:Destroy()
end

export type ModalOptions = {
	zIndex: number?,
	scrimTransparency: number?,
	reparent: boolean?,
}
-- Turns an object into a modal and blocks all inputs in container
function PopupHelper.modal(object: GuiObject, container: GuiBase2d, options: ModalOptions?)
	options = options or {}
	options.zIndex = options.zIndex or 10
	options.scrimTransparency = options.scrimTransparency or globalTheme.colors.defaultScrimTransparency
	options.reparent = if options.reparent == nil then true else options.reparent

	local modal = setmetatable({
		object = object,
		blockInputFrame = script.BlockInput:Clone(),
		_cancelled = Instance.new("BindableEvent"),
	}, Modal)

	modal.blockInputFrame.BackgroundTransparency = options.scrimTransparency
	modal.blockInputFrame.ZIndex = options.zIndex
	modal.blockInputFrame.Parent = container

	modal.cancelled = modal._cancelled.Event

	if options.reparent then
		object.Parent = container
	end
	object.ZIndex = options.zIndex + 1

	modal.blockInputFrame.ClickCapture.Activated:Connect(function()
		modal._cancelled:Fire()
	end)
	modal.blockInputFrame.ClickCapture.MouseButton2Click:Connect(function()
		modal._cancelled:Fire()
	end)

	return modal
end

return PopupHelper
