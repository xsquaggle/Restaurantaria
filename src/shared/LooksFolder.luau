--!strict
-- The CustomerLooks container (QA18-01). The server builds each customer's look into a folder
-- of this name in ReplicatedStorage, and clients clone the looks from it. A saved place can
-- carry stale folders of the same name (requiring the server module in Studio's Edit mode used
-- to create one, and saving the place kept it), and a client that took the first folder of
-- the name watched an empty one while the customers went into another. So the name alone never
-- decides: the server stamps its folder and its parent with the same token, new for every
-- server, and clients bind only the folder whose token matches.

local LooksFolder = {}

LooksFolder.NAME = "CustomerLooks"
LooksFolder.TOKEN = "CustomerLooksToken"

-- True when folder is parent's live container.
function LooksFolder.isLive(parent: Instance, folder: Instance): boolean
	local token = parent:GetAttribute(LooksFolder.TOKEN)
	return token ~= nil
		and folder.Parent == parent
		and folder.Name == LooksFolder.NAME
		and folder:GetAttribute(LooksFolder.TOKEN) == token
end

-- The live container under parent, or nil until both it and its token have arrived.
function LooksFolder.find(parent: Instance): Instance?
	for _, child in parent:GetChildren() do
		if LooksFolder.isLive(parent, child) then
			return child
		end
	end
	return nil
end

-- A client's binding: returns the live container, keeping the one it found while that stays
-- live and looking again whenever it is not (not arrived yet, or the token moved on).
function LooksFolder.binder(parent: Instance): () -> Instance?
	local bound: Instance? = nil
	return function(): Instance?
		local live = bound
		if live and LooksFolder.isLive(parent, live) then
			return live
		end
		bound = LooksFolder.find(parent)
		return bound
	end
end

-- Server, once: removes the stale empty folders of the name, leaves any other one alone (it
-- holds something, so it may be someone's work; it is never bound), then creates and stamps
-- the live folder. Returns it, with how many stale folders were removed and kept.
function LooksFolder.claim(parent: Instance, token: string): (Folder, number, number)
	local removed, kept = 0, 0
	for _, child in parent:GetChildren() do
		if child.Name == LooksFolder.NAME then
			if child:IsA("Folder") and #child:GetChildren() == 0 then
				child:Destroy()
				removed += 1
			else
				kept += 1
			end
		end
	end
	local folder = Instance.new("Folder")
	folder.Name = LooksFolder.NAME
	folder:SetAttribute(LooksFolder.TOKEN, token)
	folder.Parent = parent
	parent:SetAttribute(LooksFolder.TOKEN, token)
	return folder, removed, kept
end

return LooksFolder
