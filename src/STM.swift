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

import Foundation

//---------------------//
//MARK: Public API
//---------------------//
public protocol TVarProtocol {
    init(copy: TVarProtocol)
}

extension TVarProtocol {
    private func copy() -> Self {
        return Self(copy: self)
    }
}

extension TVarProtocol {
    public init(copy: TVarProtocol){
        self = copy as! Self
    }
}

public struct STM<A> {
    private var run: _STM<A?>
    
    private init(_ x: _STM<A?>) {
        run = x
    }
    
    public func flatMap<B> (processorGenerator: (A -> STM<B>)) -> STM<B> {
        let res: _STM<B?> = self.run.flatMap {
            if let x = $0 {
                return processorGenerator(x).run
            } else {
                return returnM(nil)
            }
        }
        
        return STM<B>(res)
    }
    
    public func flatMap_<B> (processorGenerator: (() -> STM<B>)) -> STM<B> {
        let res: _STM<B?> = self.run.flatMap {
            if let _ = $0 {
                return processorGenerator().run
            } else {
                return returnM(nil)
            }
        }
        
        return STM<B>(res)
    }
    
}

public func returnM<A> (x:A) -> STM<A> {
    return STM(returnM(x))
}


/**
Performs transaction. Warning: Swifts type system does not allow to explicitly mark function as pure.
So you still able to add function with side-effects in transactions chain
*/
public func atomic<A> (stm:STM<A>) -> A {
    var needRestart = false
    var res: A?
    var tr: Transactions
    repeat {
        needRestart = false
        (res, tr) = stm.run.run(Transactions())
        if res == nil {
            tr.validateAndWait()
            needRestart = true
        } else if !(tr.validateAndCommit()) {
            needRestart = true
        }
    } while needRestart

    return res!
}

public class TVarCommon {
    private var id: Int
    private var waitQ:[Int:dispatch_semaphore_t] = [:]
    private var fineGrainLock = _SpinlockWrapped()
    
    private init() {
        self.id = _IDGenerator.requestID()
    }
    
    private func _insertInWaitQ(key:Int, _ value:dispatch_semaphore_t) -> () {
        self.waitQ[key] = value
    }
    private func _deleteFromWaitQ(key:Int) -> () {
        self.waitQ.removeValueForKey(key)
    }
    
    deinit {
        _IDGenerator.freeID(self.id)
    }
}

public final class TVar<T: TVarProtocol where T: Equatable>: TVarCommon, _TVarPrivateProtocol {
    private var value: T
    
    private init(_ data: T) {
        self.value = data.copy()
        super.init()
    }
    
    //maybe we should use .copy
    private func _setValue(x:TVarProtocol) {
        self.value = x as! T
    }
    
    private func _getValue() -> TVarProtocol {
        return self.value
    }
    
    private func _isEqual(x:TVarProtocol) -> Bool {
        return (self.value == (x as! T))
    }
    
//    public func setValue(x:T) {
//        self.value = x.copy()
//    }
//
//    public func getValue() -> T {
//        return self.value.copy()
//    }
}

public final class TVarArray<T: Equatable>: TVarCommon, _TVarPrivateProtocol {
    private var value: [T]
    
    private init(_ data: [T]) {
        self.value = data.copy()
        super.init()
    }
    
    private func _setValue(x:TVarProtocol) {
        self.value = x as! [T]
    }
    
    private func _getValue() -> TVarProtocol {
        return self.value
    }
    
    private func _isEqual(x:TVarProtocol) -> Bool {
        return (self.value == (x as! [T]))
    }
}

public final class TVarDictionary<K: Equatable, V: Equatable where K: Hashable>: TVarCommon,_TVarPrivateProtocol {
    private var value: [K:V]
    
    private init(_ data: [K:V]) {
        self.value = data.copy()
        super.init()
    }
    
    private func _setValue(x:TVarProtocol) {
        self.value = x as! [K:V]
    }
    
    private func _getValue() -> TVarProtocol {
        return self.value
    }
    
    private func _isEqual(x:TVarProtocol) -> Bool {
        return (self.value == (x as! [K:V]))
    }
}

//MARK: newTVar
public func newTVar<T: TVarProtocol>(val: T) -> TVar<T> {
    return TVar(val)
}

