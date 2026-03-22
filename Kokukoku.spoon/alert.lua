local M = {}

local DEFAULTS = {
	continuousWork = {
		thresholds = {},
		message = "%d分経過しました。休憩しましょう",
	},
}

function M.new(options)
	options = options or {}

	local continuousConfig = options.continuousWork or DEFAULTS.continuousWork
	local thresholds = continuousConfig.thresholds or DEFAULTS.continuousWork.thresholds
	local messageTemplate = continuousConfig.message or DEFAULTS.continuousWork.message

	local notifiedThresholds = {}

	local function check(state)
		if not state.continuousStartedAt then
			notifiedThresholds = {}
			return
		end

		local elapsed = os.time() - state.continuousStartedAt

		for _, threshold in ipairs(thresholds) do
			if elapsed >= threshold and not notifiedThresholds[threshold] then
				notifiedThresholds[threshold] = true
				local minutes = math.floor(threshold / 60)
				local message = string.format(messageTemplate, minutes)
				if hs and hs.notify then
					hs.notify.new({ title = "刻刻", informativeText = message }):send()
				end
			end
		end
	end

	local function resetNotifications()
		notifiedThresholds = {}
	end

	return {
		check = check,
		resetNotifications = resetNotifications,
	}
end

return M
