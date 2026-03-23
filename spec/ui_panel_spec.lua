local hsMock = require("spec.helpers.hs_mock")

local function findElement(elements, matcher)
	for _, element in ipairs(elements) do
		if matcher(element) then
			return element
		end
	end
	return nil
end

describe("ui_panel", function()
	local uiPanel
	local mock
	local state

	before_each(function()
		mock = hsMock.new()
		_G.hs = mock.hs
		state = {
			accumulated = {},
			activeProjectId = nil,
			activeStartedAt = nil,
			continuousStartedAt = nil,
		}
		uiPanel = dofile("./Kokukoku.spoon/ui_panel.lua")
	end)

	after_each(function()
		_G.hs = nil
	end)

	local function newPanel(projects)
		return uiPanel.new({
			projects = projects,
			getState = function()
				return state
			end,
		})
	end

	it("絵文字iconはテキストとして表示する", function()
		local panel = newPanel({
			{ id = "proj-a", name = "Project A", icon = "🔵" },
		})

		panel.show()

		local elements = mock.state.canvases[1].elements
		assert.is_not_nil(findElement(elements, function(element)
			return element.type == "text" and element.text == "🔵"
		end))
		assert.is_not_nil(findElement(elements, function(element)
			return element.type == "text" and element.text == "Project A"
		end))
	end)

	it("ローカルファイルiconは画像として表示する", function()
		local image = { id = "local-image" }
		mock.state.image.pathResults["/tmp/project.png"] = image
		local panel = newPanel({
			{ id = "proj-a", name = "Project A", icon = "/tmp/project.png" },
		})

		panel.show()

		assert.is_true(#mock.state.image.pathRequests >= 1)
		assert.is_not_nil(findElement(mock.state.image.pathRequests, function(path)
			return path == "/tmp/project.png"
		end))

		local elements = mock.state.canvases[1].elements
		assert.is_not_nil(findElement(elements, function(element)
			return element.type == "image" and element.image == image and element.frame.y > 44
		end))
		assert.is_nil(findElement(elements, function(element)
			return element.type == "text" and element.text == "/tmp/project.png"
		end))
	end)

	it("ホームディレクトリ付きパスを展開して画像を読む", function()
		local home = os.getenv("HOME")
		assert.is_truthy(home)
		local resolvedPath = home .. "/project.png"
		mock.state.image.pathResults[resolvedPath] = { id = "home-image" }
		local panel = newPanel({
			{ id = "proj-a", name = "Project A", icon = "~/project.png" },
		})

		panel.show()

		assert.is_not_nil(findElement(mock.state.image.pathRequests, function(path)
			return path == resolvedPath
		end))
	end)

	it("URL iconは非同期で一度だけ取得して表示する", function()
		local url = "https://example.com/project.png"
		local panel = newPanel({
			{ id = "proj-a", name = "Project A", icon = url },
		})

		panel.show()
		panel.update({})

		assert.are.equal(1, #mock.state.image.urlRequests)
		assert.are.equal(url, mock.state.image.urlRequests[1].url)

		local beforeElements = mock.state.canvases[1].elements
		assert.is_nil(findElement(beforeElements, function(element)
			return element.type == "image" and element.frame.y > 44
		end))

		local image = { id = "remote-image" }
		mock.state.image.urlRequests[1].callback(image)

		local afterElements = mock.state.canvases[1].elements
		assert.is_not_nil(findElement(afterElements, function(element)
			return element.type == "image" and element.image == image and element.frame.y > 44
		end))

		panel.update({})
		assert.are.equal(1, #mock.state.image.urlRequests)
	end)

	it("画像取得に失敗してもパス文字列は表示しない", function()
		local panel = newPanel({
			{ id = "proj-a", name = "Project A", icon = "https://example.com/missing.png" },
		})

		panel.show()
		mock.state.image.urlRequests[1].callback(nil)

		local elements = mock.state.canvases[1].elements
		assert.is_not_nil(findElement(elements, function(element)
			return element.type == "text" and element.text == "Project A"
		end))
		assert.is_nil(findElement(elements, function(element)
			return element.type == "text" and element.text == "https://example.com/missing.png"
		end))
	end)

	describe("parseTime", function()
		it('"01:30:00" を 5400秒に変換', function()
			assert.are.equal(5400, uiPanel.parseTime("01:30:00"))
		end)

		it('"00:05:30" を 330秒に変換', function()
			assert.are.equal(330, uiPanel.parseTime("00:05:30"))
		end)

		it('"5:30" を 330秒に変換', function()
			assert.are.equal(330, uiPanel.parseTime("5:30"))
		end)

		it('"3600" を 3600秒に変換', function()
			assert.are.equal(3600, uiPanel.parseTime("3600"))
		end)

		it("空文字はnilを返す", function()
			assert.is_nil(uiPanel.parseTime(""))
		end)

		it("nilはnilを返す", function()
			assert.is_nil(uiPanel.parseTime(nil))
		end)

		it("不正な文字列はnilを返す", function()
			assert.is_nil(uiPanel.parseTime("abc"))
		end)

		it('"00:00:00" を 0秒に変換', function()
			assert.are.equal(0, uiPanel.parseTime("00:00:00"))
		end)
	end)

	describe("buildCopyText", function()
		local formatTime

		before_each(function()
			formatTime = dofile("./Kokukoku.spoon/timer_engine.lua").formatTime
		end)

		it("累積時間のあるプロジェクトのみ箇条書きにする", function()
			local projects = {
				{ id = "a", name = "ProjectA" },
				{ id = "b", name = "ProjectB" },
				{ id = "c", name = "ProjectC" },
			}
			local s = {
				accumulated = { a = 3600, b = 0, c = 1830 },
				activeProjectId = nil,
				activeStartedAt = nil,
			}

			local result = uiPanel.buildCopyText(projects, s, formatTime)
			assert.are.equal("- ProjectA: 01:00:00\n- ProjectC: 00:30:30", result)
		end)

		it("全プロジェクトの累積が0なら空文字を返す", function()
			local projects = {
				{ id = "a", name = "ProjectA" },
			}
			local s = {
				accumulated = {},
				activeProjectId = nil,
				activeStartedAt = nil,
			}

			local result = uiPanel.buildCopyText(projects, s, formatTime)
			assert.are.equal("", result)
		end)

		it("アクティブなプロジェクトの経過時間を含める", function()
			local now = os.time()
			local projects = {
				{ id = "a", name = "ProjectA" },
			}
			local s = {
				accumulated = { a = 3600 },
				activeProjectId = "a",
				activeStartedAt = now - 60,
			}

			local result = uiPanel.buildCopyText(projects, s, formatTime)
			assert.are.equal("- ProjectA: 01:01:00", result)
		end)
	end)

	it("休憩ボタンは設定したiconと名前を表示する", function()
		local panel = newPanel({
			{ id = "proj-a", name = "Project A", icon = "🔵" },
			{ id = "break", name = "深呼吸", icon = "🫖", isBreak = true },
		})

		panel.show()

		local elements = mock.state.canvases[1].elements
		assert.is_not_nil(findElement(elements, function(element)
			return element.type == "text" and element.text == "🫖"
		end))
		assert.is_not_nil(findElement(elements, function(element)
			return element.type == "text" and element.text == "深呼吸"
		end))
		assert.is_nil(findElement(elements, function(element)
			return element.type == "text" and element.text == "☕ 休憩"
		end))
	end)
end)
