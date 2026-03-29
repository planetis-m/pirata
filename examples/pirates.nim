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

proc main() =
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

when isMainModule:
  main()
