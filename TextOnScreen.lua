-- TextOnScreen.lua

local ADDON_NAME = ...

local ENTRY_DEFAULTS = {
	name = "",
	text = "",
	fontSize = 24,
	color = { r = 1, g = 1, b = 1, a = 1 },
	showWhenClosed = true,
	position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 },
}

local DEFAULTS = {
	nextId = 1,
	selectedId = nil,
	entries = {},
}

local function CopyDefaultsInto(db, defaults)
	if type(db) ~= "table" then
		db = {}
	end
	for key, value in pairs(defaults) do
		if type(value) == "table" then
			if type(db[key]) ~= "table" then
				db[key] = {}
			end
			CopyDefaultsInto(db[key], value)
		elseif db[key] == nil then
			db[key] = value
		end
	end
	return db
end

local function Clamp(numberValue, minValue, maxValue)
	if numberValue < minValue then
		return minValue
	end
	if numberValue > maxValue then
		return maxValue
	end
	return numberValue
end

local Addon = {}
Addon.configFrame = nil
Addon.entryFrames = {}
Addon.ui = {}

local function GetFontPath()
	local fontPath = GameFontNormal and GameFontNormal.GetFont and select(1, GameFontNormal:GetFont())
	if not fontPath or fontPath == "" then
		fontPath = "Fonts\\FRIZQT__.TTF"
	end
	return fontPath
end

function Addon:ApplySettings(isConfigOpen)
	if not TextOnScreenDB then
		return
	end

	local fontPath = GetFontPath()
	local entries = TextOnScreenDB.entries or {}
	for _, entry in ipairs(entries) do
		local entryId = entry.id
		if entryId then
			local frame = self.entryFrames[entryId]
			if not frame then
				frame = self:CreateOnScreenText(entryId)
			end

			local fs = frame.textString
			local fontSize = Clamp(tonumber(entry.fontSize) or ENTRY_DEFAULTS.fontSize, 8, 128)
			fs:SetFont(fontPath, fontSize, "OUTLINE")
			fs:SetText(entry.text or "")
			local c = entry.color or ENTRY_DEFAULTS.color
			fs:SetTextColor(c.r or 1, c.g or 1, c.b or 1, c.a or 1)

			local pos = entry.position or ENTRY_DEFAULTS.position
			frame:ClearAllPoints()
			frame:SetPoint(pos.point or "CENTER", UIParent, pos.relativePoint or "CENTER", pos.x or 0, pos.y or 0)

			local shouldShow
			if isConfigOpen then
				shouldShow = true
			else
				shouldShow = not not entry.showWhenClosed
				if (entry.text or "") == "" then
					shouldShow = false
				end
			end

			if shouldShow then
				local w = fs:GetStringWidth() or 0
				local h = fs:GetStringHeight() or 0
				if isConfigOpen then
					frame:SetSize(math.max(w + 20, 80), math.max(h + 20, 20))
				else
					frame:SetSize(math.max(w + 20, 1), math.max(h + 20, 1))
				end
				frame:Show()
			else
				frame:Hide()
			end
		end
	end
end

local function GetEntryById(entryId)
	if not TextOnScreenDB or not TextOnScreenDB.entries then
		return nil, nil
	end
	for index, entry in ipairs(TextOnScreenDB.entries) do
		if entry.id == entryId then
			return entry, index
		end
	end
	return nil, nil
end

function Addon:SavePositionFromFrame(entryId)
	if not (entryId and TextOnScreenDB) then
		return
	end
	local frame = self.entryFrames[entryId]
	if not frame then
		return
	end
	local entry = GetEntryById(entryId)
	if not entry then
		return
	end
	local point, _, relativePoint, xOfs, yOfs = frame:GetPoint(1)
	entry.position = entry.position or {}
	entry.position.point = point
	entry.position.relativePoint = relativePoint
	entry.position.x = xOfs
	entry.position.y = yOfs
	self:RefreshPositionDisplay()