public func newTVar<T>(val: [T]) -> TVarArray<T> {
    return TVarArray(val)
}

public func newTVar<K,V>(val: [K:V]) -> TVarDictionary<K,V> {
    return TVarDictionary(val)
}

public func newTVarSTM<T: TVarProtocol>(val: T) -> STM<TVar<T>> {
    return returnM(TVar(val))
}

public func newTVarSTM<T>(val: [T]) -> STM<TVarArray<T>> {
    return returnM(TVarArray(val))
}

public func newTVarSTM<K,V>(val: [K:V]) -> STM<TVarDictionary<K,V>> {
    return returnM(TVarDictionary(val))
}

//MARK: readTVar
public func readTVar<T: TVarProtocol>(tvar: TVar<T>) -> STM<T> {
    return STM( _readTVar(tvar) )
}

public func readTVar<T>(tvar: TVarArray<T>) -> STM<[T]> {
    return STM( _readTVar(tvar) )
}

public func readTVar<K, V>(tvar: TVarDictionary<K, V>) -> STM<[K:V]> {
    return STM( _readTVar(tvar) )
}

public func readTVarAtomic<T: TVarProtocol>(tvar: TVar<T>) -> T {
    return (tvar.value.copy())
}

public func readTVarAtomic<T>(tvar: TVarArray<T>) -> [T] {
    return (tvar.value.copy())
}

public func readTVarAtomic<K, V>(tvar: TVarDictionary<K, V>) -> [K:V] {
    return (tvar.value.copy())
}

//MARK: writeTVar
public func writeTVar<T: TVarProtocol> (tvar: TVar<T>, _ val: T) -> STM<()> {
    return STM( _writeTVar(tvar, val) )
}

public func writeTVar<T> (tvar: TVarArray<T>, _ val: [T]) -> STM<()> {
    return STM(  _writeTVar(tvar, val) )
}

public func writeTVar<K,V> (tvar: TVarDictionary<K,V>, _ val: [K:V]) -> STM<()> {
    return STM( _writeTVar(tvar, val) )
}

//MARK: modifyTVar
public func modifyTVar<T: TVarProtocol> (tvar: TVar<T>, _ f: (T->T)) -> STM<()> {
    return readTVar(tvar).flatMap { writeTVar(tvar, f($0)) }
}

public func modifyTVar<T> (tvar: TVarArray<T>, _ f: ([T]->[T])) -> STM<()> {
    return readTVar(tvar).flatMap { writeTVar(tvar, f($0)) }
}

public func modifyTVar<K,V> (tvar: TVarDictionary<K,V>, _ f: ([K:V]->[K:V])) -> STM<()> {
    return readTVar(tvar).flatMap { writeTVar(tvar, f($0)) }
}

/**
Restarts transaction.
*/
public func retry<A>() -> STM<A> {
    return STM(returnM(nil))
}

//---------------------//
//MARK: Private section
//---------------------//

private struct _STM<A> {
    private var run: (Transactions -> (A, Transactions))
    
    private init(_ x: A) {
        run = {return (x, $0)}
    }
    
    private init(_ f: Transactions -> (A, Transactions)) {
        run = f
    }

    private func flatMap<B>(processorGenerator: (A -> _STM<B>)) -> _STM<B> {
        return _STM<B>( {st -> (B, Transactions) in
            let (x, st1) = self.run(st)
            return processorGenerator(x).run(st1)
        })
    }
    
    private func flatMap_<B>(processorGenerator: (() -> _STM<B>)) -> _STM<B> {
        return _STM<B>( {st -> (B, Transactions) in
            let (_, st1) = self.run(st)
            return processorGenerator().run(st1)
        })
    }
}

private func returnM<A> (x: A) -> _STM<A> {
    return _STM(x)
}

private func _newTVarSTM<T: TVarProtocol>(val: T) -> _STM<TVar<T>> {
    return returnM(TVar(val))
}

private func _newTVarSTM<T>(val: [T]) -> _STM<TVarArray<T>> {
    return returnM(TVarArray(val))
}

private func _newTVarSTM<K,V>(val: [K:V]) -> _STM<TVarDictionary<K,V>> {
    return returnM(TVarDictionary(val))
}

