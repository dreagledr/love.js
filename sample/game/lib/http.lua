-- Cross-platform HTTP facade used by the demo.
--
-- Web (love.js): the engine "http" module (emfetch, built on emscripten_fetch).
--   Fully asynchronous; results are delivered from http.poll(), which must be
--   called from love.update (see Http.pump).
--
-- Native (desktop): LuaSocket's socket.http. Blocking, http:// only (no TLS in
--   the LÖVE 11.x desktop runtime). onSuccess/onError are invoked immediately.

local isWeb = love.system.getOS() == "Web"

local Http = {
	isWeb = isWeb,
}

if isWeb then

	local http = require("http")

	---Start an async request. See the engine module docs for the full options:
	---{ url, method, headers, data, timeout, withCredentials, onSuccess, onError }
	---@return number id
	function Http.request(opts)
		return http.request(opts)
	end

	---Cancel a pending request by id (Web only).
	function Http.cancel(id)
		return http.cancel(id)
	end

	---Pump the callback queue. Call once per frame from love.update.
	function Http.pump()
		http.poll()
	end

else

	local hasSocket, socketHttp = pcall(require, "socket.http")
	local hasLtn12, ltn12 = pcall(require, "ltn12")

	---Start a (blocking) request on desktop. Mirrors the Web API: onSuccess is
	---called for 2xx, onError otherwise.
	function Http.request(opts)
		if not hasSocket or not hasLtn12 then
			if opts.onError then
				opts.onError{ status = 0, message = "LuaSocket (socket.http/ltn12) is not available" }
			end
			return nil
		end

		local responseBody = {}
		local request = {
			url = opts.url,
			method = opts.method or "GET",
			headers = opts.headers,
			sink = ltn12.sink.table(responseBody),
		}

		if opts.data then
			request.source = ltn12.source.string(opts.data)
		end

		-- socket.http returns: on success -> 1, statusCode, headers, statusLine
		--                       on failure -> nil, errorMessage
		local ok, success, code, respHeaders, statusLine = pcall(socketHttp.request, request)

		if not ok then
			if opts.onError then
				opts.onError{ status = 0, message = tostring(success) }
			end
			return nil
		end

		if success ~= 1 then
			if opts.onError then
				opts.onError{ status = 0, message = tostring(code) }
			end
			return nil
		end

		local result = {
			status = code,
			body = table.concat(responseBody),
			headers = respHeaders or {},
		}

		if type(code) == "number" and code >= 200 and code < 300 then
			if opts.onSuccess then opts.onSuccess(result) end
		else
			result.message = tostring(statusLine or code)
			if opts.onError then opts.onError(result) end
		end

		return nil
	end

	---No-op on desktop (requests complete synchronously).
	function Http.pump() end

end

return Http
