# Orbital Bombardment

An orbital cannon for your Space Age platforms. Park the platform in orbit, open remote view of
the planet below, mark a target - and a tungsten rod comes down on it from space.

## How it works

1. Research **Orbital bombardment** (after Artillery and Tungsten steel).
2. Build an **Orbital cannon** on a space platform. It cannot be placed on a planet.
3. Load it with **Tungsten penetrators** - by hand, by inserter or by logistic request.
4. Park the platform at a planet. The cannon only fires while the platform is stopped in orbit.
5. Take the **Orbital strike designator** from the shortcut bar, open remote view of the planet
   and click a target. The bar at the top of the screen picks which round comes down. Drag a box to aim at its centre. **Shift + right click/drag** cancels
   targets that have not been fired yet.

A marked target waits in a queue until a cannon over that planet is loaded and ready; the marker
says what it is waiting for. Once fired, the ground shows a red target circle and a five second
countdown - then the rod comes down from orbit faster than the eye can follow, leaving a white-hot
streak from the sky to ground zero, and hits.

Targets have to be in charted territory: you can only hit what your radars can see.

## Numbers

| | |
|---|---|
| Ground zero (4 tiles) | 10,000 physical |
| Blast (10 tiles) | 3,000 explosion + 1,500 physical - enough for a fully evolved nest |
| Also | destroys cliffs within 6 tiles, leaves a crater |
| Flight time | 5 s from firing to impact |
| Reload | 10 s per cannon |
| Queue | up to 40 waiting targets per planet |

**Orbital cannon** - 1 artillery turret, 50 tungsten plate, 20 low density structure, 20 processing
unit. Two per rocket.

**Tungsten penetrator** - 10 tungsten plate, 4 tungsten carbide, 1 low density structure, 1
processing unit. Twenty per rocket.

**Tungsten slug** - 10 tungsten plate. Twenty-five per rocket. 25,000 physical within 1.5 tiles,
little else: the precision round against single targets.

**Cluster rod** (research *Orbital cluster munition*) - 6 tungsten carbide, 10 explosives, 2 low
density structure, 2 processing unit. Breaks up into 12 bomblets over a 12 tile circle, each 3,000
explosion + 1,000 physical within 3.5 tiles.

**EMP rod** (research *Orbital EMP munition*, needs electromagnetic science) - 10 tesla ammo, 2
supercapacitor, 5 tungsten plate, 1 processing unit. 1,200 electric damage within 12 tiles, units
stunned for 5 s, worms and nests switched off for 8 s, tesla chain lightning jumping between enemies.

## For other mods

```lua
-- returns ok, err (a localised string) - same checks as the designator
remote.call("orbital-bombardment", "order_strike", force_name, surface_name_or_index, {x = 0, y = 0},
    {ammo = "orbital-cluster-rod"}) -- ammo optional, default tungsten-penetrator
```

## Compatibility

Requires Space Age. Factorio 2.1 (0.1.0) and 2.0 (0.1.1).
