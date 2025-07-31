import Foundation

public extension Mnemonic {

    static func deriveLanguageFromMnemonic(words: [String]) -> Language? {
        func tryLanguage(_ language: Language) -> Language? {
            let vocabulary = Set(wordList(for: language))
            let wordsLeftToCheck = Set(words)
            guard wordsLeftToCheck.isSubset(of: vocabulary) else { return nil }
            return language
        }

        for language in Language.allCases {
            if let derived = tryLanguage(language) {
                return derived
            }
        }
        return nil
    }

    @discardableResult
    static func validateChecksumDerivingLanguageOf(mnemonic mnemonicWords: [String]) throws -> Bool {
        guard let derivedLanguage = deriveLanguageFromMnemonic(words: mnemonicWords) else {
            throw MnemonicError.validationError(.unableToDeriveLanguageFrom(words: mnemonicWords))
        }
        return try validateChecksumOf(mnemonic: mnemonicWords, language: derivedLanguage)
    }

    @discardableResult
    static func validateChecksumOf(mnemonic mnemonicWords: [String], language: Language) throws -> Bool {
        let vocabulary = wordList(for: language)

        // Map words to UInt11 indices safely
        let indices: [UInt11] = try mnemonicWords.map { word in
            guard let indexInVocabulary = vocabulary.firstIndex(of: word) else {
                throw MnemonicError.validationError(.wordNotInList(word, language: language))
            }
            guard let indexAs11Bits = UInt11(exactly: indexInVocabulary) else {
                fatalError("Word list longer than 2048 words (unexpected)")
            }
            return indexAs11Bits
        }

        // Initialize BitArray from binary string (from UInt11 array converted to binary string)
        let binaryString = indices.map { $0.binaryString }.joined()
        guard let bitArray = BitArray(binaryString: binaryString) else {
            fatalError("Failed to create BitArray from UInt11 binary string")
        }

        let checksumLength = mnemonicWords.count / 3

        // Use standard prefix and suffix with Int param (not maxCount)
        let dataBits = bitArray.prefix(bitArray.count - checksumLength)
        let checksumBits = bitArray.suffix(checksumLength)

        // Compute hash
        let hash = Crypto.sha256(BitArray(dataBits).asData())


        // Create BitArray from hash data again from binary string
        let hashBinaryString = hash.binaryString
        guard let hashBits = BitArray(binaryString: hashBinaryString)?.prefix(checksumLength) else {
            fatalError("Failed to create BitArray from hash")
        }

        // Compare bits (convert slices to arrays to be sure)
        guard Array(hashBits) == Array(checksumBits) else {
            throw MnemonicError.validationError(.checksumMismatch)
        }

        return true
    }
}
