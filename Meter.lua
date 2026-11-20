-- Restyle Blizzard's rows as they are acquired or resized. The native meter
-- owns combat data, ranking, scrolling and menus.

local FONT, FONT_HEIGHT = ChatFontNormal, 14
local FLAT = "Interface\\Buttons\\WHITE8X8"

-- Fractions of the row height, H.
local TEXT = 0.62 -- font size
local PAD = 3 / 8 -- from a bar's end to its text; between a control's parts
local APART = 1 / 4 -- between the meter's backdrop and the breakdown's
local CROSS = 0.45 -- the width of the close button's cross
local ARROW = 0.25 -- the size of a menu's arrow

local ROW_GAP = 1 -- between one bar and the next, in screen units
local SHADE = 0.35 -- how far a bar's colour is darkened, for white text to read on it
local FAINT = 0.7 -- the timer's grey
local FADE_SECONDS = 0.15

-- Never shown: the parent of what Blizzard would otherwise keep showing.
local unseen = CreateFrame("Frame")
unseen:Hide()

-- How far each bar reaches into the space Blizzard leaves under its row.
local function reach(owner)
	return math.max(owner:GetBarSpacing() - ROW_GAP, 0)
end

-- The height of a bar: H.
local function barHeight(owner)
	return owner:GetBarHeight() + reach(owner)
end

local SESSION_NAME = { -- Blizzard's own are "Current Segment" and "Overall"
	[Enum.DamageMeterSessionType.Current] = "Current",
	[Enum.DamageMeterSessionType.Overall] = "Overall",
}

-- The scale for row text in rows of the height given, times the text size
-- chosen in Edit Mode, which is 1 unless it has been changed.
local function textScale(owner, height)
	return owner:GetTextScale() * TEXT * height / FONT_HEIGHT
end

-- The name the game gave a past fight, where it may be read.
local function fightName(sessionID)
	for _, session in ipairs(C_DamageMeter.GetAvailableCombatSessions()) do
		if session.sessionID == sessionID then
			local name = session.name
			if canaccessvalue(name) and name and name ~= "" then
				return name
			end
		end
	end
	return DAMAGE_METER_COMBAT_NUMBER:format(sessionID)
end

-- Restyles one row, and keeps it so: Blizzard lays a row out again whenever
-- it is reused or a setting changes. `owner` is the window the row is in.
local adopted = {} -- row -> the function that lays it out
local function adopt(row, owner)
	if adopted[row] then
		return
	end
	local bar, icon = row.StatusBar, row.Icon
	local name, value = bar.Name, bar.Value
	-- Blizzard colours the bar's own image, so that is kept and made plain.
	bar:GetStatusBarTexture():SetTexture(FLAT)
	name:SetFontObject(FONT)
	value:SetFontObject(FONT)
	-- White text cannot be read on the lighter class colours (rogue, priest,
	-- hunter). The colour is Blizzard's to set and may be secret, so it is
	-- not changed: a sheet of black lies over the filled part of the bar,
	-- under the text.
	local shade = bar:CreateTexture(nil, "ARTWORK", nil, 7)
	shade:SetColorTexture(0, 0, 0, SHADE)
	shade:SetAllPoints(bar:GetStatusBarTexture())
	-- A row cuts off whatever passes its edges, which the bar now does.
	row:SetClipsChildren(false)
	icon:ClearAllPoints()
	icon:SetPoint("TOPLEFT")

	local function scaleText(height)
		local scale = textScale(owner, height)
		name:SetTextScale(scale)
		value:SetTextScale(scale)
	end

	-- Blizzard places the bar and its two texts afresh each time it applies
	-- the bar style, differently for each style: its icon is 24 square
	-- whatever the row's height, its bar inset, and in one style the name
	-- stands above the bar. All three are placed here instead, so the row is
	-- the same in every style.
	local function layOut()
		bar.Background:SetTexture(nil)
		bar.BackgroundEdge:Hide()
		if row:GetHeight() <= 0 then
			return
		end
		local below = reach(owner)
		local height = row:GetHeight() + below
		local pad = PAD * height
		icon:SetSize(height, height)
		bar:ClearAllPoints()
		bar:SetPoint("TOPLEFT", row:ShouldShowBarIcons() and height or 0, 0)
		bar:SetPoint("BOTTOMRIGHT", 0, -below)
		-- A long name ends in an ellipsis, a pad short of the number's own.
		name:ClearAllPoints()
		name:SetPoint("LEFT", pad, 0)
		name:SetPoint("RIGHT", value, "LEFT", -2 * pad, 0)
		value:ClearAllPoints()
		value:SetPoint("RIGHT", -pad, 0)
		scaleText(height)
	end
	hooksecurefunc(row, "UpdateStyle", layOut)
	hooksecurefunc(row, "SetBarHeight", layOut)
	hooksecurefunc(row, "SetTextScale", function()
		local height = row:GetHeight()
		if height > 0 then scaleText(height + reach(owner)) end
	end)
	-- A session row shows the source name without its rank. Spell breakdowns
	-- have their own names. Secret names may be passed directly to SetText.
	if owner.GetLocalPlayerEntry then
		local function writeName() name:SetText(row.sourceName) end
		hooksecurefunc(row, "UpdateName", writeName)
		writeName()
	end
	adopted[row] = layOut
	layOut()
