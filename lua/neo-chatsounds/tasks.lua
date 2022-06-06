local tasks = DEFINE_CHATSOUND_MODULE("tasks")

local task_id = 0
function tasks.create(fn, ...)
	local args = { ... }
	local co = coroutine.create(function() fn(unpack(args)) end)
	local task_name = ("neo_cs_task_[%d]"):format(task_id)

	return { identifier = task_name, coroutine = co, __type = "chatsounds_task" }
end

local function validate_task(task, fn_name)
	if not (istable(task) and task.__type == "chatsounds_task") then
		error(("bad argument #1 to '%s' (chatsounds_task expected, got %s)"):format(fn_name, type(task)))
	end
end

function tasks.run(task, on_completed)
	validate_task(task, "tasks.run")

	hook.Add("Think", task.name, function()
		local status, result = coroutine.resume(task.coroutine)
		if not status then
			hook.Remove("Think", task.name)
			error(result)
		end

		if result then
			hook.Remove("Think", task.name)
			on_completed(result)
		end
	end)
end

function tasks.run_sync(task)
	validate_task(task, "tasks.run_sync")

	while coroutine.status(task.coroutine) ~= "dead" do
		local status, result = coroutine.resume(task.coroutine)
		if not status then error(result) end

		if result then return result end
	end

	return nil
end

local iter = 0
function tasks.yield()
	if not coroutine.running() then return end

	if iter >= 10 then
		coroutine.yield()
		iter = 0
	else
		iter = iter + 1
	end
end