// This file is part of NotesKit.
// Copyright (c) 2025 6OVER3 Institute.
// Licensed under the GNU Affero General Public License v3.0.
// See LICENSE file for details.

import Foundation

/// A single note from the Apple Notes library.
public struct Note: Sendable {

  public var identifier: String { record.identifier }
  public var title: String { record.title }
  public var modificationDate: Date? { record.modificationDate }
  public var creationDate: Date? { record.creationDate }
  public var isPinned: Bool { record.isPinned }
  public var isPasswordProtected: Bool { record.isPasswordProtected }
  public var isMarkedForDeletion: Bool { record.isMarkedForDeletion }

  /// CoreData optimistic lock counter. Increments on every edit.
  public var changeCounter: Int64 { record.changeCounter }

  public var folderIdentifier: String? { record.folderIdentifier }
  public var accountIdentifier: String? { record.accountIdentifier }
  public let account: NotesAccount?
  public let folder: NotesFolder?

  private let record: NoteRecord
  package let database: NotesDatabase
  internal let backupRoot: URL

  internal init(
    record: NoteRecord,
    database: NotesDatabase,
    backupRoot: URL,
    account: NotesAccount?,
    folder: NotesFolder?
  ) {
    self.record = record
    self.database = database
    self.backupRoot = backupRoot
    self.account = account
    self.folder = folder
  }

  /// Parse the note content using a visitor.
  ///
  /// - Parameters:
  ///   - password: The note lock password. Required for encrypted notes, ignored otherwise.
  ///   - visitor: The visitor to receive parsing callbacks.
  /// - Throws: ``NotesError/passwordProtected`` if encrypted and no password is provided.
  ///   ``NotesError/decryptionFailed`` if the password is wrong.
  public func parse<V: NoteVisitor>(visitor: V, password: String? = nil) throws {
    let parser = NoteParser(database: database)

    guard isPasswordProtected else {
      try parser.parse(record, visitor: visitor)
      return
    }

    guard let password else {
      throw NotesError.passwordProtected
    }

    let parameters = try decryptionParameters()
    let decryptedData = try NoteDecrypter.decrypt(password: password, parameters: parameters)
    try parser.parse(data: decryptedData, visitor: visitor)
  }

  /// Resolve encryption parameters based on the detected format.
  private func decryptionParameters() throws -> NoteDecrypter.Parameters {
    switch NoteDecrypter.detectFormat(data: record.compressedData) {
    case .v1Neo(let parameters):
      return parameters
    case .v2Keychain:
      throw NotesError.unsupportedEncryption
    case .v1:
      guard let crypto = try database.fetchCryptoParameters(noteIdentifier: identifier) else {
        throw NotesError.decryptionFailed
      }
      return NoteDecrypter.v1Parameters(crypto: crypto, ciphertext: record.compressedData)
    case nil:
      throw NotesError.decryptionFailed
    }
  }

  /// Convert the note content to Markdown.
  ///
  /// - Parameter password: The note lock password. Required for encrypted notes, ignored otherwise.
  public func markdown(password: String? = nil) throws -> String {
    try MarkdownVisitor.markdown(from: self, password: password)
  }

  /// Flat string dictionary of note-level metadata.
  ///
  /// Merges account and folder metadata when available.
  /// Keys use snake_case. Only non-nil, non-empty values are included.
  public var metadata: [String: String] {
    var m: [String: String] = [:]
    if let account { m.merge(account.metadata) { _, new in new } }
    if let folder, let name = folder.name { m["folder"] = name }
    if isPinned { m["pinned"] = "true" }
    if isMarkedForDeletion { m["deleted"] = "true" }
    return m
  }
}
