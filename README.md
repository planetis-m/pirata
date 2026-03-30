# Pirata

`pirata` is a compact ECS for Nim that lets you register components with an enum, spawn entities fast, and query them with plain code you can read at a glance.

If you want an ECS that feels direct instead of ceremonial, this is the pitch:
- one plain world object
- one enum for component kinds
- payload components and zero-storage tags
- flat queries with include/exclude masks
- an API small enough to memorize

## Why Use It?

- It stays readable when the project grows. The core loop is still `spawn`, `add`, `fetch`, `remove`, `query`.
- Tags are first-class. Register them once, attach them with `world.add(entity, ckTag)`, and filter them out with plain set literals.
- Component lookup is explicit. You own the component enum, so access stays predictable.
- Entity handles recycle safely. Destroyed entities do not quietly turn into valid data again.
- The world is a plain object and accidental copies are blocked.

## Install

`pirata` currently lives inside this repository. Add the source directory to your Nim path:

```text
--path:"libs/pirata/src"
```

Then import it:

```nim
import pirata
```

You can compile a file directly with:

```bash
nim c -r --path:libs/pirata/src your_game.nim
```

## Two-Minute Start

This is the basic shape of `pirata`: declare component kinds, register storage, spawn entities, and run a query.

```nim
import pirata

type
  ComponentKind = enum
    ckPosition
    ckVelocity
    ckShip
    ckSunk

  Position = object
    x, y: float32

  Velocity = object
    x, y: float32

  Ship = object
    name: string

var world = newPirata[ComponentKind](128)
world.register(ckPosition, Position)
world.register(ckVelocity, Velocity)
world.register(ckShip, Ship)
world.registerTag(ckSunk)

let pearl = world.spawn()
world.add(pearl, ckShip, Ship(name: "Black Pearl"))
world.add(pearl, ckPosition, Position(x: 10, y: 4))
world.add(pearl, ckVelocity, Velocity(x: 2, y: 1))

for entity in world.query({ckShip, ckPosition, ckVelocity}, {ckSunk}):
  let drift = world.fetch(entity, ckVelocity, Velocity)
  world.fetch(entity, ckPosition, Position).x += drift.x
  world.fetch(entity, ckPosition, Position).y += drift.y

echo world.fetch(pearl, ckPosition, Position)
```

What to notice:
- `register(kind, Type)` creates payload storage for that component.
- `registerTag(kind)` creates a component that lives only in the entity signature.
- Query filters are native Nim sets, so `world.query({ckShip}, {ckSunk})` reads exactly like the data it matches.

## Pirate Demo

The full example lives in [`examples/pirates.nim`](./examples/pirates.nim). It builds a tiny fleet, sails only the ships that are still afloat, loots a treasure chest, and updates the winner's crew and rum.

