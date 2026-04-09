// This file is part of NotesKit.
// Copyright (c) 2025 6OVER3 Institute.
// Licensed under the GNU Affero General Public License v3.0.
// See LICENSE file for details.

import Foundation

public enum NotesError: LocalizedError, @unchecked Sendable {
  case decompressionFailed
  case protobufDecodingFailed(Error)
  case invalidNoteStructure
  case unsupportedVersion
  case databaseConnectionFailed(underlyingError: Error)
  case queryFailed(underlyingError: Error)
  case notFound
  case invalidData
  case passwordProtected
  case wrongPassword
  case decryptionFailed
  case unsupportedEncryption

  public var errorDescription: String? {
    switch self {
    case .decompressionFailed: "Failed to decompress note data"
    case .protobufDecodingFailed(let error):
      "Failed to decode protobuf: \(error.localizedDescription)"
    case .invalidNoteStructure: "Invalid note structure"
    case .unsupportedVersion: "Unsupported database version"
    case .databaseConnectionFailed(let error):
      "Database connection failed: \(error.localizedDescription)"
    case .queryFailed(let error): "Database query failed: \(error.localizedDescription)"
    case .notFound: "Note or attachment not found"
    case .invalidData: "Invalid data"
    case .passwordProtected: "Note is password-protected"
    case .wrongPassword: "Incorrect password"
    case .decryptionFailed: "Decryption failed"
    case .unsupportedEncryption: "Note uses device-key encryption (not password-derivable)"
    }
  }
}
