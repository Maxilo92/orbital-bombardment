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

## Rounds

Each round has its own speed, reach and punch. Flight is the time from firing to impact - the
countdown on the ground.

| Round | Flight | Reload | Radius | Damage | Research |
|---|---|---|---|---|---|
| Tungsten slug | 2 s | 4 s | 2.5 | 25,000 on one point | Orbital bombardment |
| EMP rod | 3 s | 8 s | 14 | 600 electric, units stunned 5 s, worms and nests off 8 s, tesla chain lightning | Orbital EMP munition (electromagnetic science) |
| Tungsten penetrator | 5 s | 10 s | 10 | 10,000 at the core, 4,500 to the edge, levels cliffs | Orbital bombardment |
| Incendiary rod | 6 s | 10 s | 7 | 800 burst, then 15 s of napalm at 8 fire per tick | Orbital incendiary munition |
| Cluster rod | 7 s | 12 s | 20 | 16 bomblets of 2,800 | Orbital cluster munition |
| Guided rod | 8 s | 15 s | 4 | 30,000 direct hit, 3,500 around; locks on and follows its target | Orbital guided munition |

Every round leaves its own mark: the penetrator a large crater, the slug a single hole, the cluster
rod a field of small craters, the incendiary rod blackened ground, the guided rod a mid-sized
crater - and the EMP none.

Recipes: **penetrator** 10 tungsten plate, 4 tungsten carbide, 1 low density structure, 1
processing unit - **slug** 10 tungsten plate - **cluster rod** 6 tungsten carbide, 10 explosives, 2
low density structure, 2 processing unit - **EMP rod** 10 tesla ammo, 2 supercapacitor, 5 tungsten
plate, 1 processing unit - **incendiary rod** 10 flamethrower ammo, 5 tungsten plate, 1 low density
structure, 1 processing unit - **guided rod** 2 tungsten slug, 5 processing unit, 2 low density
structure, 5 explosives.

The **orbital cannon** (1 artillery turret, 50 tungsten plate, 20 low density structure, 20
processing unit) has three ammo slots and fires one round per reload. A queue holds up to 40
waiting targets per planet.

## For other mods

```lua
-- returns ok, err (a localised string) - same checks as the designator
remote.call("orbital-bombardment", "order_strike", force_name, surface_name_or_index, {x = 0, y = 0},
    {ammo = "orbital-guided-rod"}) -- ammo optional, default tungsten-penetrator; positions as {x =, y =} or {x, y}
```

## Compatibility

Requires Space Age. Factorio 2.1 (0.1.0) and 2.0 (0.1.1).
