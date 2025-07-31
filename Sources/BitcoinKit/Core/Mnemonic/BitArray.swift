import Foundation

public struct BitArray: Hashable, RangeReplaceableCollection {

    // MARK: - Types & Constants

    fileprivate struct Constants {
        static let IntSize = MemoryLayout<Int>.size * 8
    }

    // MARK: - Internal State

    fileprivate var bits = [Int]()
    public fileprivate(set) var count = 0
    public fileprivate(set) var cardinality = 0

    // MARK: - Initializers

    public init() {}

    public init<S: Sequence>(_ elements: S) where S.Element == Bool {
        for value in elements {
            append(value)
        }
    }

    public init(arrayLiteral elements: Bool...) {
        self.init(elements)
    }

    public init(repeating repeatedValue: Bool, count: Int) {
        precondition(count >= 0, "Count must be non-negative")
        let numberOfInts = (count / Constants.IntSize) + 1
        let intValue = repeatedValue ? ~0 : 0
        bits = [Int](repeating: intValue, count: numberOfInts)
        self.count = count

        if repeatedValue {
            let missingBits = Constants.IntSize - (count % Constants.IntSize)
            self.count = count - missingBits
            for _ in 0..<missingBits {
                append(repeatedValue)
            }
            cardinality = count
        }
    }

    public init(data: Data) {
        self.init()
        for byte in data {
            for i in (0..<8).reversed() {
                let bit = ((byte >> i) & 0x01) == 1
                append(bit)
            }
        }
    }

    public init?<S: StringProtocol>(binaryString: S) {
        let mapped: [Bool] = binaryString.compactMap {
            switch $0 {
            case "1": return true
            case "0": return false
            default: return nil
            }
        }
        self.init(mapped)
    }

    public init(intRepresentation: [Int]) {
        bits.reserveCapacity((intRepresentation.count / Constants.IntSize) + 1)
        for value in intRepresentation {
            append(value != 0)
        }
    }

    // MARK: - Collection Conformance

    public var startIndex: Int { 0 }
    public var endIndex: Int { count }

    public func index(after i: Int) -> Int {
        i + 1
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

    public mutating func replaceSubrange<C>(_ subrange: Range<Int>, with newElements: C)
    where C : Collection, C.Element == Bool {
        for index in subrange.reversed() {
            _ = remove(at: index)
        }

        var insertIndex = subrange.lowerBound
        for bit in newElements {
            insert(bit, at: insertIndex)
            insertIndex += 1
        }
    }

    // MARK: - Bit Access & Mutation

    public var first: Bool? {
        isEmpty ? nil : valueAtIndex(0)
    }

    public var last: Bool? {
        isEmpty ? nil : valueAtIndex(count - 1)
    }

    public var isEmpty: Bool {
        count == 0
    }

    public mutating func append(_ bit: Bool) {
        if realIndexPath(count).arrayIndex >= bits.count {
            bits.append(0)
        }
        setValue(bit, atIndex: count)
        count += 1
    }

    public mutating func insert(_ bit: Bool, at index: Int) {
        checkIndex(index, lessThanOrEqualTo: count)
        append(false)
        for i in stride(from: count - 2, through: index, by: -1) {
            self[i + 1] = self[i]
        }
        self[index] = bit
    }

    @discardableResult
    public mutating func removeLast() -> Bool {
        guard let value = last else {
            preconditionFailure("Cannot remove from empty BitArray")
        }
        count -= 1
        setValue(false, atIndex: count)
        return value
    }

    @discardableResult
    public mutating func remove(at index: Int) -> Bool {
        checkIndex(index)
        let removed = self[index]
        for i in index..<(count - 1) {
            self[i] = self[i + 1]
        }
        count -= 1
        setValue(false, atIndex: count)
        return removed
    }

    public mutating func removeAll(keepingCapacity keepCapacity: Bool = false) {
        if keepCapacity {
            bits = Array(repeating: 0, count: bits.count)
        } else {
            bits.removeAll()
        }
        count = 0
        cardinality = 0
    }

    // MARK: - Helpers

    private func valueAtIndex(_ logicalIndex: Int) -> Bool {
        let indexPath = realIndexPath(logicalIndex)
        let mask = 1 << indexPath.bitIndex
        return (bits[indexPath.arrayIndex] & mask) != 0
    }

    private mutating func setValue(_ newValue: Bool, atIndex logicalIndex: Int) {
        let indexPath = realIndexPath(logicalIndex)
        let mask = 1 << indexPath.bitIndex
        let oldValue = (bits[indexPath.arrayIndex] & mask) != 0

        if newValue != oldValue {
            cardinality += newValue ? 1 : -1
        }

        if newValue {
            bits[indexPath.arrayIndex] |= mask
        } else {
            bits[indexPath.arrayIndex] &= ~mask
        }
    }

    private func realIndexPath(_ logicalIndex: Int) -> (arrayIndex: Int, bitIndex: Int) {
        (logicalIndex / Constants.IntSize, logicalIndex % Constants.IntSize)
    }

    private func checkIndex(_ index: Int, lessThanOrEqualTo upper: Int? = nil) {
        let limit = upper ?? count
        precondition(index >= 0 && index < limit, "Index \(index) out of bounds (limit: \(limit))")
    }

    // MARK: - Utility Methods

    public var binaryString: String {
        self.map { $0 ? "1" : "0" }.joined()
    }

    public func asBoolArray() -> [Bool] {
        Array(self)
    }

    public func asBytesArray() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: (count + 7) / 8)
        for (i, bit) in self.enumerated() where bit {
            bytes[i / 8] |= 1 << (7 - (i % 8))
        }
        return bytes
    }

    public func asData() -> Data {
        Data(asBytesArray())
    }

    public var description: String {
        binaryString
    }
}

extension BitArray: MutableCollection {}

extension BitArray: ExpressibleByArrayLiteral {}

public func == (lhs: BitArray, rhs: BitArray) -> Bool {
    lhs.count == rhs.count && lhs.cardinality == rhs.cardinality && lhs.elementsEqual(rhs)
}
