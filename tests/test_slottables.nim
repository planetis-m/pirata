import algorithm

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

proc makeStringTable(): SlotTable[string] =
  result = initSlotTableOfCap[string](4)
  discard result.incl("booty")
  discard result.incl("rum")

proc verifyCopyProducesIndependentTable() =
  var original = makeStringTable()
  let first = original.incl("gold")
  let second = original.incl("maps")
  var copied = original

  original.del(first)
  doAssert not original.contains(first)
  doAssert copied.contains(first)
  doAssert copied[first] == "gold"
  doAssert copied[second] == "maps"

proc verifyDupProducesIndependentTable() =
  var original = makeStringTable()
  let first = original.incl("parrot")
  var duplicated = `=dup`(original)

  original.del(first)
  doAssert not original.contains(first)
  doAssert duplicated.contains(first)
  doAssert duplicated[first] == "parrot"

proc verifySinkReplacesOwnedStorage() =
  var sinked = initSlotTableOfCap[string](2)
  discard sinked.incl("stale")
  sinked = makeStringTable()

  var values: seq[string] = @[]
  for entry in sinked.pairs:
    values.add(entry.value)
  values.sort()
  doAssert values == @["booty", "rum"]

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
  verifyCopyProducesIndependentTable()
  verifyDupProducesIndependentTable()
  verifySinkReplacesOwnedStorage()
  verifyMoveDoesNotDoubleDestroy()

when isMainModule:
  main()
