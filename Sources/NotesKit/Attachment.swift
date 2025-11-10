// This file is part of NotesKit.
// Copyright (c) 2025 6OVER3 Institute.
// Licensed under the GNU Affero General Public License v3.0.
// See LICENSE file for details.

import Foundation

/// An attachment in a note.
public enum NoteAttachment: Equatable, Sendable {
  case image(Image)
  case pdf(PDF)
  case video(Video)
  case audio(Audio)
  case file(File)
  case drawing(Drawing)
  case url(URLLink)
  case table(Table)
  case calendar(Calendar)
  case vcard(VCard)
  case gallery(Gallery)
  case scan(Scan)
  case unknown(Unknown)
  case deleted(Deleted)

  /// The unique identifier of the attachment.
  public var identifier: String {
    switch self {
    case .image(let a): a.identifier
    case .pdf(let a): a.identifier
    case .video(let a): a.identifier
    case .audio(let a): a.identifier
    case .file(let a): a.identifier
    case .drawing(let a): a.identifier
    case .url(let a): a.identifier
    case .table(let a): a.identifier
    case .calendar(let a): a.identifier
    case .vcard(let a): a.identifier
    case .gallery(let a): a.identifier
    case .scan(let a): a.identifier
    case .unknown(let a): a.identifier
    case .deleted(let a): a.identifier
    }
  }

  public var creationDate: Date? {
    switch self {
    case .image(let a): a.creationDate
    case .pdf(let a): a.creationDate
    case .video(let a): a.creationDate
    case .audio(let a): a.creationDate
    case .file(let a): a.creationDate
    case .drawing(let a): a.creationDate
    case .url(let a): a.creationDate
    case .table(let a): a.creationDate
    case .calendar(let a): a.creationDate
    case .vcard(let a): a.creationDate
    case .gallery(let a): a.creationDate
    case .scan(let a): a.creationDate
    case .unknown(let a): a.creationDate
    case .deleted(let a): a.creationDate
    }
  }

  public var modificationDate: Date? {
    switch self {
    case .image(let a): a.modificationDate
    case .pdf(let a): a.modificationDate
    case .video(let a): a.modificationDate
    case .audio(let a): a.modificationDate
    case .file(let a): a.modificationDate
    case .drawing(let a): a.modificationDate
    case .url(let a): a.modificationDate
    case .table(let a): a.modificationDate
    case .calendar(let a): a.modificationDate
    case .vcard(let a): a.modificationDate
    case .gallery(let a): a.modificationDate
    case .scan(let a): a.modificationDate
    case .unknown(let a): a.modificationDate
    case .deleted(let a): a.modificationDate
    }
  }

  /// The broad content category of this attachment.
  public var category: UTICategory {
    switch self {
    case .image(let a): UTIClassifier.category(for: a.uti)
    case .pdf(let a): UTIClassifier.category(for: a.uti)
    case .video(let a): UTIClassifier.category(for: a.uti)
    case .audio(let a): UTIClassifier.category(for: a.uti)
    case .file(let a): UTIClassifier.category(for: a.uti)
    case .drawing(let a): UTIClassifier.category(for: a.uti)
    case .url(let a): UTIClassifier.category(for: a.uti)
    case .calendar(let a): UTIClassifier.category(for: a.uti)
    case .vcard(let a): UTIClassifier.category(for: a.uti)
    case .scan(let a): UTIClassifier.category(for: a.uti)
    case .unknown(let a): UTIClassifier.category(for: a.uti)
    case .deleted(let a): UTIClassifier.category(for: a.uti)
    case .table: .other
    case .gallery: .other
    }
  }
}

// MARK: - Attachment Types

extension NoteAttachment {

  public struct Image: Equatable, Sendable {
    public let identifier: String
    public let uti: String
    public let filename: String?
    public let location: Location?
    public let creationDate: Date?
    public let modificationDate: Date?
    public let fileSize: Int64?
    public let width: Float?
    public let height: Float?
    public let ocrText: String?
    public let imageClassifications: [String]
    public let additionalIndexableText: String?
  }

  public struct PDF: Equatable, Sendable {
    public let identifier: String
    public let uti: String
    public let filename: String?
    public let creationDate: Date?
    public let modificationDate: Date?
    public let fileSize: Int64?
    public let ocrText: String?
    public let additionalIndexableText: String?
  }

  public struct Video: Equatable, Sendable {
    public let identifier: String
    public let uti: String
    public let filename: String?
    public let creationDate: Date?
    public let modificationDate: Date?
    public let duration: Double?
    public let fileSize: Int64?
    public let width: Float?
    public let height: Float?
  }

  public struct Audio: Equatable, Sendable {
    public let identifier: String
    public let uti: String
    public let title: String?
    public let filename: String?
    public let creationDate: Date?
    public let modificationDate: Date?
    public let duration: Double?
    public let fileSize: Int64?
  }

  public struct File: Equatable, Sendable {
    public let identifier: String
    public let uti: String
    public let filename: String?
    public let creationDate: Date?
    public let modificationDate: Date?
    public let fileSize: Int64?
  }

  public struct Drawing: Equatable, Sendable {
    public let identifier: String
    public let uti: String
    public let creationDate: Date?
    public let modificationDate: Date?
    public let width: Float?
    public let height: Float?
    public let fallbackTitle: String?
    public let handwritingSummary: String?
    public let additionalIndexableText: String?
    public let canvasBounds: CanvasBounds?
  }

  public struct URLLink: Equatable, Sendable {
    public let identifier: String
    public let uti: String
    public let creationDate: Date?
    public let modificationDate: Date?
    public let urlString: String?
    public let title: String?
    public let summary: String?
  }

  public struct Table: Equatable, Sendable {
    public let identifier: String
    public let creationDate: Date?
    public let modificationDate: Date?
  }

  public struct Calendar: Equatable, Sendable {
    public let identifier: String
    public let uti: String
    public let creationDate: Date?
    public let modificationDate: Date?
  }

  public struct VCard: Equatable, Sendable {
    public let identifier: String
    public let uti: String
    public let creationDate: Date?
    public let modificationDate: Date?
    public let filename: String?
  }

  public struct Gallery: Equatable, Sendable {
    public let identifier: String
    public let creationDate: Date?
    public let modificationDate: Date?
    public let items: [NoteAttachment]
  }

  public struct Scan: Equatable, Sendable {
    public let identifier: String
    public let uti: String
    public let creationDate: Date?
    public let modificationDate: Date?
    public let ocrText: String?
    public let additionalIndexableText: String?
  }

  public struct Unknown: Equatable, Sendable {
    public let identifier: String
    public let uti: String
    public let creationDate: Date?
    public let modificationDate: Date?
  }

  /// An attachment whose backing record was deleted from the database.
  public struct Deleted: Equatable, Sendable {
    public let identifier: String
    public let uti: String
    public let creationDate: Date?
    public let modificationDate: Date?
  }
}

// MARK: - Supporting Types

extension NoteAttachment {

  /// Canvas bounds for a drawing attachment.
  public struct CanvasBounds: Equatable, Sendable {
    public let originX: Double
    public let originY: Double
    public let width: Double
    public let height: Double
  }

  /// Geographic location for an attachment.
  public struct Location: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let placemarkData: Data?
  }

  /// A thumbnail for an attachment.
  public struct Thumbnail: Equatable, Sendable {
    public let identifier: String
    public let scale: Int
    public let width: Int
    public let height: Int
    /// 0 = light, 1 = dark.
    public let appearanceType: Int
    public let data: Data?
  }
}
