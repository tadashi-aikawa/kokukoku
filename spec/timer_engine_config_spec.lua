local hsMock = require("spec.helpers.hs_mock")

describe("timer_engine_config", function()
	local config

	before_each(function()
		local mock = hsMock.new()
		_G.hs = mock.hs
		config = dofile("./Kokukoku.spoon/timer_engine_config.lua")
	end)

	after_each(function()
		_G.hs = nil
	end)

	describe("build", function()
		it("デフォルト設定で構築できる", function()
			local result = config.build({})
			assert.are.equal(1, result.tickInterval)
			assert.are.same({}, result.projects)
		end)

		it("プロジェクトを設定できる", function()
			local projects = {
				{ id = "proj-a", name = "Project A", icon = "🔵" },
				{ id = "proj-b", name = "Project B" },
			}
			local result = config.build({ projects = projects })
			assert.are.equal(2, #result.projects)
			assert.are.equal("proj-a", result.projects[1].id)
		end)

		it("tickIntervalを設定できる", function()
			local result = config.build({ tickInterval = 5 })
			assert.are.equal(5, result.tickInterval)
		end)

		it("projectsがテーブルでない場合はエラー", function()
			assert.has_error(function()
				config.build({ projects = "invalid" })
			end)
		end)

		it("プロジェクトのidが空文字の場合はエラー", function()
			assert.has_error(function()
				config.build({ projects = { { id = "", name = "A" } } })
			end)
		end)

		it("プロジェクトのnameが空文字の場合はエラー", function()
			assert.has_error(function()
				config.build({ projects = { { id = "a", name = "" } } })
			end)
		end)

		it("プロジェクトのiconが文字列以外の場合はエラー", function()
			assert.has_error(function()
				config.build({ projects = { { id = "a", name = "A", icon = 1 } } })
			end)
		end)

		it("重複するプロジェクトIDはエラー", function()
			assert.has_error(function()
				config.build({
					projects = {
						{ id = "a", name = "A" },
						{ id = "a", name = "B" },
					},
				})
			end)
		end)

		it("コールバックを設定できる", function()
			local fn = function() end
			local result = config.build({
				onStateChange = fn,
				onTick = fn,
				onAlert = fn,
			})
			assert.are.equal(fn, result.onStateChange)
			assert.are.equal(fn, result.onTick)
			assert.are.equal(fn, result.onAlert)
		end)
	end)
end)
