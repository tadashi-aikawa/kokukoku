local hsMock = require("spec.helpers.hs_mock")

describe("persistence", function()
	local persistenceModule
	local mock
	local testPath = "/tmp/kokukoku_test_state.json"
	local originalGetenv

	before_each(function()
		mock = hsMock.new()
		_G.hs = mock.hs
		originalGetenv = os.getenv
		persistenceModule = dofile("./Kokukoku.spoon/persistence.lua")
		os.remove(testPath)
	end)

	after_each(function()
		_G.hs = nil
		os.getenv = originalGetenv
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

		it("ホームディレクトリ付きパスを展開して保存・読込できる", function()
			local fakeHome = "/tmp/kokukoku-home"
			local expandedPath = fakeHome .. "/state.json"
			local persistence = nil
			local state = {
				accumulated = { ["proj-a"] = 1800 },
				activeProjectId = nil,
				activeStartedAt = nil,
				continuousStartedAt = nil,
				lastResetAt = 990000,
			}

			os.getenv = function(name)
				if name == "HOME" then
					return fakeHome
				end
				return originalGetenv(name)
			end
			os.execute('mkdir -p "' .. fakeHome .. '"')
			os.remove(expandedPath)

			persistence = persistenceModule.new({ path = "~/state.json" })
			persistence.save(state)

			local file = io.open(expandedPath, "r")
			assert.is_not_nil(file)
			if file then
				file:close()
			end

			local loaded = persistence.load()
			assert.is_not_nil(loaded)
			assert.are.equal(1800, loaded.accumulated["proj-a"])

			os.remove(expandedPath)
			os.execute('rmdir "' .. fakeHome .. '"')
		end)
	end)
end)
