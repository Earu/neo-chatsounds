local _http = chatsounds.Module("Http")

function _http.Get(url)
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