SwiftSTM
========
This library provides Haskell-like Software Transactional Memory for Swift

Warning:
- Code is in experimental state and not tested for production
- retry() has fixed return type and currently works fine ONLY if it is last call in the chain.

Example
========
```Swift
// SimpleObject class conforms TVarProtocol
let someInt1 = 1
let someArr2 = [3, 4]
let someObj3 = SimpleObject(5, 6)

var tvar1 = newTVar(someInt1)
var tvar2 = newTVar(someArr2)
var tvar3 = newTVar(someObj3)

let stmTest1:STM<()> =
        readTVar(tvar1) >>>= { x1   in
        readTVar(tvar2) >>>= { arr2 in
        readTVar(tvar3) >>>= { obj3 in
            let (x2, y2) = (arr2[0], arr2[1])
            let (x3, y3) = obj3.getXY()
            
            if x1 == 1 {
                return retryExperimental()
            } else {
                return writeTVar(tvar2, [x1+x3, y2+y3])                >>>
                     { writeTVar(tvar3, SimpleObject(x2+x3, y2+y3))  } >>>
                     { returnM()                                     }
            }
        }}}

let stmTest2 = writeTVar(tvar1, 100)

let queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
let group = dispatch_group_create()

dispatch_group_async(group, queue) { atomic(stmTest1) }

dispatch_group_async(group, queue) { atomic(stmTest2) }

dispatch_group_wait(group, DISPATCH_TIME_FOREVER)

let arrRes = readTVarAtomic(tvar2)
let (x1, y1) = (arrRes[0], arrRes[1]) // x1 = 105, y1 = 10
let (x2, y2) = readTVarAtomic(tvar3).getXY() // x2 = 8, y2 = 10
```
