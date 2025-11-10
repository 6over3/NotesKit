// This file is part of NotesKit.
// Copyright (c) 2025 6OVER3 Institute.
// Licensed under the GNU Affero General Public License v3.0.
// See LICENSE file for details.

/// A folder in the Notes library.
public struct NotesFolder: Sendable {
  public let identifier: String
  public let name: String?
  public let parentIdentifier: String?
  public let accountIdentifier: String?

  /// Whether this is a smart folder (saved search).
  public let isSmartFolder: Bool

  /// The search query for smart folders, as JSON.
  public let smartFolderQuery: String?

  internal init(
    identifier: String,
    name: String?,
    parentIdentifier: String?,
    accountIdentifier: String?,
    isSmartFolder: Bool = false,
    smartFolderQuery: String? = nil
  ) {
    self.identifier = identifier
    self.name = name
    self.parentIdentifier = parentIdentifier
    self.accountIdentifier = accountIdentifier
    self.isSmartFolder = isSmartFolder
    self.smartFolderQuery = smartFolderQuery
  }
}
