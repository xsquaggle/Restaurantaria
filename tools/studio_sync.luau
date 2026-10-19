-- Pulls src/ from a GitHub commit into the open Studio place, mirroring default.project.json.
-- Run from the Studio command bar (or the Studio MCP) after setting SHA. Temporarily enables
-- HttpService for the fetch and restores the previous setting afterwards.

local SHA = "REPLACE_WITH_COMMIT_SHA"
local BASE = "https://raw.githubusercontent.com/xsquaggle/Restaurantaria/" .. SHA .. "/"

local HttpService = game:GetService("HttpService")
local ROOTS = {
	{ dir = "src/shared", parent = game:GetService("ReplicatedStorage"), name = "Shared" },
	{ dir = "src/server", parent = game:GetService("ServerScriptService"), name = "Server" },
	{ dir = "src/client", parent = game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts"), name = "Client" },
}

local wasEnabled = HttpService.HttpEnabled
HttpService.HttpEnabled = true
local ok, err = pcall(function()
	local tree = HttpService:JSONDecode(HttpService:GetAsync(
		"https://api.github.com/repos/xsquaggle/Restaurantaria/git/trees/" .. SHA .. "?recursive=1"
	))
	for _, root in ROOTS do
		local folder = Instance.new("Folder")
		folder.Name = root.name
		for _, entry in tree.tree do
			local path: string = entry.path
			if entry.type == "blob" and path:sub(1, #root.dir + 1) == root.dir .. "/" and path:match("%.luau$") then
				local rel = path:sub(#root.dir + 2)
				local parts = string.split(rel, "/")
				local parent: Instance = folder
				for i = 1, #parts - 1 do
					parent = parent:FindFirstChild(parts[i]) or (function()
						local f = Instance.new("Folder")
						f.Name = parts[i]
						f.Parent = parent
						return f
					end)()
				end
				local file = parts[#parts]
				local name, class
				if file:match("%.server%.luau$") then
					name, class = file:gsub("%.server%.luau$", ""), "Script"
				elseif file:match("%.client%.luau$") then
					name, class = file:gsub("%.client%.luau$", ""), "LocalScript"
				else
					name, class = file:gsub("%.luau$", ""), "ModuleScript"
				end
				local script = Instance.new(class)
				script.Name = name
				script.Source = HttpService:GetAsync(BASE .. path)
				script.Parent = parent
			end
		end
		local old = root.parent:FindFirstChild(root.name)
		if old then
			old:Destroy()
		end
		folder.Parent = root.parent
	end
end)
HttpService.HttpEnabled = wasEnabled
if not ok then
	error(err)
end
return "synced " .. SHA
