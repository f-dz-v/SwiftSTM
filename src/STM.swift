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
    func copy()-> TVarProtocol
}

public class STM<A> {
    private var run: _STM<A?>
    
    private init(_ x: _STM<A?>) {
        run = x
    }
    
    private class func ret(val: _STM<A?>) -> STM {
        return STM(val)
    }
}

public func returnM<A> (x:A) -> STM<A> {
    return STM.ret(returnM(x))
}


/**
Performs transaction. Warning: Swifts type system does not allow to explicitly mark function as pure.
So you still able to add function with side-effects in transactions chain
*/
public func atomic<A> (stm:STM<A>) -> A {
    var needRestart = false
    var res: A?
    var tr: Transactions
    do {
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

infix operator  >>>= {
    associativity left
}

public func >>>= <A,B> (processor: STM<A>, processorGenerator: (A -> STM<B>)) -> STM<B> {
    let res: _STM<B?> = processor.run >>>= {
        if let x = $0 {
            return processorGenerator(x).run
        } else {
            return returnM(nil)
        }
    }

    return STM(res)
}

infix operator  >>> {
    associativity left
}

public func >>> <A,B> (processor: STM<A>, processorGenerator: (() -> STM<B>)) -> STM<B> {
    let res: _STM<B?> = processor.run >>>= {
        if let x = $0 {
            return processorGenerator().run
        } else {
            return returnM(nil)
        }
    }

    return STM(res)
}

public class TVar<T: TVarProtocol where T: Equatable>: _TVarPrivateProtocol {
    private var value: T
    private var id: Int
    private var waitQ:[Int:UnsafeMutablePointer<pthread_cond_t>] = [:]
    
    private init(_ data: T) {
        self.value = data.copy() as T
        self.id = _IDGenerator.sharedInstance.requestID()
    }
    
    deinit {
        _IDGenerator.sharedInstance.freeID(self.id)
    }
    
    //maybe we should use .copy
    private func _setValue(x:TVarProtocol) {
        self.value = x as T
    }
    
    private func _getValue() -> TVarProtocol {
        return self.value
    }
    
    private func _isEqual(x:TVarProtocol) -> Bool {
        return (self.value == (x as T))
    }
    
    func _insertInWaitQ(key:Int, _ value:UnsafeMutablePointer<pthread_cond_t>) -> () {
        self.waitQ[key] = value
    }
    func _deleteFromWaitQ(key:Int) -> () {
        self.waitQ.removeValueForKey(key)
    }
    
//    public func setValue(x:T) {
//        self.value = x.copy()
//    }
//
//    public func getValue() -> T {
//        return self.value.copy()
//    }
}

public class TVarArray<T: Equatable>: _TVarPrivateProtocol {
    private var value: [T]
    private var id: Int
    private var waitQ:[Int:UnsafeMutablePointer<pthread_cond_t>] = [:]
    
    private init(_ data: [T]) {
        self.value = data.copy() as [T]
        self.id = _IDGenerator.sharedInstance.requestID()
    }
    
    deinit {
        _IDGenerator.sharedInstance.freeID(self.id)
    }
    
    private func _setValue(x:TVarProtocol) {
        self.value = x as [T]
    }
    
    private func _getValue() -> TVarProtocol {
        return self.value
    }
    
    private func _isEqual(x:TVarProtocol) -> Bool {
        return (self.value == (x as [T]))
    }
    
    func _insertInWaitQ(key:Int, _ value:UnsafeMutablePointer<pthread_cond_t>) -> () {
        self.waitQ[key] = value
    }
    
    func _deleteFromWaitQ(key:Int) -> () {
        self.waitQ.removeValueForKey(key)
    }
}

public class TVarDictionary<K: Equatable, V: Equatable where K: Hashable>: _TVarPrivateProtocol {
    private var value: [K:V]
    private var id: Int
    private var waitQ:[Int:UnsafeMutablePointer<pthread_cond_t>] = [:]
    
    private init(_ data: [K:V]) {
        self.value = data.copy() as [K:V]
        self.id = _IDGenerator.sharedInstance.requestID()
    }
    
    deinit {
        _IDGenerator.sharedInstance.freeID(self.id)
    }
    
    private func _setValue(x:TVarProtocol) {
        self.value = x as [K:V]
    }
    
    private func _getValue() -> TVarProtocol {
        return self.value
    }
    
    private func _isEqual(x:TVarProtocol) -> Bool {
        return (self.value == (x as [K:V]))
    }

    func _insertInWaitQ(key:Int, _ value:UnsafeMutablePointer<pthread_cond_t>) -> () {
        self.waitQ[key] = value
    }
    
    func _deleteFromWaitQ(key:Int) -> () {
        self.waitQ.removeValueForKey(key)
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
    return (tvar.value.copy() as T)
}

public func readTVarAtomic<T>(tvar: TVarArray<T>) -> [T] {
    return (tvar.value.copy() as [T])
}

public func readTVarAtomic<K, V>(tvar: TVarDictionary<K, V>) -> [K:V] {
    return (tvar.value.copy() as [K:V])
}

//MARK: writeTVar
public func writeTVar<T: TVarProtocol> (tvar: TVar<T>, val: T) -> STM<()> {
    return STM( _writeTVar(tvar, val) )
}

public func writeTVar<T> (tvar: TVarArray<T>, val: [T]) -> STM<()> {
    return STM(  _writeTVar(tvar, val) )
}

public func writeTVar<K,V> (tvar: TVarDictionary<K,V>, val: [K:V]) -> STM<()> {
    return STM( _writeTVar(tvar, val) )
}

//MARK: modifyTVar
public func modifyTVar<T: TVarProtocol> (tvar: TVar<T>, f: (T->T)) -> STM<()> {
    return readTVar(tvar) >>>= { writeTVar(tvar, f($0)) }
}

public func modifyTVar<T> (tvar: TVarArray<T>, f: ([T]->[T])) -> STM<()> {
    return readTVar(tvar) >>>= { writeTVar(tvar, f($0)) }
}

public func modifyTVar<K,V> (tvar: TVarDictionary<K,V>, f: ([K:V]->[K:V])) -> STM<()> {
    return readTVar(tvar) >>>= { writeTVar(tvar, f($0)) }
}

/**
Restarts transaction.
*/
public func retry<A>() -> STM<A> {
    return STM.ret(returnM(nil))
}

//---------------------//
//MARK: Private section
//---------------------//

private class _STM<A> {
    private var run: (Transactions -> (A, Transactions))
    
    private init(_ x: A) {
        run = {return (x, $0)}
    }
    
    private init(_ f: Transactions -> (A, Transactions)) {
        run = f
    }
    
    private class func ret(val:A) -> _STM {
        return _STM(val)
    }

}

private func returnM<A> (x: A) -> _STM<A> {
    return _STM.ret(x)
}

private func >>>= <A,B> (processor: _STM<A>, processorGenerator: (A -> _STM<B>)) -> _STM<B> {
    return _STM( {st -> (B, Transactions) in
        let (x, st1) = processor.run(st)
        return processorGenerator(x).run(st1)
    })
}

private func >>> <A,B> (processor: _STM<A>, processorGenerator: (() -> _STM<B>)) -> _STM<B> {
    return _STM( {st -> (B, Transactions) in
        let (_, st1) = processor.run(st)
        return processorGenerator().run(st1)
    })
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
private func _writeTVar<T: TVarProtocol> (tvar: TVar<T>, val: T) -> _STM<()?> {
    return _STM({ ((), __writeTVar(tvar, val, $0)) })
}

private func _writeTVar<T> (tvar: TVarArray<T>, val: [T]) -> _STM<()?> {
    return _STM({ ((), __writeTVar(tvar, val, $0)) })
}

private func _writeTVar<K,V> (tvar: TVarDictionary<K,V>, val: [K:V]) -> _STM<()?> {
    return _STM({ ((), __writeTVar(tvar, val, $0)) })
}

private protocol _TVarPrivateProtocol {
    // Looks like a dirty hack? so it is ;)

    var waitQ:[Int:UnsafeMutablePointer<pthread_cond_t>] {get set}

    func _setValue(x:TVarProtocol)
    func _getValue() -> TVarProtocol
    func _isEqual(x:TVarProtocol) -> Bool

    func _insertInWaitQ(key:Int, _ value:UnsafeMutablePointer<pthread_cond_t>) -> ()
    func _deleteFromWaitQ(key:Int) -> ()
}

private typealias TVarReadLog = protocol<TVarProtocol>?
private typealias TVarWriteLog = protocol<TVarProtocol>?
private typealias TVarLog = (TVarReadLog, TVarWriteLog)

private class Transactions {
    private var log:[Int: TVarLog] = [:]
    private var tvars:[Int: _TVarPrivateProtocol] = [:]
    private var forceRetry = false
    private var thereIsNoReads = true
    private var id:Int
    private var cond: UnsafeMutablePointer<pthread_cond_t>
    // private var env: UnsafeMutablePointer<Int32>
    
    init() {
        self.id = _IDGenerator.sharedInstance.requestID()
        self.cond = UnsafeMutablePointer.alloc(sizeof(pthread_cond_t))
        pthread_cond_init(self.cond, nil)
    }

    deinit {
        pthread_cond_destroy(self.cond)
        self.cond.dealloc(sizeof(pthread_cond_t))
        _IDGenerator.sharedInstance.freeID(self.id)
    }

    private func commitAllTVars ()->() {
        for (id, val) in self.tvars {
            let (_ , writeLog) = self.log[id]!
            if let newVal = writeLog {
                val._setValue(newVal.copy())
                for (_, cond) in val.waitQ {
                    pthread_cond_signal(cond)
                }
            }
        }
    }
    
    private func validate() -> Bool {
        var res = true
        
        if !thereIsNoReads {
            withMutexDo(_BigSTMLock.sharedInstance.lock) {
                for (id, (readLog, _)) in self.log {
                    if let readVal = readLog {
                        if !( self.tvars[id]!._isEqual(readVal) ) {
                            res = false
                            break
                        }
                    }
                }
            }
        }
        
        return res
    }

    private func validateAndCommit() -> Bool {
        var res = true

        if thereIsNoReads {
            withMutexDo(_BigSTMLock.sharedInstance.lock) {self.commitAllTVars()}
        } else {
            var allReadsAreValidated = true
            
            withMutexDo(_BigSTMLock.sharedInstance.lock) {
                for (id, (readLog, _)) in self.log {
                    if let readVal = readLog {
                        //if !( readVal.isEqual(self.tvars[id]!._getValue()) ) {
                        if !( self.tvars[id]!._isEqual(readVal) ) {
                            allReadsAreValidated = false
                            break
                        }
                    }
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

        withMutexDo(_BigSTMLock.sharedInstance.lock) {
            while(res) {
                if !(self.thereIsNoReads) {
                    for (id, (readLog, _)) in self.log {
                        if let readVal = readLog {
                            if !( self.tvars[id]!._isEqual(readVal) ) {
                                res = false
                                break
                            }
                        }
                    }
                }
                
                if res {
                    if needInsert {
                        for (id, tvar) in self.tvars {
                            let (readVal, _) = self.log[id]!
                            if readVal != nil {
                                tvar._insertInWaitQ(self.id, self.cond)
                            }
                        }
                        needInsert = false
                    }
                    pthread_cond_wait(self.cond, _BigSTMLock.sharedInstance.lock)
                }
            }
        }
        
        for (id, tvar) in self.tvars {
            let (readVal, _) = self.log[id]!
            if readVal != nil {
                tvar._deleteFromWaitQ(self.id)
            }
        }

        return res
    }
}

//TODO: nested transactions
private func orElse<A> (stm1:_STM<A>, stm2: _STM<A>) -> A {
    var res: A
    var tr: Transactions
    
    do {
        (res, tr) = stm1.run(Transactions())
        if ( tr.validateAndCommit() ) && ( !(tr.forceRetry) ) {
            return res
        } else {
            (res, tr) = stm2.run(Transactions())
        }
    } while (tr.forceRetry) || ( !(tr.validateAndCommit()) )
    
    return res
}

private func __readTVar<T: TVarProtocol> (tvar: TVar<T>, trans: Transactions) -> (T?, Transactions) {
    let id = tvar.id
    
    trans.thereIsNoReads = false
    
    if let _ = trans.tvars[id] {
        
    } else {
        trans.tvars[id] = tvar
    }
    
    if let (readLog, writeLog) = trans.log[id]  {
        if let val = writeLog {
            return ((val as T), trans)
        } else {
            let copy = tvar.value.copy() as T
            trans.log[id] = (copy, writeLog)
            return (copy, trans)
        }
    } else {
        let copy = tvar.value.copy() as T
        trans.log[id] = (copy, nil)
        return (copy, trans)
    }
}

private func __readTVar<T> (tvar: TVarArray<T>, trans: Transactions) -> ([T]?, Transactions) {
    let id = tvar.id
    
    trans.thereIsNoReads = false
    
    if let _ = trans.tvars[id] {
        
    } else {
        trans.tvars[id] = tvar
    }
    
    if let (readLog, writeLog) = trans.log[id]  {
        if let val = writeLog {
            return ((val as [T]), trans)
        } else {
            let copy = tvar.value.copy() as [T]
            trans.log[id] = (copy, writeLog)
            return (copy, trans)
        }
    } else {
        let copy = tvar.value.copy() as [T]
        trans.log[id] = (copy, nil)
        return (copy, trans)
    }
}

private func __readTVar<K,V> (tvar: TVarDictionary<K,V>, trans: Transactions) -> ([K:V]?, Transactions) {
    let id = tvar.id
    
    trans.thereIsNoReads = false
    
    if let _ = trans.tvars[id] {
        
    } else {
        trans.tvars[id] = tvar
    }
    
    if let (readLog, writeLog) = trans.log[id]  {
        if let val = writeLog {
            return ((val as [K:V]), trans)
        } else {
            let copy = tvar.value.copy() as [K:V]
            trans.log[id] = (copy, writeLog)
            return (copy, trans)
        }
    } else {
        let copy = tvar.value.copy() as [K:V]
        trans.log[id] = (copy, nil)
        return (copy, trans)
    }
}

private func __writeTVar<T: TVarProtocol> (tvar: TVar<T>, val: T, trans: Transactions) -> Transactions {
    let id = tvar.id
    
    if let _ = trans.tvars[id] {
        
    } else {
        trans.tvars[id] = tvar
    }
    
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

private func __writeTVar<T> (tvar: TVarArray<T>, val: [T], trans: Transactions) -> Transactions {
    let id = tvar.id
    
    if let _ = trans.tvars[id] {
        
    } else {
        trans.tvars[id] = tvar
    }
    
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
    
private func __writeTVar<K,V> (tvar: TVarDictionary<K,V>, val: [K:V], trans: Transactions) -> Transactions {
    let id = tvar.id
    
    if let _ = trans.tvars[id] {
        
    } else {
        trans.tvars[id] = tvar
    }
    
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

private func withMutexDo(mutex: UnsafeMutablePointer<pthread_mutex_t>, f: ()->()) {
    pthread_mutex_lock(mutex)
    f()
    pthread_mutex_unlock(mutex)
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

private let _IDGeneratorSharedInstance = _IDGenerator()
private class _IDGenerator  {
    private var returned:StackSafe<Int> = StackSafe<Int>()
    private var next = 0
    private var lock: UnsafeMutablePointer<pthread_mutex_t>
    
    private init() {
        self.lock = UnsafeMutablePointer.alloc(sizeof(pthread_mutex_t))
        pthread_mutex_init(self.lock, nil)
    }
    
    deinit {
        pthread_mutex_destroy(self.lock)
        self.lock.dealloc(sizeof(pthread_mutex_t))
    }
    
    class var sharedInstance : _IDGenerator {
    return _IDGeneratorSharedInstance
    }
    
    func requestID () -> Int {
        var res = 0
        withMutexDo(self.lock) {
            if let id = self.returned.pop() {
                res = id
            } else {
                res = self.next
                self.next++
            }
        }
        return res
    }
    
    func freeID (id: Int) -> () {
        withMutexDo(self.lock) { self.returned.push(id) }
    }
}

private let _BigSTMLockSharedInstance = _BigSTMLock()
private class _BigSTMLock  {
    private var lock: UnsafeMutablePointer<pthread_mutex_t>
    
    private init() {
        self.lock = UnsafeMutablePointer.alloc(sizeof(pthread_mutex_t))
        pthread_mutex_init(self.lock, nil)
    }
    
    deinit {
        pthread_mutex_destroy(self.lock)
        self.lock.dealloc(sizeof(pthread_mutex_t))
    }
    
    class var sharedInstance : _BigSTMLock {
        return _BigSTMLockSharedInstance
    }
}

//---------------------//
//MARK: Extensions
//---------------------//
extension Int: TVarProtocol {
    public func copy() -> TVarProtocol {
        return self
    }
}

extension Int8: TVarProtocol {
    public func copy() -> TVarProtocol {
        return self
    }
}

extension Int16: TVarProtocol {
    public func copy() -> TVarProtocol {
        return self
    }
}

extension Int32: TVarProtocol {
    public func copy() -> TVarProtocol {
        return self
    }
}

extension Int64: TVarProtocol {
    public func copy() -> TVarProtocol {
        return self
    }
}

extension UInt8: TVarProtocol {
    public func copy() -> TVarProtocol {
        return self
    }
}

extension UInt16: TVarProtocol {
    public func copy() -> TVarProtocol {
        return self
    }
}

extension UInt32: TVarProtocol {
    public func copy() -> TVarProtocol {
        return self
    }
}

extension UInt64: TVarProtocol {
    public func copy() -> TVarProtocol {
        return self
    }
}

extension String: TVarProtocol {
    public func copy() -> TVarProtocol {
        return self
    }
}

extension Bool: TVarProtocol {
    public func copy() -> TVarProtocol {
        return self
    }
}

extension Double: TVarProtocol {
    public func copy() -> TVarProtocol {
        return self
    }
}

extension Float: TVarProtocol {
    public func copy() -> TVarProtocol {
        return self
    }
}

extension Array: TVarProtocol {
    public func copy() -> TVarProtocol {
        return self
    }
}

extension Dictionary: TVarProtocol {
    public func copy() -> TVarProtocol {
        return self
    }
}
