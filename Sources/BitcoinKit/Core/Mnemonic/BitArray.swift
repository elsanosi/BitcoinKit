//
//  BitArray.swift
//
//  Created by Mauricio Santos on 2/23/15.
//  Modified by elsanosi BitcoinKit developer
//  Updated for Swift compatibility and conformance
//

import Foundation

/// An array of boolean values stored using individual bits, providing a minimal memory footprint.
/// Features constant time random access, amortized constant time appends, and conforms to:
/// `MutableCollection`, `RangeReplaceableCollection`, `ExpressibleByArrayLiteral`, `Equatable`, `Hashable`, `CustomStringConvertible`

public struct BitArray: Hashable, RangeReplaceableCollection {
    
    // MARK: - Internal Storage
    
    fileprivate var bits = [Int]()
    public fileprivate(set) var count = 0
    public fileprivate(set) var cardinality = 0

    // MARK: - Initializers

    public init() {}

    public init<S: Sequence>(_ elements: S) where S.Iterator.Element == Bool {
        for value in elements {
            append(value)
        }
    }

    public init(data: Data) {
        guard let viaBitstring = BitArray(binaryString: data.binaryString) else {
            fatalError("Failed to init from Data")
        }
        assert(viaBitstring.asData() == data)
        self = viaBitstring
    }

    public init?<S>(binaryString: S) where S: StringProtocol {
        let mapped: [Bool] = binaryString.compactMap {
            switch $0 {
            case "1": return true
            case "0": return false
            default: return nil
            }
        }
        guard mapped.count == binaryString.count else { return nil }
        self.init(mapped)
    }

    public init(intRepresentation: [Int]) {
        bits.reserveCapacity((intRepresentation.count / Constants.IntSize) + 1)
        for value in intRepresentation {
            append(value != 0)
        }
    }

    public init(repeating repeatedValue: Bool, count: Int) {
        precondition(count >= 0, "Can't construct BitArray with count < 0")
        let numberOfInts = (count / Constants.IntSize) + 1
        let intValue = repeatedValue ? ~0 : 0
        bits = [Int](repeating: intValue, count: numberOfInts)
        self.count = count

        if repeatedValue {
            bits[bits.count - 1] = 0
            let missingBits = count % Constants.IntSize
            self.count = count - missingBits
            for _ in 0..<missingBits {
                append(repeatedValue)
            }
            cardinality = count
        }
    }

    // MARK: - Querying

    public var first: Bool? {
        isEmpty ? nil : valueAtIndex(0)
    }

    public var last: Bool? {
        isEmpty ? nil : valueAtIndex(count - 1)
    }

    // MARK: - Mutation

    public mutating func append(_ bit: Bool) {
        if realIndexPath(count).arrayIndex >= bits.count {
            bits.append(0)
        }
        setValue(bit, atIndex: count)
        count += 1
    }

    public mutating func insert(_ bit: Bool, at index: Int) {
        checkIndex(index, lessThan: count + 1)
        append(bit)
        for i in stride(from: count - 2, through: index, by: -1) {
            let iBit = valueAtIndex(i)
            setValue(iBit, atIndex: i + 1)
        }
        setValue(bit, at: index)
    }

    @discardableResult
    public mutating func removeLast() -> Bool {
        guard let value = last else {
            preconditionFailure("Array is empty")
        }
        setValue(false, atIndex: count - 1)
        count -= 1
        return value
    }

    @discardableResult
    public mutating func remove(at index: Int) -> Bool {
        checkIndex(index)
        let bit = valueAtIndex(index)
        for i in (index + 1)..<count {
            let iBit = valueAtIndex(i)
            setValue(iBit, atIndex: i - 1)
        }
        _ = removeLast()
        return bit
    }

    public mutating func removeAll(keepingCapacity keep: Bool = false) {
        if !keep {
            bits.removeAll()
        } else {
            bits[0..<bits.count] = [0]
        }
        count = 0
        cardinality = 0
    }

    // MARK: - Helpers

    fileprivate func valueAtIndex(_ logicalIndex: Int) -> Bool {
        let indexPath = realIndexPath(logicalIndex)
        let mask = 1 << indexPath.bitIndex
        return (bits[indexPath.arrayIndex] & mask) != 0
    }

    fileprivate mutating func setValue(_ newValue: Bool, atIndex logicalIndex: Int) {
        let indexPath = realIndexPath(logicalIndex)
        let mask = 1 << indexPath.bitIndex
        let oldValue = (bits[indexPath.arrayIndex] & mask) != 0

        if newValue && !oldValue {
            cardinality += 1
        } else if !newValue && oldValue {
            cardinality -= 1
        }

        if newValue {
            bits[indexPath.arrayIndex] |= mask
        } else {
            bits[indexPath.arrayIndex] &= ~mask
        }
    }

    fileprivate func realIndexPath(_ logicalIndex: Int) -> (arrayIndex: Int, bitIndex: Int) {
        return (logicalIndex / Constants.IntSize, logicalIndex % Constants.IntSize)
    }

    fileprivate func checkIndex(_ index: Int, lessThan: Int? = nil) {
        let bound = lessThan ?? count
        precondition(index < bound, "Index out of range (\(index))")
    }

    fileprivate struct Constants {
        static let IntSize = MemoryLayout<Int>.size * 8
    }

    // MARK: - RangeReplaceableCollection Requirement

    public mutating func replaceSubrange<C>(
        _ subrange: Range<Int>,
        with newElements: C
    ) where C: Collection, C.Element == Bool {
        for _ in subrange.reversed() {
            _ = remove(at: $0)
        }
        var index = subrange.lowerBound
        for bit in newElements {
            insert(bit, at: index)
            index += 1
        }
    }
}

// MARK: - MutableCollection

extension BitArray: MutableCollection {
    public var startIndex: Int { 0 }
    public var endIndex: Int { count }

    public func index(after i: Int) -> Int { i + 1 }

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
}

// MARK: - ExpressibleByArrayLiteral

extension BitArray: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: Bool...) {
        self.init(elements)
    }
}

// MARK: - CustomStringConvertible

extension BitArray: CustomStringConvertible {
    public var description: String { binaryString }
    public var binaryString: String {
        map { $0 ? "1" : "0" }.joined()
    }
}

// MARK: - Utility Extensions

public extension BitArray {
    func asBoolArray() -> [Bool] {
        map { $0 }
    }

    func asBytesArray() -> [UInt8] {
        let numBytes = (count + 7) / 8
        var bytes = [UInt8](repeating: 0, count: numBytes)

        for (index, bit) in self.enumerated() where bit {
            bytes[index / 8] |= UInt8(1 << (7 - index % 8))
        }

        return bytes
    }

    func asData() -> Data {
        Data(asBytesArray())
    }
}

// MARK: - Equatable

public func == (lhs: BitArray, rhs: BitArray) -> Bool {
    lhs.count == rhs.count &&
    lhs.cardinality == rhs.cardinality &&
    lhs.elementsEqual(rhs)
}
