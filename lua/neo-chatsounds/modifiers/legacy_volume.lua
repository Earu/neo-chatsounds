return {
	name = "legacy_volume",
	legacy_syntax = "^^",
	only_legacy = true,
	default_value = { 100, 100 },
	parse_args = function(args)
		local str_args = args:Split(".")
		local volume_start = math.max(1, tonumber(str_args[1]) or 100)
		local volume_end = math.max(1, tonumber(str_args[2]) or 100)

		return { volume_start, volume_end }
	end,
}