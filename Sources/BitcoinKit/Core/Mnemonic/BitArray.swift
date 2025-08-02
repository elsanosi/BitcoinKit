import Foundation

/// An array of boolean values stored using individual bits, providing a compact memory footprint.
/// Features constant time random access and amortized constant time insertion at the end.
///
/// Conforms to:
/// - `MutableCollection`
/// - `RangeReplaceableCollection`
/// - `ExpressibleByArrayLiteral`
/// - `Equatable`
/// - `Hashable`
/// - `CustomStringConvertible`
public struct BitArray: Hashable, RangeReplaceableCollection {
    
    // MARK: - Properties and Storage
    
    /// Structure holding the bits
    private var storage: [Int]
    
    /// Number of bits stored in the bit array
    public private(set) var count: Int
    
    /// Number of bits set to `true`
    public private(set) var cardinality: Int
    
    /// Constants for bit manipulation
    private struct Constants {
        static let IntSize = MemoryLayout<Int>.size * 8
    }
    
    // MARK: - Initializers
    
    /// Creates an empty bit array
    public init() {
        storage = []
        count = 0
        cardinality = 0
    }
    
    /// Creates a bit array from a boolean sequence
    public init<S: Sequence>(_ elements: S) where S.Element == Bool {
        self.init()
        elements.forEach { append($0) }
    }
    
    /// Creates a bit array from binary data
    public init(data: Data) {
        self.init()
        data.forEach { byte in
            for bitIndex in 0..<8 {
                let bit = (byte >> (7 - bitIndex)) & 1
                append(bit == 1)
            }
        }
    }
    
    /// Creates a bit array from a binary string
    public init?<S: StringProtocol>(binaryString: S) {
        self.init()
        for char in binaryString {
            switch char {
            case "1": append(true)
            case "0": append(false)
            default: return nil
            }
        }
    }
    
    /// Creates a bit array from UInt11 values
    init<S: Sequence>(_ elements: S) where S.Element == UInt11 {
        let binaryString = elements.map(\.binaryString).joined()
        self.init(binaryString: binaryString)!
    }
    
    /// Creates a bit array from integer representations
    public init(intRepresentation: [Int]) {
        self.init(intRepresentation.map { $0 != 0 })
    }
    
    /// Creates a bit array with repeating values
    public init(repeating repeatedValue: Bool, count: Int) {
        storage = []
        self.count = 0
        cardinality = 0
        
        guard count > 0 else { return }
        
        let fullChunks = count / Constants.IntSize
        let remainder = count % Constants.IntSize
        
        if fullChunks > 0 {
            storage = Array(repeating: repeatedValue ? ~0 : 0, count: fullChunks)
        }
        
        if remainder > 0 {
            let mask = repeatedValue ? (1 << remainder) - 1 : 0
            storage.append(mask)
        }
        
        self.count = count
        cardinality = repeatedValue ? count : 0
    }
    
    // MARK: - Collection Conformance
    
    public var startIndex: Int { 0 }
    public var endIndex: Int { count }
    
    public func index(after i: Int) -> Int {
        return i + 1
    }
    
    public subscript(position: Int) -> Bool {
        get {
            precondition(position >= 0 && position < count, "Index out of bounds")
            let (arrayIndex, bitIndex) = indexPath(for: position)
            return storage[arrayIndex] & (1 << bitIndex) != 0
        }
        set {
            precondition(position >= 0 && position < count, "Index out of bounds")
            setValue(newValue, at: position)
        }
    }
    
    // MARK: - RangeReplaceableCollection
    
    public mutating func replaceSubrange<C: Collection>(
        _ subrange: Range<Int>,
        with newElements: C
    ) where C.Element == Bool {
        precondition(subrange.lowerBound >= 0 && subrange.upperBound <= count, "Range out of bounds")
        
        // Calculate new size
        let newCount = count - subrange.count + newElements.count
        var newStorage = [Int]()
        var newCardinality = 0
        
        // Pre-calculate needed capacity
        let neededInts = (newCount + Constants.IntSize - 1) / Constants.IntSize
        newStorage.reserveCapacity(neededInts)
        
        // Helper to add bits efficiently
        func appendBits(_ bits: [Bool]) {
            for bit in bits {
                let (arrayIndex, bitIndex) = indexPath(for: newStorage.count * Constants.IntSize + newCardinality)
                if arrayIndex >= newStorage.count {
                    newStorage.append(0)
                }
                if bit {
                    newStorage[arrayIndex] |= (1 << bitIndex)
                    newCardinality += 1
                }
            }
        }
        
        // Head before replacement range
        if subrange.lowerBound > 0 {
            appendBits(Array(self[0..<subrange.lowerBound]))
        }
        
        // New elements
        appendBits(Array(newElements))
        
        // Tail after replacement range
        if subrange.upperBound < count {
            appendBits(Array(self[subrange.upperBound..<count]))
        }
        
        storage = newStorage
        count = newCount
        cardinality = newCardinality
    }
    
