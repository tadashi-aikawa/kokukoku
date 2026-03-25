local M = {}

function M.new()
	local state = {
		timers = {},
		notifications = {},
		canvases = {},
		eventtaps = {},
		image = {
			pathRequests = {},
			pathResults = {},
			urlRequests = {},
			urlResults = {},
		},
		dialog = {
			prompts = {},
			nextResult = { "OK", "" },
		},
		pasteboard = {
			contents = nil,
		},
	}

	local hs = {
		timer = {
			doEvery = function(interval, fn)
				local timer = {
					interval = interval,
					callback = fn,
					stopped = false,
				}
				function timer:stop()
					self.stopped = true
				end
				table.insert(state.timers, timer)
				return timer
			end,
			doAfter = function(interval, fn)
				local timer = {
					interval = interval,
					callback = fn,
					stopped = false,
				}
				function timer:stop()
					self.stopped = true
				end
				table.insert(state.timers, timer)
				return timer
			end,
		},
		notify = {
			new = function(_, opts)
				local notification = {
					title = opts.title,
					informativeText = opts.informativeText,
					sent = false,
				}
				function notification:send()
					self.sent = true
					table.insert(state.notifications, self)
					return self
				end
				return notification
			end,
		},
		drawing = {
			getTextDrawingSize = function(text, style)
				local fontSize = style and style.size or 14
				local content = text or ""
				return {
					w = math.max(1, math.floor(#content * fontSize * 0.6)),
					h = math.max(1, math.floor(fontSize * 1.2)),
				}
			end,
		},
		mouse = {
			absolutePosition = function()
				return { x = 500, y = 500 }
			end,
		},
		json = {
			encode = function(data)
				local function encode_value(val)
					if val == nil then
						return "null"
					end
					local t = type(val)
					if t == "string" then
						return '"' .. val:gsub('"', '\\"') .. '"'
					elseif t == "number" then
						return tostring(val)
					elseif t == "boolean" then
						return tostring(val)
					elseif t == "table" then
						-- Check if array
						local is_array = true
						local max_idx = 0
						for k, _ in pairs(val) do
							if type(k) ~= "number" then
								is_array = false
								break
							end
							if k > max_idx then
								max_idx = k
							end
						end
						if is_array and max_idx == #val then
							local parts = {}
							for _, v in ipairs(val) do
								table.insert(parts, encode_value(v))
							end
							return "[" .. table.concat(parts, ",") .. "]"
						else
							local parts = {}
							for k, v in pairs(val) do
								table.insert(parts, '"' .. tostring(k) .. '":' .. encode_value(v))
							end
							return "{" .. table.concat(parts, ",") .. "}"
						end
					end
					return "null"
				end
				return encode_value(data)
			end,
			decode = function(str)
				-- Minimal JSON decoder for test data
				local pos = 1
				local function skip_whitespace()
					while pos <= #str and str:sub(pos, pos):match("%s") do
						pos = pos + 1
					end
				end
				local decode_value
				local function decode_string()
					pos = pos + 1 -- skip opening quote
					local start = pos
					while pos <= #str and str:sub(pos, pos) ~= '"' do
						if str:sub(pos, pos) == "\\" then
							pos = pos + 1
						end
						pos = pos + 1
					end
					local s = str:sub(start, pos - 1)
					pos = pos + 1 -- skip closing quote
					return s
				end
				local function decode_number()
					local start = pos
					if str:sub(pos, pos) == "-" then
						pos = pos + 1
					end
					while pos <= #str and str:sub(pos, pos):match("[%d%.eE%+%-]") do
						pos = pos + 1
					end
					return tonumber(str:sub(start, pos - 1))
				end
				local function decode_object()
					pos = pos + 1 -- skip {
					local obj = {}
					skip_whitespace()
					if str:sub(pos, pos) == "}" then
						pos = pos + 1
						return obj
					end
					while true do
						skip_whitespace()
						local key = decode_string()
						skip_whitespace()
						pos = pos + 1 -- skip :
						skip_whitespace()
						obj[key] = decode_value()
						skip_whitespace()
						if str:sub(pos, pos) == "}" then
							pos = pos + 1
							return obj
						end
						pos = pos + 1 -- skip ,
					end
				end
				local function decode_array()
					pos = pos + 1 -- skip [
					local arr = {}
					skip_whitespace()
					if str:sub(pos, pos) == "]" then
						pos = pos + 1
						return arr
					end
					while true do
						skip_whitespace()
						table.insert(arr, decode_value())
						skip_whitespace()
						if str:sub(pos, pos) == "]" then
							pos = pos + 1
							return arr
						end
						pos = pos + 1 -- skip ,
					end
				end
				decode_value = function()
					skip_whitespace()
					local c = str:sub(pos, pos)
					if c == '"' then
						return decode_string()
					elseif c == "{" then
						return decode_object()
					elseif c == "[" then
						return decode_array()
					elseif c == "t" then
						pos = pos + 4
						return true
					elseif c == "f" then
						pos = pos + 5
						return false
					elseif c == "n" then
						pos = pos + 4
						return nil
					else
						return decode_number()
					end
				end
				return decode_value()
			end,
		},
		canvas = {
			windowLevels = {
				floating = "floating",
				overlay = "overlay",
			},
			new = function(frame)
				local c = {
					frameData = frame,
					visible = false,
					deleted = false,
					elements = {},
					alphaValue = 1,
				}
				function c:level()
					return self
				end
				function c:behavior()
					return self
				end
				function c:appendElements(element)
					table.insert(self.elements, element)
					return self
				end
				function c:elementCount()
					return #self.elements
				end
				function c:removeElement(idx)
					table.remove(self.elements, idx)
					return self
				end
				function c:elementAttribute(idx, key, value)
					if value == nil then
						return self.elements[idx] and self.elements[idx][key]
					end
					if self.elements[idx] then
						self.elements[idx][key] = value
					end
					return self
				end
				function c:mouseCallback()
					return self
				end
				function c:alpha(value)
					if value == nil then
						return self.alphaValue
					end
					self.alphaValue = value
					return self
				end
				function c:frame()
					return self.frameData
				end
				function c:show()
					self.visible = true
					return self
				end
				function c:delete()
					self.deleted = true
				end
				table.insert(state.canvases, c)
				return c
			end,
		},
		image = {
			imageFromPath = function(path)
				table.insert(state.image.pathRequests, path)
				return state.image.pathResults[path]
			end,
			imageFromURL = function(url, callback)
				table.insert(state.image.urlRequests, {
					url = url,
					callback = callback,
				})
				if callback then
					return nil
				end
				return state.image.urlResults[url]
			end,
		},
		screen = {
			mainScreen = function()
				return {
					frame = function()
						return { x = 0, y = 0, w = 1920, h = 1080 }
					end,
					fullFrame = function()
						return { x = 0, y = 0, w = 1920, h = 1080 }
					end,
				}
			end,
			allScreens = function()
				return {
					{
						frame = function()
							return { x = 0, y = 0, w = 1920, h = 1080 }
						end,
						fullFrame = function()
							return { x = 0, y = 0, w = 1920, h = 1080 }
						end,
					},
				}
			end,
		},
		eventtap = {
			new = function(types, fn)
				local tap = {
					types = types,
					callback = fn,
					running = false,
				}
				function tap:start()
					self.running = true
					return self
				end
				function tap:stop()
					self.running = false
					return self
				end
				table.insert(state.eventtaps, tap)
				return tap
			end,
			event = {
				types = {
					keyDown = "keyDown",
					leftMouseDown = "leftMouseDown",
				},
			},
		},
		application = {
			get = function(_)
				return {
					activate = function() end,
				}
			end,
		},
		dialog = {
			textPrompt = function(title, message, defaultValue, ok, cancel)
				table.insert(state.dialog.prompts, {
					title = title,
					message = message,
					defaultValue = defaultValue,
					ok = ok,
					cancel = cancel,
				})
				return state.dialog.nextResult[1], state.dialog.nextResult[2]
			end,
		},
		pasteboard = {
			setContents = function(text)
				state.pasteboard.contents = text
			end,
		},
		spoons = {
			resourcePath = function(path)
				return "./Kokukoku.spoon/" .. path
			end,
		},
	}

	return {
		hs = hs,
		state = state,
	}
end

return M
