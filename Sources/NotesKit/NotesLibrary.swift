// This file is part of NotesKit.
// Copyright (c) 2025 6OVER3 Institute.
// Licensed under the GNU Affero General Public License v3.0.
// See LICENSE file for details.

import Foundation

/// Entry point for reading Apple Notes data.
public struct NotesLibrary {

  /// The source location for the Notes database.
  public enum Source {
    /// The standard Apple Notes database location on this Mac.
    case system

    /// A custom database file location.
    case custom(URL)

    /// An iTunes/Finder hashed backup directory (contains Manifest.db).
    case itunesBackup(URL)

    /// A physical device filesystem root (contains private/var/mobile/...).
    case physicalBackup(URL)
  }

  private let database: NotesDatabase
  private let backupRoot: URL

  /// Open the Notes library.
  ///
  /// - Parameter source: The database source. Defaults to the standard Apple Notes location.
  /// - Throws: ``NotesError/databaseConnectionFailed`` if the database cannot be opened.
  public init(source: Source = .system) throws {
    switch source {
    case .system:
      let notesPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Group Containers/group.com.apple.notes")
      self.backupRoot = notesPath
      let dbPath = notesPath.appendingPathComponent("NoteStore.sqlite")
      self.database = try NotesDatabase(databaseURL: dbPath)

    case .custom(let url):
      self.backupRoot = url.deletingLastPathComponent()
      self.database = try NotesDatabase(databaseURL: url)

    case .itunesBackup(let root):
      let dbPath = try Self.resolveITunesBackupDatabase(root: root)
      self.backupRoot = root
      self.database = try NotesDatabase(databaseURL: dbPath)

    case .physicalBackup(let root):
      let dbPath = try Self.resolvePhysicalBackupDatabase(root: root)
      self.backupRoot = dbPath.deletingLastPathComponent()
      self.database = try NotesDatabase(databaseURL: dbPath)
    }
  }

  // MARK: - Backup Resolution

  /// Find NoteStore.sqlite in an iTunes hashed backup via its known SHA1 hash.
  private static func resolveITunesBackupDatabase(root: URL) throws -> URL {
    // SHA1 of "AppDomainGroup-group.com.apple.notes/NoteStore.sqlite"
    let hashedPath =
      root
      .appendingPathComponent("4f")
      .appendingPathComponent("4f98687d8ab0d6d1a371110e6b7300f6e465bef2")

    if FileManager.default.fileExists(atPath: hashedPath.path) {
      return hashedPath
    }

    throw NotesError.databaseConnectionFailed(
      underlyingError: NSError(
        domain: "NotesKit",
        code: -1,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Could not find NoteStore.sqlite in iTunes backup at \(root.path)"
        ]
      )
    )
  }

  /// Find NoteStore.sqlite in a physical device filesystem backup.
  private static func resolvePhysicalBackupDatabase(root: URL) throws -> URL {
    let appGroupPath =
      root
      .appendingPathComponent("private/var/mobile/Containers/Shared/AppGroup")

    let fm = FileManager.default
    guard let contents = try? fm.contentsOfDirectory(atPath: appGroupPath.path) else {
      throw NotesError.databaseConnectionFailed(
        underlyingError: NSError(
          domain: "NotesKit",
          code: -1,
          userInfo: [
            NSLocalizedDescriptionKey:
              "Could not find AppGroup directory in physical backup at \(root.path)"
          ]
        )
      )
    }

    for uuid in contents {
      let candidate =
        appGroupPath
        .appendingPathComponent(uuid)
        .appendingPathComponent("NoteStore.sqlite")
      if fm.fileExists(atPath: candidate.path) {
        return candidate
      }
    }

    throw NotesError.databaseConnectionFailed(
      underlyingError: NSError(
        domain: "NotesKit",
        code: -1,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Could not find NoteStore.sqlite in physical backup at \(root.path)"
        ]
      )
    )
  }

  /// The detected iOS/macOS version of the Notes database.
  public var version: NotesVersion {
    database.version
  }

  /// All accounts in the library.
  public var accounts: [NotesAccount] {
    get throws { try database.fetchAllAccounts() }
  }

  /// All folders in the library.
  public var folders: [NotesFolder] {
    get throws { try database.fetchAllFolders() }
  }

  /// All notes in the library.
  public var notes: [Note] {
    get throws {
      let records = try database.fetchAllNotes()
      let accounts = try database.fetchAllAccounts()
      let folders = try database.fetchAllFolders()

      var accountLookup: [String: NotesAccount] = [:]
      for account in accounts {
        accountLookup[account.identifier] = account
      }

      var folderLookup: [String: NotesFolder] = [:]
      for folder in folders {
        folderLookup[folder.identifier] = folder
      }

      return records.map { record in
        Note(
          record: record,
          database: database,
          backupRoot: backupRoot,
          account: record.accountIdentifier.flatMap { accountLookup[$0] },
          folder: record.folderIdentifier.flatMap { folderLookup[$0] }
        )
      }
    }
  }

  /// Find a specific account by identifier.
  public func account(identifier: String) throws -> NotesAccount? {
    try accounts.first { $0.identifier == identifier }
  }

  /// Find a specific folder by identifier.
  public func folder(identifier: String) throws -> NotesFolder? {
    try folders.first { $0.identifier == identifier }
  }

  /// Find a specific note by identifier.
  public func note(identifier: String) throws -> Note? {
    let records = try database.fetchAllNotes()
    guard let record = records.first(where: { $0.identifier == identifier }) else {
      return nil
    }

    let allAccounts = try database.fetchAllAccounts()
    let allFolders = try database.fetchAllFolders()

    let account = record.accountIdentifier.flatMap { id in
      allAccounts.first { $0.identifier == id }
    }
    let folder = record.folderIdentifier.flatMap { id in
      allFolders.first { $0.identifier == id }
    }

    return Note(
      record: record,
      database: database,
      backupRoot: backupRoot,
      account: account,
      folder: folder
    )
  }
}
