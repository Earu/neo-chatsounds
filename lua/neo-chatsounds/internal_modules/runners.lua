local runners = chatsounds.Module("Runners")

local runner_id = 0
function runners.Execute(fn, ...)
	local args = { ... }

	local co = coroutine.create(function() fn(unpack(args)) end)
	local runner_name = ("chatsounds.Runner[%d]"):format(runner_id)

	local t = chatsounds.Tasks.new()
	hook.Add("Think", runner_name, function()
		local status, result = coroutine.resume(co)
		if not status then
			hook.Remove("Think", runner_name)
			t:reject(result)
		end

		if result or coroutine.status(co) == "dead" then
			hook.Remove("Think", runner_name)
			t:resolve(result)
		end
	end)

	return t
end

local iter = 0
local DEFAULT_MAX_ITERS = 25
function runners.Yield(max_iters)
	if not coroutine.running() then return end

	if iter >= (max_iters or DEFAULT_MAX_ITERS) then
		coroutine.yield()
		iter = 0
	else
		iter = iter + 1
	end
end