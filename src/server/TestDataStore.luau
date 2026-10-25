--!strict
-- Test-only adapter around an isolated test DataStore (SaveBackend's "test" kind). Every call
-- goes to the real test DataStore; faults are injected here, in front of it, so the real
-- service object is never modified. Faults, each counted down per call:
--   failNext     UpdateAsync errors before calling the DataStore (nothing written)
--   loseAckNext  UpdateAsync writes to the DataStore, then errors as if the reply was lost
--   delay        seconds every call yields first (a slow save)
-- It counts calls, and writes = UpdateAsync calls the DataStore completed (a cancelled
-- transform counts too).

local TestDataStore = {}

function TestDataStore.wrap(inner: any, name: string): any
	local self: any = { kind = "test", name = name, inner = inner, failNext = 0, loseAckNext = 0, delay = 0, calls = 0, writes = 0, gets = 0 }

	function self.GetAsync(_s: any, key: string, options: any?): any
		self.gets += 1
		if self.delay > 0 then
			task.wait(self.delay)
		end
		return inner:GetAsync(key, options)
	end

	function self.UpdateAsync(_s: any, key: string, transform: (any, any?) -> ...any): any
		self.calls += 1
		if self.delay > 0 then
			task.wait(self.delay)
		end
		if self.failNext > 0 then
			self.failNext -= 1
			error("TestDataStore: write failed before committing", 0)
		end
		local result = inner:UpdateAsync(key, transform)
		self.writes += 1
		if self.loseAckNext > 0 then
			self.loseAckNext -= 1
			error("TestDataStore: reply lost after the write", 0)
		end
		return result
	end

	return self
end

return TestDataStore
