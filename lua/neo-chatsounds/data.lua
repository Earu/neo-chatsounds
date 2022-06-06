local data = DEFINE_CHATSOUND_MODULE("data")

data.lookup = {}
data.ready = false

local repos = {
	{
		url = "https://github.com/Metastruct/garrysmod-chatsounds",
		msgpack = false,
	},
}

hook.Add("InitPostEntity", "chatsounds_data", function()
	for _, repo_data in ipairs(repos) do
		http.Fetch(repo_data.url, function()
		end)
	end
end)