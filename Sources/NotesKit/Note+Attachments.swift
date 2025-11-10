// This file is part of NotesKit.
// Copyright (c) 2025 6OVER3 Institute.
// Licensed under the GNU Affero General Public License v3.0.
// See LICENSE file for details.

import Foundation

extension Note {

  /// Retrieve thumbnails for an attachment.
  public func thumbnails(for attachment: NoteAttachment) throws -> [NoteAttachment.Thumbnail] {
    try database.fetchAttachmentThumbnails(
      identifier: attachment.identifier,
      backupRoot: backupRoot,
      accountIdentifier: accountIdentifier
    )
  }

  /// Retrieve the binary data for an attachment.
  ///
  /// For drawings, returns the fallback image. Use ``fallbackPDF(for:)``
  /// if you need the PDF render instead.
  ///
  /// - Throws: ``NotesError/notFound`` if the attachment or account doesn't exist.
  public func data(for attachment: NoteAttachment) throws -> Data {
    let id = attachment.identifier
    if case .drawing = attachment {
      if let image = try drawingFallbackImage(for: id) {
        return image
      }
    }

    guard let accountId = accountIdentifier else {
      throw NotesError.notFound
    }
    return try database.fetchAttachmentData(
      identifier: id,
      accountIdentifier: accountId,
      backupRoot: backupRoot
    )
  }

  /// Retrieve the filename for an attachment.
  public func filename(for attachment: NoteAttachment) throws -> String? {
    try database.fetchAttachmentFilename(identifier: attachment.identifier)
  }

  /// Get the file URL for an attachment on disk.
  public func url(for attachment: NoteAttachment) throws -> URL? {
    guard let record = try database.fetchAttachment(identifier: attachment.identifier),
      let accountId = accountIdentifier
    else {
      return nil
    }

    let resolver = AttachmentFileResolver(
      database: database,
      backupRoot: backupRoot,
      accountIdentifier: accountId
    )

    return try resolver.resolveFilePath(for: record)
  }

  /// Get the fallback PDF render for a drawing.
  public func fallbackPDF(for drawing: NoteAttachment.Drawing) throws -> Data? {
    guard let record = try fetchDrawingRecord(for: drawing.identifier) else { return nil }
    return try makeResolver()?.resolveFallbackPDF(for: record)
  }

  /// Get the fallback image render for a drawing.
  public func fallbackImage(for drawing: NoteAttachment.Drawing) throws -> Data? {
    guard let record = try fetchDrawingRecord(for: drawing.identifier) else { return nil }
    return try makeResolver()?.resolveFallbackImage(for: record)
  }

  /// Get the transcription for an audio attachment.
  public func transcription(for audio: NoteAttachment.Audio) throws -> AudioTranscription? {
    try audioTranscription(for: audio.identifier)
  }

  // MARK: - Private

  private func drawingFallbackImage(for identifier: String) throws -> Data? {
    guard let record = try fetchDrawingRecord(for: identifier) else { return nil }
    return try makeResolver()?.resolveFallbackImage(for: record)
  }

  private func fetchDrawingRecord(for identifier: String) throws -> AttachmentRecord? {
    guard let record = try database.fetchAttachment(identifier: identifier),
      let uti = record.uti,
      uti.contains("drawing") || uti.contains("com.apple.paper")
    else {
      return nil
    }
    return record
  }

  private func makeResolver() -> AttachmentFileResolver? {
    guard let accountId = accountIdentifier else { return nil }
    return AttachmentFileResolver(
      database: database,
      backupRoot: backupRoot,
      accountIdentifier: accountId
    )
  }
}

// MARK: - AttachmentFileResolver

internal struct AttachmentFileResolver {
  private let database: NotesDatabase
  private let backupRoot: URL
  private let accountIdentifier: String

  init(database: NotesDatabase, backupRoot: URL, accountIdentifier: String) {
    self.database = database
    self.backupRoot = backupRoot
    self.accountIdentifier = accountIdentifier
  }

  func resolveFilePath(for record: AttachmentRecord) throws -> URL? {
    let filename: String?
    if let mediaFK = record.mediaForeignKey,
      let mediaRecord = try? database.fetchMedia(primaryKey: mediaFK)
    {
      filename = mediaRecord.filename
    } else {
      filename = nil
    }

    guard let fname = filename else {
      return nil
    }

    return searchForFile(filename: fname)
  }

  func resolveFallbackPDF(for record: AttachmentRecord) throws -> Data? {
    let generation = try database.fetchGeneration(identifier: record.identifier, type: .fallbackPDF)
    let accountFolder = "Accounts/\(accountIdentifier)"

    let paths = buildFallbackPDFPaths(
      uuid: record.identifier,
      generation: generation,
      accountFolder: accountFolder
    )

    for path in paths {
      let url = backupRoot.appendingPathComponent(path)
      if let data = try? Data(contentsOf: url) {
        return data
      }
    }

    return nil
  }

  func resolveFallbackImage(for record: AttachmentRecord) throws -> Data? {
    let generation = try database.fetchGeneration(
      identifier: record.identifier,
      type: .fallbackImage
    )
    let accountFolder = "Accounts/\(accountIdentifier)"

    let paths = buildDrawingPaths(
      uuid: record.identifier,
      generation: generation,
      accountFolder: accountFolder
    )

    for path in paths {
      let url = backupRoot.appendingPathComponent(path)
      if let data = try? Data(contentsOf: url) {
        return data
      }
    }

    return nil
  }

  func searchForFile(filename: String) -> URL? {
    let searchPaths = ["Media", "Accounts"]

    for basePath in searchPaths {
      let fullPath = backupRoot.appendingPathComponent(basePath)
      if let foundURL = searchDirectory(fullPath, forFile: filename) {
        return foundURL
      }
    }

    return nil
  }

  private func searchDirectory(_ directory: URL, forFile filename: String) -> URL? {
    let enumerator = FileManager.default.enumerator(
      at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])

    while let fileURL = enumerator?.nextObject() as? URL {
      if fileURL.lastPathComponent == filename || fileURL.path.contains(filename) {
        return fileURL
      }
    }

    return nil
  }

  private func buildDrawingPaths(
    uuid: String,
    generation: String?,
    accountFolder: String
  ) -> [String] {
    var paths: [String] = []
    let extensions = ["jpeg", "png", "jpg"]

    for ext in extensions {
      if let generation = generation {
        paths.append("\(accountFolder)/FallbackImages/\(uuid)/\(generation)/FallbackImage.\(ext)")
      }
      paths.append("\(accountFolder)/FallbackImages/\(uuid).\(ext)")
    }

    return paths
  }

  private func buildFallbackPDFPaths(
    uuid: String,
    generation: String?,
    accountFolder: String
  ) -> [String] {
    var paths: [String] = []

    if let generation = generation {
      paths.append("\(accountFolder)/FallbackPDFs/\(uuid)/\(generation)/FallbackPDF.pdf")
    }
    paths.append("\(accountFolder)/FallbackPDFs/\(uuid).pdf")

    return paths
  }
}
