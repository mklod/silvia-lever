revise Valve/water-flow logic. all valves are 3-way directional control valves, so there is a complex routing of water flow.

both valves wired so the most-used state is DE-ENERGISED (default, no coil power).
saves coil power and heat over years of use.


VALVE1 = VALVE_PUMP   (Teensy pin D21)
	de-energised (default): flow from pump to thermoblock OPV  ← heaviest duty cycle
	energised:              flow from pump to boiler OPV       ← intermittent (steam only)

	physical port wiring:
		IN   ← pump check valve outlet
		OUT1 → boiler inlet
		OUT2 → thermoblock inlet (via OPV)


VALVE2 = VALVE_THERMOBLOCK   (Teensy pin D20)
	de-energised (default): portafilter manifold → drain   ← pressure relief, safe default
	energised:              portafilter manifold ↔ thermoblock outlet (brewing)

	physical port wiring:
		IN   ← portafilter manifold (and pressure sensor)
		OUT1 → pump line / thermoblock outlet
		OUT2 → drain

	NOTE: V2 IN is the portafilter manifold side, not the thermoblock side. This is
	intentional — it puts the pressure sensor and the relief path on the same physical
	port, so de-energising V2 instantly bleeds manifold pressure to drain regardless
	of upstream pump state.


─── OPERATING MODES ────────────────────────────────────────────────────

to fill/prime the thermoblock:
	leave V1 de-energised (default = pump→thermoblock).
	leave V2 de-energised (default = drain).
	pump/prime, visually inspect overflow coming out of drain. low pressure.

during brew (after priming and heating to brew temp):
	V1 stays de-energised (pump→thermoblock).
	pressing 'brew start' immediately energises V2, allowing pressure to build at the
	portafilter manifold while the pump runs.
	when 'brew stop' is pressed, V2 is de-energised, pump is halted, and remaining
	pressure is relieved instantly through drain via V2.
	max pressure controlled by thermoblock OPV (10–11 bar setting).

to fill/prime the steam boiler:
	energise V1 (pump→boiler).
	V2 stays de-energised (irrelevant during boiler fill).
	pump/prime, visually inspect overflow coming out of boiler OPV.
	when 'prime done' is pressed, pump halts and V1 de-energises.

during steam:
	primed boiler is heated to set temp. water in full boiler expands to become steam.
	excess pressure relieved by boiler OPV.
	a mechanical steam valve (not connected to any electronics) is manually opened by
	the user and manually adjusted to output steam.


─── STATE TABLE ────────────────────────────────────────────────────────

V1   V2   path                                          mode
OFF  OFF  pump → thermoblock → drain                    priming brew, flushing, idle (safe)
OFF  ON   pump → thermoblock → portafilter              brewing
ON   OFF  pump → boiler                                 priming steam, boiler fill
ON   ON   pump → boiler  (V2 state irrelevant)          (not a normal state)
