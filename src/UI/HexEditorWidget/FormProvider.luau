--!strict

local HexEditor = require(script.Parent.HexEditor)

local Validators = require(script.Parent.Parent.Parent.Validators)
local constrainTextBoxStyleState = require(script.Parent.Parent.Utilities.constrainTextBoxStyleState)

local StyleState = script.Parent.Parent.StyleState
local LabelStyleState = require(StyleState.LabelStyleState)
local TextBoxStyleState = require(StyleState.Input.TextBoxStyleState)
local ContextMenuStyleState = require(StyleState.Utility.ContextMenuStyleState)
local PopupFormStyleState = require(StyleState.Utility.PopupFormStyleState)

local FormProvider = {}

function FormProvider.generate(
	theme: any,
	hexEditorTheme: HexEditor.ThemeData,
	inputReceiver: GuiObject | UserInputService,
	container: GuiObject
): HexEditor.HexEditorFormProvider
	local betterContextMenuOptions: { [any]: ContextMenuStyleState.Options } = {
		[HexEditor.SINGLE_BYTE_CONTEXT_MENU_OPTIONS] = {
			{ icon = theme.icons.insert, text = "Insert Null Bytes" },
			{ icon = theme.icons.delete, text = "Delete Byte" },
			ContextMenuStyleState.SEPARATOR,
			{ icon = theme.icons.select, text = "Select All" },
		},
		[HexEditor.ADD_CELL_CONTEXT_MENU_OPTIONS] = {
			{ icon = theme.icons.insert, text = "Insert Null Bytes" },
			ContextMenuStyleState.SEPARATOR,
			{ icon = theme.icons.select, text = "Select All" },
		},
		[HexEditor.SELECTION_CONTEXT_MENU_OPTIONS] = {
			{ icon = theme.icons.fill, text = "Fill Selection" },
			{ icon = theme.icons.delete, text = "Delete Selection" },
			ContextMenuStyleState.SEPARATOR,
			{ icon = theme.icons.insert, text = "Insert Null Bytes" },
			{ icon = theme.icons.select, text = "Select All" },
		},
	}
	return {
		promptContextMenu = function(input, options)
			return ContextMenuStyleState.prompt(theme, container, (input.Position :: any) :: Vector2, {
				options = betterContextMenuOptions[options] or options,
			})
		end,
		promptFillWith = function(input)
			local editor: HexEditor.HexEditor
			local popup: any, modal =
				PopupFormStyleState.createPopup(theme, container, (input.Position :: any) :: Vector2, {
					title = "Fill With",
					buttons = {
						{ text = "Fill", options = { style = "primary" } },
						{ text = "Cancel", options = { style = "secondary" } },
					},
					addContents = function(frame)
						local label = script.PatternLabel:Clone()
						label.Parent = frame

						local editorContainer = Instance.new("Frame")
						editorContainer.BorderColor3 = Color3.new(0, 0, 0)
						editorContainer.BackgroundColor3 = theme.colors.background
						editorContainer.Size = UDim2.fromOffset(200, 44)

						editor = HexEditor.new(buffer.create(1), {
							container = editorContainer,
							sizing = "fillContainerY",
							theme = hexEditorTheme,
							layout = {
								columns = 8,
								showGutter = false,
								showHeader = false,
								showDecodedText = false,
							},
						}, {
							inputReceiver = inputReceiver,
						})

						editorContainer.Parent = frame

						return { LabelStyleState.from(theme, label) }
					end,
				})

			popup.frame.Size = UDim2.fromOffset(0, 0)

			local clicked = popup.interacted:Wait()

			modal:destroy()
			popup:destroy(true)

			if clicked == "Fill" then
				return editor:getBuffer()
			else
				return nil
			end
		end,
		promptInsertNullBytes = function(input)
			local textBoxStyleState: TextBoxStyleState.TextBoxStyleState
			local popup: any, modal =
				PopupFormStyleState.createPopup(theme, container, (input.Position :: any) :: Vector2, {
					title = "Insert Null Bytes",
					buttons = {
						{ text = "Insert", options = { style = "primary" } },
						{ text = "Cancel", options = { style = "secondary" } },
					},
					addContents = function(frame)
						local insertAmountRow = script.InsertAmountRow:Clone()
						local labelStyleState = LabelStyleState.from(theme, insertAmountRow.Title)
						textBoxStyleState = TextBoxStyleState.from(theme, insertAmountRow.TextBox)
						constrainTextBoxStyleState(textBoxStyleState, { Validators.positiveNonZeroInteger })

						insertAmountRow.Parent = frame

						return { labelStyleState, textBoxStyleState }
					end,
				})

			popup.frame.Size = UDim2.fromOffset(150, 0)

			textBoxStyleState.errorChanged:Connect(function()
				popup.wrapper.styleStates.buttons.Insert:setDisabled(not not textBoxStyleState.error):update()
			end)

			textBoxStyleState.textBox.FocusLost:Connect(function(entered, input)
				if entered and input then
					popup:interact("Insert")
				end
			end)

			local clicked = popup.interacted:Wait()

			modal:destroy()
			popup:destroy(true)

			if clicked == "Insert" then
				return tonumber(textBoxStyleState:getText())
			else
				return nil
			end
		end,
	}
end

return FormProvider
