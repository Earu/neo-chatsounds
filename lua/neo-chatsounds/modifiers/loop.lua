return {
	name = name,
	default = 0,
	parse_args = function(args)
		local n = tonumber(args)
		if not n then return 0 end

		return math.max(0, n)
	end,
}