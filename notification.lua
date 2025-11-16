local notificationHandler = {}
--// All UI is created via this script!

--// Services used throughout the module.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")
local TextChatService = game:GetService("TextChatService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--// centralized settings table so i can store everything cleanly here
local NOTIFICATION_SETTINGS = {
	--// different notification types, easily add more by adding another line below.
	NOTIFICATION_TYPES = {
		"Success",
		"Info",
		"Warn",
		"Alert",
		"Default",
	},
	--// the colors for each notification, syncing these with the notification types above.
	NOTIFICATION_COLORS = {
		success = Color3.fromRGB(39, 93, 50),
		info = Color3.fromRGB(61, 100, 148),
		warn = Color3.fromRGB(205, 158, 67),
		alert = Color3.fromRGB(153, 59, 39),
		default = Color3.fromRGB(50, 50, 50),
	},
	--// the icon for each notification type
	IMAGE_IDS = {
		success = "rbxassetid://112921444805850", --// originally: 74920264774407
		info = "rbxassetid://112921444805850", --// originally: 112921444805850
		warn = "rbxassetid://112921444805850", --// originally: 131688329492659
		alert = "rbxassetid://112921444805850", --// originally: 88496112693331
		default = "rbxassetid://112921444805850", --// originally: 107537390522145
	},
	--// the transparencies if you wish to change them.
	TRANSPARENCIES = {
		success = 0.8,
		info = 0.8,
		warn = 0.8,
		alert = 0.8,
		default = 0.8,
	},
	--// and here if you wish to have a different sound for any of the notifications.
	SOUND_IDS = {
		success = "rbxassetid://6753645454",
		info = "rbxassetid://6753645454",
		warn = "rbxassetid://6753645454",
		alert = "rbxassetid://6753645454",
		default = "rbxassetid://6753645454",
	}   
}
--// The show/hide animation settings, tweak them however you wish.
local ANIMATION_SETTINGS = TweenInfo.new(1/2, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, 0)

--// Some settings where you can choose the font, start & end transparency.
local selectedFont = Enum.Font.GothamBlack
local startYFadingValue = 0.5
local endYFadingValue = 0.3
local Camera = Workspace.CurrentCamera
local BASE_SCREEN_MIN = 1080

--// Settings for each device, like text size etc. You can add one for console aswell if you wish.
local DEVICE_SETTINGS = {
	Mobile = {
		MinTextSize = 14,
		MaxTextSize = 24,
		ImageSize = 26,
		Padding = 10,
		WidthPercentage = 0.3,
		MaxWidth = 250,
		Duration = 4,
		CornerRadius = 8,
		CanvasWidth = 3,
		ScrollBarThickness = 4
	},
	Desktop = {
		MinTextSize = 24,
		MaxTextSize = 34,
		ImageSize = 36,
		Padding = 16,
		WidthPercentage = 0.3,
		MaxWidth = 500,
		Duration = 3,
		CornerRadius = 12,
		CanvasWidth = 5,
		ScrollBarThickness = 6
	}
}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--// This gets the device settings depending on what kind of device the player is using. Used for calculations later.
local function getDeviceSettings()
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled 
		and DEVICE_SETTINGS.Mobile 
		or DEVICE_SETTINGS.Desktop
end

--// this calculates all scaled values dynamically using the viewport size, this keeps the notifications visually consistent over different resolutions.
local function getScaledSettings()
	local viewport = Camera.ViewportSize

	--// min(viewport) gives consistent scale on ultra-wide screens.
	--// clamped to prevent absurd scaling on extreme resolutions.
	local fontScale = math.clamp(math.min(viewport.X, viewport.Y) / BASE_SCREEN_MIN, 0.7, 1.3)
	local base = getDeviceSettings()

	return {
		MinTextSize = base.MinTextSize,
		MaxTextSize = base.MaxTextSize,
		ImageSize = base.ImageSize * fontScale,
		Padding = base.Padding * fontScale,
		WidthPercentage = base.WidthPercentage,
		MaxWidth = base.MaxWidth,
		Duration = base.Duration,
		CornerRadius = base.CornerRadius * fontScale,
		CanvasWidth = base.CanvasWidth * fontScale,
		FontScale = fontScale,
		ScrollBarThickness = base.ScrollBarThickness
	}
end

--// this fades notifications out as they move upward, this helps prevent visual overlap when many stack, it works by checking the y position relative to fade thresholds.
local function updateFrameTransparency(frame: Frame)
	local viewportHeight = Camera.ViewportSize.Y
	local startY = viewportHeight * startYFadingValue
	local endY = viewportHeight * endYFadingValue

	--// Bottom point of the notification (used for fade progression).
	local frameBottomY = frame.AbsolutePosition.Y + frame.AbsoluteSize.Y
	
	--// Fade amount computed linearly between startY and endY.
	local transparency = frameBottomY > startY and 0 or math.clamp((startY - frameBottomY)/(startY - endY), 0, 1)
	local notificationType = frame.Name:match("^(%a+)_Notification"):lower()

	--// Base transparency + fade effect.
	frame.BackgroundTransparency = NOTIFICATION_SETTINGS.TRANSPARENCIES[notificationType] + transparency * (1 - NOTIFICATION_SETTINGS.TRANSPARENCIES[notificationType])

	--// All children tagged with UpdateTransparency get the fading effect, tag-based filtering prevents fading irrelevant elements.
	for _, child in ipairs(frame:GetDescendants()) do
		if not child:HasTag("UpdateTransparency") then continue end
		if child:IsA("ImageLabel") then
			child.ImageTransparency = transparency
		elseif child:IsA("TextLabel") then
			child.TextTransparency = transparency
		elseif child:IsA("Frame") then
			child.BackgroundTransparency = transparency
		end
	end
end

--// creates a gradient fade animation by constructing a NumberSequence every frame, this avoids TweenService limitations on sequences and gives full control.
local function animateGradientTransparency(uiGradient: UIGradient, duration: number)
	if not uiGradient:IsA("UIGradient") then return end

	local numKeypoints = 20 -- this lets us have a smoother gradient
	local startTime = tick()
	local connection

	connection = RunService.Heartbeat:Connect(function()
		local currentElapsedTime = tick() - startTime
		local progress = math.clamp(currentElapsedTime / duration, 0, 1)

		-- builds a custom NumberSequence to represent new transparency.
		local keypoints = {}
		for i = 0, numKeypoints - 1 do
			local fadeStartTime = (i / numKeypoints)
			local fadeProgress = math.clamp((progress - fadeStartTime) * numKeypoints, 0, 1)

			local transparencyValue = 1 - fadeProgress
			table.insert(keypoints, NumberSequenceKeypoint.new(i / (numKeypoints - 1), transparencyValue))
		end

		uiGradient.Transparency = NumberSequence.new(keypoints)

		-- cleanup when done
		if progress == 1 then
			if connection then connection:Disconnect() connection = nil end
			uiGradient:Destroy()
			return
		end
	end)
end

--// calculates the correct width, height, and text size for a notification.
--// this exists Text wrapping depends on available width (varies by device & scale), height must expand based on multi-line messages and TextService:GetTextSize gives pixel perfect text bounds
local function calculateNotificationSize(currentSettings: table, message: string)
	-- determine device type for potential future adjustments
	local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local screenWidth = Camera.ViewportSize.X
	-- width is a percentage but never exceeds MaxWidth, this allows responsive design AND predictable max limit
	local fixedWidth = math.min(screenWidth * currentSettings.WidthPercentage, currentSettings.MaxWidth)
	-- remaining width once icon, canvas bar, and padding are removed
	local textAvailableWidth = fixedWidth - (currentSettings.ImageSize + currentSettings.CanvasWidth + currentSettings.Padding * 3)


	-- font size scaled but clamped to expected design bounds
	local scaledMin = currentSettings.MinTextSize * currentSettings.FontScale
	local scaledMax = currentSettings.MaxTextSize * currentSettings.FontScale
	local textSize = math.clamp(math.round(scaledMin), scaledMin, scaledMax)

	-- get wrapped text height
	local textBounds = TextService:GetTextSize(
		message,
		textSize,
		selectedFont,
		Vector2.new(textAvailableWidth, math.huge)
	)

	-- used to account for final padding/line height
	local lineHeight = TextService:GetTextSize(
		"",
		textSize,
		selectedFont,
		Vector2.new(math.huge, math.huge)
	).Y

	local totalTextHeight = textBounds.Y + lineHeight

	-- height must accommodate: icon height or text height, padding 
	return {
		Width = fixedWidth,
		Height = math.ceil(math.max(
			totalTextHeight + currentSettings.Padding,
			currentSettings.ImageSize + currentSettings.Padding
			)),
		TextSize = textSize
	}
end

--// recalculates layout for every currently active notification, triggered on viewport size change to maintain responsive design
local function resizeAllNotifications()
	local container = playerGui:FindFirstChild("NotificationGui") and playerGui.NotificationGui.MainContainer
	if not container then return end

	local currentSettings = getScaledSettings()
	-- update spacing between notifications
	local layout = container:FindFirstChild("UIListLayout")
	if layout then
		layout.Padding = UDim.new(0, currentSettings.Padding * 0.4)
	end

	-- recompute each notifications size
	for _, frame in ipairs(container:GetChildren()) do
		if frame:IsA("Frame") and frame.Name:find("_Notification") then
			-- skip if its an interactive input notification (added it now so i dont gotta do it later lmao)
			if frame:FindFirstChild("MessageInput") then
				continue
			end

			local textLabel = frame:FindFirstChild("MessageLabel")
			local message = textLabel and textLabel.Text or ""

			local sizeInfo = calculateNotificationSize(currentSettings, message)


			-- update corner radius — makes pill shape maintain correct curve
			local corner = frame:FindFirstChild("UICorner")
			if corner then
				corner.CornerRadius = UDim.new(0, currentSettings.CornerRadius)
			end

			-- update padding
			local padding = frame:FindFirstChild("UIPadding")
			if padding then
				padding.PaddingLeft = UDim.new(0, currentSettings.Padding)
				padding.PaddingRight = UDim.new(0, currentSettings.Padding)
				padding.PaddingTop = UDim.new(0, currentSettings.Padding * 0.5)
				padding.PaddingBottom = UDim.new(0, currentSettings.Padding * 0.5)
			end

			-- update icon size
			local icon = frame:FindFirstChild("IconLabel")
			if icon then
				icon.Size = UDim2.fromOffset(currentSettings.ImageSize, currentSettings.ImageSize)
			end

			-- update time bar size
			local timeContainer = frame:FindFirstChild("TimeLeftContainer")
			if timeContainer then
				timeContainer.Size = UDim2.fromOffset(currentSettings.CanvasWidth, currentSettings.ImageSize)
			end

			-- update text constraints
			if textLabel then
				textLabel.TextSize = sizeInfo.TextSize
				textLabel.Size = UDim2.new(1, -(currentSettings.ImageSize + currentSettings.CanvasWidth + currentSettings.Padding * 3), 1, 0)
			end

			-- smooth resize transition
			TweenService:Create(frame, ANIMATION_SETTINGS, {Size = UDim2.fromOffset(sizeInfo.Width, sizeInfo.Height)}):Play()
		end
	end
end

--// creates the top level ScreenGui and the frame container that holds notifications. 
--// and why a separate container you may ask? well UIListLayouts sorts notifications vertically and we can safely destroy the whole system if no notifications remain
local function createMainContainer()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "NotificationGui"
	screenGui.IgnoreGuiInset = true -- ensures perfect position across platforms
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

	-- folder for notification sounds
	local soundsFolder = Instance.new("Folder")
	soundsFolder.Name = "Sounds"
	soundsFolder.Parent = screenGui

	-- container at bottom-center of screen
	local container = Instance.new("Frame")
	container.Name = "MainContainer"
	container.AnchorPoint = Vector2.new(0.5, 1)
	container.Position = UDim2.fromScale(0.5, 0.97)
	container.Size = UDim2.new(1, 0, 0, 0)
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.BackgroundTransparency = 1
	container.Parent = screenGui

	-- layout for vertical stacking
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Padding = UDim.new(0, getScaledSettings().Padding * 0.4)
	layout.Parent = container
 
	-- every frame we update fading positions
	local heartbeatConnection = game:GetService("RunService").Heartbeat:Connect(function()
		for _, frame in ipairs(container:GetChildren()) do
			if frame:IsA("Frame") and frame.Name:find("_Notification") then
				updateFrameTransparency(frame)
			end
		end
	end)
	-- dynamic rescaling when viewport changes
	local viewportConnection = Camera:GetPropertyChangedSignal("ViewportSize"):Connect(resizeAllNotifications)
	
	-- cleanup when container is destroyed
	container.Destroying:Connect(function()
		heartbeatConnection:Disconnect()
		viewportConnection:Disconnect()
		heartbeatConnection = nil
		viewportConnection = nil
	end)

	return container
end

--// this plays the correct sound based on the notification type. 
--// the reason the sound is put in a folder is because sounds inside a ScreenGui replicate instantly to the local client and destroying them after playback prevents memory buildup. 
local function playSound(notificationType: string)
	local notificationGui = playerGui:FindFirstChild("NotificationGui")
	if not notificationGui then return end
	local soundsFolder = notificationGui:FindFirstChild("Sounds")
	if not soundsFolder then return end

	-- creates a temporary sound instance
	local sound = Instance.new("Sound")
	sound.Volume = 0.1
	sound.SoundId = NOTIFICATION_SETTINGS.SOUND_IDS[notificationType:lower()]
	sound.Name = notificationType:sub(1, 1):upper() .. notificationType:sub(2) .. "_Sound"
	sound.Parent = soundsFolder
	sound:Play()
	-- destroy after playing to avoid memory clutter
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
end

--// entry animation, grows from 0 to full size.
--// and here we use tweenservice so we can get a smooth transition and it avoids instant popping and maintains theme consistency
local function animateIn(element: Frame, targetSize: UDim2)
	if not element:IsA("Frame") then return end
	local container = element.Parent

	TweenService:Create(element, ANIMATION_SETTINGS, {Size = targetSize}):Play()
end

--// exit animation, shrinks to small bar then destroys
--// After finishing, calls callback (used to destroy container if empty)
local function animateOut(element: Frame, callback: () -> ())
	local notificationTween = TweenService:Create(element, ANIMATION_SETTINGS, {Size = UDim2.fromOffset(0, 6.7)})

	notificationTween.Completed:Connect(function()
		element:Destroy()
		if callback then
			callback()
		end
	end)
	notificationTween:Play()
end

--// builds the notification frame and returns it
--// why use a builder function? well it gives clean separation of UI construction from logic and reusable if new variants are added (input fields, progress bars, etc.)
local function createNotificationFrame(notificationType: string, isExecutedFunction: boolean)
	local currentSettings = getScaledSettings()
	
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = NOTIFICATION_SETTINGS.NOTIFICATION_COLORS[notificationType:lower()]
	frame.Size = UDim2.fromOffset(0, 0) -- start small for animation
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundTransparency = NOTIFICATION_SETTINGS.TRANSPARENCIES[notificationType]
	frame.ClipsDescendants = true
	frame.Name = notificationType:sub(1, 1):upper() .. notificationType:sub(2) .. "_Notification"

	-- if the notification is tied to a function execution then we move it to the bottom
	frame.LayoutOrder = isExecutedFunction and math.huge or os.time()

	-- gives it the rounded/pill shape
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(10, currentSettings.CornerRadius)
	corner.Parent = frame

	-- this gives us a horizontal layout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Wraps = true
	layout.Padding = UDim.new(0, currentSettings.Padding * 0.6)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = frame

	-- padding on all sides of the notification
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, currentSettings.Padding)
	padding.PaddingRight = UDim.new(0, currentSettings.Padding)
	padding.PaddingTop = UDim.new(0, currentSettings.Padding * 0.5)
	padding.PaddingBottom = UDim.new(0, currentSettings.Padding * 0.5)
	padding.Parent = frame

	return frame
