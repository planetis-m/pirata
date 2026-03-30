import algorithm

import ../src/pirata

type
  ComponentKind = enum
    ckPosition
    ckVelocity
    ckTag
    ckPayload
    ckOwned
    ckTracked

  Position = object
    x, y: float32

  Velocity = object
    x, y: float32

  Payload = object
    text: string

  HookTracker = object
    id: int
    token: ptr int

  TracedPayload = object
    id: int

var destroyedTokens: seq[uint] = @[]
var traceVisits = 0

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

proc `=trace`(x: var TracedPayload; env: pointer) =
  inc traceVisits

proc makeHookTracker(id: int): HookTracker =
  result = HookTracker(id: id, token: nil)
  result.token = cast[ptr int](alloc(sizeof(int)))
  result.token[] = id

proc verifyBasicWorldFlow() =
  var world = newPirata[ComponentKind](16)
  world.register(ckPosition, Position)
  world.register(ckVelocity, Velocity)
  world.registerTag(ckTag)
  world.register(ckPayload, Payload)
  world.register(ckOwned, HookTracker)
  world.register(ckTracked, TracedPayload)

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

proc verifyOwnedComponentCleanup() =
  destroyedTokens.setLen(0)
  var ownedWorld = newPirata[ComponentKind](8)
  ownedWorld.register(ckOwned, HookTracker)
  let keptEntity = ownedWorld.spawn()
  let removedEntity = ownedWorld.spawn()
  ownedWorld.add(keptEntity, ckOwned, makeHookTracker(10))
  ownedWorld.add(removedEntity, ckOwned, makeHookTracker(20))
  doAssert ownedWorld.fetch(keptEntity, ckOwned, HookTracker).id == 10
  ownedWorld.remove(keptEntity, ckOwned)
  ownedWorld.destroy(removedEntity)
  doAssert destroyedTokens.len == 2

proc verifyTracing() =
  traceVisits = 0
  var tracedWorld = newPirata[ComponentKind](8)
  tracedWorld.register(ckTracked, TracedPayload)
  tracedWorld.register(ckPosition, Position)
  let firstTrackedEntity = tracedWorld.spawn()
  let secondTrackedEntity = tracedWorld.spawn()
  let plainEntity = tracedWorld.spawn()
  tracedWorld.add(firstTrackedEntity, ckTracked, TracedPayload(id: 1))
  tracedWorld.add(secondTrackedEntity, ckTracked, TracedPayload(id: 2))
  tracedWorld.add(plainEntity, ckPosition, Position(x: 0, y: 0))
  tracedWorld.remove(secondTrackedEntity, ckTracked)
  var traceEnv: pointer = nil
  `=trace`(tracedWorld, traceEnv)
  doAssert traceVisits == 1

proc main() =
  verifyBasicWorldFlow()
  verifyOwnedComponentCleanup()
  verifyTracing()

when isMainModule:
  main()
