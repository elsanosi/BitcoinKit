//
//  BitArray.swift
//
//  Created by Mauricio Santos on 2/23/15.
//  Modified by BitcoinKit developers and Elsanosi (PRO Mode upgrade)
//

import Foundation

/// An array of boolean values stored using individual bits,
/// providing minimal memory footprint and fast access.
/// Conforms to MutableCollection, RangeReplaceableCollection,
/// ExpressibleByArrayLiteral, Equatable, Hashable, CustomStringConvertible.
public struct BitArray: Hashable, RangeReplaceableCollection {
    
    // MARK: - Initialization
    
    public init() {}
    
    public init<S: Sequence>(_ elements: S) where S.Iterator.Element == Bool {
        for value in elements {
            append(value)
        }
    }
    
    public init(data: Data) {
        guard let viaBitstring = BitArray(binaryString: data.binaryString) else {
            fatalError("Failed to initialize BitArray from Data. Check Data.binaryString implementation or BitArray(binaryString:).")
        }
        assert(viaBitstring.asData() == data, "Conversion correctness assert failed.")
        self = viaBitstring
    }
    
    public init?<S>(binaryString: S) where S: StringProtocol {
        let mapped: [Bool] = binaryString.compactMap {
            switch $0 {
            case "1": return true
            case "0": return false
            default:
                fatalError("Invalid character '\($0)' in binary string. Only '0' or '1' allowed.")
            }
        }
        self.init(mapped)
    }
    
    /// Internal initializer for UInt11 sequences to avoid exposing UInt11 publicly
    init(fromUInt11s elements: [UInt11]) {
        let binaryString = elements.map { $0.binaryString }.joined()
        guard let bitArray = BitArray(binaryString: binaryString) else {
            fatalError("Failed to create BitArray from UInt11 sequence")
        }
        self = bitArray
    }
    
    public init(intRepresentation: [Int]) {
        bits.reserveCapacity((intRepresentation.count / Constants.IntSize) + 1)
        for value in intRepresentation {
            append(value != 0)
        }
    }
    
    public init(repeating repeatedValue: Bool, count: Int) {
        precondition(count >= 0, "Count must not be negative")
        let numberOfInts = (count / Constants.IntSize) + 1
        let intValue = repeatedValue ? ~0 : 0
        bits = [Int](repeating: intValue, count: numberOfInts)
        self.count = count
        
        if repeatedValue {
            let missingBits = count % Constants.IntSize
            if missingBits > 0 {
                bits[bits.count - 1] = 0
                for i in 0..<missingBits {
                    setValue(true, atIndex: count - missingBits + i)
                }
            }
            cardinality = count
        }
    }
    
    // MARK: - Properties
    
    public fileprivate(set) var count = 0
    public fileprivate(set) var cardinality = 0
    
    public var first: Bool? {
        return isEmpty ? nil : self[0]
    }
    
    public var last: Bool? {
        return isEmpty ? nil : self[count - 1]
    }
    
    fileprivate var bits = [Int]()
    
    // MARK: - Methods: Adding/Removing
    
    public mutating func append(_ bit: Bool) {
        if realIndexPath(count).arrayIndex >= bits.count {
            bits.append(0)
        }
        setValue(bit, atIndex: count)
        count += 1
    }
    
    public mutating func insert(_ bit: Bool, at index: Int) {
        checkIndex(index, lessThan: count + 1)
        append(false) // extend by one to have space
        
        for i in stride(from: count - 2, through: index, by: -1) {
            let bitValue = self[i]
            setValue(bitValue, atIndex: i + 1)
        }
        
        setValue(bit, atIndex: index)
    }
    
    @discardableResult
    public mutating func removeLast() -> Bool {
        precondition(!isEmpty, "Cannot removeLast from empty BitArray")
        let lastBit = self[count - 1]
        setValue(false, atIndex: count - 1)
        count -= 1
        return lastBit
    }
    
    @discardableResult
    public mutating func remove(at index: Int) -> Bool {
        checkIndex(index)
        let removedBit = self[index]
        
        for i in (index + 1)..<count {
            let bitValue = self[i]
            setValue(bitValue, atIndex: i - 1)
        }
        
        removeLast()
        return removedBit
    }
    
    public mutating func removeAll(keepingCapacity keep: Bool = false) {
        if !keep {
            bits.removeAll(keepingCapacity: false)
        } else {
            bits = [0]
        }
        count = 0
        cardinality = 0
    }
    
    // MARK: - Private Helpers
    
    fileprivate func valueAtIndex(_ logicalIndex: Int) -> Bool {
        let (arrayIndex, bitIndex) = realIndexPath(logicalIndex)
        let mask = 1 << bitIndex
        return (bits[arrayIndex] & mask) != 0
    }
    
    fileprivate mutating func setValue(_ newValue: Bool, atIndex logicalIndex: Int) {
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
    
    fileprivate func realIndexPath(_ logicalIndex: Int) -> (arrayIndex: Int, bitIndex: Int) {
        return (logicalIndex / Constants.IntSize, logicalIndex % Constants.IntSize)
    }
    
    fileprivate func checkIndex(_ index: Int, lessThan: Int? = nil) {
        let upperBound = lessThan ?? count
        precondition(index >= 0 && index < upperBound, "Index out of range: \(index)")
    }
    
    // MARK: - Constants
    
    fileprivate struct Constants {
        static let IntSize = MemoryLayout<Int>.size * 8
    }
}

// MARK: - MutableCollection conformance

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

// MARK: - ExpressibleByArrayLiteral conformance

extension BitArray: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: Bool...) {
        bits.reserveCapacity((elements.count / Constants.IntSize) + 1)
        for element in elements {
            append(element)
        }
    }
}

// MARK: - CustomStringConvertible

extension BitArray: CustomStringConvertible {
    public var description: String { binaryString }
    public var binaryString: String { map { $0 ? "1" : "0" }.joined() }
}

// MARK: - Equatable

public func == (lhs: BitArray, rhs: BitArray) -> Bool {
    if lhs.count != rhs.count || lhs.cardinality != rhs.cardinality {
        return false
    }
    return lhs.elementsEqual(rhs)
}

// MARK: - RangeReplaceableCollection

public extension BitArray {
    mutating func replaceSubrange<C>(
        _ subrange: Range<Int>,
        with newElements: C
    ) where C: Collection, C.Element == Bool {
        // Remove existing bits in subrange from the end for efficiency
        for index in subrange.reversed() {
            _ = remove(at: index)
        }
        
        // Insert new bits
        var insertIndex = subrange.lowerBound
        for bit in newElements {
            insert(bit, at: insertIndex)
            insertIndex += 1
        }
    }
}

// MARK: - Additional Utilities

public extension BitArray {
    func asBoolArray() -> [Bool] {
        Array(self)
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
        Data(asBytesArray())
    }
}