end


function Addon:SelectEntry(entryId)
	if not TextOnScreenDB then
		return
	end
	TextOnScreenDB.selectedId = entryId
	self:RefreshEntryList()
	self:RefreshEditor()
end

function Addon:CreateOnScreenText(entryId)
	if self.entryFrames[entryId] then
		return self.entryFrames[entryId]
	end

	local frame = CreateFrame("Frame", nil, UIParent)
	frame.entryId = entryId
	frame:SetSize(1, 1)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")

	frame:SetScript("OnMouseDown", function(_, button)
		if button == "LeftButton" then
			Addon:SelectEntry(entryId)
		end
	end)

	frame:SetScript("OnDragStart", function(f)
		if InCombatLockdown and InCombatLockdown() then
			return
		end
		Addon:SelectEntry(entryId)
		f._tosDragElapsed = 0
		f:SetScript("OnUpdate", function(ff, elapsed)
			ff._tosDragElapsed = (ff._tosDragElapsed or 0) + (elapsed or 0)
			if ff._tosDragElapsed >= 0.05 then
				ff._tosDragElapsed = 0
				Addon:RefreshPositionDisplayFromFrame(ff.entryId)
			end
		end)
		f:StartMoving()
	end)

	frame:SetScript("OnDragStop", function(f)
		f:SetScript("OnUpdate", nil)
		f:StopMovingOrSizing()
		Addon:SavePositionFromFrame(f.entryId)
	end)

	local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	fs:SetPoint("CENTER")
	fs:SetJustifyH("CENTER")
	fs:SetJustifyV("MIDDLE")
	frame.textString = fs

	self.entryFrames[entryId] = frame
	return frame
end

local function EnsureAtLeastOneEntry()
	TextOnScreenDB.entries = TextOnScreenDB.entries or {}
	if #TextOnScreenDB.entries == 0 then
		local id = TextOnScreenDB.nextId or 1
		TextOnScreenDB.nextId = id + 1
		table.insert(TextOnScreenDB.entries, CopyDefaultsInto({ id = id, name = "Text " .. tostring(id), text = "New Text" }, ENTRY_DEFAULTS))
		TextOnScreenDB.selectedId = id
	end
end

local function MigrateSingleEntryDB()
	if not TextOnScreenDB or TextOnScreenDB.entries then
		return
	end
	if TextOnScreenDB.text == nil and TextOnScreenDB.fontSize == nil and TextOnScreenDB.color == nil then
		return
	end
	local id = 1
	TextOnScreenDB.entries = {
		CopyDefaultsInto({
			id = id,
			text = TextOnScreenDB.text,
			fontSize = TextOnScreenDB.fontSize,
			color = TextOnScreenDB.color,
			showWhenClosed = TextOnScreenDB.showWhenClosed,
			position = TextOnScreenDB.position,
		}, ENTRY_DEFAULTS),
	}
	TextOnScreenDB.nextId = 2
	TextOnScreenDB.selectedId = id
	TextOnScreenDB.text = nil
	TextOnScreenDB.fontSize = nil
	TextOnScreenDB.color = nil
	TextOnScreenDB.showWhenClosed = nil
	TextOnScreenDB.position = nil
end

local function CreateLabel(parent, text, x, y)
	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	label:SetText(text)
	return label
end

local function CreateButton(parent, text, width, height)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetText(text)
	button:SetSize(width, height)
	return button
end

