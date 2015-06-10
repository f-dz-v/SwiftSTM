SwiftSTM
========
This library provides Haskell-like Software Transactional Memory for Swift

Warning:
- This is proof of concept code which not tested for production

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
        readTVar(tvar1).flatMap { x1   in
        readTVar(tvar2).flatMap { arr2 in
        readTVar(tvar3).flatMap { obj3 in
            let (x2, y2) = (arr2[0], arr2[1])
            let (x3, y3) = obj3.getXY()
            
            if x1 == 1 {
                return retry()
            } else {
                return writeTVar(tvar2, [x1+x3, y2+y3]).flatMap_
                     { writeTVar(tvar3, SimpleObject(x2+x3, y2+y3))  }.flatMap_
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
