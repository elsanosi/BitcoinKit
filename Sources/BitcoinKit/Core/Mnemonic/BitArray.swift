import Foundation

public struct BitArray: Hashable, RangeReplaceableCollection {
    // MARK: - Storage
    private var bits: [Int] = []
    public private(set) var count: Int = 0
    public private(set) var cardinality: Int = 0

    // MARK: - Constants
    private static let intSize = MemoryLayout<Int>.size * 8

    // MARK: - Initializers
    public init() {}

    public init<S: Sequence>(_ elements: S) where S.Element == Bool {
        for bit in elements {
            append(bit)
        }
    }

    public init(repeating repeatedValue: Bool, count: Int) {
        precondition(count >= 0, "Count must be non-negative")
        self = BitArray()
        for _ in 0..<count {
            append(repeatedValue)
        }
    }

    public init?<S>(binaryString: S) where S: StringProtocol {
        let bits = binaryString.compactMap { char -> Bool? in
            switch char {
            case "0": return false
            case "1": return true
            default: return nil
            }
        }
        guard bits.count == binaryString.count else { return nil }
        self.init(bits)
    }

    // MARK: - Collection Conformance
    public var startIndex: Int { 0 }
    public var endIndex: Int { count }

    public func index(after i: Int) -> Int {
        return i + 1
    }

    public subscript(index: Int) -> Bool {
        get {
            checkIndex(index)
            return bit(atIndex: index)
        }
        set {
            checkIndex(index)
            setBit(newValue, atIndex: index)
        }
    }

    // MARK: - Replaceable Collection
    public mutating func replaceSubrange<C>(
        _ subrange: Range<Int>,
        with newElements: C
    ) where C: Collection, C.Element == Bool {
        for _ in subrange.reversed() {
            remove(at: $0)
        }
        var i = subrange.lowerBound
        for bit in newElements {
            insert(bit, at: i)
            i += 1
        }
    }

    // MARK: - ExpressibleByArrayLiteral
    public init(arrayLiteral elements: Bool...) {
        self.init(elements)
    }

    // MARK: - Public API
    public mutating func append(_ bit: Bool) {
        if count / Self.intSize >= bits.count {
            bits.append(0)
        }
        setBit(bit, atIndex: count)
        count += 1
    }

    public mutating func insert(_ bit: Bool, at index: Int) {
        checkInsertIndex(index)
        append(false)
        for i in (index..<count - 1).reversed() {
            setBit(self[i], atIndex: i + 1)
        }
        setBit(bit, atIndex: index)
    }

    @discardableResult
    public mutating func removeLast() -> Bool {
        precondition(count > 0, "Cannot remove from empty BitArray")
        let bit = self[count - 1]
        count -= 1
        setBit(false, atIndex: count)
        return bit
    }

    @discardableResult
    public mutating func remove(at index: Int) -> Bool {
        checkIndex(index)
        let removed = self[index]
        for i in index..<(count - 1) {
            setBit(self[i + 1], atIndex: i)
        }
        count -= 1
        setBit(false, atIndex: count)
        return removed
    }

    public mutating func removeAll(keepingCapacity keepCapacity: Bool = false) {
        count = 0
        cardinality = 0
        if !keepCapacity {
            bits.removeAll()
        }
    }

    public var binaryString: String {
        map { $0 ? "1" : "0" }.joined()
    }

    public var description: String {
        binaryString
    }

    public func asBytesArray() -> [UInt8] {
        let byteCount = (count + 7) / 8
        var bytes = [UInt8](repeating: 0, count: byteCount)

        for (i, bit) in self.enumerated() where bit {
            bytes[i / 8] |= 1 << (7 - (i % 8))
        }

        return bytes
    }

    public func asData() -> Data {
        Data(asBytesArray())
    }

    public func asBoolArray() -> [Bool] {
        Array(self)
    }

    // MARK: - Private Helpers
    private func checkIndex(_ index: Int) {
        precondition(index >= 0 && index < count, "Index \(index) out of range")
    }

    private func checkInsertIndex(_ index: Int) {
        precondition(index >= 0 && index <= count, "Index \(index) out of range")
    }

    private func bit(atIndex index: Int) -> Bool {
        let (bucket, offset) = index.quotientAndRemainder(dividingBy: Self.intSize)
        let mask = 1 << offset
        return (bits[bucket] & mask) != 0
    }

    private mutating func setBit(_ value: Bool, atIndex index: Int) {
        let (bucket, offset) = index.quotientAndRemainder(dividingBy: Self.intSize)
        let mask = 1 << offset

        let wasSet = (bits[bucket] & mask) != 0
        if value {
            bits[bucket] |= mask
            if !wasSet { cardinality += 1 }
        } else {
            bits[bucket] &= ~mask
            if wasSet { cardinality -= 1 }
        }
    }
}
