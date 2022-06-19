local MODIFIER = {}

MODIFIER.Name = "duration"
MODIFIER.LegacySyntax = "="
MODIFIER.DefaultValue = 0

function MODIFIER:ParseArgs(args)
	local duration = tonumber(args)
	if not duration then return -1 end

	return math.max(0, duration)
end

function MODIFIER:GetValue()
	if not self.Value then return self.DefaultValue end
	if isfunction(self.ExpressionFn) then
		local _, ret = pcall(self.ExpressionFn)
		if not isnumber(ret) then return self.DefaultValue end

		return math.max(0, ret)
	end

	return self.Value
end

function MODIFIER:OnStreamInit(stream)
	if self.Value ~= -1 then
		stream.Duration = self:GetValue()
	end

	if self.IsLegacy then
		stream.Overlap = true
	end
end

return MODIFIER