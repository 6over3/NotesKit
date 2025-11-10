// This file is part of NotesKit.
// Copyright (c) 2025 6OVER3 Institute.
// Licensed under the GNU Affero General Public License v3.0.
// See LICENSE file for details.

import CommonCrypto
import CryptoKit
import Foundation

/// Decrypt password-protected Apple Notes.
///
/// Supports two encryption schemes:
/// - **V1** (iOS 16 and earlier): AES-128-GCM, 16-byte keys, params stored in DB columns.
/// - **V1 Neo** (macOS 15+): AES-256-GCM, 32-byte keys, params embedded in ZDATA as an NSKeyedArchive plist.
///
/// A third scheme (V2) uses Keychain-stored keys and cannot be decrypted with a password alone.
internal struct NoteDecrypter: Sendable {

  /// Normalized crypto parameters for both V1 and V1 Neo.
  struct Parameters: Sendable {
    let salt: Data
    let iterations: Int
    let keyLength: Int
    let wrappedKey: Data
    let iv: Data
    let tag: Data
    let ciphertext: Data
    let authenticatedData: Data?
  }

  /// Decrypt an encrypted note given a password and normalized parameters.
  /// Return the gzip-compressed protobuf.
  /// - Throws: ``NotesError/wrongPassword`` if the password doesn't unwrap the key.
  ///   ``NotesError/decryptionFailed`` if decryption fails for other reasons.
  static func decrypt(password: String, parameters: Parameters) throws -> Data {
    guard
      let kek = deriveKey(
        password: password, salt: parameters.salt,
        iterations: parameters.iterations, keyLength: parameters.keyLength
      )
    else { throw NotesError.decryptionFailed }

    guard let dek = unwrapKey(wrappedKey: parameters.wrappedKey, kek: kek) else {
      throw NotesError.wrongPassword
    }

    guard
      let plaintext = decryptAESGCM(
        key: dek, iv: parameters.iv, tag: parameters.tag,
        ciphertext: parameters.ciphertext, aad: parameters.authenticatedData
      )
    else { throw NotesError.decryptionFailed }

    return plaintext
  }

  // MARK: - Format Detection

  /// The encryption format detected from ZDATA.
  enum Format {
    /// V1: crypto params live in DB columns, ZDATA is raw ciphertext.
    case v1
    /// V1 Neo: crypto params embedded in the ZDATA plist, password-decryptable.
    case v1Neo(Parameters)
    /// V2: requires a Keychain-stored key, not password-decryptable.
    case v2Keychain
  }

  private static let bplistMagic = Data("bplist00".utf8)

  /// Detect the encryption format from ZDATA.
  /// Returns nil if the data isn't a recognized encrypted format.
  static func detectFormat(data: Data) -> Format? {
    guard data.count > 8, data.prefix(8) == bplistMagic else {
      return .v1
    }
    return parseEncryptionPlist(data)
  }

  /// Build V1 parameters from DB columns and the raw ZDATA ciphertext.
  static func v1Parameters(crypto: CryptoParameters, ciphertext: Data) -> Parameters {
    Parameters(
      salt: crypto.salt, iterations: crypto.iterations, keyLength: 16,
      wrappedKey: crypto.wrappedKey, iv: crypto.iv, tag: crypto.tag,
      ciphertext: ciphertext, authenticatedData: nil
    )
  }

  // MARK: - NSKeyedArchive Parsing

