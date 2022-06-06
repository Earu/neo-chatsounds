return {
	name = "lfo_volume",
	default_value = { 5, 0.1 },
	parse_args = function(args)
		local str_args = args:Split(",")
		local time = math.max(0, tonumber(str_args[1]) or 5)
		local amount = math.max(0, tonumber(str_args[2]) or 0.1)

		return { time, amount }
	end,
}