    public mutating func reserveCapacity(_ minimumCapacity: Int) {
        let neededInts = (minimumCapacity + Constants.IntSize - 1) / Constants.IntSize
        if neededInts > storage.capacity {
            storage.reserveCapacity(neededInts)
        }
    }
    
    // MARK: - Bit Manipulation
    
    private mutating func setValue(_ newValue: Bool, at position: Int) {
        let (arrayIndex, bitIndex) = indexPath(for: position)
        let mask = 1 << bitIndex
        let oldValue = storage[arrayIndex] & mask != 0
        
        switch (oldValue, newValue) {
        case (false, true):
            storage[arrayIndex] |= mask
            cardinality += 1
        case (true, false):
            storage[arrayIndex] &= ~mask
            cardinality -= 1
        default:
            break
        }
    }
    
    private func indexPath(for logicalIndex: Int) -> (arrayIndex: Int, bitIndex: Int) {
        return (logicalIndex / Constants.IntSize, logicalIndex % Constants.IntSize)
    }
    
    // MARK: - Adding and Removing Bits
    
    public mutating func append(_ bit: Bool) {
        let (arrayIndex, bitIndex) = indexPath(for: count)
        if arrayIndex >= storage.count {
            storage.append(0)
        }
        setValue(bit, at: count)
        count += 1
    }
    
    public mutating func insert(_ bit: Bool, at index: Int) {
        precondition(index >= 0 && index <= count, "Index out of bounds")
        replaceSubrange(index..<index, with: CollectionOfOne(bit))
    }
    
    @discardableResult
    public mutating func remove(at index: Int) -> Bool {
        precondition(index >= 0 && index < count, "Index out of bounds")
        let element = self[index]
        replaceSubrange(index..<(index + 1), with: EmptyCollection())
        return element
    }
    
    public mutating func removeFirst() {
        remove(at: 0)
    }
    
    @discardableResult
    public mutating func removeLast() -> Bool {
        precondition(!isEmpty, "Cannot remove last from empty collection")
        return remove(at: count - 1)
    }
    
    public mutating func removeAll(keepingCapacity keepCapacity: Bool = false) {
        storage.removeAll(keepingCapacity: keepCapacity)
        count = 0
        cardinality = 0
    }
    
    // MARK: - Convenience Properties
    
    public var first: Bool? { isEmpty ? nil : self[0] }
    public var last: Bool? { isEmpty ? nil : self[count - 1] }
}

// MARK: - Protocol Conformances
extension BitArray: MutableCollection {}
extension BitArray: RandomAccessCollection {}

extension BitArray: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: Bool...) {
        self.init(elements)
    }
}

extension BitArray: CustomStringConvertible {
    public var description: String { binaryString }
    public var binaryString: String { map { $0 ? "1" : "0" }.joined() }
}

// MARK: - Conversion Utilities
extension BitArray {
    public func asBoolArray() -> [Bool] {
        return Array(self)
    }
    
    public func asBytes() -> [UInt8] {
        let numBytes = (count + 7) / 8
        var bytes = [UInt8](repeating: 0, count: numBytes)
        
        for (index, bit) in enumerated() where bit {
            let byteIndex = index / 8
            let bitIndex = 7 - (index % 8)
            bytes[byteIndex] |= (1 << bitIndex)
        }
        
        return bytes
    }
    
    public func asData() -> Data {
        return Data(asBytes())
    }
}

// MARK: - Equality
extension BitArray: Equatable {
    public static func == (lhs: BitArray, rhs: BitArray) -> Bool {
        guard lhs.count == rhs.count, lhs.storage.count == rhs.storage.count else {
            return false
        }
        
        for i in 0..<lhs.storage.count {
            if lhs.storage[i] != rhs.storage[i] {
                return false
            }
        }
        
        return true
    }
}

// MARK: - UInt11 Simulation (for completeness)
public struct UInt11 {
    let value: UInt16
    var binaryString: String { String(value, radix: 2).leftPadding(toLength: 11, withPad: "0") }
    
    init(_ value: UInt16) {
        precondition(value < 2048, "UInt11 value out of range")
        self.value = value
    }
}
