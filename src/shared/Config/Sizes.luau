--!strict
-- Weight / size rolls for fish.
--
-- A normal catch rolls t = random()^curveExponent (luck pushes it a little toward heavy),
-- weight = lerp(minWeight, maxWeight, t) and value multiplier = lerp(valueAtMin, valueAtMax, t).
-- A Colossal roll replaces that with a weight above the species maximum, a big value multiplier
-- and a 3x model scale in reveals and the aquarium.

return {
	curveExponent = 1.8,
	-- luck^luckExponent divides curveExponent (never below minExponent), making heavy fish likelier.
	luckExponent = 0.25,
	minExponent = 1.0,
	valueAtMin = 0.6,
	valueAtMax = 1.5,
	modelScaleAtMin = 0.85,
	modelScaleAtMax = 1.25,

	colossal = {
		odds = 500, -- 1 in 500 (× luck^Game.Luck.ColossalExponent)
		valueMultiplier = 5,
		modelScale = 3,
		weightMin = 1.6, -- × species max weight
		weightMax = 2.4,
	},
}
