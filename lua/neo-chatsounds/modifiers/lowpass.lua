local MODIFIER = {}

MODIFIER.Name = "lowpass"
MODIFIER.DefaultValue = 0.5

function MODIFIER:ParseArgs(args)
	local cutoff = tonumber(args)
	if not cutoff then return self.DefaultValu end

	return math.min(1, cutoff)
end

function MODIFIER:GetValue()
	if not self.Value then return self.DefaultValue end
	if isfunction(self.ExpressionFn) then
		local _, ret = pcall(self.ExpressionFn)
		if not isnumber(ret) then return self.DefaultValue end

		return math.min(1, ret)
	end

	return self.Value
end

function MODIFIER:OnStreamInit(stream)
	stream:SetFilterType(1)
	stream:SetFilterFraction(self:GetValue())
end

return MODIFIER