end

-- Adopts every row of a list, now and as Blizzard creates more, and lays
-- them out again when the spacing between them is changed. A row out of use
-- at that moment is laid out when Blizzard next brings it into use. The
-- `adopted` passed along only names the registration, as Blizzard's lists
-- require; any value of this addon's own would do.
local function adoptRows(owner)
	local list = owner:GetScrollBox()
	list:ForEachFrame(function(row) adopt(row, owner) end)
	ScrollUtil.AddAcquiredFrameCallback(list, function(_, row) adopt(row, owner) end, adopted)
	hooksecurefunc(owner, "OnBarSpacingChanged", function()
		list:ForEachFrame(function(row) adopted[row]() end)
	end)
end

-- A title line and a backdrop for a list of rows. The line is unseen, and
-- only what the title's parts hang from: it sits above the list, which moves
-- with the scrollbar. The backdrop wraps the line and the rows down to the
-- last one, not the foot of the window: its foot is moved each time the list
-- is laid out. Returns the two, and a function to call when a setting
-- changes.
local function frameList(owner)
	local list = owner:GetScrollBox()
	local line = owner:CreateTexture()
	local backdrop = owner:CreateTexture(nil, "BACKGROUND")
	backdrop:SetColorTexture(0, 0, 0, 0.5)
	backdrop:SetPoint("TOPLEFT", line, "TOPLEFT")
	local function place()
		local shown = math.min(list:GetDerivedExtent() or 0, list:GetVisibleExtent() or 0)
		if shown > 0 then
			backdrop:SetPoint("BOTTOMRIGHT", list, "TOPRIGHT", 0, -shown - reach(owner))
		else
			backdrop:SetPoint("BOTTOMRIGHT", line, "BOTTOMRIGHT")
		end
	end
	list:RegisterCallback(BaseScrollBoxEvents.OnLayout, place, backdrop) -- named as in adoptRows
	return line, backdrop, function()
		line:SetHeight(barHeight(owner))
		line:SetPoint("BOTTOMLEFT", list, "TOPLEFT", 0, ROW_GAP)
		line:SetPoint("BOTTOMRIGHT", list, "TOPRIGHT", 0, ROW_GAP)
		place()
	end
end

-- Makes a button a segment of the title line: under the mouse the whole of
-- it lightens.
local function segment(button)
	local light = button:CreateTexture(nil, "BORDER")
	light:SetColorTexture(1, 1, 1, 0.12)
	light:SetAllPoints()
	light:Hide()
	button:HookScript("OnEnter", function() light:Show() end)
	button:HookScript("OnLeave", function() light:Hide() end)
end

-- A segment that opens a list is a word followed by a small down arrow, a
-- pad from each end. Returns the arrow, and a function that sizes the
-- segment for rows of the height given: to the word, or to the room given
-- if the word is wider, which then ends in an ellipsis.
local function wordMenu(button, word)
	word:SetFontObject(FONT)
	word:SetWordWrap(false)
	word:ClearAllPoints()
	local arrow = button:CreateTexture(nil, "OVERLAY")
	arrow:SetAtlas("friendslist-categorybutton-arrow-down")
	arrow:SetDesaturated(true)
	segment(button)
	return arrow, function(height, room)
		local pad = PAD * height
		word:SetPoint("LEFT", pad, 0)
		arrow:SetSize(ARROW * height, ARROW * height)
		arrow:SetPoint("LEFT", word, "RIGHT", pad / 2, 0)
		local width = word:GetUnboundedStringWidth()
		if room and room < width then
			width = math.max(room, 1)
			word:SetWidth(width)
		else
			word:SetWidth(0) -- as wide as the word
		end
		button:SetSize(pad + width + pad / 2 + ARROW * height + pad, height)
	end
