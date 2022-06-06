return {
	name = "cutoff",
	legacy_syntax = "--",
	default_value = 0,
	parse_args = function(args)
		local cutoff = tonumber(args)
		if not cutoff then return 0 end

		return math.max(0, cutoff)
	end,
}