function Addon:OpenColorPicker(entryId)
	if not TextOnScreenDB or not entryId then
		return
	end
	local entry = GetEntryById(entryId)
	if not entry then
		return
	end
	local c = entry.color or ENTRY_DEFAULTS.color
	local colorPicker = _G["ColorPickerFrame"]
	if not colorPicker then
		return
	end

	local prev = { r = c.r or 1, g = c.g or 1, b = c.b or 1, a = c.a or 1 }

	local function ApplyColor(r, g, b, a)
		a = a or 1
		entry.color = entry.color or {}
		entry.color.r = r
		entry.color.g = g
		entry.color.b = b
		entry.color.a = a
		Addon:ApplySettings(true)
		Addon:RefreshEditor()
	end

	local function InterpretAlpha(value)
		local prevA = prev.a or 1
		if value == nil then
			return prevA
		end
		if type(value) ~= "number" then
			return prevA
		end
		if value < 0 or value > 1 then
			return prevA
		end
		local cand1 = value
		local cand2 = 1 - value
		if math.abs(cand1 - prevA) <= math.abs(cand2 - prevA) then
			return cand1
		end
		return cand2
	end

	local function OnColorChanged()
		local r, g, b = colorPicker:GetColorRGB()
		local rawAlphaOrOpacity
		if colorPicker.GetColorAlpha then
			rawAlphaOrOpacity = colorPicker:GetColorAlpha()
		else
			rawAlphaOrOpacity = 1 - (colorPicker.opacity or 0)
		end
		local a = InterpretAlpha(rawAlphaOrOpacity)
		ApplyColor(r, g, b, a)
	end

	local function OnCancel()
		ApplyColor(prev.r, prev.g, prev.b, prev.a)
	end

	if colorPicker.SetupColorPickerAndShow then
		local info = {
			r = prev.r,
			g = prev.g,
			b = prev.b,
			opacity = 1 - prev.a,
			hasOpacity = true,
			swatchFunc = OnColorChanged,
			opacityFunc = OnColorChanged,
			cancelFunc = OnCancel,
		}
		colorPicker:SetupColorPickerAndShow(info)
		return
	end

	colorPicker.hasOpacity = true
	colorPicker.opacity = 1 - prev.a
	colorPicker.previousValues = prev
	colorPicker.func = OnColorChanged
	colorPicker.opacityFunc = OnColorChanged
	colorPicker.cancelFunc = OnCancel
	if colorPicker.SetColorRGB then
		colorPicker:SetColorRGB(prev.r, prev.g, prev.b)
	end
	colorPicker:Show()
end

local function GetEntryDisplayText(entry)
	if not entry then
		return "(missing)"
	end
	local name = (entry.name or ""):gsub("\n", " ")
	if name ~= "" then
		return name
	end
	local t = (entry.text or ""):gsub("\n", " ")
	if t == "" then
		return "(empty)"
	end
	if #t > 18 then
		return t:sub(1, 18) .. "..."
	end
	return t
end

