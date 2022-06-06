local tasks = DEFINE_CHATSOUND_MODULE("tasks")

local task_id = 0

function tasks.execute_runner(fn, ...)
	local args = { ... }

	local co = coroutine.create(function() fn(unpack(args)) end)
	local task_name = ("neo_chatsounds_task_runner_[%d]"):format(task_id)

	local t = tasks.new()
	hook.Add("Think", task_name, function()
		local status, result = coroutine.resume(co)
		if not status then
			hook.Remove("Think", task_name)
			t:reject(result)
		end

		if result then
			hook.Remove("Think", task_name)
			t:resolve(result)
		end
	end)

	return t
end

local iter = 0
function tasks.yield_runner()
	if not coroutine.running() then return end

	if iter >= 10 then
		coroutine.yield()
		iter = 0
	else
		iter = iter + 1
	end
end