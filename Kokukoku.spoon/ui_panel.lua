local M = {}

local function resourcePath(fileName)
	if not hs or not hs.spoons or not hs.spoons.resourcePath then
		error("[kokukoku.ui_panel] hs.spoons.resourcePath is not available")
	end

	local path = hs.spoons.resourcePath(fileName)
	if not path then
		error("[kokukoku.ui_panel] failed to resolve Spoon resource: " .. tostring(fileName))
	end
	return path
end

local timerEngineModule = nil
local function loadTimerEngine()
	if timerEngineModule == nil then
		timerEngineModule = dofile(resourcePath("timer_engine.lua"))
	end
	return timerEngineModule
end

local PANEL_WIDTH = 420
local HEADER_HEIGHT = 44
local ROW_HEIGHT = 36
local FOOTER_HEIGHT = 40
local PADDING = 12
local PROJECT_CONTENT_X = PADDING + 22
local PROJECT_NAME_RIGHT = 232
local ICON_TEXT_WIDTH = 24
local ICON_IMAGE_SIZE = 20
local ICON_GAP = 8
local ICON_SLOT_WIDTH = 24

local COLORS = {
	background = { red = 0.15, green = 0.15, blue = 0.15, alpha = 0.95 },
	headerBg = { red = 0.12, green = 0.12, blue = 0.12, alpha = 1 },
	rowBg = { red = 0.18, green = 0.18, blue = 0.18, alpha = 1 },
	rowHoverBg = { red = 0.24, green = 0.24, blue = 0.24, alpha = 1 },
	activeRowBg = { red = 0.3, green = 0.24, blue = 0.08, alpha = 1 },
	activeRowHoverBg = { red = 0.35, green = 0.28, blue = 0.1, alpha = 1 },
	switchSuccessBg = { red = 0.5, green = 0.4, blue = 0.1, alpha = 1 },
	footerBg = { red = 0.12, green = 0.12, blue = 0.12, alpha = 1 },
	footerHoverBg = { red = 0.2, green = 0.2, blue = 0.2, alpha = 1 },
	text = { red = 0.9, green = 0.9, blue = 0.9, alpha = 1 },
	subText = { red = 0.6, green = 0.6, blue = 0.6, alpha = 1 },
	activeText = { red = 1.0, green = 0.85, blue = 0.35, alpha = 1 },
	separator = { red = 0.3, green = 0.3, blue = 0.3, alpha = 1 },
}

local function isIconUrl(icon)
	return type(icon) == "string" and icon:match("^https?://") ~= nil
end

local function isIconFilePath(icon)
	return type(icon) == "string" and (icon:match("^/") ~= nil or icon:match("^~/") ~= nil)
end

local function expandHomePath(path)
	if type(path) ~= "string" then
		return path
	end
	if path:sub(1, 2) ~= "~/" then
		return path
	end

	local home = os.getenv("HOME")
	if not home or home == "" then
		return path
	end

	return home .. path:sub(2)
end

local function centeredOffset(containerHeight, contentHeight)
	return math.floor((containerHeight - contentHeight) / 2)
end

local function measureTextHeight(text, font, size)
	local fallback = math.max(size + 8, size)
	if not hs or not hs.drawing or not hs.drawing.getTextDrawingSize then
		return fallback
	end

	local measured = hs.drawing.getTextDrawingSize(text ~= "" and text or " ", {
		font = font,
		size = size,
	})
	if not measured then
		return fallback
	end

	return measured.h or measured.H or fallback
end

