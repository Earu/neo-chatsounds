local MODIFIER = {}

MODIFIER.Name = "lfo_pitch"
MODIFIER.DefaultValue = { 5, 0.1 }

function MODIFIER:ParseArgs(args)
	local str_args = args:Split(",")
	local time = math.max(0, tonumber(str_args[1]) or self.DefaultValue[1])
	local amount = math.max(0, tonumber(str_args[2]) or self.DefaultValue[2])

	return { time, amount }
end

function MODIFIER:GetValue()
	if not self.Value then return self.DefaultValue end
	if isfunction(self.ExpressionFn) then
		local _, ret = pcall(self.ExpressionFn)
		if not istable(ret) then return self.DefaultValue end

		if not isnumber(ret[1]) then
			ret[1] = self.DefaultValue[1]
		else
			ret[1] = math.max(0, ret[1])
		end

		if not isnumber(ret[2]) then
			ret[2] = self.DefaultValue[2]
		else
			ret[2] = math.max(0, ret[2])
		end

		return ret
	end

	return self.Value
end

function MODIFIER:OnStreamInit(stream)
	local value = self:GetValue()

	stream:SetPitchLFOAmount(value[2])
	stream:SetPitchLFOTime(value[1])
end

return MODIFIER