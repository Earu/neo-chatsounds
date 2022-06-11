local MODIFIER = {}

MODIFIER.Name = "lfo_volume"
MODIFIER.DefaultValue = { 5, 0.1 }

function MODIFIER:ParseArgs(args)
	local str_args = args:Split(",")
	local time = math.max(0, tonumber(str_args[1]) or 5)
	local amount = math.max(0, tonumber(str_args[2]) or 0.1)

	return { time, amount }
end

return MODIFIER