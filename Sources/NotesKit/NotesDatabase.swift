// This file is part of NotesKit.
// Copyright (c) 2025 6OVER3 Institute.
// Licensed under the GNU Affero General Public License v3.0.
// See LICENSE file for details.

import Foundation
import SQLite3
import SwiftProtobuf

// MARK: - Notes Database

package final class NotesDatabase {
  private let connection: OpaquePointer?
  private(set) var version: NotesVersion = .unknown

  enum GenerationType {
    case media
    case fallbackImage
    case fallbackPDF
  }

  init(databaseURL: URL) throws {
    var db: OpaquePointer?
    let flags = SQLITE_OPEN_READONLY
    let result = sqlite3_open_v2(databaseURL.path, &db, flags, nil)

    guard result == SQLITE_OK else {
      let message = String(cString: sqlite3_errmsg(db))
      sqlite3_close(db)
      throw NotesError.databaseConnectionFailed(
        underlyingError: NSError(
          domain: "SQLite",
          code: Int(result),
          userInfo: [NSLocalizedDescriptionKey: message]
        )
      )
    }

    self.connection = db
    self.version = detectVersion()
  }

  deinit {
    sqlite3_close(connection)
  }

  private func detectVersion() -> NotesVersion {
    let columns = getTableColumns("ZICCLOUDSYNCINGOBJECT")

    if columns.contains(where: { $0.hasPrefix("ZUNAPPLIEDENCRYPTEDRECORDDATA") }) {
      return .v18
    }
    if columns.contains(where: { $0.hasPrefix("ZGENERATION") }) {
      return .v17
    }
    if columns.contains(where: { $0.hasPrefix("ZACCOUNT6") }) {
      return .v16
    }
    if columns.contains(where: { $0.hasPrefix("ZACCOUNT5") }) {
      return .v15
    }
    if columns.contains(where: { $0.hasPrefix("ZLASTOPENEDDATE") }) {
      return .v14
    }
    if columns.contains(where: { $0.hasPrefix("ZACCOUNT4") }) {
      return .v13
    }
    if columns.contains(where: { $0.hasPrefix("ZSERVERRECORDDATA") }) {
      return .v12
    }

    return .unknown
  }

  private func getTableColumns(_ tableName: String) -> [String] {
    var columns: [String] = []
    let query = "PRAGMA table_info(\(tableName));"

    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(connection, query, -1, &statement, nil) == SQLITE_OK else {
      return []
    }
    defer { sqlite3_finalize(statement) }

    while sqlite3_step(statement) == SQLITE_ROW {
      if let cString = sqlite3_column_text(statement, 1) {
        columns.append(String(cString: cString))
      }
    }

    return columns
  }

  func fetchAllAccounts() throws -> [NotesAccount] {
    // First get the entity ID for ICAccount
    let entityQuery = "SELECT Z_ENT FROM Z_PRIMARYKEY WHERE Z_NAME = 'ICAccount'"
    var statement: OpaquePointer?

    guard sqlite3_prepare_v2(connection, entityQuery, -1, &statement, nil) == SQLITE_OK else {
      throw NotesError.queryFailed(underlyingError: makeSQLiteError())
    }
    defer { sqlite3_finalize(statement) }

    guard sqlite3_step(statement) == SQLITE_ROW else {
      return []
    }

    let accountEntity = sqlite3_column_int64(statement, 0)

    let hasAccountType = hasColumn(table: "ZICCLOUDSYNCINGOBJECT", column: "ZACCOUNTTYPE")

    var accounts: [NotesAccount] = []

    let query: String
    if hasAccountType {
      query = """
        SELECT ZIDENTIFIER, ZNAME, ZACCOUNTTYPE
        FROM ZICCLOUDSYNCINGOBJECT
        WHERE Z_ENT = ? AND (ZMARKEDFORDELETION = 0 OR ZMARKEDFORDELETION IS NULL)
        """
    } else {
      query = """
        SELECT ZIDENTIFIER, ZNAME
        FROM ZICCLOUDSYNCINGOBJECT
        WHERE Z_ENT = ? AND (ZMARKEDFORDELETION = 0 OR ZMARKEDFORDELETION IS NULL)
        """
    }

    var queryStatement: OpaquePointer?
    guard sqlite3_prepare_v2(connection, query, -1, &queryStatement, nil) == SQLITE_OK else {
      throw NotesError.queryFailed(underlyingError: makeSQLiteError())
    }
    defer { sqlite3_finalize(queryStatement) }

    sqlite3_bind_int64(queryStatement, 1, accountEntity)

    while sqlite3_step(queryStatement) == SQLITE_ROW {
      guard let identifierCStr = sqlite3_column_text(queryStatement, 0) else { continue }
      let identifier = String(cString: identifierCStr)

      let name: String?
      if let nameCStr = sqlite3_column_text(queryStatement, 1) {
        name = String(cString: nameCStr)
      } else {
        name = nil
      }

      let accountType: NotesAccount.AccountType
      if hasAccountType {
        let accountTypeRaw = sqlite3_column_int64(queryStatement, 2)
        accountType = NotesAccount.AccountType(rawValue: Int(accountTypeRaw)) ?? .unknown
      } else {
        accountType = .unknown
      }

      accounts.append(
        NotesAccount(
          identifier: identifier,
          name: name,
          accountType: accountType
        ))
    }

    return accounts
  }

  func fetchAllFolders() throws -> [NotesFolder] {
    // First get the entity ID for ICFolder
    let entityQuery = "SELECT Z_ENT FROM Z_PRIMARYKEY WHERE Z_NAME = 'ICFolder'"
    var statement: OpaquePointer?

    guard sqlite3_prepare_v2(connection, entityQuery, -1, &statement, nil) == SQLITE_OK else {
      throw NotesError.queryFailed(underlyingError: makeSQLiteError())
    }
    defer { sqlite3_finalize(statement) }

    guard sqlite3_step(statement) == SQLITE_ROW else {
      return []
    }

    let folderEntity = sqlite3_column_int64(statement, 0)

    let columns = getTableColumns("ZICCLOUDSYNCINGOBJECT")
    let accountColumnName: String? =
      if columns.contains("ZOWNER") {
        "ZOWNER"
      } else if columns.contains("ZACCOUNT") {
        "ZACCOUNT"
      } else if columns.contains("ZACCOUNT2") {
        "ZACCOUNT2"
      } else {
        nil
      }

    let titleColumnName =
      if columns.contains("ZTITLE2") {
        "ZTITLE2"
      } else if columns.contains("ZTITLE1") {
        "ZTITLE1"
      } else {
        "ZTITLE"
      }

    let hasSmartFolderColumn = columns.contains("ZSMARTFOLDERQUERYJSON")
    let smartFolderExpr = hasSmartFolderColumn ? "ZSMARTFOLDERQUERYJSON" : "NULL"

    var folders: [NotesFolder] = []

    let query: String
    if let accountCol = accountColumnName {
      query = """
        SELECT ZIDENTIFIER, \(titleColumnName), ZPARENT, \(accountCol), \(smartFolderExpr)
        FROM ZICCLOUDSYNCINGOBJECT
        WHERE Z_ENT = ? AND (ZMARKEDFORDELETION = 0 OR ZMARKEDFORDELETION IS NULL)
        """
    } else {
      query = """
        SELECT ZIDENTIFIER, \(titleColumnName), ZPARENT, NULL, \(smartFolderExpr)
        FROM ZICCLOUDSYNCINGOBJECT
        WHERE Z_ENT = ? AND (ZMARKEDFORDELETION = 0 OR ZMARKEDFORDELETION IS NULL)
        """
    }

    var queryStatement: OpaquePointer?
    guard sqlite3_prepare_v2(connection, query, -1, &queryStatement, nil) == SQLITE_OK else {
      throw NotesError.queryFailed(underlyingError: makeSQLiteError())
    }
    defer { sqlite3_finalize(queryStatement) }

    sqlite3_bind_int64(queryStatement, 1, folderEntity)

    while sqlite3_step(queryStatement) == SQLITE_ROW {
      guard let identifierCStr = sqlite3_column_text(queryStatement, 0) else { continue }
      let identifier = String(cString: identifierCStr)

      let title: String?
      if let titleCStr = sqlite3_column_text(queryStatement, 1) {
        title = String(cString: titleCStr)
      } else {
        title = nil
      }

      let parent: String?
      if let parentCStr = sqlite3_column_text(queryStatement, 2) {
        parent = String(cString: parentCStr)
      } else {
        parent = nil
      }

      let account: String?
      if let accountCStr = sqlite3_column_text(queryStatement, 3) {
        account = String(cString: accountCStr)
      } else {
        account = nil
      }

      let smartFolderQuery: String?
      if let queryCStr = sqlite3_column_text(queryStatement, 4) {
        smartFolderQuery = String(cString: queryCStr)
      } else {
        smartFolderQuery = nil
      }

      folders.append(
        NotesFolder(
          identifier: identifier,
          name: title,
          parentIdentifier: parent,
          accountIdentifier: account,
          isSmartFolder: smartFolderQuery != nil && !smartFolderQuery!.isEmpty,
          smartFolderQuery: smartFolderQuery
        ))
    }

    return folders
  }

  func fetchAllNotes() throws -> [NoteRecord] {
    // First get entity IDs
    let entityQuery = "SELECT Z_ENT FROM Z_PRIMARYKEY WHERE Z_NAME IN ('ICAccount', 'ICNote')"
    var statement: OpaquePointer?

    guard sqlite3_prepare_v2(connection, entityQuery, -1, &statement, nil) == SQLITE_OK else {
      throw NotesError.queryFailed(underlyingError: makeSQLiteError())
    }
    defer { sqlite3_finalize(statement) }

    var accountEntity: Int64 = 0
    var noteEntity: Int64 = 0

    // Get both entity IDs
    let entNameQuery =
      "SELECT Z_ENT, Z_NAME FROM Z_PRIMARYKEY WHERE Z_NAME IN ('ICAccount', 'ICNote')"
    var entStatement: OpaquePointer?
    guard sqlite3_prepare_v2(connection, entNameQuery, -1, &entStatement, nil) == SQLITE_OK else {
      throw NotesError.queryFailed(underlyingError: makeSQLiteError())
    }
    defer { sqlite3_finalize(entStatement) }

    while sqlite3_step(entStatement) == SQLITE_ROW {
      let ent = sqlite3_column_int64(entStatement, 0)
      if let nameCStr = sqlite3_column_text(entStatement, 1) {
        let name = String(cString: nameCStr)
        if name == "ICAccount" {
          accountEntity = ent
        } else if name == "ICNote" {
          noteEntity = ent
        }
      }
    }

    guard accountEntity != 0 && noteEntity != 0 else {
      throw NotesError.queryFailed(
        underlyingError: NSError(domain: "NotesKit", code: -1)
      )
    }

    let columns = getTableColumns("ZICCLOUDSYNCINGOBJECT")

    let titleColumnName =
      if columns.contains("ZTITLE1") {
        "ZTITLE1"
      } else if columns.contains("ZTITLE2") {
        "ZTITLE2"
      } else {
        "ZTITLE"
      }

    let folderColumnName = columns.contains("ZFOLDER") ? "ZFOLDER" : "ZFOLDER2"

    let accountColumnName: String? =
      if columns.contains("ZACCOUNT7") {
        "ZACCOUNT7"
      } else if columns.contains("ZACCOUNT4") {
        "ZACCOUNT4"
      } else if columns.contains("ZACCOUNT3") {
        "ZACCOUNT3"
      } else if columns.contains("ZACCOUNT2") {
        "ZACCOUNT2"
      } else if columns.contains("ZACCOUNT") {
        "ZACCOUNT"
      } else {
        nil
      }

    let creationDateColumnName =
      if columns.contains("ZCREATIONDATE3") {
        "ZCREATIONDATE3"
      } else if columns.contains("ZCREATIONDATE1") {
        "ZCREATIONDATE1"
      } else {
        "ZCREATIONDATE"
      }

    let modificationDateColumnName =
      if columns.contains("ZMODIFICATIONDATE1") {
        "ZMODIFICATIONDATE1"
      } else {
        "ZMODIFICATIONDATE"
      }

    let query: String
    if let accountCol = accountColumnName {
      query = """
        SELECT
          n.ZIDENTIFIER,
          n.\(titleColumnName),
          n.\(modificationDateColumnName),
          n.\(creationDateColumnName),
          n.ZISPINNED,
          n.\(folderColumnName),
          a.ZIDENTIFIER,
          d.ZDATA,
          n.ZISPASSWORDPROTECTED
        FROM ZICCLOUDSYNCINGOBJECT n
        LEFT OUTER JOIN ZICCLOUDSYNCINGOBJECT a
          ON n.\(accountCol) = a.Z_PK AND a.Z_ENT = ?
        INNER JOIN ZICNOTEDATA d
          ON n.ZNOTEDATA = d.Z_PK
        WHERE n.Z_ENT = ? AND d.ZDATA IS NOT NULL
        """
    } else {
      query = """
        SELECT
          n.ZIDENTIFIER,
          n.\(titleColumnName),
          n.\(modificationDateColumnName),
          n.\(creationDateColumnName),
          n.ZISPINNED,
          n.\(folderColumnName),
          d.ZDATA,
          n.ZISPASSWORDPROTECTED
        FROM ZICCLOUDSYNCINGOBJECT n
        INNER JOIN ZICNOTEDATA d
          ON n.ZNOTEDATA = d.Z_PK
        WHERE n.Z_ENT = ? AND d.ZDATA IS NOT NULL
        """
    }

    var queryStatement: OpaquePointer?
    guard sqlite3_prepare_v2(connection, query, -1, &queryStatement, nil) == SQLITE_OK else {
      throw NotesError.queryFailed(underlyingError: makeSQLiteError())
    }
    defer { sqlite3_finalize(queryStatement) }

    if accountColumnName != nil {
      sqlite3_bind_int64(queryStatement, 1, accountEntity)
      sqlite3_bind_int64(queryStatement, 2, noteEntity)
    } else {
      sqlite3_bind_int64(queryStatement, 1, noteEntity)
    }

    var notes: [NoteRecord] = []

    while sqlite3_step(queryStatement) == SQLITE_ROW {
      guard let identifierCStr = sqlite3_column_text(queryStatement, 0) else { continue }
      let identifier = String(cString: identifierCStr)

      let title: String
      if let titleCStr = sqlite3_column_text(queryStatement, 1) {
        title = String(cString: titleCStr)
      } else {
        title = ""
      }

      let modificationDate: Date?
      if sqlite3_column_type(queryStatement, 2) != SQLITE_NULL {
        let timestamp = sqlite3_column_int64(queryStatement, 2)
        modificationDate = convertCoreDataTimestamp(timestamp)
      } else {
        modificationDate = nil
      }

      let creationDate: Date?
      if sqlite3_column_type(queryStatement, 3) != SQLITE_NULL {
        let timestamp = sqlite3_column_int64(queryStatement, 3)
        creationDate = convertCoreDataTimestamp(timestamp)
      } else {
        creationDate = nil
      }

      let isPinned = sqlite3_column_int64(queryStatement, 4) != 0

      let folderIdentifier: String?
      if let folderCStr = sqlite3_column_text(queryStatement, 5) {
        folderIdentifier = String(cString: folderCStr)
      } else {
        folderIdentifier = nil
      }

      let accountIdentifier: String?
      let dataColumnIndex: Int32
      let passwordColumnIndex: Int32

      if accountColumnName != nil {
        if let accountCStr = sqlite3_column_text(queryStatement, 6) {
          accountIdentifier = String(cString: accountCStr)
        } else {
          accountIdentifier = nil
        }
        dataColumnIndex = 7
        passwordColumnIndex = 8
      } else {
        accountIdentifier = nil
        dataColumnIndex = 6
        passwordColumnIndex = 7
      }

      guard let dataBytes = sqlite3_column_blob(queryStatement, dataColumnIndex) else {
        continue
      }
      let dataLength = sqlite3_column_bytes(queryStatement, dataColumnIndex)
      let compressedData = Data(bytes: dataBytes, count: Int(dataLength))

      let isPasswordProtected = sqlite3_column_int64(queryStatement, passwordColumnIndex) != 0

      notes.append(
        NoteRecord(
          identifier: identifier,
          title: title,
          compressedData: compressedData,
          modificationDate: modificationDate,
          creationDate: creationDate,
          isPinned: isPinned,
          isPasswordProtected: isPasswordProtected,
          folderIdentifier: folderIdentifier,
          accountIdentifier: accountIdentifier
        ))
    }

    return notes
  }

  func fetchAttachment(identifier: String) throws -> AttachmentRecord? {
    let columns = getTableColumns("ZICCLOUDSYNCINGOBJECT")
    // COALESCE across all title column variants — different schema versions
    // store attachment titles in different columns
    var titleColumns: [String] = []
    for col in ["ZTITLE", "ZTITLE1", "ZTITLE2"] {
      if columns.contains(col) { titleColumns.append(col) }
    }
    let titleExpression =
      titleColumns.isEmpty ? "NULL" : "COALESCE(\(titleColumns.joined(separator: ", ")))"

    let creationDateCol =
      if columns.contains("ZCREATIONDATE3") {
        "ZCREATIONDATE3"
      } else if columns.contains("ZCREATIONDATE1") {
        "ZCREATIONDATE1"
      } else {
        "ZCREATIONDATE"
      }

    let modificationDateCol =
      if columns.contains("ZMODIFICATIONDATE1") {
        "ZMODIFICATIONDATE1"
      } else {
        "ZMODIFICATIONDATE"
      }

    let query = """
      SELECT
        ZIDENTIFIER, ZTYPEUTI, ZTYPEUTI1, ZMEDIA, ZMERGEABLEDATA1, ZMERGEABLEDATA,
        ZURLSTRING, Z_PK, ZALTTEXT, ZTOKENCONTENTIDENTIFIER, ZUSERTITLE, ZDURATION,
        ZFILESIZE, ZOCRSUMMARY, ZHANDWRITINGSUMMARY, ZIMAGECLASSIFICATIONSUMMARY,
        ZADDITIONALINDEXABLETEXT, ZFALLBACKTITLE, ZFALLBACKSUBTITLEIOS,
        ZFALLBACKSUBTITLEMAC, ZMETADATADATA, \(titleExpression),
        \(creationDateCol), \(modificationDateCol)
      FROM ZICCLOUDSYNCINGOBJECT
      WHERE ZIDENTIFIER = ?
      """

    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(connection, query, -1, &statement, nil) == SQLITE_OK else {
      throw NotesError.queryFailed(underlyingError: makeSQLiteError())
    }
    defer { sqlite3_finalize(statement) }

    guard let identifierCStr = identifier.cString(using: .utf8) else {
      return nil
    }
    sqlite3_bind_text(statement, 1, identifierCStr, -1, nil)

    guard sqlite3_step(statement) == SQLITE_ROW else {
      return nil
    }

    guard let idCStr = sqlite3_column_text(statement, 0) else { return nil }
    let id = String(cString: idCStr)

    let uti: String?
    if let uti1CStr = sqlite3_column_text(statement, 2) {
      uti = String(cString: uti1CStr)
    } else if let utiCStr = sqlite3_column_text(statement, 1) {
      uti = String(cString: utiCStr)
    } else {
      uti = nil
    }

    let mediaFK: Int64?
    if sqlite3_column_type(statement, 3) != SQLITE_NULL {
      mediaFK = sqlite3_column_int64(statement, 3)
    } else {
      mediaFK = nil
    }

    let mergeableData: Data?
    if let data1Bytes = sqlite3_column_blob(statement, 4) {
      let length = sqlite3_column_bytes(statement, 4)
      mergeableData = Data(bytes: data1Bytes, count: Int(length))
    } else if let dataBytes = sqlite3_column_blob(statement, 5) {
      let length = sqlite3_column_bytes(statement, 5)
      mergeableData = Data(bytes: dataBytes, count: Int(length))
    } else {
      mergeableData = nil
    }

    let urlString = sqlite3_column_text(statement, 6).map { String(cString: $0) }
    let altText = sqlite3_column_text(statement, 8).map { String(cString: $0) }
    let tokenIdentifier = sqlite3_column_text(statement, 9).map { String(cString: $0) }
    let userTitle = sqlite3_column_text(statement, 10).map { String(cString: $0) }

    let duration: Double?
    if sqlite3_column_type(statement, 11) != SQLITE_NULL {
      duration = sqlite3_column_double(statement, 11)
    } else {
      duration = nil
    }

    let fileSize: Int64?
    if sqlite3_column_type(statement, 12) != SQLITE_NULL {
      fileSize = sqlite3_column_int64(statement, 12)
    } else {
      fileSize = nil
    }

    let ocrSummary = sqlite3_column_text(statement, 13).map { String(cString: $0) }
    let handwritingSummary = sqlite3_column_text(statement, 14).map { String(cString: $0) }

    let classifications = Array(
      Set(
        sqlite3_column_text(statement, 15)
          .map { String(cString: $0) }?
          .split(separator: " ")
          .map(String.init) ?? []
      ))

    let additionalIndexableText = sqlite3_column_text(statement, 16).map { String(cString: $0) }
    let fallbackTitle = sqlite3_column_text(statement, 17).map { String(cString: $0) }
    let fallbackSubtitleIOS = sqlite3_column_text(statement, 18).map { String(cString: $0) }
    let fallbackSubtitleMac = sqlite3_column_text(statement, 19).map { String(cString: $0) }

    let metadataJSON: String?
    if let metadataBytes = sqlite3_column_blob(statement, 20) {
      let length = sqlite3_column_bytes(statement, 20)
      let data = Data(bytes: metadataBytes, count: Int(length))
      metadataJSON = String(data: data, encoding: .utf8)
    } else {
      metadataJSON = nil
    }

    let title = sqlite3_column_text(statement, 21).map { String(cString: $0) }

    let creationDate: Date?
    if sqlite3_column_type(statement, 22) != SQLITE_NULL {
      creationDate = convertCoreDataTimestamp(sqlite3_column_int64(statement, 22))
    } else {
      creationDate = nil
    }

    let modificationDate: Date?
    if sqlite3_column_type(statement, 23) != SQLITE_NULL {
      modificationDate = convertCoreDataTimestamp(sqlite3_column_int64(statement, 23))
    } else {
      modificationDate = nil
    }

    return AttachmentRecord(
      identifier: id,
      title: title,
      uti: uti,
      mediaForeignKey: mediaFK,
      mergeableData: mergeableData,
      urlString: urlString,
      altText: altText,
      tokenIdentifier: tokenIdentifier,
      userTitle: userTitle,
      duration: duration,
      fileSize: fileSize,
      ocrSummary: ocrSummary,
      handwritingSummary: handwritingSummary,
      imageClassifications: classifications,
      additionalIndexableText: additionalIndexableText,
      fallbackTitle: fallbackTitle,
      fallbackSubtitleIOS: fallbackSubtitleIOS,
      fallbackSubtitleMac: fallbackSubtitleMac,
      metadataJSON: metadataJSON,
      creationDate: creationDate,
      modificationDate: modificationDate
    )
  }

  func fetchAttachmentData(
    identifier: String,
    accountIdentifier: String,
    backupRoot: URL
  ) throws -> Data {
    guard let attachmentRecord = try fetchAttachment(identifier: identifier) else {
      throw NotesError.notFound
    }

    if let uti = attachmentRecord.uti {
      if uti == "com.apple.paper" {
        let resolver = AttachmentFileResolver(
          database: self,
          backupRoot: backupRoot,
          accountIdentifier: accountIdentifier
        )
        if let fallbackData = try resolver.resolveFallbackImage(for: attachmentRecord) {
          return fallbackData
        }
      } else if uti == "com.apple.paper.doc.pdf" {
        let resolver = AttachmentFileResolver(
          database: self,
          backupRoot: backupRoot,
          accountIdentifier: accountIdentifier
        )
        if let fallbackData = try resolver.resolveFallbackPDF(for: attachmentRecord) {
          return fallbackData
        }
      }
    }

    guard let mediaFK = attachmentRecord.mediaForeignKey else {
      let resolver = AttachmentFileResolver(
        database: self,
        backupRoot: backupRoot,
        accountIdentifier: accountIdentifier
      )

      if let fileURL = try resolver.resolveFilePath(for: attachmentRecord) {
        return try Data(contentsOf: fileURL)
      }

      throw NotesError.notFound
    }

    guard let mediaRecord = try fetchMedia(primaryKey: mediaFK),
      let filename = mediaRecord.filename
    else {
      throw NotesError.notFound
    }

    let resolver = AttachmentFileResolver(
      database: self,
      backupRoot: backupRoot,
      accountIdentifier: accountIdentifier
    )

    if let fileURL = resolver.searchForFile(filename: filename) {
      return try Data(contentsOf: fileURL)
    }

    throw NotesError.notFound
  }

  func fetchAttachmentFilename(identifier: String) throws -> String? {
    let query = "SELECT ZMEDIA FROM ZICCLOUDSYNCINGOBJECT WHERE ZIDENTIFIER = ?"

    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(connection, query, -1, &statement, nil) == SQLITE_OK else {
      return nil
    }
    defer { sqlite3_finalize(statement) }

    guard let identifierCStr = identifier.cString(using: .utf8) else {
      return nil
    }
    sqlite3_bind_text(statement, 1, identifierCStr, -1, nil)

    guard sqlite3_step(statement) == SQLITE_ROW,
      sqlite3_column_type(statement, 0) != SQLITE_NULL
    else {
      return nil
    }

    let mediaPK = sqlite3_column_int64(statement, 0)
    let mediaRecord = try fetchMedia(primaryKey: mediaPK)
    return mediaRecord?.filename
  }

  func fetchMedia(primaryKey: Int64) throws -> MediaRecord? {
    let query = """
      SELECT ZIDENTIFIER, ZFILENAME, ZSIZEWIDTH, ZSIZEHEIGHT
      FROM ZICCLOUDSYNCINGOBJECT
      WHERE Z_PK = ?
      """

    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(connection, query, -1, &statement, nil) == SQLITE_OK else {
      throw NotesError.queryFailed(underlyingError: makeSQLiteError())
    }
    defer { sqlite3_finalize(statement) }

    sqlite3_bind_int64(statement, 1, primaryKey)

    guard sqlite3_step(statement) == SQLITE_ROW else {
      return nil
    }

    guard let identifierCStr = sqlite3_column_text(statement, 0) else { return nil }
    let identifier = String(cString: identifierCStr)

    let filename = sqlite3_column_text(statement, 1).map { String(cString: $0) }

    let width: Int?
    if sqlite3_column_type(statement, 2) != SQLITE_NULL {
      width = Int(sqlite3_column_int64(statement, 2))
    } else {
      width = nil
    }

    let height: Int?
    if sqlite3_column_type(statement, 3) != SQLITE_NULL {
      height = Int(sqlite3_column_int64(statement, 3))
    } else {
      height = nil
    }

    return MediaRecord(
      identifier: identifier,
      filename: filename,
      width: width,
      height: height
    )
  }

  func fetchMergeableData(identifier: String) throws -> Data? {
    let query = """
      SELECT ZMERGEABLEDATA1
      FROM ZICCLOUDSYNCINGOBJECT
      WHERE ZIDENTIFIER = ? AND (ZMARKEDFORDELETION = 0 OR ZMARKEDFORDELETION IS NULL)
      LIMIT 1
      """

    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(connection, query, -1, &statement, nil) == SQLITE_OK else {
      throw NotesError.queryFailed(underlyingError: makeSQLiteError())
    }
    defer { sqlite3_finalize(statement) }

    guard let identifierCStr = identifier.cString(using: .utf8) else {
      return nil
    }
    sqlite3_bind_text(statement, 1, identifierCStr, -1, nil)

    guard sqlite3_step(statement) == SQLITE_ROW else {
      return nil
    }

    guard let dataBytes = sqlite3_column_blob(statement, 0) else {
      return nil
    }

    let length = sqlite3_column_bytes(statement, 0)
    return Data(bytes: dataBytes, count: Int(length))
  }

  func fetchURLLinkCard(identifier: String) throws -> (url: String, title: String?)? {
    let query = """
      SELECT ZMERGEABLEDATA1, ZTITLE, ZALTTEXT, ZURLSTRING
      FROM ZICCLOUDSYNCINGOBJECT
      WHERE ZIDENTIFIER = ? AND (ZMARKEDFORDELETION = 0 OR ZMARKEDFORDELETION IS NULL)
      """

    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(connection, query, -1, &statement, nil) == SQLITE_OK else {
      throw NotesError.queryFailed(underlyingError: makeSQLiteError())
    }
    defer { sqlite3_finalize(statement) }

    guard let identifierCStr = identifier.cString(using: .utf8) else {
      return nil
    }
    sqlite3_bind_text(statement, 1, identifierCStr, -1, nil)

    guard sqlite3_step(statement) == SQLITE_ROW else {
      return nil
    }

    let title =
      sqlite3_column_text(statement, 1).map { String(cString: $0) }
      ?? sqlite3_column_text(statement, 2).map { String(cString: $0) }

    if let urlCStr = sqlite3_column_text(statement, 3) {
      let url = String(cString: urlCStr)
      if !url.isEmpty {
        return (url: url, title: title)
      }
    }

    if let dataBytes = sqlite3_column_blob(statement, 0) {
      let length = sqlite3_column_bytes(statement, 0)
      let data = Data(bytes: dataBytes, count: Int(length))
      let decompressed = data.gunzipped() ?? data
      if let url = extractURLFromProtobuf(decompressed) {
        return (url: url, title: title)
      }
    }

    return nil
  }

  private func extractURLFromProtobuf(_ data: Data) -> String? {
    do {
      let proto = try Notes_MergableDataProto(serializedBytes: data)
      let objectData = proto.mergableDataObject.mergeableDataObjectData

      for entry in objectData.mergeableDataObjectEntry {
        if entry.hasNote {
          let text = entry.note.noteText
          if text.hasPrefix("http://") || text.hasPrefix("https://") {
            return text
          }
        }
      }
    } catch {
      return nil
    }

    return nil
  }

  func fetchAttachmentThumbnails(
    identifier: String,
    backupRoot: URL,
    accountIdentifier: String?
  ) throws -> [NoteAttachment.Thumbnail] {
    // First get the primary key for the attachment
    let pkQuery = "SELECT Z_PK FROM ZICCLOUDSYNCINGOBJECT WHERE ZIDENTIFIER = ?"
    var pkStatement: OpaquePointer?

    guard sqlite3_prepare_v2(connection, pkQuery, -1, &pkStatement, nil) == SQLITE_OK else {
      throw NotesError.queryFailed(underlyingError: makeSQLiteError())
    }
    defer { sqlite3_finalize(pkStatement) }

    guard let identifierCStr = identifier.cString(using: .utf8) else {
      return []
    }
    sqlite3_bind_text(pkStatement, 1, identifierCStr, -1, nil)

    guard sqlite3_step(pkStatement) == SQLITE_ROW else {
      return []
    }

    let basePK = sqlite3_column_int64(pkStatement, 0)

    let query = """
      SELECT ZIDENTIFIER, ZSCALE, ZWIDTH, ZHEIGHT, ZAPPEARANCETYPE
      FROM ZICCLOUDSYNCINGOBJECT
      WHERE ZATTACHMENT = ? AND Z_ENT = 5
      """

    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(connection, query, -1, &statement, nil) == SQLITE_OK else {
      throw NotesError.queryFailed(underlyingError: makeSQLiteError())
    }
    defer { sqlite3_finalize(statement) }

    sqlite3_bind_int64(statement, 1, basePK)

    var thumbnails: [NoteAttachment.Thumbnail] = []

    while sqlite3_step(statement) == SQLITE_ROW {
      guard let idCStr = sqlite3_column_text(statement, 0),
        sqlite3_column_type(statement, 1) != SQLITE_NULL,
        sqlite3_column_type(statement, 2) != SQLITE_NULL,
        sqlite3_column_type(statement, 3) != SQLITE_NULL,
        sqlite3_column_type(statement, 4) != SQLITE_NULL
      else {
        continue
      }

      let id = String(cString: idCStr)
      let scale = Int(sqlite3_column_int64(statement, 1))
      let width = Int(sqlite3_column_int64(statement, 2))
      let height = Int(sqlite3_column_int64(statement, 3))
      let appearance = Int(sqlite3_column_int64(statement, 4))

      var thumbnailData: Data?
      if let accountId = accountIdentifier {
        let extensions = ["jpg", "jpeg", "png"]

        for ext in extensions {
          let path =
            backupRoot
            .appendingPathComponent("Accounts/\(accountId)/Media/\(id).\(ext)")
          if let data = try? Data(contentsOf: path) {
            thumbnailData = data
            break
          }
        }
      }

      thumbnails.append(
        NoteAttachment.Thumbnail(
          identifier: id,
          scale: scale,
          width: width,
          height: height,
          appearanceType: appearance,
          data: thumbnailData
        ))
    }

    return thumbnails
  }

  func fetchGeneration(
    identifier: String,
    type: GenerationType = .media
  ) throws -> String? {
    let columnName: String
    switch type {
    case .media:
      columnName = "ZGENERATION"
    case .fallbackImage:
      columnName = "ZFALLBACKIMAGEGENERATION"
    case .fallbackPDF:
      columnName = "ZFALLBACKPDFGENERATION"
    }

    guard hasColumn(table: "ZICCLOUDSYNCINGOBJECT", column: columnName) else {
      return nil
    }

    let query = "SELECT \(columnName) FROM ZICCLOUDSYNCINGOBJECT WHERE ZIDENTIFIER = ?"

    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(connection, query, -1, &statement, nil) == SQLITE_OK else {
      return nil
    }
    defer { sqlite3_finalize(statement) }

    guard let identifierCStr = identifier.cString(using: .utf8) else {
      return nil
    }
    sqlite3_bind_text(statement, 1, identifierCStr, -1, nil)

    guard sqlite3_step(statement) == SQLITE_ROW,
      let generationCStr = sqlite3_column_text(statement, 0)
    else {
      return nil
    }

    return String(cString: generationCStr)
  }

  private func hasColumn(table: String, column: String) -> Bool {
    let query = "PRAGMA table_info(\(table))"
    var statement: OpaquePointer?

    guard sqlite3_prepare_v2(connection, query, -1, &statement, nil) == SQLITE_OK else {
      return false
    }
    defer { sqlite3_finalize(statement) }

    while sqlite3_step(statement) == SQLITE_ROW {
      if let columnName = sqlite3_column_text(statement, 1) {
        if String(cString: columnName) == column {
          return true
        }
      }
    }

    return false
  }

  func fetchCryptoParameters(noteIdentifier: String) throws -> CryptoParameters? {
    let query = """
      SELECT n.ZCRYPTOSALT, n.ZCRYPTOITERATIONCOUNT, n.ZCRYPTOWRAPPEDKEY,
             d.ZCRYPTOINITIALIZATIONVECTOR, d.ZCRYPTOTAG
      FROM ZICCLOUDSYNCINGOBJECT n
      INNER JOIN ZICNOTEDATA d ON n.ZNOTEDATA = d.Z_PK
      WHERE n.ZIDENTIFIER = ?
      """

    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(connection, query, -1, &statement, nil) == SQLITE_OK else {
      throw NotesError.queryFailed(underlyingError: makeSQLiteError())
    }
    defer { sqlite3_finalize(statement) }

    guard let cStr = noteIdentifier.cString(using: .utf8) else { return nil }
    sqlite3_bind_text(statement, 1, cStr, -1, nil)

    guard sqlite3_step(statement) == SQLITE_ROW else { return nil }

    guard let saltPtr = sqlite3_column_blob(statement, 0),
      let wrappedKeyPtr = sqlite3_column_blob(statement, 2),
      let ivPtr = sqlite3_column_blob(statement, 3),
      let tagPtr = sqlite3_column_blob(statement, 4)
    else {
      return nil
    }

    let salt = Data(bytes: saltPtr, count: Int(sqlite3_column_bytes(statement, 0)))
    let iterations = Int(sqlite3_column_int64(statement, 1))
    let wrappedKey = Data(bytes: wrappedKeyPtr, count: Int(sqlite3_column_bytes(statement, 2)))
    let iv = Data(bytes: ivPtr, count: Int(sqlite3_column_bytes(statement, 3)))
    let tag = Data(bytes: tagPtr, count: Int(sqlite3_column_bytes(statement, 4)))

    guard !salt.isEmpty, iterations > 0, !wrappedKey.isEmpty, !iv.isEmpty, !tag.isEmpty else {
      return nil
    }

    return CryptoParameters(
      salt: salt, iterations: iterations, wrappedKey: wrappedKey, iv: iv, tag: tag)
  }

  private func convertCoreDataTimestamp(_ timestamp: Int64) -> Date {
    let referenceDate = Date(timeIntervalSinceReferenceDate: 0)
    return referenceDate.addingTimeInterval(TimeInterval(timestamp))
  }

  private func makeSQLiteError() -> Error {
    let message =
      connection.flatMap { sqlite3_errmsg($0) }
      .map { String(cString: $0) } ?? "Unknown SQLite error"
    let code = connection.map { sqlite3_errcode($0) } ?? SQLITE_ERROR
    return NSError(
      domain: "SQLite",
      code: Int(code),
      userInfo: [NSLocalizedDescriptionKey: message]
    )
  }
}
