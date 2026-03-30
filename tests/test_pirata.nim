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

when runtimeChecksEnabled:
  proc expectPirataError(body: proc ()) =
    var raised = false
    try:
      body()
    except PirataError:
      raised = true
    doAssert raised, "Expected a PirataError"

proc main() =
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

  when runtimeChecksEnabled:
    expectPirataError(proc () =
      discard world.fetch(first, ckVelocity, Velocity)
    )

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

  when runtimeChecksEnabled:
    expectPirataError(proc () =
      discard world.fetch(first, ckPosition, Position)
    )

  let recycled = world.spawn()
  doAssert recycled.idx == first.idx
  doAssert recycled.version != first.version
  doAssert world.contains(recycled)

  world.add(recycled, ckPayload, Payload(text: "fresh"))
  doAssert world.fetch(recycled, ckPayload, Payload).text == "fresh"

  world.add(recycled, ckPosition, Position(x: 3, y: 4))

  when runtimeChecksEnabled:
    expectPirataError(proc () =
      world.add(recycled, ckPosition, Position(x: 5, y: 6))
    )
  else:
    world.add(recycled, ckPosition, Position(x: 5, y: 6))
    let position = world.fetch(recycled, ckPosition, Position)
    doAssert position.x == 5
    doAssert position.y == 6

  destroyedTokens.setLen(0)
  block:
    var table = initSlotTableOfCap[HookTracker](4)
    let firstTracked = table.incl(makeHookTracker(1))
    let secondTracked = table.incl(makeHookTracker(2))
    let thirdTracked = table.incl(makeHookTracker(3))
    table.del(firstTracked)
    doAssert table.contains(secondTracked)
    doAssert table.contains(thirdTracked)
    doAssert table[secondTracked].id == 2
    doAssert table[thirdTracked].id == 3
  doAssert destroyedTokens.len == 3

  destroyedTokens.setLen(0)
  block:
    var ownedWorld = newPirata[ComponentKind](8)
    ownedWorld.register(ckOwned, HookTracker)
    let kept = ownedWorld.spawn()
    let removed = ownedWorld.spawn()
    ownedWorld.add(kept, ckOwned, makeHookTracker(10))
    ownedWorld.add(removed, ckOwned, makeHookTracker(20))
    doAssert ownedWorld.fetch(kept, ckOwned, HookTracker).id == 10
    ownedWorld.remove(kept, ckOwned)
    ownedWorld.destroy(removed)
  doAssert destroyedTokens.len == 2

  traceVisits = 0
  block:
    var tracedWorld = newPirata[ComponentKind](8)
    tracedWorld.register(ckTracked, TracedPayload)
    tracedWorld.register(ckPosition, Position)
    let firstTrace = tracedWorld.spawn()
    let secondTrace = tracedWorld.spawn()
    let plain = tracedWorld.spawn()
    tracedWorld.add(firstTrace, ckTracked, TracedPayload(id: 1))
    tracedWorld.add(secondTrace, ckTracked, TracedPayload(id: 2))
    tracedWorld.add(plain, ckPosition, Position(x: 0, y: 0))
    tracedWorld.remove(secondTrace, ckTracked)
    var env: pointer = nil
    `=trace`(tracedWorld, env)
  doAssert traceVisits == 1

when isMainModule:
  main()
