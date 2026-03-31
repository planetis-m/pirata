import algorithm

import ../src/pirata

type
  ComponentKind = enum
    ckPosition
    ckVelocity
    ckTag
    ckPayload
    ckOwned

  Position = object
    x, y: float32

  Velocity = object
    x, y: float32

  Payload = object
    text: string

  HookTracker = object
    id: int
    token: ptr int

var destroyedTokens: seq[uint] = @[]

proc `=destroy`(x: HookTracker) =
  if x.token != nil:
    let tokenId = cast[uint](x.token)
    for seen in destroyedTokens:
      doAssert seen != tokenId, "HookTracker destroyed twice"
    destroyedTokens.add(tokenId)
    dealloc(x.token)

proc `=wasMoved`(x: var HookTracker) =
  x.token = nil

proc `=copy`(dest: var HookTracker; src: HookTracker) {.error.}

proc makeHookTracker(id: int): HookTracker =
  result = HookTracker(id: id, token: nil)
  result.token = cast[ptr int](alloc(sizeof(int)))
  result.token[] = id

proc initWorld(capacity = 16): PirataWorld[ComponentKind] =
  result = newPirata[ComponentKind](capacity)
  result.register(ckPosition, Position)
  result.register(ckVelocity, Velocity)
  result.registerTag(ckTag)
  result.register(ckPayload, Payload)
  result.register(ckOwned, HookTracker)

proc makeOwnedWorld(id: int): PirataWorld[ComponentKind] =
  result = initWorld(4)
  let entity = result.spawn()
  result.add(entity, ckOwned, makeHookTracker(id))

proc verifyBasicWorldFlow() =
  var world = initWorld()

  let first = world.spawn()
  doAssert world.contains(first)

  world.add(first, ckPosition, Position(x: 1, y: 2))
  doAssert world.has(first, ckPosition)
  doAssert world.fetch(first, ckPosition, Position).x == 1
  doAssert world.fetch(first, ckPosition, Position).y == 2

  world.add(first, ckPayload, Payload(text: "booty"))
  doAssert world.fetch(first, ckPayload, Payload).text == "booty"

  let moving = world.spawn()
  world.add(moving, ckPosition, Position(x: 5, y: 8))
  world.add(moving, ckVelocity, Velocity(x: 1, y: 1))

  let tagged = world.spawn()
  world.add(tagged, ckPosition, Position(x: 9, y: 9))
  world.add(tagged, ckTag)
  doAssert world.contains(tagged)

  var queried: seq[int] = @[]
  for entity in world.query({ckPosition}, {ckTag}):
    queried.add(entity.idx)
  queried.sort()
  doAssert queried == @[first.idx, moving.idx]

  world.remove(moving, ckVelocity)
  doAssert not world.has(moving, ckVelocity)

  world.destroy(first)
  doAssert not world.contains(first)

  let recycled = world.spawn()
  doAssert recycled.idx == first.idx
  doAssert recycled.version != first.version
  doAssert world.contains(recycled)

  world.add(recycled, ckPayload, Payload(text: "fresh"))
  doAssert world.fetch(recycled, ckPayload, Payload).text == "fresh"

  world.add(recycled, ckPosition, Position(x: 3, y: 4))

  world.add(recycled, ckPosition, Position(x: 5, y: 6))
  let position = world.fetch(recycled, ckPosition, Position)
  doAssert position.x == 5
  doAssert position.y == 6

proc verifyDeferredOwnedCleanup() =
  destroyedTokens.setLen(0)
  block:
    var ownedWorld = initWorld(8)
    let keptEntity = ownedWorld.spawn()
    let removedEntity = ownedWorld.spawn()
    ownedWorld.add(keptEntity, ckOwned, makeHookTracker(10))
    ownedWorld.add(removedEntity, ckOwned, makeHookTracker(20))
    doAssert ownedWorld.fetch(keptEntity, ckOwned, HookTracker).id == 10
    ownedWorld.remove(keptEntity, ckOwned)
    ownedWorld.destroy(removedEntity)
    doAssert destroyedTokens.len == 0
  doAssert destroyedTokens.len == 2

  destroyedTokens.setLen(0)
  block:
    var world = initWorld(4)
    let first = world.spawn()
    world.add(first, ckOwned, makeHookTracker(10))
    world.destroy(first)
    doAssert destroyedTokens.len == 0

    let recycled = world.spawn()
    doAssert recycled.idx == first.idx
    world.add(recycled, ckOwned, makeHookTracker(20))
    doAssert destroyedTokens.len == 1
    doAssert world.fetch(recycled, ckOwned, HookTracker).id == 20
  doAssert destroyedTokens.len == 2

proc verifyOwnedComponentOverwrite() =
  destroyedTokens.setLen(0)
  block:
    var world = initWorld(4)
    let entity = world.spawn()
    world.add(entity, ckOwned, makeHookTracker(1))
    world.add(entity, ckOwned, makeHookTracker(2))
    doAssert destroyedTokens.len == 1
    doAssert world.fetch(entity, ckOwned, HookTracker).id == 2
  doAssert destroyedTokens.len == 2

proc verifyWorldMoveDoesNotDoubleDestroy() =
  destroyedTokens.setLen(0)
  block:
    var world = initWorld(4)
    let entity = world.spawn()
    world.add(entity, ckOwned, makeHookTracker(1))
    var movedWorld = move(world)
    doAssert movedWorld.fetch(entity, ckOwned, HookTracker).id == 1
  doAssert destroyedTokens.len == 1

proc verifyWorldSinkAssignment() =
  destroyedTokens.setLen(0)
  block:
    var world = makeOwnedWorld(1)
    world = makeOwnedWorld(2)
    doAssert destroyedTokens.len == 1

    var ownedIds: seq[int] = @[]
    for entity in world.query({ckOwned}):
      ownedIds.add(world.fetch(entity, ckOwned, HookTracker).id)
    doAssert ownedIds == @[2]
  doAssert destroyedTokens.len == 2

proc main() =
  verifyBasicWorldFlow()
  verifyDeferredOwnedCleanup()
  verifyOwnedComponentOverwrite()
  verifyWorldMoveDoesNotDoubleDestroy()
  verifyWorldSinkAssignment()

when isMainModule:
  main()
