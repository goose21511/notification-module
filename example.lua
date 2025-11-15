--// This is an example on how to use the module.
local notif = require(game.ReplicatedStorage:WaitForChild("NotificationHandler")) --// Reference the module (Wherever you have it)
local uis = game:GetService("UserInputService")

uis.InputBegan:Connect(function(i, e)
	if e then return end
	if i.KeyCode == Enum.KeyCode.G then
		notif:CreateNotification("Info", "Simply an example!", 2) --// The first string is the notification type, choose one from the module or make your own, the second string is your message, and the last is a number where you can choose how long it lasts.
	end
end)