end

--// core logic that builds, animates, and manages notification lifetime
local function showNotification(notificationType: string, message: string, duration: number, executedFunction: () -> nil)
	-- input validation ensures silent fail instead of throwing errors.
	if type(notificationType) ~= "string" or type(message) ~= "string" then return end
	if executedFunction and type(executedFunction) ~= "function" then return end
	if duration and type(duration) ~= "number" then return end

	local isExecutedFunction = executedFunction and true or false
	notificationType = notificationType:lower()

	-- validate the notification type exists
	local isValidType = false
	for _, currentType in pairs(NOTIFICATION_SETTINGS.NOTIFICATION_TYPES) do
		if string.lower(currentType) == string.lower(notificationType) then
			isValidType = true
			break
		end 
	end
	if not isValidType then return end
	
	local currentSettings = getScaledSettings()
	-- Ensure container exists (creates if needed)
	local container = playerGui:FindFirstChild("NotificationGui") and playerGui.NotificationGui.MainContainer or createMainContainer()
	-- calculate sizes for the message
	local sizeInfo = calculateNotificationSize(currentSettings, message)
	-- creates the main notification frame
	local frame = createNotificationFrame(notificationType, isExecutedFunction)

	-- notification icon
	local icon = Instance.new("ImageLabel")
	icon.Image = NOTIFICATION_SETTINGS.IMAGE_IDS[notificationType]
	icon.Size = UDim2.fromOffset(currentSettings.ImageSize, currentSettings.ImageSize)
	icon.BackgroundTransparency = 1
	icon.ImageTransparency = 1 -- so we can fade it in later
	icon.LayoutOrder = 0
	icon.Name = "IconLabel"
	icon:AddTag("UpdateTransparency")
	icon.Parent = frame

	-- optional bar that indicates the amount of time left
	local timeContainer, timeFiller
	if not isExecutedFunction then
		timeContainer = Instance.new("Frame")
		timeContainer.Size = UDim2.fromOffset(currentSettings.CanvasWidth, currentSettings.ImageSize)
		timeContainer.BackgroundColor3 = Color3.fromRGB(175, 175, 175)
		timeContainer.BorderSizePixel = 0
		timeContainer.LayoutOrder = 1
		timeContainer.Transparency = 1 -- Change to 0.5 if you wish to have a bar indicating time left untill notification is removed.
		timeContainer.Name = "TimeLeftContainer"

		-- Filler animates vertically over lifetime
		timeFiller = Instance.new("Frame")
		timeFiller.AnchorPoint = Vector2.new(0.5, 1)
		timeFiller.Size = UDim2.fromScale(1, 1)
		timeFiller.Position = UDim2.fromScale(0.5, 1)
		timeFiller.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		timeFiller.BorderSizePixel = 0
		timeFiller.Transparency = 1 -- Change to 0 if you wish to have a bar indicating time left untill notification is removed.
		timeFiller.Name = "TimeLeftFiller"
		timeFiller.Parent = timeContainer
		timeContainer.Parent = frame
	end

	-- main text
	local textLabel = Instance.new("TextLabel")
	textLabel.Text = message
	textLabel.Size = UDim2.new(1, -(currentSettings.ImageSize + currentSettings.CanvasWidth + currentSettings.Padding * 3), 1, 0)
	textLabel.Position = UDim2.new(0, currentSettings.ImageSize + currentSettings.Padding, 0.5, 0)
	textLabel.AnchorPoint = Vector2.new(0, 0.5)
	textLabel.BackgroundTransparency = 1
	textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	textLabel.Font = selectedFont
	textLabel.TextSize = sizeInfo.TextSize
	textLabel.TextTransparency = 1 -- so we can fade it in
	textLabel.TextWrapped = true
	textLabel.LayoutOrder = isExecutedFunction and 1 or 2
	textLabel:AddTag("UpdateTransparency")
	textLabel.Name = "MessageLabel"
	textLabel.Parent = frame

	-- gradient that basically fades in the text
	local textGradient = Instance.new("UIGradient")
	textGradient.Parent = textLabel
	-- inserts the frame into the container
	frame.Parent = container
	-- plays the sound
	playSound(notificationType)
	-- default duration time if none is provided when creating the notification
	local notificationTime = duration or currentSettings.Duration
	-- animates the text gradient
	animateGradientTransparency(textGradient, ANIMATION_SETTINGS.Time * 1)
	-- this animated the timer
	if not isExecutedFunction then TweenService:Create(timeFiller, TweenInfo.new(notificationTime, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, 0), {Size = UDim2.fromScale(1, 0)}):Play() end
	
	-- animates the notification entering
	animateIn(frame, UDim2.fromOffset(sizeInfo.Width, sizeInfo.Height))
	TweenService:Create(icon, ANIMATION_SETTINGS, {ImageTransparency = 0}):Play()
	TweenService:Create(textLabel, ANIMATION_SETTINGS, {TextTransparency = 0}):Play()

	-- animated the notification closing
	local function closeNotification()
		animateOut(frame, function()
			frame:Destroy()
			-- if container only has layout object left then we remove whole GUI
			if #container:GetChildren() == 1 then
				container.Parent:Destroy()
			end
		end)
		-- fade out icon & text
		TweenService:Create(icon, ANIMATION_SETTINGS, {ImageTransparency = 1}):Play()
		TweenService:Create(textLabel, ANIMATION_SETTINGS, {TextTransparency = 1}):Play()
	end
	-- if function provided, close notification after it completes
	if executedFunction then
		task.spawn(function()
			pcall(executedFunction)
			closeNotification()
		end)
	else
		task.delay(notificationTime, closeNotification) -- otherwise close after duration
	end
end

--// this is simply a wrapper around the internal `showNotification` function. External scripts call this to create notifications without touching internals.
function notificationHandler:CreateNotification(notificationType: string, message: string, duration: number, executedFunction: () -> nil)
	showNotification(notificationType, message, duration, executedFunction)
end
--// it iterates over every notification frame, plays exit animation on each and destroys UI cleanly when all notifications are gone

--// and why dont we instant destroy? well users expect smooth UX, not sudden UI popping so it reuses the same exit animation logic for consistency
function notificationHandler:ClearNotifications()
	local container = playerGui:FindFirstChild("NotificationGui") and playerGui.NotificationGui:FindFirstChild("MainContainer")
	if not container then return end
	for _, frame in ipairs(container:GetChildren()) do
		if frame:IsA("Frame") and frame.Name:find("_Notification") then
			-- uses exiting animation wrapper
			animateOut(frame, function()
				frame:Destroy()
				-- when only UIListLayout remains, delete entire GUI (The container always has at least 1 child (the layout))
				if #container:GetChildren() == 1 then
					container.Parent:Destory()
				end
			end)
		end
	end
end

return notificationHandler
