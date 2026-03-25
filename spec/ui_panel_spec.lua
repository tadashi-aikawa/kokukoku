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
			continuousElapsedBase = 0,
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

	local function keyEvent(char, keyCode)
		return {
			getCharacters = function()
				return char
			end,
			getKeyCode = function()
				return keyCode or 0
			end,
		}
	end

	it("showVersionByDefault=trueならヘッダー右上に控えめなバージョンを表示する", function()
		local panel = uiPanel.new({
			projects = {
				{ id = "proj-a", name = "Project A", icon = "🔵" },
			},
			versionText = "v0.5.0",
			showVersionByDefault = true,
			getState = function()
				return state
			end,
		})

		panel.show()

		local elements = mock.state.canvases[1].elements
		assert.is_not_nil(findElement(elements, function(element)
			return element.type == "text"
				and element.text == "v0.5.0"
				and element.frame.y < 12
				and element.textAlignment == "right"
		end))
	end)

	it("showVersionByDefault未指定ならデフォルトでバージョンを表示しない", function()
		local panel = uiPanel.new({
			projects = {
				{ id = "proj-a", name = "Project A", icon = "🔵" },
			},
			versionText = "v0.5.0",
			getState = function()
				return state
			end,
		})

		panel.show()

		local elements = mock.state.canvases[1].elements
		assert.is_nil(findElement(elements, function(element)
			return element.type == "text" and element.text == "v0.5.0"
		end))
	end)

	it("vキーでバージョン表示を切り替える", function()
		local panel = uiPanel.new({
			projects = {
				{ id = "proj-a", name = "Project A", icon = "🔵" },
			},
			versionText = "v0.5.0",
			getState = function()
				return state
			end,
		})

		panel.show()

		local keyTap = mock.state.eventtaps[1]
		assert.is_not_nil(keyTap)
		assert.is_false(findElement(mock.state.canvases[1].elements, function(element)
			return element.type == "text" and element.text == "v0.5.0"
		end) ~= nil)

		assert.is_true(keyTap.callback(keyEvent("v")))
		assert.is_not_nil(findElement(mock.state.canvases[1].elements, function(element)
			return element.type == "text" and element.text == "v0.5.0"
		end))

		assert.is_true(keyTap.callback(keyEvent("v")))
		assert.is_nil(findElement(mock.state.canvases[1].elements, function(element)
			return element.type == "text" and element.text == "v0.5.0"
		end))
	end)

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

	it("初期待機状態でもヘッダーに00:00:00を表示する", function()
		local panel = newPanel({
			{ id = "proj-a", name = "Project A", icon = "🔵" },
		})

		panel.show()

		local elements = mock.state.canvases[1].elements
		assert.is_not_nil(findElement(elements, function(element)
			return element.type == "text" and element.text == "00:00:00"
		end))
	end)

	it("停止中は基準継続時間をヘッダーに表示する", function()
		state.continuousElapsedBase = 600
		local panel = newPanel({
			{ id = "proj-a", name = "Project A", icon = "🔵" },
		})

		panel.show()

		local elements = mock.state.canvases[1].elements
		assert.is_not_nil(findElement(elements, function(element)
			return element.type == "text" and element.text == "00:10:00"
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

			local result = uiPanel.buildCopyText(projects, s)
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

			local result = uiPanel.buildCopyText(projects, s)
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

			local result = uiPanel.buildCopyText(projects, s)
			assert.are.equal("- ProjectA: 01:01:00", result)
		end)

		it("カスタムフォーマットで行が生成される", function()
			local projects = {
				{ id = "a", name = "ProjectA" },
				{ id = "b", name = "ProjectB" },
			}
			local s = {
				accumulated = { a = 3600, b = 1830 },
				activeProjectId = nil,
				activeStartedAt = nil,
			}

			local result = uiPanel.buildCopyText(projects, s, "{name} ({hh}:{mm})")
			assert.are.equal("ProjectA (01:00)\nProjectB (00:30)", result)
		end)

		it("カスタム区切り文字で結合される", function()
			local projects = {
				{ id = "a", name = "ProjectA" },
				{ id = "b", name = "ProjectB" },
			}
			local s = {
				accumulated = { a = 3600, b = 1830 },
				activeProjectId = nil,
				activeStartedAt = nil,
			}

			local result = uiPanel.buildCopyText(projects, s, "{name}: {hh}:{mm}", " / ")
			assert.are.equal("ProjectA: 01:00 / ProjectB: 00:30", result)
		end)

		it("ゼロ埋めなしプレースホルダーが正しく動作する", function()
			local projects = {
				{ id = "a", name = "ProjectA" },
			}
			local s = {
				accumulated = { a = 3665 },
				activeProjectId = nil,
				activeStartedAt = nil,
			}

			local result = uiPanel.buildCopyText(projects, s, "{name}: {h}h{m}m{s}s")
			assert.are.equal("ProjectA: 1h1m5s", result)
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