function Addon:RefreshEntryList()
	if not (self.ui and self.ui.listButtons and self.ui.scrollFrame and TextOnScreenDB and TextOnScreenDB.entries) then
		return
	end

	local entries = TextOnScreenDB.entries
	local offset = FauxScrollFrame_GetOffset(self.ui.scrollFrame)
	local buttons = self.ui.listButtons
	local selectedId = TextOnScreenDB.selectedId

	for i = 1, #buttons do
		local entryIndex = i + offset
		local button = buttons[i]
		local entry = entries[entryIndex]
		if entry then
			button.entryId = entry.id
			button:SetText(GetEntryDisplayText(entry))
			button:Show()
			if entry.id == selectedId then
				button:LockHighlight()
			else
				button:UnlockHighlight()
			end
		else
			button.entryId = nil
			button:Hide()
		end
	end

	FauxScrollFrame_Update(self.ui.scrollFrame, #entries, #buttons, 22)
end

function Addon:RefreshEditor()
	if not (self.ui and self.ui.nameEditBox and self.ui.textEditBox and self.ui.slider and self.ui.showCheck and self.ui.fontSizeValue and TextOnScreenDB) then
		return
	end
	local entry = GetEntryById(TextOnScreenDB.selectedId)
	local hasEntry = entry ~= nil

	self.ui.nameEditBox:SetEnabled(hasEntry)
	self.ui.textEditBox:SetEnabled(hasEntry)
	self.ui.slider:SetEnabled(hasEntry)
	self.ui.showCheck:SetEnabled(hasEntry)
	if self.ui.colorButton and self.ui.colorButton.SetEnabled then
		self.ui.colorButton:SetEnabled(hasEntry)
	end

	if entry == nil then
		self.ui.nameEditBox:SetText("")
		self.ui.textEditBox:SetText("")
		self.ui.slider:SetValue(ENTRY_DEFAULTS.fontSize)
		self.ui.showCheck:SetChecked(false)
		self.ui.fontSizeValue:SetText("")
		self:RefreshPositionDisplay()
		return
	end

	self.ui.nameEditBox:SetText(entry.name or "")
	self.ui.nameEditBox:SetCursorPosition(#(entry.name or ""))
	self.ui.textEditBox:SetText(entry.text or "")
	self.ui.textEditBox:SetCursorPosition(#(entry.text or ""))
	self.ui.slider:SetValue(tonumber(entry.fontSize) or ENTRY_DEFAULTS.fontSize)
	self.ui.showCheck:SetChecked(not not entry.showWhenClosed)
	self.ui.fontSizeValue:SetText(tostring(tonumber(entry.fontSize) or ENTRY_DEFAULTS.fontSize))
	self:RefreshPositionDisplay()
end

function Addon:RefreshPositionDisplay()
	if not (self.ui and self.ui.anchorLabel and self.ui.coordLabel and TextOnScreenDB) then
		return
	end
	local entry = GetEntryById(TextOnScreenDB.selectedId)
	if not entry then
		self.ui.anchorLabel:SetText("Anchor: -")
		self.ui.coordLabel:SetText("X: -  Y: -")
		return
	end
	local pos = entry.position or ENTRY_DEFAULTS.position
	local point = pos.point or "CENTER"
	local rel = pos.relativePoint or "CENTER"
	local x = math.floor((pos.x or 0) + 0.5)
	local y = math.floor((pos.y or 0) + 0.5)
	self.ui.anchorLabel:SetText("Anchor: " .. point .. " / " .. rel)
	self.ui.coordLabel:SetText("X: " .. tostring(x) .. "  Y: " .. tostring(y))
end

function Addon:RefreshPositionDisplayFromFrame(entryId)
	if not (self.ui and self.ui.anchorLabel and self.ui.coordLabel and TextOnScreenDB) then
		return
	end
	if TextOnScreenDB.selectedId ~= entryId then
		return
	end
	local frame = self.entryFrames[entryId]
	if not frame then
		return
	end
	local point, _, relativePoint, xOfs, yOfs = frame:GetPoint(1)
	local x = math.floor((xOfs or 0) + 0.5)
	local y = math.floor((yOfs or 0) + 0.5)
	self.ui.anchorLabel:SetText("Anchor: " .. (point or "-") .. " / " .. (relativePoint or "-"))
	self.ui.coordLabel:SetText("X: " .. tostring(x) .. "  Y: " .. tostring(y))
end

function Addon:NudgeSelectedEntry(dx, dy)
	if not TextOnScreenDB then
		return
	end
	local entry = GetEntryById(TextOnScreenDB.selectedId)
	if not entry then
		return
	end
	entry.position = entry.position or {}
	entry.position.point = entry.position.point or "CENTER"
	entry.position.relativePoint = entry.position.relativePoint or "CENTER"
	entry.position.x = (entry.position.x or 0) + dx
	entry.position.y = (entry.position.y or 0) + dy
	self:ApplySettings(true)
	self:RefreshPositionDisplay()
end

function Addon:AddEntry()
	if not TextOnScreenDB then
		return
	end
	local id = TextOnScreenDB.nextId or 1
	TextOnScreenDB.nextId = id + 1
	TextOnScreenDB.entries = TextOnScreenDB.entries or {}
	local entry = CopyDefaultsInto({ id = id, name = "Text " .. tostring(id), text = "New Text" }, ENTRY_DEFAULTS)
	table.insert(TextOnScreenDB.entries, entry)
	TextOnScreenDB.selectedId = id
	self:CreateOnScreenText(id)
	self:ApplySettings(true)
	self:RefreshEntryList()
	self:RefreshEditor()
end

function Addon:DeleteSelectedEntry()
	if not TextOnScreenDB then
		return
	end
	local entryId = TextOnScreenDB.selectedId
	if not entryId then
		return
	end
	local _, index = GetEntryById(entryId)
	if not index then
		return
	end

	local frame = self.entryFrames[entryId]
	if frame then
		frame:Hide()
		self.entryFrames[entryId] = nil
	end

	table.remove(TextOnScreenDB.entries, index)
	if #TextOnScreenDB.entries > 0 then
		local newIndex = math.min(index, #TextOnScreenDB.entries)
		TextOnScreenDB.selectedId = TextOnScreenDB.entries[newIndex].id
	else
		TextOnScreenDB.selectedId = nil
	end

	self:ApplySettings(true)
	self:RefreshEntryList()
	self:RefreshEditor()
end

function Addon:CreateConfigDialog()
	if self.configFrame then
		return
	end

	local frame = CreateFrame("Frame", "TextOnScreen_ConfigFrame", UIParent, "BasicFrameTemplateWithInset")
	frame:SetSize(620, 430)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:Hide()

	frame.TitleText:SetText("TextOnScreen")

	local dragger = CreateFrame("Frame", nil, frame)
	dragger:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	dragger:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	dragger:SetHeight(28)
	dragger:EnableMouse(true)
	dragger:RegisterForDrag("LeftButton")
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	dragger:SetScript("OnDragStart", function()
		frame:StartMoving()
	end)
	dragger:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
	end)

	local MIN_W, MIN_H = 620, 460
	frame:SetResizable(true)
	if frame.SetMinResize then
		frame:SetMinResize(MIN_W, MIN_H)
	end
	if frame.SetResizeBounds then
		frame:SetResizeBounds(MIN_W, MIN_H, 900, 700)
	end
	local resizeButton = CreateFrame("Button", nil, frame)
	resizeButton:SetSize(16, 16)
	resizeButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 6)
	resizeButton:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	resizeButton:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	resizeButton:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	resizeButton:RegisterForDrag("LeftButton")
	resizeButton:SetScript("OnDragStart", function()
		frame:StartSizing("BOTTOMRIGHT")
	end)
	resizeButton:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		Addon:RefreshPositionDisplay()
	end)

	CreateLabel(frame, "Entries:", 16, -36)
	local scrollFrame = CreateFrame("ScrollFrame", "TextOnScreen_EntryScrollFrame", frame, "FauxScrollFrameTemplate")
	scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -56)
	scrollFrame:SetSize(180, 240)
	self.ui.scrollFrame = scrollFrame

	local listButtons = {}
	for i = 1, 10 do
		local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
		button:SetSize(150, 22)
		button:SetPoint("TOPLEFT", frame, "TOPLEFT", 26, -56 - ((i - 1) * 22))
		button:SetScript("OnClick", function(btn)
			if btn.entryId then
				Addon:SelectEntry(btn.entryId)
			end
		end)
		listButtons[i] = button
	end
	self.ui.listButtons = listButtons

	scrollFrame:SetScript("OnVerticalScroll", function(_, offset)
		FauxScrollFrame_OnVerticalScroll(scrollFrame, offset, 22, function()
			Addon:RefreshEntryList()
		end)
	end)

	local addButton = CreateButton(frame, "Add", 80, 22)
	addButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -306)
	addButton:SetScript("OnClick", function()
		Addon:AddEntry()
	end)

	local deleteButton = CreateButton(frame, "Delete", 80, 22)
	deleteButton:SetPoint("LEFT", addButton, "RIGHT", 10, 0)
	deleteButton:SetScript("OnClick", function()
		Addon:DeleteSelectedEntry()
	end)

	CreateLabel(frame, "Name:", 220, -36)
	local nameEditBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
	nameEditBox:SetSize(370, 26)
	nameEditBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 220, -56)
	nameEditBox:SetAutoFocus(false)
	nameEditBox:SetScript("OnEnterPressed", function(selfBox)
		selfBox:ClearFocus()
	end)
	nameEditBox:SetScript("OnEscapePressed", function(selfBox)
		selfBox:ClearFocus()
	end)
	nameEditBox:SetScript("OnTextChanged", function(selfBox, userInput)
		if not userInput then
			return
		end
		local entry = GetEntryById(TextOnScreenDB and TextOnScreenDB.selectedId)
		if not entry then
			return
		end
		entry.name = selfBox:GetText() or ""
		Addon:RefreshEntryList()
	end)

	CreateLabel(frame, "Text (multiline):", 220, -92)
	local textScroll = CreateFrame("ScrollFrame", "TextOnScreen_TextScrollFrame", frame, "UIPanelScrollFrameTemplate")
	textScroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 220, -112)
	textScroll:SetSize(340, 150)
	local textEditBox = CreateFrame("EditBox", nil, textScroll)
	textEditBox:SetMultiLine(true)
	textEditBox:SetAutoFocus(false)
	textEditBox:SetFontObject("ChatFontNormal")
	textEditBox:SetWidth(320)
	textEditBox:SetScript("OnEscapePressed", function(selfBox)
		selfBox:ClearFocus()
	end)
	textEditBox:SetScript("OnTextChanged", function(selfBox, userInput)
		textScroll:UpdateScrollChildRect()
		if not userInput then
			return
		end
		local entry = GetEntryById(TextOnScreenDB and TextOnScreenDB.selectedId)
		if not entry then
			return
		end
		entry.text = selfBox:GetText() or ""
		Addon:ApplySettings(true)
		Addon:RefreshEntryList()
	end)
	textScroll:SetScrollChild(textEditBox)

	CreateLabel(frame, "Font size:", 220, -270)
	local slider = CreateFrame("Slider", "TextOnScreen_FontSizeSlider", frame, "OptionsSliderTemplate")
	slider:SetPoint("TOPLEFT", frame, "TOPLEFT", 220, -296)
	slider:SetWidth(270)
	slider:SetMinMaxValues(8, 72)
	slider:SetValueStep(1)
	slider:SetObeyStepOnDrag(true)
	_G[slider:GetName() .. "Low"]:SetText("8")
	_G[slider:GetName() .. "High"]:SetText("72")
	_G[slider:GetName() .. "Text"]:SetText("")

	local fontSizeValue = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	fontSizeValue:SetPoint("LEFT", slider, "RIGHT", 8, 0)
	fontSizeValue:SetText("")

	slider:SetScript("OnValueChanged", function(selfSlider, value)
		value = math.floor((tonumber(value) or DEFAULTS.fontSize) + 0.5)
		local entry = GetEntryById(TextOnScreenDB and TextOnScreenDB.selectedId)
		if not entry then
			return
		end
		entry.fontSize = value
		fontSizeValue:SetText(tostring(value))
		Addon:ApplySettings(true)
	end)

	CreateLabel(frame, "Color:", 220, -330)
	local colorButton = CreateButton(frame, "Pick color", 100, 22)
	colorButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 220, -352)
	colorButton:SetScript("OnClick", function()
		Addon:OpenColorPicker(TextOnScreenDB and TextOnScreenDB.selectedId)
	end)

	local showCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	showCheck.Text:SetText("Show text when dialog is closed")
	showCheck:SetScript("OnClick", function(selfCheck)
		local entry = GetEntryById(TextOnScreenDB and TextOnScreenDB.selectedId)
		if not entry then
			return
		end
		entry.showWhenClosed = selfCheck:GetChecked() and true or false
		Addon:ApplySettings(true)
	end)

	local anchorLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	anchorLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -338)
	anchorLabel:SetText("Anchor: -")

	local coordLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	coordLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -360)
	coordLabel:SetText("X: -  Y: -")

	local upButton = CreateButton(frame, "Up", 50, 22)
	upButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -386)
	upButton:SetScript("OnClick", function()
		Addon:NudgeSelectedEntry(0, 1)
	end)

	local downButton = CreateButton(frame, "Down", 50, 22)
	downButton:SetPoint("LEFT", upButton, "RIGHT", 6, 0)
	downButton:SetScript("OnClick", function()
		Addon:NudgeSelectedEntry(0, -1)
	end)

	local leftButton = CreateButton(frame, "Left", 50, 22)
	leftButton:SetPoint("LEFT", downButton, "RIGHT", 6, 0)
	leftButton:SetScript("OnClick", function()
		Addon:NudgeSelectedEntry(-1, 0)
	end)

	local rightButton = CreateButton(frame, "Right", 50, 22)
	rightButton:SetPoint("LEFT", leftButton, "RIGHT", 6, 0)
	rightButton:SetScript("OnClick", function()
		Addon:NudgeSelectedEntry(1, 0)
	end)

	showCheck:ClearAllPoints()
	showCheck:SetPoint("LEFT", rightButton, "RIGHT", 18, 0)

	local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	hint:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 12)
	hint:SetText("Drag text to move; use buttons for 1px nudges")

	local function Layout()
		local w, h = frame:GetSize()
		local rightX = 220
		local padding = 16
		local rightWidth = math.max(200, w - rightX - padding)
		local scrollBarReserve = 28
		nameEditBox:SetWidth(rightWidth)
		local scrollWidth = math.max(200, rightWidth - scrollBarReserve)
		textScroll:SetWidth(scrollWidth)
		textEditBox:SetWidth(math.max(100, scrollWidth - 20))
		slider:SetWidth(math.max(140, rightWidth - 100))
		textScroll:SetHeight(math.max(90, h - 280))
		Addon:RefreshPositionDisplay()
	end

	frame:SetScript("OnSizeChanged", function()
		if frame._tosClampingSize then
			return
		end
		local w, h = frame:GetSize()
		if w < MIN_W or h < MIN_H then
			frame._tosClampingSize = true
			frame:SetSize(math.max(w, MIN_W), math.max(h, MIN_H))
			frame._tosClampingSize = nil
			return
		end
		Layout()
	end)
	Layout()

	frame:SetScript("OnShow", function()
		Addon:RefreshEntryList()
		Addon:RefreshEditor()
		Addon:ApplySettings(true)
	end)

	frame:SetScript("OnHide", function()
		Addon:ApplySettings(false)
	end)

	self.configFrame = frame
	self.ui.nameEditBox = nameEditBox
	self.ui.textEditBox = textEditBox
	self.ui.slider = slider
	self.ui.showCheck = showCheck
	self.ui.colorButton = colorButton
	self.ui.fontSizeValue = fontSizeValue
	self.ui.anchorLabel = anchorLabel
	self.ui.coordLabel = coordLabel
end

function Addon:ToggleConfig()
	if not self.configFrame then
		self:CreateConfigDialog()
	end
	if self.configFrame:IsShown() then
		self.configFrame:Hide()
	else
		self.configFrame:Show()
	end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
		TextOnScreenDB = CopyDefaultsInto(TextOnScreenDB, DEFAULTS)
		MigrateSingleEntryDB()
		for _, entry in ipairs(TextOnScreenDB.entries or {}) do
			if entry and entry.id then
				CopyDefaultsInto(entry, ENTRY_DEFAULTS)
				Addon:CreateOnScreenText(entry.id)
			end
		end
		Addon:CreateConfigDialog()
		Addon:ApplySettings(false)

		SLASH_TEXTONSCREEN1 = "/tos"
		SlashCmdList.TEXTONSCREEN = function()
			Addon:ToggleConfig()
		end
	end
end)
