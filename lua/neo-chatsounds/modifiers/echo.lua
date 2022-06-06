return {
	name = "echo",
	default_value = { 0.25, 0.5 },
	parse_args = function(args)
		local str_args = args:Split(",")
		local echo_delay = math.max(0, tonumber(str_args[1]) or 0.25)
		local echo_feedback = math.max(0, tonumber(str_args[2]) or 0.5)

		return { echo_delay, echo_feedback }
	end,
}