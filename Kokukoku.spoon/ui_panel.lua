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

local COLORS = {
	background = { red = 0.15, green = 0.15, blue = 0.15, alpha = 0.95 },
	headerBg = { red = 0.12, green = 0.12, blue = 0.12, alpha = 1 },
	rowBg = { red = 0.18, green = 0.18, blue = 0.18, alpha = 1 },
	activeRowBg = { red = 0.1, green = 0.3, blue = 0.15, alpha = 1 },
	footerBg = { red = 0.12, green = 0.12, blue = 0.12, alpha = 1 },
	text = { red = 0.9, green = 0.9, blue = 0.9, alpha = 1 },
	subText = { red = 0.6, green = 0.6, blue = 0.6, alpha = 1 },
	activeText = { red = 0.5, green = 1.0, blue = 0.6, alpha = 1 },
	separator = { red = 0.3, green = 0.3, blue = 0.3, alpha = 1 },
}

function M.new(options)
	options = options or {}

	local projects = options.projects or {}
	local onProjectSelect = options.onProjectSelect
	local onBreak = options.onBreak
	local onReset = options.onReset
	local getState = options.getState
	local formatTime = loadTimerEngine().formatTime

	local canvas = nil
	local escTap = nil
	local visible = false

	local nonBreakProjects = {}
	for _, p in ipairs(projects) do
		if not p.isBreak then
			table.insert(nonBreakProjects, p)
		end
	end

	local panelHeight = HEADER_HEIGHT + (#nonBreakProjects * ROW_HEIGHT) + FOOTER_HEIGHT

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

		-- Header text
		local headerText = "刻刻"
		if state.continuousStartedAt then
			headerText = headerText .. "  連続作業: " .. formatTime(continuousElapsed)
		end
		table.insert(elements, {
			type = "text",
			frame = { x = PADDING, y = 8, w = PANEL_WIDTH - PADDING * 2, h = 28 },
			text = headerText,
			textFont = ".AppleSystemUIFontBold",
			textSize = 16,
			textColor = COLORS.text,
			textAlignment = "center",
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

			local accumulated = state.accumulated[project.id] or 0
			if isActive and state.activeStartedAt then
				accumulated = accumulated + (os.time() - state.activeStartedAt)
			end

			-- Row background
			table.insert(elements, {
				type = "rectangle",
				action = "fill",
				frame = { x = 0, y = y, w = PANEL_WIDTH, h = ROW_HEIGHT },
				fillColor = isActive and COLORS.activeRowBg or COLORS.rowBg,
				trackMouseEnterExit = true,
				trackMouseDown = true,
				id = "row_" .. project.id,
			})

			-- Icon + Project name
			local icon = project.icon or ""
			local displayName = icon .. " " .. project.name
			table.insert(elements, {
				type = "text",
				frame = { x = PADDING, y = y + 6, w = 220, h = 24 },
				text = displayName,
				textFont = ".AppleSystemUIFont",
				textSize = 14,
				textColor = isActive and COLORS.activeText or COLORS.text,
			})

			-- Accumulated time
			table.insert(elements, {
				type = "text",
				frame = { x = 240, y = y + 6, w = 100, h = 24 },
				text = formatTime(accumulated),
				textFont = "Menlo",
				textSize = 14,
				textColor = isActive and COLORS.activeText or COLORS.subText,
				textAlignment = "right",
			})

			-- Active indicator
			if isActive then
				table.insert(elements, {
					type = "text",
					frame = { x = 350, y = y + 6, w = 60, h = 24 },
					text = "▶ 計測中",
					textFont = ".AppleSystemUIFont",
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

		-- Break button
		table.insert(elements, {
			type = "text",
			frame = { x = PADDING, y = footerY + 8, w = 120, h = 24 },
			text = "☕ 休憩",
			textFont = ".AppleSystemUIFont",
			textSize = 14,
			textColor = COLORS.text,
			trackMouseDown = true,
			id = "btn_break",
		})

		-- Reset button
		table.insert(elements, {
			type = "text",
			frame = { x = PANEL_WIDTH - PADDING - 100, y = footerY + 8, w = 100, h = 24 },
			text = "🔄 リセット",
			textFont = ".AppleSystemUIFont",
			textSize = 14,
			textColor = COLORS.subText,
			textAlignment = "right",
			trackMouseDown = true,
			id = "btn_reset",
		})

		return elements
	end

	local function handleClick(_, _, elementId)
		if not elementId then
			return
		end

		if type(elementId) == "string" then
			if elementId:match("^row_") then
				local projectId = elementId:sub(5)
				if onProjectSelect then
					onProjectSelect(projectId)
				end
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

		-- Rebuild panel after action
		if canvas and visible then
			local elements = buildElements()
			-- Remove all existing elements and re-add
			while canvas:elementCount() > 0 do
				canvas:removeElement(1)
			end
			for _, element in ipairs(elements) do
				canvas:appendElements(element)
			end
		end
	end

	local function show()
		if visible and canvas then
			return
		end

		local screen = hs.screen.mainScreen()
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

		canvas:mouseCallback(function(c, msg, id, x2, y2)
			if msg == "mouseDown" then
				handleClick(c, msg, id)
			end
		end)

		canvas:show()
		visible = true

		-- Escapeキーでパネルを閉じる
		escTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(event)
			if event:getKeyCode() == 53 then -- Escape
				M._hide(canvas, escTap)
				canvas = nil
				escTap = nil
				visible = false
				return true
			end
			return false
		end)
		escTap:start()
	end

	function M._hide(c, tap)
		if tap then
			tap:stop()
		end
		if c then
			c:delete()
		end
	end

	local function hide()
		M._hide(canvas, escTap)
		canvas = nil
		escTap = nil
		visible = false
	end

	local function toggle()
		if visible then
			hide()
		else
			show()
		end
	end

	local function update(state)
		if not visible or not canvas then
			return
		end

		local elements = buildElements()
		while canvas:elementCount() > 0 do
			canvas:removeElement(1)
		end
		for _, element in ipairs(elements) do
			canvas:appendElements(element)
		end
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
