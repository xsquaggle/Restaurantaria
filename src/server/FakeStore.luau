--!strict
-- In-memory stand-in for a DataStore, for tests and Studio save-flow captures only. It never
-- touches a real save. Faults, each counted down per call:
--   failNext     UpdateAsync errors before anything is written
--   loseAckNext  UpdateAsync writes, then errors as if the reply was lost
--   delay        seconds every call yields first (a slow save)
--   interleave   a function run once between two transform calls of the next UpdateAsync,
--                as if another server wrote the key meanwhile (the transform is re-run)

local FakeStore = {}

local function copy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local t = {}
	for k, x in v do
		t[k] = copy(x)
	end
	return t
end

function FakeStore.new(): any
	local self: any = { data = {}, failNext = 0, loseAckNext = 0, delay = 0, interleave = nil, calls = 0, writes = 0, transforms = 0 }

	function self.GetAsync(_s: any, key: string): any
		if self.delay > 0 then
			task.wait(self.delay)
		end
		return copy(self.data[key])
	end

	function self.UpdateAsync(_s: any, key: string, transform: (any) -> any): any
		self.calls += 1
		if self.delay > 0 then
			task.wait(self.delay)
		end
		if self.failNext > 0 then
			self.failNext -= 1
			error("FakeStore: write failed before committing")
		end
		if self.interleave then
			-- The first answer is discarded: the key changed underneath it.
			self.transforms += 1
			transform(copy(self.data[key]))
			local other = self.interleave
			self.interleave = nil
			self.data[key] = other(copy(self.data[key]))
		end
		self.transforms += 1
		local result = transform(copy(self.data[key]))
		if result ~= nil then
			self.data[key] = copy(result)
			self.writes += 1
		end
		if self.loseAckNext > 0 then
			self.loseAckNext -= 1
			error("FakeStore: reply lost after the write")
		end
		return copy(result)
	end

	return self
end

return FakeStore
