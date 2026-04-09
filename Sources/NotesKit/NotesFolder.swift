// This file is part of NotesKit.
// Copyright (c) 2025 6OVER3 Institute.
// Licensed under the GNU Affero General Public License v3.0.
// See LICENSE file for details.

/// A folder in the Notes library.
public struct NotesFolder: Sendable, Codable {
  public let identifier: String
  public let name: String?
  public let parentIdentifier: String?
  public let accountIdentifier: String?

  /// Whether this is a smart folder (saved search).
  public let isSmartFolder: Bool

  /// The search query for smart folders, as JSON.
  public let smartFolderQuery: String?

  /// Whether this is the "Recently Deleted" trash folder.
  public let isTrash: Bool

  private enum CodingKeys: String, CodingKey {
    case identifier, name
    case parentIdentifier = "parent_identifier"
    case accountIdentifier = "account_identifier"
    case isSmartFolder = "is_smart_folder"
    case smartFolderQuery = "smart_folder_query"
    case isTrash = "is_trash"
  }

  internal init(
    identifier: String,
    name: String?,
    parentIdentifier: String?,
    accountIdentifier: String?,
    isSmartFolder: Bool = false,
    smartFolderQuery: String? = nil,
    isTrash: Bool = false
  ) {
    self.identifier = identifier
    self.name = name
    self.parentIdentifier = parentIdentifier
    self.accountIdentifier = accountIdentifier
    self.isSmartFolder = isSmartFolder
    self.smartFolderQuery = smartFolderQuery
    self.isTrash = isTrash
  }
}
