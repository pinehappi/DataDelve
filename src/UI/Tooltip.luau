--!strict

local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local PopupHelper = require(script.Parent.PopupHelper)

local Tooltip = {}
Tooltip.__index = Tooltip

local FrameTemplate = script.FrameTemplate
local DropShadowTemplate = script.DropShadowTemplate
local TextLabelTemplate = script.TextLabelTemplate

local APPEAR_DELAY = 0.5
local APPEAR_DURATION = 0.06

local TOOLTIP_DISTANCE = 8
local TOOLTIP_PADDING_X = 6
local TOOLTIP_PADDING_Y = 6
local TOOLTIP_MAX_X = 200

local SHADOW_EXTRA_SIZE_X = 30
local SHADOW_EXTRA_SIZE_Y = 26
local SHADOW_OFFSET_X = -15
local SHADOW_OFFSET_Y = -9

--[[ Main Tooltip Interface ]]

-- Bind tooltip to button, placing it right below.
function Tooltip.bindButtonGeneric(theme: any, button: GuiObject, message: string)
	Tooltip.bind(theme, button, message, {
		on = button,
		offsetAnchor = Vector2.new(0.5, 1),
		tooltipAnchor = Vector2.new(0.5, 0),
	})
end

-- Ignores rotation
local function isHovering(object: GuiObject, position: Vector2): boolean
	return (object.AbsolutePosition.X <= position.X)
		and (object.AbsolutePosition.X + object.AbsoluteSize.X >= position.X)
		and (object.AbsolutePosition.Y <= position.Y)
		and (object.AbsolutePosition.Y + object.AbsoluteSize.Y >= position.Y)
end

-- Bind tooltip to button with extra options
function Tooltip.bind(theme: any, interactObject: GuiObject, message: string, showOptions: ShowOptions)
	local tooltip = Tooltip.new(theme, message)
	local hover = nil

	-- If the interactObject moves (like when scrolling), mouse events won't fire, so have to track if the mouse is
	-- still on the object manually
	local positionConnection: RBXScriptConnection?

	interactObject.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			local myHover = newproxy()
			hover = myHover
			task.wait(APPEAR_DELAY)

			if (not tooltip.object) and (hover == myHover) then
				if positionConnection then
					positionConnection:Disconnect()
				end

				positionConnection = interactObject:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
					if not isHovering(interactObject, input.Position :: any) then
						hover = nil
						tooltip:clear()

						if positionConnection then
							positionConnection:Disconnect()
							positionConnection = nil
						end
					end
				end)

				tooltip:show(showOptions)
			end
		elseif
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			hover = nil
			tooltip:clear()

			if positionConnection then
				positionConnection:Disconnect()
				positionConnection = nil
			end
		end
	end)

	interactObject.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			hover = nil
			tooltip:clear()

			if positionConnection then
				positionConnection:Disconnect()
				positionConnection = nil
			end
		end
	end)
end

--[[ Internal Tooltip Stuff ]]

function Tooltip.new(theme: any, message: string)
	local self = setmetatable({
		theme = theme,
		message = message,

		object = nil :: (Frame | CanvasGroup)?,
	}, Tooltip)

	return self
end

export type ShowOptions = {
	on: GuiObject,
	offsetAnchor: Vector2,
	tooltipAnchor: Vector2,

	offsetOnX: boolean?,
}
function Tooltip:show(options: ShowOptions)
	if self.object then
		self:clear()
	end

	local params = Instance.new("GetTextBoundsParams")
	params.Text = self.message
	params.Font = TextLabelTemplate.FontFace
	params.Size = TextLabelTemplate.TextSize
	params.Width = TOOLTIP_MAX_X
	params.RichText = true

	local textBounds = TextService:GetTextBoundsAsync(params)
	local frameBounds = textBounds + Vector2.new(2 * TOOLTIP_PADDING_X, 2 * TOOLTIP_PADDING_Y)
	local objectBounds = frameBounds + Vector2.new(SHADOW_EXTRA_SIZE_X, SHADOW_EXTRA_SIZE_Y)

	local object: any = Instance.new("CanvasGroup")
	object.BackgroundTransparency = 1
	object.Size = UDim2.fromOffset(objectBounds.X, objectBounds.Y)
	object.GroupTransparency = 1
	object.ZIndex = 50

	local shadow = DropShadowTemplate:Clone()
	shadow.Size = UDim2.fromOffset(objectBounds.X, objectBounds.Y)
	shadow.Parent = object

	local frame = FrameTemplate:Clone()
	frame.BackgroundColor3 = self.theme.colors.message.background
	frame.UIStroke.Color = self.theme.colors.message.outline
	frame.Position = UDim2.fromOffset(-SHADOW_OFFSET_X, -SHADOW_OFFSET_Y)
	frame.Size = UDim2.fromOffset(frameBounds.X, frameBounds.Y)
	frame.Parent = object

	local textLabel = TextLabelTemplate:Clone()
	textLabel.TextColor3 = self.theme.colors.message.text
	textLabel.Position = UDim2.fromOffset(TOOLTIP_PADDING_X, TOOLTIP_PADDING_Y)
	textLabel.Size = UDim2.fromOffset(textBounds.X + 1, textBounds.Y + 1)
	textLabel.Text = self.message
	textLabel.Parent = frame

	local container = options.on:FindFirstAncestorWhichIsA("LayerCollector") :: LayerCollector
	local function updatePosition(alpha: number)
		local offsetX = 0
		local offsetY = 0
		if options.offsetOnX then
			offsetX = TOOLTIP_DISTANCE * options.offsetAnchor.X
		else
			offsetY = TOOLTIP_DISTANCE * options.offsetAnchor.Y
		end

		object.Position = UDim2.fromOffset(
			options.on.AbsolutePosition.X
				+ SHADOW_OFFSET_X
				+ options.offsetAnchor.X * options.on.AbsoluteSize.X
				+ alpha * offsetX
				- options.tooltipAnchor.X * frameBounds.X,
			options.on.AbsolutePosition.Y
				+ SHADOW_OFFSET_Y
				+ options.offsetAnchor.Y * options.on.AbsoluteSize.Y
				+ alpha * offsetY
				- options.tooltipAnchor.Y * frameBounds.Y
		)

		PopupHelper.clamp(object, container, {
			boundaryDistance = 5 + SHADOW_OFFSET_X,
		})
	end

	updatePosition(0)

	object.Parent = container
	self.object = object

	task.spawn(function()
		local start = os.clock()
		while object.Parent and self.object == object do
			local delta = math.min(os.clock() - start, APPEAR_DURATION)
			local a = TweenService:GetValue(delta / APPEAR_DURATION, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out)

			updatePosition(a)
			object.GroupTransparency = 1 - a

			if delta >= APPEAR_DURATION then
				break
			end
			task.wait()
		end

		if object.Parent and self.object == object then
			local newObject = Instance.new("Frame")
			newObject.Size = object.Size
			newObject.BackgroundTransparency = 1
			newObject.ZIndex = 50

			shadow.Parent = newObject
			frame.Parent = newObject

			object:Destroy()
			object = newObject
			object.Parent = container
			self.object = object
			updatePosition(1)
		end
	end)
end

function Tooltip:clear()
	if self.object then
		self.object:Destroy()
		self.object = nil :: any
	end
end

return Tooltip