end

-- The spell breakdown that opens beside the meter when a player's row is
-- clicked: the same backdrop and rows, under the player's name.
local function setupBreakdown(breakdown)
	adoptRows(breakdown)

	-- Blizzard's bordered panel. Its list of rows hangs from it, inset for
	-- that border by 20, 15, 22 and 17, so it is emptied, not hidden.
	breakdown.Background:SetTexture(nil)
	breakdown:GetScrollBar():SetParent(unseen)
	local line, _, placeLine = frameList(breakdown)

	local title = breakdown:CreateFontString(nil, "OVERLAY")
	title:SetFontObject(FONT)
	title:SetWordWrap(false)
	title:SetJustifyH("LEFT")
	local function writeTitle() title:SetText(breakdown.sourceName) end
	hooksecurefunc(breakdown, "SetSource", writeTitle)
	hooksecurefunc(breakdown, "ClearSource", writeTitle)
	writeTitle()

	-- The close button, shown when the breakdown has been pinned open with a
	-- shift-click: a plain cross in place of the red box.
	local close = breakdown.CloseButton
	for _, texture in ipairs({ close:GetRegions() }) do
		texture:SetAlpha(0)
	end
	close:ClearAllPoints()
	local cross = close:CreateFontString(nil, "OVERLAY")
	cross:SetFontObject(FONT)
	cross:SetText("\195\151") -- the multiplication sign
	cross:SetPoint("CENTER")
	segment(close)

	local function fitTitle()
		local pad = PAD * barHeight(breakdown)
		if close:IsShown() then
			title:SetPoint("RIGHT", close, "LEFT", -pad, 0)
		else
			title:SetPoint("RIGHT", line, "RIGHT", -pad, 0)
		end
	end
	hooksecurefunc(breakdown, "SetSticky", fitTitle)
	local function layOut()
		local height = barHeight(breakdown)
		local pad, scale = PAD * height, textScale(breakdown, height)
		placeLine()
		title:SetTextScale(scale)
		title:SetPoint("LEFT", line, "LEFT", pad, 0)
		cross:SetTextScale(scale)
		close:SetSize(pad + CROSS * height + pad, height)
		close:SetPoint("RIGHT", line, "RIGHT")
		fitTitle()
	end
	for _, setting in ipairs({ "OnBarHeightChanged", "OnBarSpacingChanged", "OnTextScaleChanged" }) do
		hooksecurefunc(breakdown, setting, layOut)
	end
	layOut()

	-- Blizzard puts the breakdown's window against the meter's, level with
	-- its top. Its list starts 15 below its top and the meter's 34 below, and
	-- the two lists stand 21 apart on one side and 27 on the other. Move it
	-- so that the two title lines are level and the backdrops a quarter of
	-- a row apart.
	hooksecurefunc(breakdown, "AnchorToSessionWindow", function()
		local height = barHeight(breakdown)
		local apart = APART * height
		local across = breakdown:IsRightSide() and apart - 21 or 27 - apart
		for i = 1, breakdown:GetNumPoints() do
			local point, relativeTo, relativePoint, x, y = breakdown:GetPoint(i)
			breakdown:SetPoint(point, relativeTo, relativePoint, x + across, point:find("TOP") and y - 19 or y)
		end
	end)
end

