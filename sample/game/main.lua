-- love.js fetch demo.
--
-- Talks to the bun dev server in sample/dev.ts and prints whatever comes back:
--   space  GET  /api/random   a fresh payload every time
--   e      POST /api/echo     echoes the request body
--   f      GET  /api/fail     a 500, to show the onError path
--   r      reset the counter
--   esc    quit
--
-- The same game runs on the desktop (LuaSocket) via the facade in lib/http.lua.

local Http = require("lib.http")

-- On the web the page is same-origin with the API, so relative URLs work.
-- On the desktop point LOVEJS_DEMO_API at the dev server (see sample/readme.md).
local BASE = Http.isWeb and "" or (os.getenv("LOVEJS_DEMO_API") or "http://127.0.0.1:8080")

local COLORS = {
	ok = { 0.45, 0.85, 0.52 },
	error = { 0.97, 0.45, 0.41 },
	loading = { 0.96, 0.84, 0.42 },
	idle = { 0.64, 0.66, 0.72 },
	text = { 0.88, 0.90, 0.94 },
	dim = { 0.55, 0.58, 0.64 },
}

local demo = {
	state = "idle",
	label = "-",
	status = "-",
	elapsed = 0,
	count = 0,
	startedAt = 0,
	bodyLines = {},
	font = nil,
	titleFont = nil,
	bodyFont = nil,
}

local setColor = function(c)
	love.graphics.setColor(c[1], c[2], c[3], 1)
end

local function splitLines(text)
	local lines = {}
	if text == nil or text == "" then
		return { "(empty body)" }
	end
	for line in (text .. "\n"):gmatch("(.-)\n") do
		lines[#lines + 1] = line
	end
	return lines
end

local function finish(failed, response)
	response = response or {}

	demo.state = failed and "error" or "ok"
	demo.elapsed = love.timer.getTime() - demo.startedAt
	demo.count = demo.count + 1

	local statusText = response.statusText
	if statusText == nil or statusText == "" then
		statusText = response.message or (failed and "request failed" or "OK")
	end

	demo.status = string.format("HTTP %s  %s", tostring(response.status or "?"), statusText)
	demo.bodyLines = splitLines(response.body)
end

local function request(label, opts)
	demo.state = "loading"
	demo.label = label
	demo.status = "request in flight..."
	demo.bodyLines = {}
	demo.startedAt = love.timer.getTime()

	local options = {
		url = BASE .. opts.path,
		method = opts.method or "GET",
		data = opts.data,
		headers = opts.headers,
		timeout = 10,
		onSuccess = function(response) finish(false, response) end,
		onError = function(error) finish(true, error) end,
	}

	demo.id = Http.request(options)
end

local ACTIONS = {
	random = function() request("GET /api/random", { path = "/api/random" }) end,
	echo = function()
		local payload = "hello from LÖVE at " .. os.date("%H:%M:%S")
		request("POST /api/echo", {
			path = "/api/echo",
			method = "POST",
			headers = { ["Content-Type"] = "text/plain; charset=utf-8" },
			data = payload,
		})
	end,
	fail = function() request("GET /api/fail", { path = "/api/fail" }) end,
}

function love.load()
	demo.titleFont = love.graphics.newFont(22)
	demo.bodyFont = love.graphics.newFont(14)
	demo.font = love.graphics.newFont(15)

	ACTIONS.random()
end

function love.update()
	Http.pump()
end

function love.keypressed(key)
	if key == "space" then
		ACTIONS.random()
	elseif key == "e" then
		ACTIONS.echo()
	elseif key == "f" then
		ACTIONS.fail()
	elseif key == "r" then
		demo.count = 0
		demo.state = "idle"
		demo.label = "-"
		demo.status = "-"
		demo.elapsed = 0
		demo.bodyLines = {}
	elseif key == "escape" then
		love.event.quit()
	end
end

function love.draw()
	local w = love.graphics.getWidth()
	local h = love.graphics.getHeight()

	love.graphics.clear(0.09, 0.10, 0.13)

	local y = 24

	setColor(COLORS.text)
	love.graphics.setFont(demo.titleFont)
	love.graphics.print("love.js fetch demo", 32, y)
	y = y + 38

	love.graphics.setFont(demo.font)
	setColor(COLORS.dim)
	love.graphics.print("engine:   " .. (Http.isWeb and "web (emfetch / emscripten_fetch)" or "desktop (LuaSocket)"), 32, y)
	y = y + 20
	love.graphics.print("endpoint: " .. (BASE == "" and "(same origin)" or BASE), 32, y)
	y = y + 32

	setColor(COLORS.text)
	love.graphics.print(demo.label, 32, y)
	y = y + 24

	setColor(COLORS[demo.state] or COLORS.text)
	love.graphics.print(demo.status, 32, y)
	y = y + 20

	setColor(COLORS.dim)
	love.graphics.print(string.format("%d requests   %d ms", demo.count, math.floor(demo.elapsed * 1000)), 32, y)
	y = y + 28

	love.graphics.setColor(0.22, 0.24, 0.30, 1)
	love.graphics.line(32, y, w - 32, y)
	y = y + 14

	love.graphics.setFont(demo.bodyFont)
	setColor(COLORS.text)
	local lineHeight = demo.bodyFont:getHeight() + 2
	local footerHeight = 42
	for i = 1, #demo.bodyLines do
		if y + lineHeight > h - footerHeight then
			setColor(COLORS.dim)
			love.graphics.print("...", 32, y)
			break
		end
		love.graphics.print(demo.bodyLines[i], 32, y)
		y = y + lineHeight
	end

	love.graphics.setFont(demo.font)
	setColor(COLORS.dim)
	love.graphics.print("space: random    e: echo    f: fail (500)    r: reset    esc: quit", 32, h - 30)
end
