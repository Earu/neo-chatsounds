local MODIFIER = {}

MODIFIER.Name = "cutoff"
MODIFIER.LegacySyntax = "--"
MODIFIER.DefaultValue = 100

function MODIFIER:ParseArgs(args)
	local cutoff = tonumber(args)
	if not cutoff then return self.DefaultValue end

	return math.max(0, cutoff)
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
	stream.Duration = stream.Duration * (self:GetValue() / 100)
	stream.Overlap = false
end

return MODIFIER