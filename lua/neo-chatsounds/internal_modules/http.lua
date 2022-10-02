local _http = chatsounds.Module("Http")

local function encode_sound_path(path)
	local path_chunks = path:Split("/")
	path_chunks[#path_chunks] = path_chunks[#path_chunks]:gsub("%d", function(n)
		return "%3" .. n
	end)

	return table.concat(path_chunks, "/")
end

function _http.Get(url, should_encode)
	if should_encode then
		url = encode_sound_path(url):gsub(" ", "%%20")
	end

	local t = chatsounds.Tasks.new()
	local success = HTTP({
		method = "GET",
		url = url,
		failed = function(err)
			t:reject(err)
		end,
		success = function(http_code, body, headers)
			t:resolve({
				Body = body,
				Headers = headers,
				Status = http_code,
			})
		end,
	})

	if not success then
		t:reject("HTTP request failed")
	end

	return t
end