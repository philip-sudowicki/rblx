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
			KeyboardMouse = "Walk to the Launch Bay and press E to dive.",
			Gamepad = "Walk to the Launch Bay and press X to dive.",
			Touch = "Walk to the Launch Bay and tap Dive!",
		},
	},
	{
		id = "Descend",
		icon = "🌊",
		title = "Take her down",
		target = nil,
		text = {
			KeyboardMouse = "Steer with WASD + mouse. Shift sinks, Space rises, Q boosts.",
			Gamepad = "Steer with the sticks. L2 sinks, R2 rises, RB boosts.",
			Touch = "Use the joystick to steer. Hold ⬇️ DOWN to sink.",
		},
	},
	{
		id = "Catch",
		icon = "🎣",
		title = "Catch a fish",
		target = "Fish",
		text = {
			KeyboardMouse = "Swim up to the fish, click, then click again in the green!",
			Gamepad = "Swim up to the fish, press A, then A again in the green!",
			Touch = "Swim up to the fish, tap CATCH, then tap again in the green!",
		},
	},
	{
		id = "Salvage",
		icon = "🧲",
		title = "Salvage treasure",
		target = "Treasure",
		text = {
			KeyboardMouse = "Treasure! Get close and hold the mouse button to grab it.",
			Gamepad = "Treasure! Get close and hold A to grab it.",
			Touch = "Treasure! Get close and hold SALVAGE to grab it.",
		},
	},
	{
		id = "Surface",
		icon = "⬆️",
		title = "Bring it home",
		target = "Surface",
		text = {
			KeyboardMouse = "Loot is safe once you surface. Hold Space to go up.",
			Gamepad = "Loot is safe once you surface. Hold R2 to go up.",
			Touch = "Loot is safe once you surface. Hold ⬆️ UP to go up.",
		},
	},
	{
		id = "Sell",
		icon = "💰",
		title = "Cash in",
		target = "Sell",
		text = {
			KeyboardMouse = "Sell your catch at the Fish Market (press E).",
			Gamepad = "Sell your catch at the Fish Market (press X).",
			Touch = "Sell your catch at the Fish Market.",
		},
	},
	{
		id = "Upgrade",
		icon = "🛠️",
		title = "Upgrade your sub",
		target = "Upgrades",
		text = {
			KeyboardMouse = "Buy an upgrade at the Workshop. Better hull = deeper dives!",
			Gamepad = "Buy an upgrade at the Workshop. Better hull = deeper dives!",
			Touch = "Buy an upgrade at the Workshop. Better hull = deeper dives!",
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
