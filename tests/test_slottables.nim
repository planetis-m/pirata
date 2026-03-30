import ../src/pirata/slottables

type
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

proc verifyMoveDoesNotDoubleDestroy() =
  destroyedTokens.setLen(0)
  block:
    var table = initSlotTableOfCap[HookTracker](4)
    let tracked = table.incl(makeHookTracker(1))
    var movedTable = move(table)
    doAssert movedTable.contains(tracked)
    doAssert movedTable[tracked].id == 1
  doAssert destroyedTokens.len == 1

proc main() =
  destroyedTokens.setLen(0)
  block:
    var table = initSlotTableOfCap[HookTracker](4)
    let firstTracked = table.incl(makeHookTracker(1))
    let secondTracked = table.incl(makeHookTracker(2))
    let thirdTracked = table.incl(makeHookTracker(3))
    table.del(firstTracked)
    doAssert destroyedTokens.len == 1
    doAssert table.contains(secondTracked)
    doAssert table.contains(thirdTracked)
    doAssert table[secondTracked].id == 2
    doAssert table[thirdTracked].id == 3
  doAssert destroyedTokens.len == 3
  verifyMoveDoesNotDoubleDestroy()

when isMainModule:
  main()