  /// Parse the ICCryptoEncryptionObject plist embedded in ZDATA.
  private static func parseEncryptionPlist(_ data: Data) -> Format? {
    guard
      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
        as? [String: Any],
      let objects = plist["$objects"] as? [Any],
      objects.count >= 6,
      let mainDict = objects[1] as? [String: Any],
      let metadataIdx = archiveUID(mainDict["metadata"]),
      let unauthIdx = archiveUID(mainDict["unauthenticatedMetadata"]),
      let wrappedKeyIdx = archiveUID(mainDict["wrappedEncryptionKey"]),
      let encDataIdx = archiveUID(mainDict["encryptedData"]),
      let authenticatedData = objects[metadataIdx] as? Data
    else { return nil }

    // V2 notes carry an accountKeyIdentifier — not password-decryptable
    if let metaPlist = try? PropertyListSerialization.propertyList(
      from: authenticatedData, format: nil) as? [String: Any],
      metaPlist["accountKeyIdentifier"] != nil
    {
      return .v2Keychain
    }

    guard
      let unauthData = objects[unauthIdx] as? Data,
      let unauthPlist = try? PropertyListSerialization.propertyList(
        from: unauthData, format: nil) as? [String: Any],
      let salt = unauthPlist["passphraseSalt"] as? Data,
      let iterations = unauthPlist["passphraseIterationCount"] as? Int,
      let wrappedKey = objects[wrappedKeyIdx] as? Data,
      let encryptedData = objects[encDataIdx] as? Data,
      encryptedData.count > 48
    else { return nil }

    // encryptedData layout: ciphertext(N) + IV(32) + tag(16)
    let splitPoint = encryptedData.count - 48
    let params = Parameters(
      salt: salt, iterations: iterations, keyLength: 32,
      wrappedKey: wrappedKey,
      iv: encryptedData.subdata(in: splitPoint..<(splitPoint + 32)),
      tag: encryptedData.subdata(in: (splitPoint + 32)..<encryptedData.count),
      ciphertext: encryptedData.prefix(splitPoint),
      authenticatedData: authenticatedData
    )
    return .v1Neo(params)
  }

  /// Extract the integer index from a CFKeyedArchiverUID plist object.
  private static func archiveUID(_ object: Any?) -> Int? {
    guard let object else { return nil }
    // CFKeyedArchiverUID's description: "<CFKeyedArchiverUID ...>{value = N}"
    let desc = String(describing: object)
    guard let range = desc.range(of: "value = ") else { return nil }
    return Int(desc[range.upperBound...].prefix(while: \.isNumber))
  }

  // MARK: - Crypto Primitives

  private static func deriveKey(
    password: String, salt: Data, iterations: Int, keyLength: Int
  ) -> Data? {
    var derivedKey = Data(count: keyLength)
    let status = derivedKey.withUnsafeMutableBytes { derivedBytes in
      salt.withUnsafeBytes { saltBytes in
        CCKeyDerivationPBKDF(
          CCPBKDFAlgorithm(kCCPBKDF2),
          password, password.utf8.count,
          saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
          CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
          UInt32(iterations),
          derivedBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), keyLength
        )
      }
    }
    return status == kCCSuccess ? derivedKey : nil
  }

  private static func unwrapKey(wrappedKey: Data, kek: Data) -> Data? {
    var unwrappedSize = CCSymmetricUnwrappedSize(CCWrappingAlgorithm(kCCWRAPAES), wrappedKey.count)
    var unwrapped = Data(count: unwrappedSize)
    let status = unwrapped.withUnsafeMutableBytes { unwrappedBytes in
      wrappedKey.withUnsafeBytes { wrappedBytes in
        kek.withUnsafeBytes { kekBytes in
          guard let unwrappedPtr = unwrappedBytes.baseAddress,
            let wrappedPtr = wrappedBytes.baseAddress,
            let kekPtr = kekBytes.baseAddress
          else { return Int32(kCCParamError) }
          return CCSymmetricKeyUnwrap(
            CCWrappingAlgorithm(kCCWRAPAES),
            CCrfc3394_iv, CCrfc3394_ivLen,
            kekPtr, kek.count,
            wrappedPtr, wrappedKey.count,
            unwrappedPtr, &unwrappedSize
          )
        }
      }
    }
    guard status == kCCSuccess else { return nil }
    return unwrapped.prefix(unwrappedSize)
  }

  private static func decryptAESGCM(
    key: Data, iv: Data, tag: Data, ciphertext: Data, aad: Data?
  ) -> Data? {
    do {
      let sealedBox = try AES.GCM.SealedBox(
        nonce: AES.GCM.Nonce(data: iv), ciphertext: ciphertext, tag: tag
      )
      if let aad {
        return try AES.GCM.open(sealedBox, using: SymmetricKey(data: key), authenticating: aad)
      }
      return try AES.GCM.open(sealedBox, using: SymmetricKey(data: key))
    } catch {
      return nil
    }
  }
}
