--!strict

local TweenService = game:GetService("TweenService")

local Assets = script.Parent.Parent.Assets
local StyleState = script.Parent.Parent.StyleState

local Theme = require(script.Parent.Parent.Theme)
local PopupHelper = require(script.Parent.Parent.PopupHelper)
local ViewerTypes = require(script.Parent.Parent.Viewers.Types)

local StyleStateHelper = require(StyleState.StyleStateHelper)
local BackgroundStyleState = require(StyleState.BackgroundStyleState)
local LabelStyleState = require(StyleState.LabelStyleState)
local ButtonStyleState = require(StyleState.ButtonStyleState)
local TextBoxStyleState = require(StyleState.Input.TextBoxStyleState)

local function getStyleStates(theme: Theme.Theme, frame: typeof(Assets.Views.Search))
	return {
		background = BackgroundStyleState.from(theme, frame, { style = "popup" }),
		next = ButtonStyleState.from(theme, frame.Next, { style = "dormant" }),
		prev = ButtonStyleState.from(theme, frame.Previous, { style = "dormant" }),
		close = ButtonStyleState.from(theme, frame.Close, { style = "dormant" }),
		textBox = TextBoxStyleState.from(theme, frame.TextBox),
		matches = LabelStyleState.from(theme, frame.Matches),
	}
end

export type SearchViewOptions = {
	theme: Theme.Theme,
	parent: Instance,
	position: UDim2,
	anchorPoint: Vector2,

	nextClicked: () -> (),
	prevClicked: () -> (),
	closeClicked: () -> (),
	searchChanged: (searchTerm: string) -> (),
}

type SearchViewImplementation = {
	__index: SearchViewImplementation,

	new: (SearchViewOptions) -> SearchView,
	update: (SearchView, StyleStateHelper.TransitionSpeed) -> (),
	captureFocus: (SearchView) -> (),

	animateIn: (SearchView) -> (),
	animateOut: (SearchView) -> (),

	setResult: (SearchView, result: ViewerTypes.SearchResult) -> (),
	destroy: (SearchView) -> (),
}

type SearchViewFields = {
	_theme: Theme.Theme,
	_styleStates: typeof(getStyleStates({} :: any)),
	_frame: typeof(Assets.Views.Search),
	_dropShadow: ImageLabel,

	_dead: boolean,
	_isAnimating: boolean,
}

export type SearchView = typeof(setmetatable({} :: SearchViewFields, {} :: SearchViewImplementation))

local SearchView: SearchViewImplementation = {} :: SearchViewImplementation
SearchView.__index = SearchView

function SearchView.new(options)
	local self = setmetatable({}, SearchView)

	self._theme = options.theme

	self._frame = Assets.Views.Search:Clone()
	self._styleStates = getStyleStates(self._theme, self._frame)

	self._styleStates.next.button.Activated:Connect(options.nextClicked)
	self._styleStates.prev.button.Activated:Connect(options.prevClicked)
	self._styleStates.close.button.Activated:Connect(options.closeClicked)
	self._styleStates.textBox.textBox.FocusLost:Connect(function(_, input)
		if input and input.KeyCode == Enum.KeyCode.Escape then
			options.closeClicked()
		end
	end)
	self._styleStates.textBox.textBox:GetPropertyChangedSignal("Text"):Connect(function()
		options.searchChanged(self._styleStates.textBox.textBox.Text)
	end)

	self._frame.Position = options.position
	self._frame.AnchorPoint = options.anchorPoint
	self._frame.ZIndex = 10
	self._frame.Parent = options.parent

	self._dropShadow = PopupHelper.attachDropShadow(self._frame)

	self._dead = false
	self._isAnimating = false

	self:setResult({ kind = "none" })

	return self
end

function SearchView:update(speed)
	StyleStateHelper.update(self._styleStates, speed :: StyleStateHelper.TransitionSpeed)
end

local animateTweenInfo = TweenInfo.new(0.1, Enum.EasingStyle.Quad)
function SearchView:animateIn()
	if self._isAnimating then
		return
	end

	local canvasGroup = Instance.new("CanvasGroup")
	canvasGroup.Size = UDim2.fromScale(1, 1)
	canvasGroup.Position = UDim2.fromOffset(0, 16)
	canvasGroup.BackgroundTransparency = 1
	canvasGroup.GroupTransparency = 1

	canvasGroup.Parent = self._frame.Parent
	self._frame.Parent = canvasGroup
	self._dropShadow.Parent = canvasGroup

	local originalTransparency = self._dropShadow.ImageTransparency
	self._dropShadow.ImageTransparency = 1
	TweenService:Create(self._dropShadow, animateTweenInfo, {
		ImageTransparency = originalTransparency,
	}):Play()

	local tween = TweenService:Create(canvasGroup, animateTweenInfo, {
		GroupTransparency = 0,
		Position = UDim2.fromOffset(0, 0),
	})
	tween:Play()
	tween.Completed:Wait()

	if self._dead then
		canvasGroup:Destroy()
		return
	end

	self._frame.Parent = canvasGroup.Parent
	self._dropShadow.Parent = canvasGroup.Parent
	canvasGroup:Destroy()

	self._isAnimating = false
end

function SearchView:animateOut()
	if self._isAnimating then
		return
	end

	local canvasGroup = Instance.new("CanvasGroup")
	canvasGroup.Size = UDim2.fromScale(1, 1)
	canvasGroup.Position = UDim2.fromOffset(0, 16)
	canvasGroup.BackgroundTransparency = 1
	canvasGroup.GroupTransparency = 0

	canvasGroup.Parent = self._frame.Parent
	self._frame.Parent = canvasGroup
	self._dropShadow.Parent = canvasGroup

	TweenService:Create(self._dropShadow, animateTweenInfo, {
		ImageTransparency = 1,
	}):Play()

	local tween = TweenService:Create(canvasGroup, animateTweenInfo, {
		GroupTransparency = 1,
		Position = UDim2.fromOffset(0, 8),
	})
	tween:Play()
	tween.Completed:Wait()

	if self._dead then
		canvasGroup:Destroy()
		return
	end

	self._frame.Parent = canvasGroup.Parent
	self._dropShadow.Parent = canvasGroup.Parent
	canvasGroup:Destroy()

	self._isAnimating = false
end

function SearchView:captureFocus()
	self._styleStates.textBox.textBox:CaptureFocus()
end

function SearchView:setResult(result)
	if result.kind == "none" then
		self._styleStates.matches.Visible = false
		self._styleStates.matches.label.Text = ""
	else
		local suffix = if result.matches == 1 then "match" else "matches"
		self._styleStates.matches.Visible = true
		self._styleStates.matches.label.Text = `{result.matches} {suffix}`
	end
end

function SearchView:destroy()
	self._dead = true
	self._frame:Destroy()
	self._dropShadow:Destroy()
end

return SearchView
