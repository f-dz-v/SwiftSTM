// Copyright (c) 2014, f-dz-v
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// * Redistributions of source code must retain the above copyright notice, this
//   list of conditions and the following disclaimer.
//
// * Redistributions in binary form must reproduce the above copyright notice,
//   this list of conditions and the following disclaimer in the documentation
//   and/or other materials provided with the distribution.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
// OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

import Cocoa
import XCTest
import STM

public class SimpleObject: TVarProtocol, Equatable {
    public var x:Int = 0
    public var y:Int = 0
    
    public init(_ x:Int,_ y:Int) {
        self.x = x
        self.y = y
    }
    
    public func copy() -> SimpleObject {
        return SimpleObject(self.x, self.y)
    }
    
    public func getXY() -> (Int, Int) {
        return (self.x, self.y)
    }
    
}

public func ==(lhs: SimpleObject, rhs: SimpleObject) -> Bool {
    if (lhs.x == rhs.x) && (lhs.y == rhs.y) {
        return true
    } else {
        return false
    }
}

class STMTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func testSTMsimple() {
        let someObj = SimpleObject(11, 23)
        
        var tvar1 = newTVar(someObj)
        let stmTest1 = writeTVar(tvar1, SimpleObject(4,7))   >>>=
                     { readTVar(tvar1)                     } >>>
                     { writeTVar(tvar1, SimpleObject(6,9)) } >>>=
                     { readTVar(tvar1)                     }

        let (x1, y1) = atomic(stmTest1).getXY()
        
        var tvar2 = newTVar(someObj)
        
        let (x2, y2) = readTVarAtomic(tvar2).getXY()
        
        XCTAssert(x1 == 6 && y1 == 9, "writeTVar then readTVar OK")
        XCTAssert(x2 == 11 && y2 == 23, "readTVar OK")
    }
    
    func testSTMwithRestart() {
        let someObj = SimpleObject(11, 23)
        
        func fun (x: SimpleObject) -> SimpleObject {
            sleep(2)
            let (x, y) = x.getXY()
            return SimpleObject(x+10, y + 20)
        }
        
        var tvar = newTVar(someObj)
        let stmTest1 = modifyTVar(tvar, fun) >>>
                     { readTVar(tvar) }
        let stmTest2 = writeTVar(tvar, SimpleObject(6,9)) >>>
                     { readTVar(tvar) }
        
        let queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
        let group = dispatch_group_create()
        
        var x1 = 0
        var y1 = 0
        var x2 = 0
        var y2 = 0
        
        dispatch_group_async(group, queue) { (x1, y1) = atomic(stmTest1).getXY() }
        
        dispatch_group_async(group, queue) {
            sleep(1)
            (x2, y2) = atomic(stmTest2).getXY()
        }
        dispatch_group_wait(group, DISPATCH_TIME_FOREVER)
        
        XCTAssert((x1 == 16 && y1 == 29) && (x2 == 6 && y2 == 9), "restart OK")
    }
    
    func testSTMRetry() {
        let someObj = SimpleObject(11, 23)
        
        func fun (x: SimpleObject) -> SimpleObject {
            let (x, y) = x.getXY()
            return SimpleObject(x+10, y + 20)
        }
        
        var tvar = newTVar(someObj)
        let stmTest1:STM<()> = modifyTVar(tvar, fun) >>>
                             { readTVar(tvar)}       >>>=
                             { if $0.x != 16 {
                                    return retry()
                               } else {
                                    return returnM()
                             }}
        let stmTest2 = writeTVar(tvar, SimpleObject(6,9)) >>>
                     { readTVar(tvar) }
        
        
        let queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
        let group = dispatch_group_create()
        
        var x1 = 0
        var y1 = 0
        var x2 = 0
        var y2 = 0
        
        dispatch_group_async(group, queue) {
            atomic(stmTest1)
        }
        
        dispatch_group_async(group, queue) {
            sleep(1)
            (x2, y2) = atomic(stmTest2).getXY()
        }
        dispatch_group_wait(group, DISPATCH_TIME_FOREVER)
        
        (x1, y1) = readTVarAtomic(tvar).getXY()
        
        XCTAssert((x1 == 16 && y1 == 29) && (x2 == 6 && y2 == 9), "retry OK")
    }
    
    func testSTMSeveralTVars() {
        let someInt1 = 1
        let someArr2 = [3, 4]
        let someObj3 = SimpleObject(5, 6)
        
        var tvar1 = newTVar(someInt1)
        var tvar2 = newTVar(someArr2)
        var tvar3 = newTVar(someObj3)
        
        let stmTest1:STM<()> =
                readTVar(tvar1) >>>= { x1 in
                readTVar(tvar2) >>>= { arr2 in
                readTVar(tvar3) >>>= { obj3 in
                    let (x2, y2) = (arr2[0], arr2[1])
                    let (x3, y3) = obj3.getXY()
                    
                    if x1 == 1 {
                        return retry()
                    } else {
                        return writeTVar(tvar2, [x1+x3, y2+y3])                >>>
                             { writeTVar(tvar3, SimpleObject(x2+x3, y2+y3))  } >>>
                             { returnM()                                     }
                    }
                }}}
        
        let stmTest2 = writeTVar(tvar1, 100)
        
        let queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
        let group = dispatch_group_create()
        
        dispatch_group_async(group, queue) {
            atomic(stmTest1)
        }
        
        dispatch_group_async(group, queue) {
            atomic(stmTest2)
        }
        
        dispatch_group_wait(group, DISPATCH_TIME_FOREVER)
        
        let arrRes = readTVarAtomic(tvar2)
        let (x1, y1) = (arrRes[0], arrRes[1])
        let (x2, y2) = readTVarAtomic(tvar3).getXY()
        
        XCTAssert((x1 == 105 && y1 == 10) && (x2 == 8 && y2 == 10), "3 tvars OK")
    }
    
    func testSTMInt() {
        let someInt = 11
        
        func fun (x: Int) -> Int {
            return (x+10)
        }
        
        var tvar = newTVar(someInt)
        let stmTest1:STM<()> = modifyTVar(tvar, fun) >>>
                             { readTVar(tvar)}       >>>=
                             { if $0 != 16 {
                                 return retry()
                             } else {
                                 return returnM()
                             }}
        let stmTest2 = writeTVar(tvar, 6) >>> { readTVar(tvar) }
        
        
        let queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
        let group = dispatch_group_create()
        
        var x1 = 0
        var x2 = 0
        
        dispatch_group_async(group, queue) {
            atomic(stmTest1)
        }
        
        dispatch_group_async(group, queue) {
            sleep(1)
            x2 = atomic(stmTest2)
        }
        dispatch_group_wait(group, DISPATCH_TIME_FOREVER)
        
        x1 = readTVarAtomic(tvar)
        
        XCTAssert(x1 == 16 && x2 == 6, "retry OK")

    }
}
