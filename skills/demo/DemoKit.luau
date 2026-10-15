-- DemoKit: the `Demo` API a demo script runs with. demo.js wraps it, the project's ready check and the demo body into
-- one LocalScript and sets Demo._nonce / Demo._config / Demo._readyCheck / Demo._signal before Demo._run.
-- Every print is "[demo:<nonce>] ..." so the recorder, reading Studio's log, takes only this run's lines.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- start flash: magenta then green; end flash: magenta then blue (demo.js tells them apart by the second colour).
-- With Demo._config.errorFlash (live mode only) an errored demo ends magenta then red instead, which `process` refuses
-- to pass off as a clean clip. Studio recordings leave it off, so their end flash is always blue as before.
const MARKER_COLOUR = Color3.fromRGB(255, 0, 255)
const MARKER_START_COLOUR = Color3.fromRGB(0, 255, 0)
const MARKER_END_COLOUR = Color3.fromRGB(0, 0, 255)
const MARKER_ERROR_COLOUR = Color3.fromRGB(255, 0, 0)
const MARKER_SECONDS = 0.5
const CAPTION_FONT = Enum.Font.GothamBold
const KEY_BIND_SECONDS = 5
const VIEWPORT_STABLE_SECONDS = 1

local Demo = {}
Demo.player = Players.LocalPlayer
Demo._nonce = "local"
Demo._config = { readyTimeout = 90, preroll = 1.5 }
Demo._readyCheck = nil
Demo._signal = function(_kind) end

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

local function prefix()
	return "[demo:" .. Demo._nonce .. "] "
end

function Demo.log(message)
	print(prefix() .. message)
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

local inputManager = nil

-- The project's InputManager (Runner framework: ReplicatedStorage.Shared.Generic.InputManager, which the Runner only
-- moves into ReplicatedStorage at run time), waiting up to `timeout` for it. Only a found module is cached, so an early
-- call cannot pin "none" for the rest of the demo.
local function findInputManager(timeout)
	if inputManager then
		return inputManager
	end
	local shared = ReplicatedStorage:WaitForChild("Shared", timeout)
	local generic = shared and shared:WaitForChild("Generic", timeout)
	local module = generic and generic:WaitForChild("InputManager", timeout)
	if not module then
		return nil
	end
	local loaded, result = pcall(require, module)
	if loaded and type(result) == "table" and type(result.simulateKey) == "function" then
		inputManager = result
	end
	return inputManager
end

-- Presses the key through InputManager.simulateKey: the same action path as the keyboard, in-game, with no latency.
-- A key not bound yet is retried for KEY_BIND_SECONDS (the component binding it may still be starting), then errors.
-- There is no OS-level fallback: a real key press goes to whatever window has focus (in the editor an installed
-- plugin binds F to Delete), so a project without InputManager drives the feature through Demo.component instead.
function Demo.key(keyCode, holdSeconds)
	local hold = holdSeconds or 0.15
	local code = if typeof(keyCode) == "EnumItem" then keyCode else Enum.KeyCode[tostring(keyCode)]
	local manager = findInputManager(10)
	if not manager then
		error("Demo.key: this project has no ReplicatedStorage.Shared.Generic.InputManager with simulateKey; call the feature through Demo.component instead", 2)
	end
	local deadline = os.clock() + KEY_BIND_SECONDS
	while not manager.simulateKey(code, hold) do
		if os.clock() > deadline then
			error(string.format("Demo.key: %s is not bound to any InputManager action after %d s", code.Name, KEY_BIND_SECONDS), 2)
		end
		task.wait(0.1)
	end
	Demo.log("key " .. code.Name)
	task.wait(hold)
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

function Demo._marker(secondColour)
	marker.BackgroundColor3 = MARKER_COLOUR
	marker.Visible = true
	task.wait(MARKER_SECONDS)
	marker.BackgroundColor3 = secondColour
	task.wait(MARKER_SECONDS)
	marker.Visible = false
	task.wait(0.1)
end

local isReady = false
local begun = false

-- Waits until the game view is worth recording: the game loaded, the character and its root part in, the viewport
-- size unchanged for VIEWPORT_STABLE_SECONDS, and the project's own check (demo-source/ready.luau, Demo._readyCheck)
-- true; then holds Demo._config.preroll seconds. Errors after Demo._config.readyTimeout. Runs once.
function Demo.ready()
	if isReady then
		return
	end
	local started = os.clock()
	local deadline = started + Demo._config.readyTimeout
	local function waitFor(what, check)
		while not check() do
			if os.clock() > deadline then
				error(string.format("Demo.ready: %s not ready after %d s", what, Demo._config.readyTimeout), 0)
			end
			task.wait(0.1)
		end
	end
	waitFor("game:IsLoaded()", function()
		return game:IsLoaded()
	end)
	waitFor("the character", function()
		local character = Demo.player.Character
		return character ~= nil and character:FindFirstChild("HumanoidRootPart") ~= nil and character:FindFirstChildOfClass("Humanoid") ~= nil
	end)
	local lastSize, stableSince = nil, os.clock()
	waitFor("a stable viewport", function()
		local size = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
		if size ~= lastSize then
			lastSize, stableSince = size, os.clock()
		end
		return size ~= nil and size.X > 100 and size.Y > 100 and os.clock() - stableSince >= VIEWPORT_STABLE_SECONDS
	end)
	if Demo._readyCheck then
		local complained = false
		waitFor("the project's ready check (demo-source/ready.luau)", function()
			local ok, result = pcall(Demo._readyCheck, Demo)
			if not ok and not complained then
				complained = true
				warn(prefix() .. "ready check errored (retrying): " .. tostring(result))
			end
			return ok and result == true
		end)
	end
	task.wait(Demo._config.preroll)
	isReady = true
	Demo.log(string.format("ready after %.1f s", os.clock() - started))
end

-- The clip starts here: the start flash, after Demo.ready(). A demo that does its own setup first (waits for knights,
-- teleports) calls this once that is done, so the setup is not in the clip; otherwise it runs before the first line.
function Demo.begin()
	if begun then
		return
	end
	Demo.ready()
	begun = true
	Demo.log("start")
	Demo._signal("begin")
	Demo._marker(MARKER_START_COLOUR)
end

function Demo._run(body, deferBegin)
	local succeeded, failure = pcall(function()
		Demo.ready()
		if not deferBegin then
			Demo.begin()
		end
		body(Demo)
		if not begun then
			error("the demo finished without calling Demo.begin()", 0)
		end
	end)
	if not succeeded then
		warn(prefix() .. "error: " .. tostring(failure))
		if begun then
			Demo.caption("Demo error: " .. tostring(failure))
			task.wait(3)
		end
	end
	if begun then
		Demo.clearCaption()
		Demo._marker(if not succeeded and Demo._config.errorFlash then MARKER_ERROR_COLOUR else MARKER_END_COLOUR)
	end
	Demo.log("done")
	Demo._signal("done")
	releaseCamera()
	overlay:Destroy()
end

return Demo
