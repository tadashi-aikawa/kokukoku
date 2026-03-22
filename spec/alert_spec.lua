local hsMock = require("spec.helpers.hs_mock")

describe("alert", function()
	local alertModule
	local mock

	before_each(function()
		mock = hsMock.new()
		_G.hs = mock.hs
		alertModule = dofile("./Kokukoku.spoon/alert.lua")
	end)

	after_each(function()
		_G.hs = nil
	end)

	describe("check", function()
		it("閾値を超えると通知が送られる", function()
			local alert = alertModule.new({
				continuousWork = {
					thresholds = { 10 },
					message = "%d分経過",
				},
			})

			alert.check({
				continuousStartedAt = os.time() - 15,
			})

			assert.are.equal(1, #mock.state.notifications)
			assert.is_true(mock.state.notifications[1].sent)
		end)

		it("閾値に達していない場合は通知しない", function()
			local alert = alertModule.new({
				continuousWork = {
					thresholds = { 100 },
				},
			})

			alert.check({
				continuousStartedAt = os.time() - 10,
			})

			assert.are.equal(0, #mock.state.notifications)
		end)

		it("同じ閾値では重複通知しない", function()
			local alert = alertModule.new({
				continuousWork = {
					thresholds = { 10 },
					message = "%d分経過",
				},
			})

			local state = { continuousStartedAt = os.time() - 15 }
			alert.check(state)
			alert.check(state)

			assert.are.equal(1, #mock.state.notifications)
		end)

		it("連続作業が停止している場合は通知フラグをリセットする", function()
			local alert = alertModule.new({
				continuousWork = {
					thresholds = { 10 },
					message = "%d分経過",
				},
			})

			alert.check({ continuousStartedAt = os.time() - 15 })
			assert.are.equal(1, #mock.state.notifications)

			-- 休憩（continuousStartedAt = nil）
			alert.check({ continuousStartedAt = nil })

			-- 再開後に再度通知される
			alert.check({ continuousStartedAt = os.time() - 15 })
			assert.are.equal(2, #mock.state.notifications)
		end)

		it("複数閾値に対応する", function()
			local alert = alertModule.new({
				continuousWork = {
					thresholds = { 10, 20 },
					message = "%d分経過",
				},
			})

			alert.check({ continuousStartedAt = os.time() - 25 })
			assert.are.equal(2, #mock.state.notifications)
		end)
	end)

	describe("resetNotifications", function()
		it("通知フラグをリセットできる", function()
			local alert = alertModule.new({
				continuousWork = {
					thresholds = { 10 },
					message = "%d分経過",
				},
			})

			alert.check({ continuousStartedAt = os.time() - 15 })
			alert.resetNotifications()
			alert.check({ continuousStartedAt = os.time() - 15 })

			assert.are.equal(2, #mock.state.notifications)
		end)
	end)
end)
