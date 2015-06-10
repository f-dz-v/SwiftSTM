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

public class TBQueue<T: Equatable> {
    private var _q:TVarArray<T> = newTVar([])
    private var _size:TVar<Int>
    private init(_ size: Int) {
        self._size = newTVar(size)
    }
}

public func newTBQueue<T> (size: Int) -> TBQueue<T> {
    return TBQueue(size)
}

public func newTBQueueSTM<T> (size: Int) -> STM<TBQueue<T>> {
    return returnM(TBQueue(size))
}

public func writeTBQueue<T> (queue: TBQueue<T>, _ val: T) -> STM<()> {
    return ( readTVar(queue._size).flatMap {(size) -> STM<()> in
        if size == 0 {
            return retry()
        } else {
            return writeTVar(queue._size, size - 1).flatMap_
                { modifyTVar(queue._q, {$0 + [val]}) }
        }} )
}

public func readTBQueue<T> (queue: TBQueue<T>) -> STM<T> {
    return ( readTVar(queue._q).flatMap { xs in
        if xs.isEmpty {
            return retry()
        }
        let res = xs[0]
        var newArr = xs
        newArr.removeAtIndex(0)
        return writeTVar(queue._q, newArr).flatMap_
            { modifyTVar(queue._size, {$0+1}) }.flatMap_
            { returnM(res)}
        } )
}

// TODO: orElse
public func tryReadTBQueue<T> (queue: TBQueue<T>) -> STM<T?> {
    return ( readTVar(queue._q).flatMap { xs in
        if xs.isEmpty {
            return returnM(nil)
        }
        let res = xs[0]
        var newArr = xs
        newArr.removeAtIndex(0)
        return writeTVar(queue._q, newArr).flatMap_
            { modifyTVar(queue._size, {$0+1}) }.flatMap
            { returnM(res)}
        } )
}

public func unGetTBQueue<T> (queue: TBQueue<T>, _ val: T) -> STM<()> {
    return readTVar(queue._size).flatMap { size in
        if size == 0 {
            return retry()
        } else {
            return modifyTVar(queue._q, {[val] + $0}).flatMap_
                { modifyTVar(queue._size, {$0-1}) }
        }
    }
}

public func peekTBQueue<T> (queue: TBQueue<T>) -> STM<T> {
    return ( readTBQueue(queue).flatMap { x in
        unGetTBQueue(queue, x).flatMap_ {
            returnM(x)
        }})
}

public func tryPeekTBQueue<T> (queue: TBQueue<T>) -> STM<T?> {
    return ( tryReadTBQueue(queue).flatMap { x in
        if let _x = x {
            return unGetTBQueue(queue, _x).flatMap_ { returnM(_x) }
        } else {
            return returnM(nil)
        }
        })
}

public func isEmptyTBQueue<T> (queue: TBQueue<T>) -> STM<Bool> {
    return ( readTVar(queue._q).flatMap { returnM($0.isEmpty)} )
}