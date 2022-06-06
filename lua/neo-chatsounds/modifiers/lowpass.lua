return {
	name = "lowpass",
	default_value = 0.5,
	parse_args = function(args)
		local cutoff = tonumber(args)
		if not cutoff then return 0.5 end

		return math.min(1, cutoff)
	end,
}