//MARK: readTVar
private func _readTVar<T: TVarProtocol>(tvar: TVar<T>) -> _STM<T?> {
    return _STM({ __readTVar(tvar, $0) })
}

private func _readTVar<T>(tvar: TVarArray<T>) -> _STM<[T]?> {
    return _STM({ __readTVar(tvar, $0) })
}

private func _readTVar<K, V>(tvar: TVarDictionary<K, V>) -> _STM<[K:V]?> {
    return _STM({ __readTVar(tvar, $0) })
}

//MARK: writeTVar
private func _writeTVar<T: TVarProtocol> (tvar: TVar<T>, _ val: T) -> _STM<()?> {
    return _STM({ ((), __writeTVar(tvar, val, $0)) })
}

private func _writeTVar<T> (tvar: TVarArray<T>, _ val: [T]) -> _STM<()?> {
    return _STM({ ((), __writeTVar(tvar, val, $0)) })
}

private func _writeTVar<K,V> (tvar: TVarDictionary<K,V>, _ val: [K:V]) -> _STM<()?> {
    return _STM({ ((), __writeTVar(tvar, val, $0)) })
}

private protocol _TVarPrivateProtocol {
    // Looks like a dirty hack? so it is ;)

    var waitQ:[Int:dispatch_semaphore_t] {get set}
    
    var id: Int {get}
    var fineGrainLock: _SpinlockWrapped {get}

    func _setValue(x:TVarProtocol)
    func _getValue() -> TVarProtocol
    func _isEqual(x:TVarProtocol) -> Bool

    func _insertInWaitQ(key:Int, _ value:dispatch_semaphore_t) -> ()
    func _deleteFromWaitQ(key:Int) -> ()
}

private typealias TVarReadLog = protocol<TVarProtocol>?
private typealias TVarWriteLog = protocol<TVarProtocol>?
private typealias TVarLog = (TVarReadLog, TVarWriteLog)

private let FINE_LOCK_GRAB_ATTEMPTS = 1

private final class Transactions {
    private var log:[Int: TVarLog] = [:]
    private var tvars:[Int: _TVarPrivateProtocol] = [:]
    private var fineLocks: [(Int, _SpinlockWrapped)] = []
    private var sortOnceToken = dispatch_once_t()
    private var forceRetry = false
    private var thereIsNoReads = true
    private var id:Int
    private var sema: dispatch_semaphore_t = dispatch_semaphore_create(0)
    // private var env: UnsafeMutablePointer<Int32>
    
    init() {
        self.id = _IDGenerator.requestID()
    }

    deinit {
        _IDGenerator.freeID(self.id)
    }

    private func grabFineLocks() {
        dispatch_once(&sortOnceToken) {
            self.fineLocks.sortInPlace{ $0.0 < $1.0 }
        }
        
        var unableToGrabAllLocks = false
        var n = FINE_LOCK_GRAB_ATTEMPTS
        
        repeat {
            withSpinlockDo(&_COARSE_LOCK) {
                for (_ , fineLock) in self.fineLocks {
                    unableToGrabAllLocks = !fineLock.tryLock()
                    if unableToGrabAllLocks {
                        break
                    }
                }
            }
            if (unableToGrabAllLocks) && (n == 0) {
//                thread_switch(mach_port_name_t(MACH_PORT_NULL), SWITCH_OPTION_DEPRESS, min_timeout)
//                swtch_pri(0);
                n = FINE_LOCK_GRAB_ATTEMPTS
                sched_yield()
            } else {
                n -= 1 
            }
        } while unableToGrabAllLocks
    }
    
    private func releaseFineLocks() {
        withSpinlockDo(&_COARSE_LOCK) {
            for (_ , fineLock) in self.fineLocks.reverse() {
                fineLock.unlock()
            }
        }
    }
    
    private func releaseFineLocksAndWait() {
        withSpinlockDo(&_COARSE_LOCK) {
            for (_, fineLock) in self.fineLocks.reverse() {
                fineLock.unlock()
            }
        }
        dispatch_semaphore_wait(self.sema, DISPATCH_TIME_FOREVER)
    }
    
    private func withFineGrainLocks(f: ()->()) {
        grabFineLocks()
        f()
        releaseFineLocks()
    }
    