function M.new(options)
	options = options or {}

	local projects = options.projects or {}
	local onProjectSelect = options.onProjectSelect
	local onBreak = options.onBreak
	local onReset = options.onReset
	local getState = options.getState
	local formatTime = loadTimerEngine().formatTime
	local fontName = options.fontName or ".AppleSystemUIFont"
	local monoFontName = options.monoFontName or "Menlo"

	local canvas = nil
	local escTap = nil
	local clickTap = nil
	local visible = false
	local selectedIndex = nil
	local isClosing = false
	local feedbackDelayTimer = nil
	local feedbackFadeTimer = nil
	local iconCache = {}
	local rebuildPanel

	local nonBreakProjects = {}
	local breakProject = nil
	for _, p in ipairs(projects) do
		if p.isBreak and breakProject == nil then
			breakProject = p
		elseif not p.isBreak then
			table.insert(nonBreakProjects, p)
		end
	end

	local totalSelectableItems = #nonBreakProjects + 2 -- プロジェクト + 休憩 + リセット
	local panelHeight = HEADER_HEIGHT + (#nonBreakProjects * ROW_HEIGHT) + FOOTER_HEIGHT

	local function cacheImage(key, image)
		if image then
			iconCache[key] = {
				status = "loaded",
				image = image,
			}
		else
			iconCache[key] = {
				status = "failed",
			}
		end
	end

	local function resolveIconImage(icon)
		if not hs or not hs.image or type(icon) ~= "string" or icon == "" then
			return nil
		end

		if isIconUrl(icon) then
			local cacheKey = "url:" .. icon
			local cached = iconCache[cacheKey]
			if cached then
				if cached.status == "loaded" then
					return cached.image
				end
				return nil
			end

			iconCache[cacheKey] = { status = "loading" }
			hs.image.imageFromURL(icon, function(image)
				cacheImage(cacheKey, image)
				if rebuildPanel then
					rebuildPanel()
				end
			end)
			return nil
		end

		if isIconFilePath(icon) then
			local resolvedPath = expandHomePath(icon)
			local cacheKey = "path:" .. resolvedPath
			local cached = iconCache[cacheKey]
			if cached then
				if cached.status == "loaded" then
					return cached.image
				end
				return nil
			end

			cacheImage(cacheKey, hs.image.imageFromPath(resolvedPath))
			if iconCache[cacheKey].status == "loaded" then
				return iconCache[cacheKey].image
			end
		end

		return nil
	end

	local function buildElements()
		local state = getState()
		local elements = {}

		local continuousElapsed = 0
		if state.continuousStartedAt then
			continuousElapsed = os.time() - state.continuousStartedAt
		end

		-- Background
		table.insert(elements, {
			type = "rectangle",
			action = "fill",
			frame = { x = 0, y = 0, w = PANEL_WIDTH, h = panelHeight },
			fillColor = COLORS.background,
			roundedRectRadii = { xRadius = 10, yRadius = 10 },
		})

		-- Header background
		table.insert(elements, {
			type = "rectangle",
			action = "fill",
			frame = { x = 0, y = 0, w = PANEL_WIDTH, h = HEADER_HEIGHT },
			fillColor = COLORS.headerBg,
			roundedRectRadii = { xRadius = 10, yRadius = 10 },
		})
		-- Header bottom rect to cover bottom rounded corners
		table.insert(elements, {
			type = "rectangle",
			action = "fill",
			frame = { x = 0, y = HEADER_HEIGHT - 10, w = PANEL_WIDTH, h = 10 },
			fillColor = COLORS.headerBg,
		})

		-- Header logo + time (centered)
		local logoSize = 28
		local logoTextGap = 6
		local timeTextWidth = 90
		local totalWidth = logoSize + logoTextGap + timeTextWidth
		local startX = (PANEL_WIDTH - totalWidth) / 2

		local logoPath = resourcePath("kokukoku.webp")
		local logoImage = hs.image.imageFromPath(logoPath)
		if logoImage then
			table.insert(elements, {
				type = "image",
				frame = { x = startX, y = 8, w = logoSize, h = logoSize },
				image = logoImage,
				imageScaling = "shrinkToFit",
			})
		end

		local timeText = state.continuousStartedAt and formatTime(continuousElapsed) or "--:--:--"
		table.insert(elements, {
			type = "text",
			frame = { x = startX + logoSize + logoTextGap, y = 12, w = timeTextWidth, h = 28 },
			text = timeText,
			textFont = monoFontName,
			textSize = 16,
			textColor = state.continuousStartedAt and COLORS.text or COLORS.subText,
		})

		-- Separator after header
		table.insert(elements, {
			type = "rectangle",
			action = "fill",
			frame = { x = 0, y = HEADER_HEIGHT, w = PANEL_WIDTH, h = 1 },
			fillColor = COLORS.separator,
		})

		-- Project rows
		for i, project in ipairs(nonBreakProjects) do
			local y = HEADER_HEIGHT + (i - 1) * ROW_HEIGHT
			local isActive = state.activeProjectId == project.id
			local isSelected = selectedIndex == i

			local accumulated = state.accumulated[project.id] or 0
			if isActive and state.activeStartedAt then
				accumulated = accumulated + (os.time() - state.activeStartedAt)
			end

			-- Row background
			local rowColor
			if isActive then
				rowColor = isSelected and COLORS.activeRowHoverBg or COLORS.activeRowBg
			else
				rowColor = isSelected and COLORS.rowHoverBg or COLORS.rowBg
			end
			table.insert(elements, {
				type = "rectangle",
				action = "fill",
				frame = { x = 0, y = y, w = PANEL_WIDTH, h = ROW_HEIGHT },
				fillColor = rowColor,
				trackMouseEnterExit = true,
				trackMouseDown = true,
				id = "row_" .. project.id,
			})

			-- Number indicator
			if i <= 9 then
				local numberText = tostring(i)
				local numberHeight = measureTextHeight(numberText, monoFontName, 12)
				table.insert(elements, {
					type = "text",
					frame = { x = PADDING, y = y + centeredOffset(ROW_HEIGHT, numberHeight), w = 20, h = numberHeight },
					text = numberText,
					textFont = monoFontName,
					textSize = 12,
					textColor = COLORS.subText,
				})
			end

			-- Icon + Project name
			local icon = project.icon or ""
			local iconImage = resolveIconImage(icon)
			local nameX = PROJECT_CONTENT_X
			local nameWidth = PROJECT_NAME_RIGHT - nameX
			local nameHeight = measureTextHeight(project.name, fontName, 14)
			if iconImage then
				table.insert(elements, {
					type = "image",
					frame = {
						x = PROJECT_CONTENT_X + math.floor((ICON_SLOT_WIDTH - ICON_IMAGE_SIZE) / 2),
						y = y + centeredOffset(ROW_HEIGHT, ICON_IMAGE_SIZE),
						w = ICON_IMAGE_SIZE,
						h = ICON_IMAGE_SIZE,
					},
					image = iconImage,
					imageScaling = "scaleProportionally",
				})
			elseif icon ~= "" and not isIconUrl(icon) and not isIconFilePath(icon) then
				local iconTextHeight = measureTextHeight(icon, fontName, 14)
				table.insert(elements, {
					type = "text",
					frame = {
						x = PROJECT_CONTENT_X,
						y = y + centeredOffset(ROW_HEIGHT, iconTextHeight),
						w = ICON_SLOT_WIDTH,
						h = iconTextHeight,
					},
					text = icon,
					textFont = fontName,
					textSize = 14,
					textColor = isActive and COLORS.activeText or COLORS.text,
					textAlignment = "center",
				})
			end
			nameX = PROJECT_CONTENT_X + ICON_SLOT_WIDTH + ICON_GAP
			nameWidth = PROJECT_NAME_RIGHT - nameX
			table.insert(elements, {
				type = "text",
				frame = { x = nameX, y = y + centeredOffset(ROW_HEIGHT, nameHeight), w = nameWidth, h = nameHeight },
				text = project.name,
				textFont = fontName,
				textSize = 14,
				textColor = isActive and COLORS.activeText or COLORS.text,
			})

			-- Accumulated time
			local accumulatedText = formatTime(accumulated)
			local accumulatedHeight = measureTextHeight(accumulatedText, monoFontName, 14)
			table.insert(elements, {
				type = "text",
				frame = { x = 240, y = y + centeredOffset(ROW_HEIGHT, accumulatedHeight), w = 100, h = accumulatedHeight },
				text = accumulatedText,
				textFont = monoFontName,
				textSize = 14,
				textColor = isActive and COLORS.activeText or COLORS.subText,
				textAlignment = "right",
			})

			-- Active indicator
			if isActive then
				local activeText = "▶ 計測中"
				local activeHeight = measureTextHeight(activeText, fontName, 11)
				table.insert(elements, {
					type = "text",
					frame = { x = 350, y = y + centeredOffset(ROW_HEIGHT, activeHeight), w = 60, h = activeHeight },
					text = activeText,
					textFont = fontName,
					textSize = 11,
					textColor = COLORS.activeText,
				})
			end

			-- Row separator
			if i < #nonBreakProjects then
				table.insert(elements, {
					type = "rectangle",
					action = "fill",
					frame = { x = PADDING, y = y + ROW_HEIGHT - 1, w = PANEL_WIDTH - PADDING * 2, h = 1 },
					fillColor = COLORS.separator,
				})
			end
		end

		-- Separator before footer
		local footerY = HEADER_HEIGHT + #nonBreakProjects * ROW_HEIGHT
		table.insert(elements, {
			type = "rectangle",
			action = "fill",
			frame = { x = 0, y = footerY, w = PANEL_WIDTH, h = 1 },
			fillColor = COLORS.separator,
		})

		-- Footer background
		table.insert(elements, {
			type = "rectangle",
			action = "fill",
			frame = { x = 0, y = footerY, w = PANEL_WIDTH, h = FOOTER_HEIGHT },
			fillColor = COLORS.footerBg,
			roundedRectRadii = { xRadius = 10, yRadius = 10 },
		})
		-- Footer top rect to cover top rounded corners
		table.insert(elements, {
			type = "rectangle",
			action = "fill",
			frame = { x = 0, y = footerY, w = PANEL_WIDTH, h = 10 },
			fillColor = COLORS.footerBg,
		})

		local isBreakSelected = selectedIndex == #nonBreakProjects + 1
		local breakConfig = breakProject or { name = "休憩", icon = "☕" }
		local breakName = breakConfig.name or "休憩"
		local breakIcon = breakConfig.icon or ""
		local breakIconImage = resolveIconImage(breakIcon)
		local breakTextHeight = measureTextHeight(breakName, fontName, 14)

		-- Break button background (for hover)
		table.insert(elements, {
			type = "rectangle",
			action = "fill",
			frame = { x = PADDING - 4, y = footerY + 4, w = 132, h = 30 },
			fillColor = isBreakSelected and COLORS.footerHoverBg or COLORS.footerBg,
			roundedRectRadii = { xRadius = 6, yRadius = 6 },
			trackMouseEnterExit = true,
			trackMouseDown = true,
			id = "btn_break",
		})

		-- Break button content
		table.insert(elements, {
			type = "text",
			frame = { x = PADDING, y = footerY + centeredOffset(30, breakTextHeight), w = 24, h = breakTextHeight },
			text = "0:",
			textFont = monoFontName,
			textSize = 14,
			textColor = COLORS.text,
		})
		local breakIconX = PADDING + 24
		if breakIconImage then
			table.insert(elements, {
				type = "image",
				frame = {
					x = breakIconX + math.floor((ICON_SLOT_WIDTH - ICON_IMAGE_SIZE) / 2),
					y = footerY + 5 + centeredOffset(24, ICON_IMAGE_SIZE),
					w = ICON_IMAGE_SIZE,
					h = ICON_IMAGE_SIZE,
				},
				image = breakIconImage,
				imageScaling = "scaleProportionally",
			})
		elseif breakIcon ~= "" and not isIconUrl(breakIcon) and not isIconFilePath(breakIcon) then
			local breakIconHeight = measureTextHeight(breakIcon, fontName, 14)
			table.insert(elements, {
				type = "text",
				frame = {
					x = breakIconX,
					y = footerY + 5 + centeredOffset(24, breakIconHeight),
					w = ICON_SLOT_WIDTH,
					h = breakIconHeight,
				},
				text = breakIcon,
				textFont = fontName,
				textSize = 14,
				textColor = COLORS.text,
				textAlignment = "center",
			})
		end
		table.insert(elements, {
			type = "text",
			frame = { x = breakIconX + ICON_SLOT_WIDTH + ICON_GAP, y = footerY + centeredOffset(30, breakTextHeight), w = 72, h = breakTextHeight },
			text = breakName,
			textFont = fontName,
			textSize = 14,
			textColor = COLORS.text,
		})

		local isResetSelected = selectedIndex == #nonBreakProjects + 2

		-- Reset button background (for hover)
		table.insert(elements, {
			type = "rectangle",
			action = "fill",
			frame = { x = PANEL_WIDTH - PADDING - 114, y = footerY + 4, w = 118, h = 30 },
			fillColor = isResetSelected and COLORS.footerHoverBg or COLORS.footerBg,
			roundedRectRadii = { xRadius = 6, yRadius = 6 },
			trackMouseEnterExit = true,
			trackMouseDown = true,
			id = "btn_reset",
		})

		-- Reset button text
		table.insert(elements, {
			type = "text",
			frame = { x = PANEL_WIDTH - PADDING - 110, y = footerY + 8, w = 110, h = 24 },
			text = "r: 🔄 リセット",
			textFont = fontName,
			textSize = 14,
			textColor = COLORS.subText,
			textAlignment = "right",
		})

		return elements
	end

	local function hide()
		if feedbackFadeTimer then
			feedbackFadeTimer:stop()
			feedbackFadeTimer = nil
		end
		if feedbackDelayTimer then
			feedbackDelayTimer:stop()
			feedbackDelayTimer = nil
		end
		if escTap then
			escTap:stop()
			escTap = nil
		end
		if clickTap then
			clickTap:stop()
			clickTap = nil
		end
		if canvas then
			canvas:delete()
			canvas = nil
		end
		visible = false
		selectedIndex = nil
		isClosing = false
	end

	local function findElementIndexById(c, elementId)
		for i = 1, c:elementCount() do
			if c:elementAttribute(i, "id") == elementId then
				return i
			end
		end
		return nil
	end

	local FEEDBACK_DELAY = 0.4
	local FADE_DURATION = 0.3
	local FADE_STEPS = 10

	local function hideWithFeedback(projectId)
		if not canvas or not visible then
			return
		end

		isClosing = true

		-- 選択した行をハイライト
		local rowId = "row_" .. projectId
		local idx = findElementIndexById(canvas, rowId)
		if idx then
			canvas:elementAttribute(idx, "fillColor", COLORS.switchSuccessBg)
		end

		-- 一定時間後にフェードアウト開始
		feedbackDelayTimer = hs.timer.doAfter(FEEDBACK_DELAY, function()
			feedbackDelayTimer = nil
			if not canvas then
				return
			end
			local step = 0
			feedbackFadeTimer = hs.timer.doEvery(FADE_DURATION / FADE_STEPS, function()
				step = step + 1
				if not canvas then
					if feedbackFadeTimer then
						feedbackFadeTimer:stop()
						feedbackFadeTimer = nil
					end
					return
				end
				local alpha = 1 - (step / FADE_STEPS)
				if alpha <= 0 then
					if feedbackFadeTimer then
						feedbackFadeTimer:stop()
						feedbackFadeTimer = nil
					end
					hide()
				else
					canvas:alpha(alpha)
				end
			end)
		end)
	end

	rebuildPanel = function()
		if canvas and visible then
			local elements = buildElements()
			while canvas:elementCount() > 0 do
				canvas:removeElement(1)
			end
			for _, element in ipairs(elements) do
				canvas:appendElements(element)
			end
		end
	end

	local function selectProject(projectId)
		local state = getState()
		local isAlreadyActive = state.activeProjectId == projectId
		if onProjectSelect then
			onProjectSelect(projectId)
		end
		if not isAlreadyActive then
			hideWithFeedback(projectId)
		else
			rebuildPanel()
		end
	end

	local function handleClick(_, _, elementId)
		if not elementId or isClosing then
			return
		end

		if type(elementId) == "string" then
			if elementId:match("^row_") then
				local projectId = elementId:sub(5)
				selectProject(projectId)
				return
			elseif elementId == "btn_break" then
				if onBreak then
					onBreak()
				end
			elseif elementId == "btn_reset" then
				if onReset then
					onReset()
				end
			end
		end

		rebuildPanel()
	end

	local function screenForMousePosition()
		local mousePoint = hs.mouse.absolutePosition()
		for _, s in ipairs(hs.screen.allScreens()) do
			local frame = s:fullFrame()
			if
				mousePoint.x >= frame.x
				and mousePoint.x < frame.x + frame.w
				and mousePoint.y >= frame.y
				and mousePoint.y < frame.y + frame.h
			then
				return s
			end
		end
		return hs.screen.mainScreen()
	end

	local function executeSelectedAction()
		if not selectedIndex then
			return
		end
		if selectedIndex <= #nonBreakProjects then
			local project = nonBreakProjects[selectedIndex]
			selectProject(project.id)
		elseif selectedIndex == #nonBreakProjects + 1 then
			if onBreak then
				onBreak()
			end
			rebuildPanel()
		elseif selectedIndex == #nonBreakProjects + 2 then
			if onReset then
				onReset()
			end
			rebuildPanel()
		end
	end

	local function show()
		if visible and canvas then
			return
		end

		-- カーソル初期位置をアクティブプロジェクトに設定
		selectedIndex = nil
		local state = getState()
		if state.activeProjectId then
			for i, p in ipairs(nonBreakProjects) do
				if p.id == state.activeProjectId then
					selectedIndex = i
					break
				end
			end
		end

		-- アクティブモニタ(マウスカーソルのあるスクリーン)の中央に表示
		local screen = screenForMousePosition()
		local screenFrame = screen:frame()
		local x = screenFrame.x + (screenFrame.w - PANEL_WIDTH) / 2
		local y = screenFrame.y + (screenFrame.h - panelHeight) / 2

		canvas = hs.canvas.new({ x = x, y = y, w = PANEL_WIDTH, h = panelHeight })
		canvas:level(hs.canvas.windowLevels.floating)
		canvas:behavior({ "canJoinAllSpaces" })

		local elements = buildElements()
		for _, element in ipairs(elements) do
			canvas:appendElements(element)
		end

		canvas:mouseCallback(function(_, msg, id)
			if msg == "mouseDown" then
				handleClick(nil, msg, id)
			elseif msg == "mouseEnter" then
				if type(id) == "string" and canvas then
					local idx = findElementIndexById(canvas, id)
					if idx then
						if id:match("^row_") then
							local projectId = id:sub(5)
							local state = getState()
							local isActive = state.activeProjectId == projectId
							canvas:elementAttribute(idx, "fillColor", isActive and COLORS.activeRowHoverBg or COLORS.rowHoverBg)
						elseif id == "btn_break" or id == "btn_reset" then
							canvas:elementAttribute(idx, "fillColor", COLORS.footerHoverBg)
						end
					end
				end
			elseif msg == "mouseExit" then
				if type(id) == "string" and canvas then
					local idx = findElementIndexById(canvas, id)
					if idx then
						if id:match("^row_") then
							local projectId = id:sub(5)
							local state = getState()
							local isActive = state.activeProjectId == projectId
							canvas:elementAttribute(idx, "fillColor", isActive and COLORS.activeRowBg or COLORS.rowBg)
						elseif id == "btn_break" or id == "btn_reset" then
							canvas:elementAttribute(idx, "fillColor", COLORS.footerBg)
						end
					end
				end
			end
		end)

		canvas:show()
		visible = true

		-- キーボード操作 (Escape, 数字キー, j/k/↑/↓, Enter, 0, r)
		escTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(event)
			if isClosing then
				return true
			end

			local keyCode = event:getKeyCode()
			local char = event:getCharacters()

			if keyCode == 53 then -- Escape
				hide()
				return true
			elseif keyCode == 36 then -- Enter/Return
				if selectedIndex then
					executeSelectedAction()
				end
				return true
			elseif char == "j" or keyCode == 125 then -- 125 = Down arrow
				if selectedIndex == nil then
					selectedIndex = 1
				else
					selectedIndex = selectedIndex + 1
					if selectedIndex > totalSelectableItems then
						selectedIndex = 1
					end
				end
				rebuildPanel()
				return true
			elseif char == "k" or keyCode == 126 then -- 126 = Up arrow
				if selectedIndex == nil then
					selectedIndex = totalSelectableItems
				else
					selectedIndex = selectedIndex - 1
					if selectedIndex < 1 then
						selectedIndex = totalSelectableItems
					end
				end
				rebuildPanel()
				return true
			elseif char == "0" then
				if onBreak then
					onBreak()
				end
				rebuildPanel()
				return true
			elseif char == "r" then
				if onReset then
					onReset()
				end
				rebuildPanel()
				return true
			elseif char and char:match("^[1-9]$") then
				local idx = tonumber(char)
				if idx <= #nonBreakProjects then
					local project = nonBreakProjects[idx]
					selectProject(project.id)
				end
				return true
			end

			return false
		end)
		escTap:start()

		-- パネル外クリックで閉じる
		clickTap = hs.eventtap.new({ hs.eventtap.event.types.leftMouseDown }, function(event)
			local pos = event:location()
			local canvasFrame = canvas:frame()
			if
				pos.x < canvasFrame.x
				or pos.x > canvasFrame.x + canvasFrame.w
				or pos.y < canvasFrame.y
				or pos.y > canvasFrame.y + canvasFrame.h
			then
				hide()
				return false
			end
			return false
		end)
		clickTap:start()
	end

	local function toggle()
		if visible then
			hide()
		else
			show()
		end
	end

	local function update(_)
		rebuildPanel()
	end

	local function teardown()
		hide()
	end

	return {
		show = show,
		hide = hide,
		toggle = toggle,
		update = update,
		teardown = teardown,
	}
end

return M
