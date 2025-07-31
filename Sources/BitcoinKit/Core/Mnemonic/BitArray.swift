//
//  BitArray.swift
//
//  Created by Mauricio Santos on 2/23/15.
//  Modified by BitcoinKit developers and Elsanosi for Dogecoin multisig wallet
//
//  Github: https://github.com/mauriciosantos/Buckets-Swift/blob/master/Source/BitArray.swift
//
//  Copyright (c) 2015 Mauricio Santos
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Foundation

public struct BitArray: Hashable, RangeReplaceableCollection {

    // MARK: - Properties

    fileprivate var bits = [Int]()
    public private(set) var count = 0
    public private(set) var cardinality = 0

    // MARK: - Initialization

    public init() {}

    public init<S: Sequence>(_ elements: S) where S.Element == Bool {
        bits.reserveCapacity((elements.underestimatedCount / Constants.IntSize) + 1)
        for bit in elements {
            append(bit)
        }
    }

    public init?(binaryString: some StringProtocol) {
        var bools = [Bool]()
        bools.reserveCapacity(binaryString.count)

        for c in binaryString {
            switch c {
            case "0": bools.append(false)
            case "1": bools.append(true)
            default:
                return nil
            }
        }
        self.init(bools)
    }

    public init(intRepresentation: [Int]) {
        bits.reserveCapacity((intRepresentation.count / Constants.IntSize) + 1)
        for val in intRepresentation {
            append(val != 0)
        }
    }

    public init(repeating repeatedValue: Bool, count: Int) {
        precondition(count >= 0, "Count must be non-negative")

        if count == 0 {
            self.init()
            return
        }

        let numInts = (count + Constants.IntSize - 1) / Constants.IntSize
        let intValue = repeatedValue ? ~0 : 0
        bits = [Int](repeating: intValue, count: numInts)
        self.count = count
        self.cardinality = repeatedValue ? count : 0

        // Clear unused bits in last Int if repeating true
        if repeatedValue {
            let remainder = count % Constants.IntSize
            if remainder != 0 {
                let mask = ~0 >> (Constants.IntSize - remainder)
                bits[numInts - 1] &= mask
            }
        }
    }

    /// Init from UInt11 sequence (used for BIP39 indices)
    public init(fromUInt11s elements: [UInt11]) {
        let binaryString = elements.map { $0.binaryString }.joined()
        guard let bitArray = BitArray(binaryString: binaryString) else {
            fatalError("Failed to initialize BitArray from UInt11 sequence")
        }
        self = bitArray
    }

    public init(data: Data) {
        guard let viaBitString = BitArray(binaryString: data.binaryString) else {
            fatalError("Failed to init BitArray from Data")
        }
        assert(viaBitString.asData() == data, "Data conversion inconsistency")
        self = viaBitString
    }

    // MARK: - Collection Conformance

    public var startIndex: Int { 0 }
    public var endIndex: Int { count }

    public func index(after i: Int) -> Int {
        precondition(i < endIndex, "Index out of range")
        return i + 1
    }

    public subscript(index: Int) -> Bool {
        get {
            checkIndex(index)
            return valueAtIndex(index)
        }
        set {
            checkIndex(index)
            setValue(newValue, atIndex: index)
        }
    }

    // MARK: - RangeReplaceableCollection

    public mutating func replaceSubrange<C: Collection>(
        _ subrange: Range<Int>,
        with newElements: C
    ) where C.Element == Bool {
        precondition(subrange.lowerBound >= 0 && subrange.upperBound <= count, "Range out of bounds")

        // Remove bits in the range
        for i in subrange.reversed() {
            _ = remove(at: i)
        }

        // Insert new bits
        var insertIndex = subrange.lowerBound
        for bit in newElements {
            insert(bit, at: insertIndex)
            insertIndex += 1
        }
    }

    public mutating func append(_ bit: Bool) {
        if realIndexPath(count).arrayIndex >= bits.count {
            bits.append(0)
        }
        setValue(bit, atIndex: count)
        count += 1
    }

    public mutating func insert(_ bit: Bool, at index: Int) {
        precondition(index >= 0 && index <= count, "Index out of bounds")
        append(bit)
        for i in stride(from: count - 2, through: index, by: -1) {
            let bitToShift = valueAtIndex(i)
            setValue(bitToShift, atIndex: i + 1)
        }
        setValue(bit, atIndex: index)
    }

    @discardableResult
    public mutating func removeLast() -> Bool {
        precondition(count > 0, "Removing from empty BitArray")
        let value = valueAtIndex(count - 1)
        setValue(false, atIndex: count - 1)
        count -= 1
        return value
    }

    @discardableResult
    public mutating func remove(at index: Int) -> Bool {
        checkIndex(index)
        let removedBit = valueAtIndex(index)
        for i in (index + 1)..<count {
            let bitToShift = valueAtIndex(i)
            setValue(bitToShift, atIndex: i - 1)
        }
        _ = removeLast()
        return removedBit
    }

    public mutating func removeAll(keepingCapacity keep: Bool = false) {
        if keep {
            bits = [0]
        } else {
            bits.removeAll(keepingCapacity: false)
        }
        count = 0
        cardinality = 0
    }

    // MARK: - Private helpers

    private func valueAtIndex(_ logicalIndex: Int) -> Bool {
        let (arrayIndex, bitIndex) = realIndexPath(logicalIndex)
        return (bits[arrayIndex] & (1 << bitIndex)) != 0
    }

    private mutating func setValue(_ newValue: Bool, atIndex logicalIndex: Int) {
        let (arrayIndex, bitIndex) = realIndexPath(logicalIndex)
        let mask = 1 << bitIndex
        let oldValue = (bits[arrayIndex] & mask) != 0

        switch (oldValue, newValue) {
        case (false, true): cardinality += 1
        case (true, false): cardinality -= 1
        default: break
        }

        if newValue {
            bits[arrayIndex] |= mask
        } else {
            bits[arrayIndex] &= ~mask
        }
    }

    private func realIndexPath(_ logicalIndex: Int) -> (arrayIndex: Int, bitIndex: Int) {
        return (logicalIndex / Constants.IntSize, logicalIndex % Constants.IntSize)
    }

    private func checkIndex(_ index: Int) {
        precondition(index >= 0 && index < count, "Index out of range (\(index))")
    }

    // MARK: - Constants

    private struct Constants {
        static let IntSize = MemoryLayout<Int>.size * 8
    }
}

// MARK: - ExpressibleByArrayLiteral

extension BitArray: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: Bool...) {
        self.init(elements)
    }
}

// MARK: - CustomStringConvertible

extension BitArray: CustomStringConvertible {
    public var description: String {
        return binaryString
    }
    public var binaryString: String {
        return self.map { $0 ? "1" : "0" }.joined()
    }
}

// MARK: - Equatable

public func == (lhs: BitArray, rhs: BitArray) -> Bool {
    guard lhs.count == rhs.count, lhs.cardinality == rhs.cardinality else {
        return false
    }
    return lhs.elementsEqual(rhs)
}

// MARK: - Extensions

public extension BitArray {

    func asBoolArray() -> [Bool] {
        return Array(self)
    }

    func asBytesArray() -> [UInt8] {
        let numBits = count
        let numBytes = (numBits + 7) / 8
        var bytes = [UInt8](repeating: 0, count: numBytes)

        for (index, bit) in self.enumerated() where bit {
            bytes[index / 8] |= UInt8(1 << (7 - (index % 8)))
        }

        return bytes
    }

    func asData() -> Data {
        return Data(asBytesArray())
    }
}