    private func commitAllTVars ()->() {
        for (id, val) in self.tvars {
            if case let (_ , newVal?) = self.log[id]! {
                val._setValue(newVal.copy())
                for (_, sema) in val.waitQ {
                    dispatch_semaphore_signal(sema)
                }
            }

        }
    }
    
    private func validate() -> Bool {
        var res = true
        
        if !thereIsNoReads {
            withFineGrainLocks() {
                for case let (id, (readVal?, _)) in self.log
                    where !( self.tvars[id]!._isEqual(readVal) ) {
                        res = false
                        break
                }
            }
        }
        
        return res
    }

    private func validateAndCommit() -> Bool {
        var res = true

        if thereIsNoReads {
            withFineGrainLocks {self.commitAllTVars()}
        } else {
            var allReadsAreValidated = true
            
            withFineGrainLocks {
                for case let (id, (readVal?, _)) in self.log
                    where !( self.tvars[id]!._isEqual(readVal) ) {
                        allReadsAreValidated = false
                        break
                }
                if allReadsAreValidated {
                    self.commitAllTVars()
                } else {
                    res = false
                }
            }
        }

        return res
    }
    
    private func validateAndWait() -> Bool {
        var res = true
        var needInsert = true

        while(res) {
            grabFineLocks()
            if !(self.thereIsNoReads) {
                for case let  (id, (readVal?, _)) in self.log
                    where !( self.tvars[id]!._isEqual(readVal) ) {
                        res = false
                        break
                }
            }
            
            if res {
                if needInsert {
                    for (id, tvar) in self.tvars {
                        if case (_?, _) = self.log[id]! {
                            tvar._insertInWaitQ(self.id, self.sema)
                        }
                    }
                    needInsert = false
                }
                releaseFineLocksAndWait()
            }
        }
        
        for (id, tvar) in self.tvars {
            if case (_?, _) = self.log[id]! {
                tvar._deleteFromWaitQ(self.id)
            }
        }
        
        releaseFineLocks()

        return res
    }
}

//TODO: nested transactions
private func orElse<A> (stm1:_STM<A>, stm2: _STM<A>) -> A {
    var res: A
    var tr: Transactions
    
    repeat {
        (res, tr) = stm1.run(Transactions())
        if ( tr.validateAndCommit() ) && ( !(tr.forceRetry) ) {
            return res
        } else {
            (res, tr) = stm2.run(Transactions())
        }
    } while (tr.forceRetry) || ( !(tr.validateAndCommit()) )
    
    return res
}

private func __readTVarCommon(tvar: _TVarPrivateProtocol, _ trans: Transactions) -> Int {
    let id = tvar.id
    
    trans.thereIsNoReads = false
    
    if trans.tvars[id] == nil {
        trans.tvars[id] = tvar
        trans.fineLocks.append((id, tvar.fineGrainLock))
    }
    
    return id
}

private func __readTVar<T: TVarProtocol> (tvar: TVar<T>, _ trans: Transactions) -> (T?, Transactions) {
    let id = __readTVarCommon(tvar, trans)
    
    if let (_, writeLog) = trans.log[id]  {
        if let val = writeLog {
            return ((val as! T), trans)
        } else {
            let copy = tvar.value.copy()
            trans.log[id] = (copy, writeLog)
            return (copy, trans)
        }
    } else {
        let copy = tvar.value.copy()
        trans.log[id] = (copy, nil)
        return (copy, trans)
    }
}

private func __readTVar<T> (tvar: TVarArray<T>, _ trans: Transactions) -> ([T]?, Transactions) {
    let id = __readTVarCommon(tvar, trans)
    
    if let (_, writeLog) = trans.log[id]  {
        if let val = writeLog {
            return ((val as! [T]), trans)
        } else {
            let copy = tvar.value.copy()
            trans.log[id] = (copy, writeLog)
            return (copy, trans)
        }
    } else {
        let copy = tvar.value.copy()
        trans.log[id] = (copy, nil)
        return (copy, trans)
    }
}

private func __readTVar<K,V> (tvar: TVarDictionary<K,V>, _ trans: Transactions) -> ([K:V]?, Transactions) {
    let id = __readTVarCommon(tvar, trans)
    
    if let (_, writeLog) = trans.log[id]  {
        if let val = writeLog {
            return ((val as! [K:V]), trans)
        } else {
            let copy = tvar.value.copy()
            trans.log[id] = (copy, writeLog)
            return (copy, trans)
        }
    } else {
        let copy = tvar.value.copy()
        trans.log[id] = (copy, nil)
        return (copy, trans)
    }
}