```nim
import ../src/pirata

type
  ComponentKind = enum
    ckPosition
    ckVelocity
    ckShip
    ckTreasure
    ckSunk

  Position = object
    x, y: float32

  Velocity = object
    x, y: float32

  Ship = object
    name: string
    crew: int
    rum: int

  Treasure = object
    doubloons: int

proc sail(world: var PirataWorld[ComponentKind]) =
  for entity in world.query({ckShip, ckPosition, ckVelocity}, {ckSunk}):
    let drift = world.fetch(entity, ckVelocity, Velocity)
    world.fetch(entity, ckPosition, Position).x += drift.x
    world.fetch(entity, ckPosition, Position).y += drift.y

proc fleetReport(world: var PirataWorld[ComponentKind]) =
  echo "Fleet report:"
  for entity in world.query({ckShip, ckPosition}, {ckSunk}):
    let ship = world.fetch(entity, ckShip, Ship)
    let pos = world.fetch(entity, ckPosition, Position)
    echo "  ", ship.name, " at (", pos.x, ", ", pos.y, "), crew=", ship.crew, ", rum=", ship.rum

var world = newPirata[ComponentKind](64)
world.register(ckPosition, Position)
world.register(ckVelocity, Velocity)
world.register(ckShip, Ship)
world.register(ckTreasure, Treasure)
world.registerTag(ckSunk)

let blackPearl = world.spawn()
world.add(blackPearl, ckShip, Ship(name: "Black Pearl", crew: 28, rum: 14))
world.add(blackPearl, ckPosition, Position(x: 10, y: 5))
world.add(blackPearl, ckVelocity, Velocity(x: 3, y: 1))

let queenAnnesRevenge = world.spawn()
world.add(queenAnnesRevenge, ckShip, Ship(name: "Queen Anne's Revenge", crew: 40, rum: 9))
world.add(queenAnnesRevenge, ckPosition, Position(x: -4, y: 2))
world.add(queenAnnesRevenge, ckVelocity, Velocity(x: 2, y: 0))

let wreck = world.spawn()
world.add(wreck, ckShip, Ship(name: "Wreck of Nassau", crew: 0, rum: 0))
world.add(wreck, ckPosition, Position(x: 100, y: -30))
world.add(wreck, ckSunk)

let treasureChest = world.spawn()
world.add(treasureChest, ckTreasure, Treasure(doubloons: 250))
world.add(treasureChest, ckPosition, Position(x: 14, y: 6))

echo "Before sailing:"
fleetReport(world)

sail(world)

let prize = world.fetch(treasureChest, ckTreasure, Treasure).doubloons
world.fetch(blackPearl, ckShip, Ship).rum += 5
world.fetch(blackPearl, ckShip, Ship).crew += prize div 100
world.destroy(treasureChest)

world.remove(queenAnnesRevenge, ckVelocity)

echo ""
echo "After one raid:"
fleetReport(world)
```

Expected output:

```text
Before sailing:
Fleet report:
  Black Pearl at (10.0, 5.0), crew=28, rum=14
  Queen Anne's Revenge at (-4.0, 2.0), crew=40, rum=9

After one raid:
Fleet report:
  Black Pearl at (13.0, 6.0), crew=30, rum=19
  Queen Anne's Revenge at (-2.0, 2.0), crew=40, rum=9
```

Why this example matters:
- Ships, treasure, and wrecks all live in one world without extra scaffolding.
- `ckSunk` is a true tag component, so wrecks are filtered out without storing dead payload data.
- Looting and movement stay as plain gameplay code, not framework ceremony.

## Common Pattern: Tags And Filters

Tags are useful for state like `Dead`, `Hidden`, `Sleeping`, `Selected`, or `NeedsSync`.

```nim
for entity in world.query({ckPosition, ckVelocity}, {ckSleeping}):
  let velocity = world.fetch(entity, ckVelocity, Velocity)
  world.fetch(entity, ckPosition, Position).x += velocity.x
  world.fetch(entity, ckPosition, Position).y += velocity.y
```

That pattern scales well because it stays obvious:
- the first mask says what must exist
- the second mask says what must not exist

## API At A Glance

- `newPirata[ComponentKind](capacity)`
- `world.register(ckPosition, Position)`
- `world.registerTag(ckSunk)`
- `let entity = world.spawn()`
- `world.add(entity, ckPosition, Position(...))`
- `world.add(entity, ckSunk)`
- `world.fetch(entity, ckPosition, Position)`
- `world.remove(entity, ckPosition)`
- `world.has(entity, ckPosition)`
- `world.destroy(entity)`
- `world.query({ckPosition, ckVelocity})`
- `world.query({ckShip}, {ckSunk})`

## Limits

- `maxEntities` must stay within the current entity-id limit of `8191`.
- The component enum defines the world layout, so keep it deliberate and compact.
- `pirata` is built around slot-indexed columns and flat queries.

## Runtime Contract

`pirata` assumes the world layout is finalized up front and that hot-path entity/component usage is valid. It does not re-validate every entity handle and component access on each `add`, `fetch`, `remove`, `has`, or `destroy` call.

## Run The Demo And Tests

Run the pirate example:

```bash
nim c -r libs/pirata/examples/pirates.nim
```

Run the test modules:

```bash
nim c -r libs/pirata/tests/test_pirata.nim
nim c -r libs/pirata/tests/test_slottables.nim
```

Run the micro-benchmarks:

```bash
nimble benchmark
nimble benchmark_asan
```
