local _http = chatsounds.Module("Http")

function _http.Get(url)
	local t = chatsounds.Tasks.new()
	http.Fetch(url, function(body, _, headers, http_code)
		t:resolve({
			Body = body,
			Headers = headers,
			Status = http_code,
		})
	end, function(err)
		t:reject(err)
	end)

	return t
end