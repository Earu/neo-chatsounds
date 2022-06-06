return {
	name = "select",
	legacy_syntax = "#",
	only_legacy = true,
	default_value = 0,
	parse_args = function(args)
		local select_id = tonumber(args)
		if not select_id then return 0 end

		return math.max(0, select_id)
	end,
}