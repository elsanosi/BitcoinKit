import Foundation

/// An array of boolean values stored using individual bits, providing a compact memory footprint.
public struct BitArray: Hashable, RangeReplaceableCollection {
    
    // MARK: - Storage
    
    private var storage: [Int]
    public private(set) var count: Int
    public private(set) var cardinality: Int
    
    private struct Constants {
        static let IntSize = MemoryLayout<Int>.size * 8
    }
    
    // MARK: - Initializers

    public init<C: Collection>(uInt11Values: C) where C.Element == UInt11 {
    self.init(uInt11Values.map { $0 != UInt11(0) })
}
    
    public init() {
        storage = []
        count = 0
        cardinality = 0
    }
    
    public init<S: Sequence>(_ elements: S) where S.Element == Bool {
        self.init()
        elements.forEach { append($0) }
    }
    
    public init(data: Data) {
        self.init()
        data.forEach { byte in
            for bitIndex in 0..<8 {
               append(((byte >> (7 - bitIndex)) & 1) == 1)
            }
        }
    }
    
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
    
    public init(intRepresentation: [Int]) {
        self.init(intRepresentation.map { $0 != 0 })
    }
    
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
    
    public func index(after i: Int) -> Int { i + 1 }
    
    public subscript(position: Int) -> Bool {
        get {
            precondition(indices.contains(position), "Index out of bounds")
            let (arrayIndex, bitIndex) = indexPath(for: position)
            return storage[arrayIndex] & (1 << bitIndex) != 0
        }
        set {
            precondition(indices.contains(position), "Index out of bounds")
            setValue(newValue, at: position)
        }
    }
    
    // MARK: - RangeReplaceableCollection
    
    public mutating func replaceSubrange<C: Collection>(
        _ subrange: Range<Int>,
        with newElements: C
    ) where C.Element == Bool {
        precondition(subrange.lowerBound >= 0 && subrange.upperBound <= count, "Range out of bounds")
        
        // Convert to array once for multiple accesses
        let newElementsArray = Array(newElements)
        let removalCount = subrange.count
        let insertionCount = newElementsArray.count
        let delta = insertionCount - removalCount
        
        // Adjust storage capacity if needed
        if delta > 0 {
            reserveCapacity(count + delta)
        }
        
        // Shift elements after the range
        if delta != 0 {
            for i in stride(from: count - 1, through: subrange.upperBound, by: -1) {
                let newPosition = i + delta
                if newPosition < count {
                    self[newPosition] = self[i]
                }
            }
        }
        
        // Insert new elements
        for (offset, element) in newElementsArray.enumerated() {
            let position = subrange.lowerBound + offset
            if position < count {
                self[position] = element
            } else {
                append(element)
            }
        }
        
        // Remove leftover elements if new range is smaller
        if delta < 0 {
            removeLast(-delta)
        }
    }
    
    public mutating func reserveCapacity(_ minimumCapacity: Int) {
        let neededInts = (minimumCapacity + Constants.IntSize - 1) / Constants.IntSize
        storage.reserveCapacity(neededInts)
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
        default: break
        }
    }
    
    private func indexPath(for logicalIndex: Int) -> (arrayIndex: Int, bitIndex: Int) {
        return (logicalIndex / Constants.IntSize, logicalIndex % Constants.IntSize)
    }
    
    // MARK: - Mutations
    
    public mutating func append(_ bit: Bool) {
        let (arrayIndex, bitIndex) = indexPath(for: count)
        if arrayIndex >= storage.count {
            storage.append(0)
        }
        setValue(bit, at: count)
        count += 1
    }
    
    public mutating func insert(_ bit: Bool, at index: Int) {
        replaceSubrange(index..<index, with: CollectionOfOne(bit))
    }
    
    @discardableResult
    public mutating func remove(at index: Int) -> Bool {
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
    
    // MARK: - Convenience
    
    public var first: Bool? { isEmpty ? nil : self[0] }
    public var last: Bool? { isEmpty ? nil : self[count - 1] }
}

// MARK: - Protocol Conformances
extension BitArray: MutableCollection, RandomAccessCollection {}

extension BitArray: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: Bool...) {
        self.init(elements)
    }
}

extension BitArray: CustomStringConvertible {
    public var description: String { binaryString }
    public var binaryString: String { map { $0 ? "1" : "0" }.joined() }
}

// MARK: - Conversion
extension BitArray {
    public func asBoolArray() -> [Bool] { Array(self) }
    
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
    
    public func asData() -> Data { Data(asBytes()) }
}

// MARK: - Equality
extension BitArray: Equatable {
    public static func == (lhs: BitArray, rhs: BitArray) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return lhs.elementsEqual(rhs)
    }
}

// MARK: - String Padding Helper
extension String {
    func leftPadding(toLength length: Int, withPad pad: String) -> String {
        guard count < length else { return self }
        return String(repeating: pad, count: length - count) + self
    }
}