local function setup(window)
	-- The rows, the copy of the player's own row that is pinned in view when
	-- the real one scrolls out, and the spell breakdown.
	adoptRows(window)
	local ownRow = window:GetLocalPlayerEntry()
	adopt(ownRow, window)
	hooksecurefunc(window, "OnBarSpacingChanged", adopted[ownRow])
	-- Blizzard updates text scale on scroll-box rows. The pinned copy is
	-- a separate button and can stay on screen throughout the change.
	hooksecurefunc(window, "OnTextScaleChanged", adopted[ownRow])
	-- Blizzard lays that copy over the first or last row in view, 4 beyond
	-- the list's edge, and relies on its dark bar to hide what is under it.
	-- Put it squarely on the list's edge, on a dark sheet of its own.
	local list = window:GetScrollBox()
	local sheet = ownRow:CreateTexture(nil, "BACKGROUND")
	sheet:SetColorTexture(0, 0, 0, 0.9)
	sheet:SetPoint("TOPLEFT")
	sheet:SetPoint("BOTTOMRIGHT", ownRow.StatusBar, "BOTTOMRIGHT")
	hooksecurefunc(window, "ShowLocalPlayerEntry", function(_, aboveTheRows)
		ownRow:ClearAllPoints()
		if aboveTheRows then
			ownRow:SetPoint("TOPLEFT", list, "TOPLEFT")
			ownRow:SetPoint("TOPRIGHT", list, "TOPRIGHT")
		else
			local below = reach(window)
			ownRow:SetPoint("BOTTOMLEFT", list, "BOTTOMLEFT", 0, below)
			ownRow:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", 0, below)
		end
	end)
	setupBreakdown(window:GetSourceWindow())

	-- The gold bar. Other regions hang from it, so it is emptied, not hidden.
	window.Header:SetTexture(nil)
	local line, backdrop, placeLine = frameList(window)

	-- The title: what is being measured. Blizzard shows a boxed arrow that
	-- opens the list, with the name beside it. The name becomes the button.
	local typeMenu = window.DamageMeterTypeDropdown
	local title = typeMenu.TypeName
	typeMenu.Arrow:SetAlpha(0) -- Blizzard swaps its image on every hover and click
	typeMenu:ClearAllPoints()
	typeMenu:SetPoint("LEFT", line, "LEFT")
	local titleArrow, sizeTitle = wordMenu(typeMenu, title)

	-- The fight's length, after the title and always in view. Blizzard writes
	-- it in brackets ahead of the title, which pushes the title aside
	-- whenever a fight starts and ends. The brackets go wherever the number
	-- may be read. During a fight Blizzard writes it every frame, so it is
	-- overwritten every frame too, with text made once a second.
	local timer = window.SessionTimer
	timer:SetFontObject(FONT)
	timer:SetTextColor(FAINT, FAINT, FAINT)
	timer:ClearAllPoints()
	timer:SetPoint("LEFT", typeMenu, "RIGHT")
	local shownSecond, clock
	hooksecurefunc(window, "SetSessionDuration", function(_, seconds)
		if canaccessvalue(seconds) and seconds and seconds ~= 0 then
			local second = math.floor(seconds)
			if second ~= shownSecond then
				shownSecond, clock = second, SecondsToClock(seconds)
			end
			timer:SetText(clock)
		end
	end)

	-- Settings: a right-click anywhere on the window, in place of a gear to
	-- aim at. Only the gear's own button can open the list of settings
	-- without marking Blizzard's code, so that button is emptied and laid
	-- over the whole window, above the rows. It answers the right button, and
	-- lets the left button and the mouse's movement through to whatever is
	-- under it. Blizzard allows those changes only out of combat.
	local settings = window.SettingsDropdown
	settings.Icon:SetAlpha(0)
	local function coverWindow()
		settings:ClearAllPoints()
		settings:SetAllPoints(window)
		settings:SetFrameLevel(window:GetFrameLevel() + 20)
		settings:RegisterForMouse("RightButtonDown", "RightButtonUp")
		settings:SetPassThroughButtons("LeftButton")
		settings:SetPropagateMouseMotion(true)
	end
	if InCombatLockdown() then
		EventUtil.RegisterOnceFrameEventAndCallback("PLAYER_REGEN_ENABLED", coverWindow)
	else
		coverWindow()
	end

	-- The scrollbar. The wheel still scrolls the rows.
	window:GetScrollBar():SetParent(unseen)

	-- Which fight is shown, at the right. Blizzard boxes a single letter, and
	-- behind it keeps the chosen entry of its list in gold. Hide those and
	-- write the fight's name.
	local sessionMenu = window.SessionDropdown
	local sessionName = sessionMenu.SessionName
	sessionMenu.Background:SetAlpha(0)
	sessionMenu.Arrow:SetAlpha(0)
	sessionMenu.Text:SetAlpha(0)
	sessionMenu:ClearAllPoints()
	sessionMenu:SetPoint("RIGHT", line, "RIGHT")
	local _, sizeSessionMenu = wordMenu(sessionMenu, sessionName)

	local function layOut()
		local height = barHeight(window)
		local pad, scale = PAD * height, textScale(window, height)
		placeLine()
		title:SetTextScale(scale)
		sessionName:SetTextScale(scale)
		timer:SetTextScale(scale)
		sizeTitle(height)
		-- The title is never cut. The fight's name gets what is left of the
		-- line after the title, a timer of five figures (two and a half times
		-- the font's height) and its own pads and arrow.
		local width = line:GetWidth()
		local taken = typeMenu:GetWidth() + 2.5 * scale * FONT_HEIGHT + 2.5 * pad + ARROW * height
		sizeSessionMenu(height, width > 0 and width - taken or nil)
	end
	local function nameSession(sessionType, sessionID)
		sessionName:SetText(SESSION_NAME[sessionType] or sessionID and fightName(sessionID) or "")
		layOut()
	end
	for _, setting in ipairs({ "OnBarHeightChanged", "OnBarSpacingChanged", "OnTextScaleChanged", "SetDamageMeterType" }) do
		hooksecurefunc(window, setting, layOut)
	end
	hooksecurefunc(window, "SetSession", function(_, sessionType, sessionID)
		nameSession(sessionType, sessionID)
	end)
	window:HookScript("OnSizeChanged", layOut)
	nameSession(window:GetSessionType(), window:GetSessionID())

	-- Minimise is dropped. Should a window already be minimised, the button
	-- stays until it has been used to bring the window back.
	local minimize = window.MinimizeButton
	minimize:SetShown(window:IsMinimized() == true)
	hooksecurefunc(window, "SetMinimized", function(_, minimized)
		minimize:SetShown(minimized)
	end)

	-- The backdrop and the title's controls fade in while the mouse is over
	-- the window or one of its lists is open, and out again after. The
	-- segments stay clickable throughout, so each also starts the fade when
	-- the mouse reaches it first.
	local hoverOnly = { backdrop, titleArrow, sessionMenu }
	local menus = { typeMenu, sessionMenu, settings }
	local alpha = 0
	local function setAlpha()
		for _, region in ipairs(hoverOnly) do
			region:SetAlpha(alpha)
		end
	end
	local function inUse()
		if window:IsMouseOver() then
			return true
		end
		for _, menu in ipairs(menus) do
			if menu:IsMenuOpen() then
				return true
			end
		end
	end
	local fader = CreateFrame("Frame", nil, window)
	fader:Hide()
	fader:SetScript("OnUpdate", function(_, elapsed)
		local step = elapsed / FADE_SECONDS
		local was = alpha
		local target = inUse() and 1 or 0
		alpha = target == 1 and math.min(alpha + step, 1) or math.max(alpha - step, 0)
		if alpha ~= was then
			setAlpha()
		end
		if alpha == target then
			fader:Hide()
		end
	end)
	setAlpha()
	local function wake()
		fader:Show()
	end
	window:HookScript("OnShow", wake)
	-- Blizzard tracks the pointer across rows and the resize handle. Its
	-- MouseOver reason clears even when a child received the last mouse event.
	hooksecurefunc(window, "SetOnUpdateReason", function(_, reason)
		if reason == "MouseOver" then wake() end
	end)
	window:HookScript("OnHide", function()
		fader:Hide()
		alpha = 0
		setAlpha()
	end)
	for _, menu in ipairs(menus) do
		menu:HookScript("OnEnter", wake)
		menu:HookScript("OnLeave", wake)
		menu:RegisterCallback(DropdownButtonMixin.Event.OnMenuOpen, wake, fader)
		menu:RegisterCallback(DropdownButtonMixin.Event.OnMenuClose, wake, fader)
	end
	if window:IsVisible() and window:IsMouseOver() then wake() end
end

-- Blizzard sets up a window when it first shows it and again each time it is
-- shown after being hidden.
local done = {}
local function setupOnce(window)
	if not done[window] then
		done[window] = true
		setup(window)
	end
end

DamageMeter:ForEachSessionWindow(setupOnce)
hooksecurefunc(DamageMeter, "SetupSessionWindow", function(_, _, windowData)
	setupOnce(windowData.sessionWindow)
end)
