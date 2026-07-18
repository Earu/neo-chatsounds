local _http = chatsounds.Module("Http")

local function encode_sound_path(path)
	local path_chunks = path:Split("/")
	path_chunks[#path_chunks] = path_chunks[#path_chunks]:gsub("%d", function(n)
		return "%3" .. n
	end)

	return table.concat(path_chunks, "/")
end

-- Cap how many requests are in flight at once. Firing the whole on-join msgpack burst
-- (plus rapid new-sound downloads) from a single IP is what trips GitHub's per-IP rate
-- limit; queueing anything past the cap smooths that out.
local MAX_CONCURRENT = 4
local in_flight = 0
local queue = {}

local function dispatch(url, t)
	in_flight = in_flight + 1

	local finished = false
	local function done()
		if finished then return end
		finished = true

		in_flight = in_flight - 1

		local nxt = table.remove(queue, 1)
		if nxt then
			dispatch(nxt.Url, nxt.Task)
		end
	end

	local success = HTTP({
		method = "GET",
		url = url,
		failed = function(err)
			done()
			t:reject(err)
		end,
		success = function(http_code, body, headers)
			done()
			t:resolve({
				Body = body,
				Headers = headers,
				Status = http_code,
			})
		end,
	})

	if not success then
		done()
		t:reject("HTTP request failed")
	end
end

function _http.Get(url, should_encode)
	if should_encode then
		url = encode_sound_path(url):gsub(" ", "%%20")
	end

	local t = chatsounds.Tasks.new()

	if in_flight >= MAX_CONCURRENT then
		table.insert(queue, { Url = url, Task = t })
	else
		dispatch(url, t)
	end

	return t
end
