local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

const MARKER_COLOUR = Color3.fromRGB(255, 0, 255)
const MARKER_SECOND_COLOUR = Color3.fromRGB(0, 255, 0)
const MARKER_SECONDS = 0.5
const CAPTION_FONT = Enum.Font.GothamBold

local Demo = {}
Demo.player = Players.LocalPlayer

local overlay = Instance.new("ScreenGui")
overlay.Name = "__DemoOverlay"
overlay.IgnoreGuiInset = true
overlay.ResetOnSpawn = false
overlay.DisplayOrder = 2147483647
overlay.Parent = Demo.player:WaitForChild("PlayerGui")

local marker = Instance.new("Frame")
marker.Name = "Marker"
marker.Size = UDim2.fromScale(1, 1)
marker.BackgroundColor3 = MARKER_COLOUR
marker.BorderSizePixel = 0
marker.Visible = false
marker.ZIndex = 100
marker.Parent = overlay

local function textBox(name, anchorY, positionY, heightScale)
	local holder = Instance.new("Frame")
	holder.Name = name
	holder.AnchorPoint = Vector2.new(0.5, anchorY)
	holder.Position = UDim2.fromScale(0.5, positionY)
	holder.Size = UDim2.fromScale(0.8, heightScale)
	holder.BackgroundColor3 = Color3.new(0, 0, 0)
	holder.BackgroundTransparency = 0.35
	holder.Visible = false
	holder.ZIndex = 50
	holder.Parent = overlay
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.2, 0)
	corner.Parent = holder
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(0.94, 0.8)
	label.Position = UDim2.fromScale(0.03, 0.1)
	label.Font = CAPTION_FONT
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.ZIndex = 51
	label.Parent = holder
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 42
	limit.Parent = label
	return holder
end

local captionBox = textBox("Caption", 1, 0.95, 0.09)
local titleBox = textBox("Title", 0.5, 0.5, 0.16)

function Demo.log(message)
	print("[demo] " .. message)
end

function Demo.wait(seconds)
	task.wait(seconds)
end

function Demo.character()
	return Demo.player.Character or Demo.player.CharacterAdded:Wait()
end

function Demo.humanoid()
	return Demo.character():WaitForChild("Humanoid")
end

function Demo.root()
	return Demo.character():WaitForChild("HumanoidRootPart")
end

function Demo.teleport(target)
	local cframe = if typeof(target) == "Vector3" then CFrame.new(target) else target
	Demo.character():PivotTo(cframe)
	task.wait(0.1)
end

function Demo.walkTo(position, timeout)
	local humanoid = Demo.humanoid()
	humanoid:MoveTo(position)
	local finished = false
	local connection = humanoid.MoveToFinished:Connect(function()
		finished = true
	end)
	local deadline = os.clock() + (timeout or 15)
	while not finished and os.clock() < deadline do
		task.wait()
	end
	connection:Disconnect()
	return finished
end

function Demo.face(position)
	local root = Demo.root()
	local flat = Vector3.new(position.X, root.Position.Y, position.Z)
	if (flat - root.Position).Magnitude > 0.01 then
		root.CFrame = CFrame.lookAt(root.Position, flat)
	end
end

function Demo.key(keyCode, holdSeconds)
	local hold = holdSeconds or 0.15
	print(string.format("[demo:key] %s %.2f", tostring(keyCode), hold))
	task.wait(hold + 0.6)
end

function Demo.caption(text, seconds)
	captionBox.Text.Text = text
	captionBox.Visible = true
	if seconds then
		task.delay(seconds, function()
			if captionBox.Text.Text == text then
				captionBox.Visible = false
			end
		end)
	end
end

function Demo.clearCaption()
	captionBox.Visible = false
end

function Demo.title(text, seconds)
	titleBox.Text.Text = text
	titleBox.Visible = true
	task.wait(seconds or 1.5)
	titleBox.Visible = false
end

function Demo.component(instance, tag, timeout)
	local runner = Demo.player:WaitForChild("PlayerScripts"):WaitForChild("Runner", 10)
	local store = runner and require(runner:WaitForChild("EntityStore"))
	if not store then
		return nil
	end
	local deadline = os.clock() + (timeout or 10)
	repeat
		local component = store.findComponent(instance, tag)
		if component then
			return component
		end
		task.wait(0.1)
	until os.clock() > deadline
	return nil
end

Demo.camera = {}
local cameraConnection = nil

local function camera()
	return workspace.CurrentCamera
end

local function releaseCamera()
	if cameraConnection then
		cameraConnection:Disconnect()
		cameraConnection = nil
	end
end

function Demo.camera.reset()
	releaseCamera()
	camera().CameraType = Enum.CameraType.Custom
end

function Demo.camera.fixed(position, lookAt)
	releaseCamera()
	camera().CameraType = Enum.CameraType.Scriptable
	camera().CFrame = CFrame.lookAt(position, lookAt)
end

function Demo.camera.moveTo(position, lookAt, seconds)
	releaseCamera()
	camera().CameraType = Enum.CameraType.Scriptable
	local tween = TweenService:Create(camera(), TweenInfo.new(seconds or 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { CFrame = CFrame.lookAt(position, lookAt) })
	tween:Play()
	tween.Completed:Wait()
end

-- Chase camera: sits `distance` studs behind and `height` above the subject's facing, eased toward that spot each frame.
function Demo.camera.follow(subject, distance, height)
	releaseCamera()
	camera().CameraType = Enum.CameraType.Scriptable
	local back = distance or 18
	local up = height or 7
	cameraConnection = RunService.RenderStepped:Connect(function(deltaTime)
		local target = subject or Demo.root()
		if not target or not target.Parent then
			return
		end
		local pivot = target:GetPivot()
		local desired = CFrame.lookAt(pivot.Position - pivot.LookVector * back + Vector3.new(0, up, 0), pivot.Position + Vector3.new(0, up * 0.25, 0))
		local alpha = 1 - math.exp(-6 * deltaTime)
		camera().CFrame = camera().CFrame:Lerp(desired, alpha)
	end)
end

-- Orbit: angle advances 2π per revolution over `seconds`, camera on a circle of `radius` at `height` around the subject.
function Demo.camera.orbit(subject, radius, height, seconds)
	releaseCamera()
	camera().CameraType = Enum.CameraType.Scriptable
	local started = os.clock()
	local duration = seconds or 6
	cameraConnection = RunService.RenderStepped:Connect(function()
		local centre = (if typeof(subject) == "Vector3" then subject else subject:GetPivot().Position)
		local angle = (os.clock() - started) / duration * math.pi * 2
		local offset = Vector3.new(math.cos(angle) * (radius or 20), height or 8, math.sin(angle) * (radius or 20))
		camera().CFrame = CFrame.lookAt(centre + offset, centre)
	end)
	task.wait(duration)
	releaseCamera()
end

function Demo._marker()
	marker.BackgroundColor3 = MARKER_COLOUR
	marker.Visible = true
	task.wait(MARKER_SECONDS)
	marker.BackgroundColor3 = MARKER_SECOND_COLOUR
	task.wait(MARKER_SECONDS)
	marker.Visible = false
	task.wait(0.1)
end

function Demo._run(body)
	Demo.character()
	task.wait(1)
	Demo.log("start")
	Demo._marker()
	local succeeded, failure = pcall(body, Demo)
	if not succeeded then
		warn("[demo] error: " .. tostring(failure))
		Demo.caption("Demo error: " .. tostring(failure))
		task.wait(3)
	end
	Demo.clearCaption()
	Demo._marker()
	Demo.log("done")
	releaseCamera()
	overlay:Destroy()
end

return Demo
