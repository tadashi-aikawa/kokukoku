local hsMock = require("spec.helpers.hs_mock")

describe("persistence", function()
	local persistenceModule
	local mock
	local testPath = "/tmp/kokukoku_test_state.json"

	before_each(function()
		mock = hsMock.new()
		_G.hs = mock.hs
		persistenceModule = dofile("./Kokukoku.spoon/persistence.lua")
		os.remove(testPath)
	end)

	after_each(function()
		_G.hs = nil
		os.remove(testPath)
	end)

	describe("save and load", function()
		it("状態を保存して読み込める", function()
			local persistence = persistenceModule.new({ path = testPath })
			local state = {
				accumulated = { ["proj-a"] = 3600 },
				activeProjectId = "proj-a",
				activeStartedAt = 1000000,
				continuousStartedAt = 999000,
				lastResetAt = 990000,
			}

			persistence.save(state)
			local loaded = persistence.load()

			assert.is_not_nil(loaded)
			assert.are.equal(3600, loaded.accumulated["proj-a"])
			assert.are.equal("proj-a", loaded.activeProjectId)
			assert.are.equal(1000000, loaded.activeStartedAt)
			assert.are.equal(999000, loaded.continuousStartedAt)
			assert.are.equal(990000, loaded.lastResetAt)
		end)

		it("ファイルが存在しない場合はnilを返す", function()
			local persistence = persistenceModule.new({ path = testPath })
			local loaded = persistence.load()
			assert.is_nil(loaded)
		end)

		it("空のaccumulatedを保存・読み込める", function()
			local persistence = persistenceModule.new({ path = testPath })
			local state = {
				accumulated = {},
				activeProjectId = nil,
				activeStartedAt = nil,
				continuousStartedAt = nil,
				lastResetAt = 990000,
			}

			persistence.save(state)
			local loaded = persistence.load()

			assert.is_not_nil(loaded)
		end)
	end)
end)
