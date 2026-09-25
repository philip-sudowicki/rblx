--!strict
-- The first-time tutorial (about 2-3 minutes). Steps advance on real gameplay, checked on the
-- server (TutorialService); the client shows the text for the player's input device and a guide
-- beam to the step's target. Players can skip it at any time from the tutorial panel.
--
-- target: "Launch" | "Sell" | "Upgrades" (dock prompts), "Fish" | "Treasure" (the tutorial
--         spawn), "Surface" (straight up) or nil
-- text  : per input mode (KeyboardMouse / Gamepad / Touch)

export type Step = {
	id: string,
	icon: string,
	title: string,
	target: string?,
	text: { KeyboardMouse: string, Gamepad: string, Touch: string },
}

local steps: { Step } = {
	{
		id = "Launch",
		icon = "⚓",
		title = "Welcome to DEEP HAUL!",
		target = "Launch",
		text = {
			KeyboardMouse = "Follow the beam to the Launch Bay at the end of the pier, press E and launch your sub.",
			Gamepad = "Follow the beam to the Launch Bay at the end of the pier, press X and launch your sub.",
			Touch = "Follow the beam to the Launch Bay at the end of the pier, tap Dive! and launch your sub.",
		},
	},
	{
		id = "Descend",
		icon = "🌊",
		title = "Take her down",
		target = nil,
		text = {
			KeyboardMouse = "Steer with WASD and aim with the mouse. Hold Shift to sink and Space to rise.",
			Gamepad = "Steer with the left stick and aim with the right. Hold L2 to sink and R2 to rise.",
			Touch = "Steer with the joystick and drag to look around. Hold ▼ DOWN to sink.",
		},
	},
	{
		id = "Catch",
		icon = "🎣",
		title = "Catch a fish",
		target = "Fish",
		text = {
			KeyboardMouse = "Swim up to the fish and click to cast. Click again while the marker is inside the green zone!",
			Gamepad = "Swim up to the fish and press A to cast. Press A again while the marker is inside the green zone!",
			Touch = "Swim up to the fish and tap CATCH. Tap again while the marker is inside the green zone!",
		},
	},
	{
		id = "Salvage",
		icon = "🦾",
		title = "Salvage treasure",
		target = "Treasure",
		text = {
			KeyboardMouse = "Treasure lies on the sea floor. Get close and hold the mouse button to grab it with your claw.",
			Gamepad = "Treasure lies on the sea floor. Get close and hold A to grab it with your claw.",
			Touch = "Treasure lies on the sea floor. Get close and hold SALVAGE to grab it with your claw.",
		},
	},
	{
		id = "Surface",
		icon = "⬆️",
		title = "Bring it home",
		target = "Surface",
		text = {
			KeyboardMouse = "Your haul is only safe once you surface. Watch your oxygen and hull, and hold Space to rise to the top.",
			Gamepad = "Your haul is only safe once you surface. Watch your oxygen and hull, and hold R2 to rise to the top.",
			Touch = "Your haul is only safe once you surface. Watch your oxygen and hull, and hold ▲ UP to rise to the top.",
		},
	},
	{
		id = "Sell",
		icon = "💰",
		title = "Cash in",
		target = "Sell",
		text = {
			KeyboardMouse = "Take your catch to the Fish Market, press E and sell it.",
			Gamepad = "Take your catch to the Fish Market, press X and sell it.",
			Touch = "Take your catch to the Fish Market, tap Sell Haul and sell it.",
		},
	},
	{
		id = "Upgrade",
		icon = "🛠️",
		title = "Upgrade your sub",
		target = "Upgrades",
		text = {
			KeyboardMouse = "Visit the Workshop and buy an upgrade. A stronger hull lets you dive deeper, where rarer fish live!",
			Gamepad = "Visit the Workshop and buy an upgrade. A stronger hull lets you dive deeper, where rarer fish live!",
			Touch = "Visit the Workshop and buy an upgrade. A stronger hull lets you dive deeper, where rarer fish live!",
		},
	},
}

local indexOf: { [string]: number } = {}
for index, step in steps do
	indexOf[step.id] = index
end

return {
	steps = steps,
	indexOf = indexOf,
	-- seconds before the tutorial fish/treasure is respawned if it's gone
	respawnCheckSeconds = 4,
}
