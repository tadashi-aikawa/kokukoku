local M = {}

local DEFAULTS = {
	path = os.getenv("HOME") .. "/.kokukoku/state.json",
}

function M.new(options)
	options = options or {}
	local filePath = options.path or DEFAULTS.path

	local function ensureDir()
		local dir = filePath:match("(.+)/[^/]+$")
		if dir then
			os.execute('mkdir -p "' .. dir .. '"')
		end
	end

	local function save(state)
		ensureDir()

		local data = {
			accumulated = state.accumulated,
			activeProjectId = state.activeProjectId,
			activeStartedAt = state.activeStartedAt,
			continuousStartedAt = state.continuousStartedAt,
			lastResetAt = state.lastResetAt,
		}

		local json = hs.json.encode(data, true)
		local file = io.open(filePath, "w")
		if file then
			file:write(json)
			file:close()
		end
	end

	local function load()
		local file = io.open(filePath, "r")
		if not file then
			return nil
		end

		local content = file:read("*a")
		file:close()

		if not content or content == "" then
			return nil
		end

		local ok, data = pcall(hs.json.decode, content)
		if not ok or type(data) ~= "table" then
			return nil
		end

		return data
	end

	return {
		save = save,
		load = load,
	}
end

return M
