# Exhaust stack: what can and cannot be vented

The **exhaust stack** chooses its vent recipe by itself. Once a second it reads the fluids held by whatever is
connected to its inlet (the north face when unrotated; rotate the stack to move it) and sets the matching recipe.
Its status line says what it is doing. Run `/ipp-vent-list` in game to print this list.
The single source of truth is `D.vent` in `shared/defs.lua`; vent recipes are generated from it.

## Can be vented

| Fluid | Rate per stack | Unlocked by |
|---|---|---|
| Exhaust steam | 500 /s | Industrial steam power |
| Flue gas | 200 /s | Combined-cycle gas power |
| Hot exhaust (heat-recovery bypass) | 200 /s | Combined-cycle gas power |

## Cannot be vented (the stack refuses and clears its recipe)

| Fluid | Reason |
|---|---|
| Industrial steam, high-pressure steam, steam, water, cooling water, warm cooling water | valuable working fluid: send it to its consumer |
| Fuel gas, petroleum gas, light oil, heavy oil, crude oil | fuel: burn it instead |
| Lubricant, sulfuric acid, primary water, hot primary water, reprocessing solvent | hazardous (the primary water is radioactive): not allowed to be released |
| Anything else (including other mods' fluids) | not on the vent list |

If the connected pipe holds several fluids, a ventable fluid wins over a refused one.
If a fluid is ventable but its recipe is not researched yet, the stack waits and says which research is needed.
To allow another fluid, add it to `D.vent.allowed` (a recipe is generated automatically) and unlock the recipe in a technology.
