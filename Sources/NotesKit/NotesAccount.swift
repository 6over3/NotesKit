// This file is part of NotesKit.
// Copyright (c) 2025 6OVER3 Institute.
// Licensed under the GNU Affero General Public License v3.0.
// See LICENSE file for details.

/// A Notes account (iCloud, On My Mac, Gmail, etc.).
public struct NotesAccount: Sendable {

  /// The type of Notes account.
  public enum AccountType: Int, Sendable {
    case local = 0
    case exchange = 1
    case imap = 2
    case iCloud = 3
    case google = 4
    case unknown = -1

    public var displayName: String {
      switch self {
      case .local: "On My Mac"
      case .exchange: "Exchange"
      case .imap: "IMAP"
      case .iCloud: "iCloud"
      case .google: "Google"
      case .unknown: "Unknown"
      }
    }
  }

  public let identifier: String
  public let name: String?
  public let accountType: AccountType
}