private func __writeTVarCommon(tvar: _TVarPrivateProtocol, _ trans: Transactions) -> Int {
    let id = tvar.id
    
    if trans.tvars[id] == nil {
        trans.tvars[id] = tvar
        trans.fineLocks.append((id, tvar.fineGrainLock))
    }
    
    return id
}

private func __writeTVar<T: TVarProtocol> (tvar: TVar<T>, _ val: T, _ trans: Transactions) -> Transactions {
    let id = __writeTVarCommon(tvar, trans)
    
    if let (readLog, writeLog) = trans.log[id] {
        var newWriteLog = writeLog
        newWriteLog = val
        trans.log[id] = (readLog, newWriteLog)
        return trans
    } else {
        trans.log[id] = (nil, val)
        return trans
    }
}

private func __writeTVar<T> (tvar: TVarArray<T>, _ val: [T], _ trans: Transactions) -> Transactions {
    let id = __writeTVarCommon(tvar, trans)
    
    if let (readLog, writeLog) = trans.log[id] {
        var newWriteLog = writeLog
        newWriteLog = val
        trans.log[id] = (readLog, newWriteLog)
        return trans
    } else {
        trans.log[id] = (nil, val)
        return trans
    }
}
    
private func __writeTVar<K,V> (tvar: TVarDictionary<K,V>, _ val: [K:V], _ trans: Transactions) -> Transactions {
    let id = __writeTVarCommon(tvar, trans)
    
    if let (readLog, writeLog) = trans.log[id] {
        var newWriteLog = writeLog
        newWriteLog = val
        trans.log[id] = (readLog, newWriteLog)
        return trans
    } else {
        trans.log[id] = (nil, val)
        return trans
    }
}

//---------------------//
//MARK: Private utils
//---------------------//
private func withSpinlockDo(lock: UnsafeMutablePointer<OSSpinLock>, f: ()->()) {
    OSSpinLockLock(lock)
    f()
    OSSpinLockUnlock(lock)
}

struct StackSafe<T> {
    var items = [T]()
    mutating func push(item: T) {
        items.append(item)
    }
    mutating func pop() -> T? {
        if !(items.isEmpty) {
            return items.removeLast()
        } else {
            return nil
        }
    }
}

private var _IDGenerator = __IDGenerator()
private struct __IDGenerator  {
    private var returned:StackSafe<Int> = StackSafe<Int>()
    private var next = 0
    private var spinlock: OSSpinLock = OS_SPINLOCK_INIT
    

    mutating func requestID () -> Int {
        var res = 0
        withSpinlockDo(&spinlock) {
            if let id = self.returned.pop() {
                res = id
            } else {
                res = self.next
                self.next++
            }
        }
        return res
    }
    
    mutating func freeID (id: Int) -> () {
        withSpinlockDo(&spinlock) { self.returned.push(id) }
    }
}

private var _COARSE_LOCK = OS_SPINLOCK_INIT

private final class _SpinlockWrapped {
    private var _spinlock: OSSpinLock = OS_SPINLOCK_INIT
    
    private func lock() {
        OSSpinLockLock(&_spinlock)
    }
    
    private func tryLock() -> Bool {
        return OSSpinLockTry(&_spinlock)
    }
    
    private func unlock() {
        OSSpinLockUnlock(&_spinlock)
    }
}

//---------------------//
//MARK: Extensions
//---------------------//
extension Int: TVarProtocol {}

extension Int8: TVarProtocol {}

extension Int16: TVarProtocol {}

extension Int32: TVarProtocol {}

extension Int64: TVarProtocol {}

extension UInt8: TVarProtocol {}

extension UInt16: TVarProtocol {}

extension UInt32: TVarProtocol {}

extension UInt64: TVarProtocol {}

extension String: TVarProtocol {}

extension Bool: TVarProtocol {}

extension Double: TVarProtocol {}

extension Float: TVarProtocol {}

extension Array: TVarProtocol {}

extension Dictionary: TVarProtocol {}

extension Set: TVarProtocol {}
