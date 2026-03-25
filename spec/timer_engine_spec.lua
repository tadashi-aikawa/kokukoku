local hsMock = require("spec.helpers.hs_mock")

describe("timer_engine", function()
	local timerEngine
	local mock

	local projects = {
		{ id = "proj-a", name = "Project A", icon = "🔵" },
		{ id = "proj-b", name = "Project B", icon = "🟢" },
		{ id = "break", name = "休憩", icon = "☕", isBreak = true },
	}

	before_each(function()
		mock = hsMock.new()
		_G.hs = mock.hs
		timerEngine = dofile("./Kokukoku.spoon/timer_engine.lua")
	end)

	after_each(function()
		_G.hs = nil
	end)

	describe("formatTime", function()
		it("0秒を00:00:00に変換", function()
			assert.are.equal("00:00:00", timerEngine.formatTime(0))
		end)

		it("3661秒を01:01:01に変換", function()
			assert.are.equal("01:01:01", timerEngine.formatTime(3661))
		end)

		it("nilの場合は00:00:00", function()
			assert.are.equal("00:00:00", timerEngine.formatTime(nil))
		end)

		it("負の値の場合は00:00:00", function()
			assert.are.equal("00:00:00", timerEngine.formatTime(-1))
		end)
	end)

	describe("new", function()
		it("エンジンを生成できる", function()
			local engine = timerEngine.new({ projects = projects })
			assert.is_not_nil(engine)
			assert.is_not_nil(engine.startProject)
			assert.is_not_nil(engine.startBreak)
			assert.is_not_nil(engine.reset)
			assert.is_not_nil(engine.getState)
			assert.is_not_nil(engine.getSnapshot)
			assert.is_not_nil(engine.teardown)
		end)

		it("初期状態ではアクティブなプロジェクトがない", function()
			local engine = timerEngine.new({ projects = projects })
			local state = engine.getState()
			assert.is_nil(state.activeProjectId)
			assert.is_nil(state.activeStartedAt)
			assert.are.equal(0, state.continuousElapsedBase)
			assert.is_nil(state.continuousStartedAt)
		end)
	end)

	describe("startProject", function()
		it("プロジェクトを開始できる", function()
			local engine = timerEngine.new({ projects = projects })
			engine.startProject("proj-a")
			local state = engine.getState()
			assert.are.equal("proj-a", state.activeProjectId)
			assert.is_not_nil(state.activeStartedAt)
			assert.is_not_nil(state.continuousStartedAt)
		end)

		it("プロジェクトを切り替えできる", function()
			local engine = timerEngine.new({ projects = projects })
			engine.startProject("proj-a")
			engine.startProject("proj-b")
			local state = engine.getState()
			assert.are.equal("proj-b", state.activeProjectId)
		end)

		it("切り替え時に前プロジェクトの時間が積み上げられる", function()
			local engine = timerEngine.new({ projects = projects })
			engine.startProject("proj-a")
			-- 時刻を手動で設定してテスト
			local state = engine.getState()
			state.activeStartedAt = os.time() - 100
			engine.startProject("proj-b")
			state = engine.getState()
			assert.is_true((state.accumulated["proj-a"] or 0) >= 99)
		end)

		it("存在しないプロジェクトIDは無視される", function()
			local engine = timerEngine.new({ projects = projects })
			engine.startProject("nonexistent")
			local state = engine.getState()
			assert.is_nil(state.activeProjectId)
		end)

		it("休憩プロジェクトを選ぶと計測停止", function()
			local engine = timerEngine.new({ projects = projects })
			engine.startProject("proj-a")
			engine.startProject("break")
			local state = engine.getState()
			assert.is_nil(state.activeProjectId)
			assert.are.equal(0, state.continuousElapsedBase)
			assert.is_nil(state.continuousStartedAt)
		end)

		it("onStateChangeコールバックが呼ばれる", function()
			local called = false
			local engine = timerEngine.new({
				projects = projects,
				onStateChange = function()
					called = true
				end,
			})
			engine.startProject("proj-a")
			assert.is_true(called)
		end)
	end)

	describe("startBreak", function()
		it("計測を停止し連続作業時間をリセットする", function()
			local engine = timerEngine.new({ projects = projects })
			engine.startProject("proj-a")
			engine.startBreak()
			local state = engine.getState()
			assert.is_nil(state.activeProjectId)
			assert.are.equal(0, state.continuousElapsedBase)
			assert.is_nil(state.continuousStartedAt)
		end)

		it("休憩中に編集した継続時間を再開時に引き継ぐ", function()
			local engine = timerEngine.new({ projects = projects })
			engine.startProject("proj-a")
			engine.startBreak()
			engine.setContinuousElapsed(600)
			engine.startProject("proj-b")
			local state = engine.getState()
			local snapshot = engine.getSnapshot()
			assert.are.equal(600, state.continuousElapsedBase)
			assert.is_not_nil(state.continuousStartedAt)
			assert.is_true(snapshot.continuousElapsed >= 600)
		end)
	end)

	describe("reset", function()
		it("全てのデータをクリアする", function()
			local engine = timerEngine.new({ projects = projects })
			engine.startProject("proj-a")
			engine.reset()
			local state = engine.getState()
			assert.is_nil(state.activeProjectId)
			assert.are.equal(0, state.continuousElapsedBase)
			assert.is_nil(state.continuousStartedAt)
			assert.are.same({}, state.accumulated)
		end)
	end)

	describe("getSnapshot", function()
		it("プロジェクトのスナップショットを取得できる", function()
			local engine = timerEngine.new({ projects = projects })
			engine.startProject("proj-a")
			local snapshot = engine.getSnapshot()
			assert.are.equal(2, #snapshot.projects) -- 休憩を除く
			assert.is_true(snapshot.isRunning)
			assert.are.equal("proj-a", snapshot.activeProjectId)
		end)

		it("休憩プロジェクトはスナップショットに含まれない", function()
			local engine = timerEngine.new({ projects = projects })
			local snapshot = engine.getSnapshot()
			for _, p in ipairs(snapshot.projects) do
				assert.are_not.equal("break", p.id)
			end
		end)
	end)

	describe("initialState", function()
		it("初期状態を復元できる", function()
			local engine = timerEngine.new({
				projects = projects,
				initialState = {
					accumulated = { ["proj-a"] = 3600 },
					activeProjectId = "proj-a",
					activeStartedAt = os.time() - 100,
					continuousElapsedBase = 120,
					continuousStartedAt = os.time() - 200,
				},
			})
			local state = engine.getState()
			assert.are.equal(3600, state.accumulated["proj-a"])
			assert.are.equal("proj-a", state.activeProjectId)
			assert.are.equal(120, state.continuousElapsedBase)
		end)
	end)

	describe("setAccumulated", function()
		it("累積時間を設定できる", function()
			local engine = timerEngine.new({ projects = projects })
			local result = engine.setAccumulated("proj-a", 3600)
			assert.is_true(result)
			assert.are.equal(3600, engine.getState().accumulated["proj-a"])
		end)

		it("存在しないプロジェクトIDではfalseを返す", function()
			local engine = timerEngine.new({ projects = projects })
			local result = engine.setAccumulated("nonexistent", 100)
			assert.is_false(result)
		end)

		it("休憩プロジェクトではfalseを返す", function()
			local engine = timerEngine.new({ projects = projects })
			local result = engine.setAccumulated("break", 100)
			assert.is_false(result)
		end)

		it("負の値ではfalseを返す", function()
			local engine = timerEngine.new({ projects = projects })
			local result = engine.setAccumulated("proj-a", -1)
			assert.is_false(result)
		end)

		it("計測中プロジェクトに設定するとactiveStartedAtがリセットされる", function()
			local engine = timerEngine.new({ projects = projects })
			engine.startProject("proj-a")
			local state = engine.getState()
			state.activeStartedAt = os.time() - 100
			engine.setAccumulated("proj-a", 7200)
			state = engine.getState()
			assert.are.equal(7200, state.accumulated["proj-a"])
			assert.is_true(math.abs(state.activeStartedAt - os.time()) <= 1)
		end)

		it("onStateChangeコールバックが呼ばれる", function()
			local called = false
			local engine = timerEngine.new({
				projects = projects,
				onStateChange = function()
					called = true
				end,
			})
			called = false
			engine.setAccumulated("proj-a", 1000)
			assert.is_true(called)
		end)

		it("小数は切り捨てられる", function()
			local engine = timerEngine.new({ projects = projects })
			engine.setAccumulated("proj-a", 3661.7)
			assert.are.equal(3661, engine.getState().accumulated["proj-a"])
		end)

		it("0秒に設定できる", function()
			local engine = timerEngine.new({ projects = projects })
			engine.setAccumulated("proj-a", 3600)
			engine.setAccumulated("proj-a", 0)
			assert.are.equal(0, engine.getState().accumulated["proj-a"])
		end)
	end)

	describe("setContinuousElapsed", function()
		it("連続稼働中に時間を設定できる", function()
			local engine = timerEngine.new({ projects = projects })
			engine.startProject("proj-a")
			local result = engine.setContinuousElapsed(3600)
			assert.is_true(result)
			local state = engine.getState()
			assert.are.equal(3600, state.continuousElapsedBase)
			assert.is_true(math.abs(state.continuousStartedAt - os.time()) <= 1)
		end)

		it("停止中でも時間を設定できる", function()
			local engine = timerEngine.new({ projects = projects })
			local result = engine.setContinuousElapsed(100)
			assert.is_true(result)
			local state = engine.getState()
			assert.are.equal(100, state.continuousElapsedBase)
			assert.is_nil(state.continuousStartedAt)
		end)

		it("負の値ではfalseを返す", function()
			local engine = timerEngine.new({ projects = projects })
			engine.startProject("proj-a")
			local result = engine.setContinuousElapsed(-1)
			assert.is_false(result)
		end)

		it("小数は切り捨てられる", function()
			local engine = timerEngine.new({ projects = projects })
			engine.startProject("proj-a")
			engine.setContinuousElapsed(3661.7)
			local state = engine.getState()
			assert.are.equal(3661, state.continuousElapsedBase)
			assert.is_true(math.abs(state.continuousStartedAt - os.time()) <= 1)
		end)

		it("onStateChangeコールバックが呼ばれる", function()
			local called = false
			local engine = timerEngine.new({
				projects = projects,
				onStateChange = function()
					called = true
				end,
			})
			engine.startProject("proj-a")
			called = false
			engine.setContinuousElapsed(1000)
			assert.is_true(called)
		end)

		it("0秒に設定できる", function()
			local engine = timerEngine.new({ projects = projects })
			engine.startProject("proj-a")
			local result = engine.setContinuousElapsed(0)
			assert.is_true(result)
			local state = engine.getState()
			assert.are.equal(0, state.continuousElapsedBase)
			assert.is_true(math.abs(os.time() - state.continuousStartedAt) <= 1)
		end)

		it("休憩で停止後も時間を設定できる", function()
			local engine = timerEngine.new({ projects = projects })
			engine.startProject("proj-a")
			engine.startBreak()
			local result = engine.setContinuousElapsed(100)
			assert.is_true(result)
			local state = engine.getState()
			assert.are.equal(100, state.continuousElapsedBase)
			assert.is_nil(state.continuousStartedAt)
		end)
	end)

	describe("teardown", function()
		it("タイマーを停止する", function()
			local engine = timerEngine.new({ projects = projects })
			engine.teardown()
			assert.is_true(mock.state.timers[1].stopped)
		end)
	end)
end)
