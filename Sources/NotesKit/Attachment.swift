// This file is part of NotesKit.
// Copyright (c) 2025 6OVER3 Institute.
// Licensed under the GNU Affero General Public License v3.0.
// See LICENSE file for details.

import Foundation

/// An attachment in a note.
public enum NoteAttachment: Equatable, Sendable, Codable {
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

  /// CoreData optimistic lock counter. Increments on every edit.
  public var changeCounter: Int64 {
    switch self {
    case .image(let a): a.changeCounter
    case .pdf(let a): a.changeCounter
    case .video(let a): a.changeCounter
    case .audio(let a): a.changeCounter
    case .file(let a): a.changeCounter
    case .drawing(let a): a.changeCounter
    case .url(let a): a.changeCounter
    case .table(let a): a.changeCounter
    case .calendar(let a): a.changeCounter
    case .vcard(let a): a.changeCounter
    case .gallery(let a): a.changeCounter
    case .scan(let a): a.changeCounter
    case .unknown(let a): a.changeCounter
    case .deleted(let a): a.changeCounter
    }
  }

  /// Media generation identifier. Changes when the attachment's backing file is regenerated.
  public var generation: String? {
    switch self {
    case .image(let a): a.generation
    case .pdf(let a): a.generation
    case .video(let a): a.generation
    case .audio(let a): a.generation
    case .file(let a): a.generation
    case .drawing(let a): a.generation
    case .url(let a): a.generation
    case .table(let a): a.generation
    case .calendar(let a): a.generation
    case .vcard(let a): a.generation
    case .gallery(let a): a.generation
    case .scan(let a): a.generation
    case .unknown(let a): a.generation
    case .deleted(let a): a.generation
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

// MARK: - Type Name

extension NoteAttachment {

  /// Machine-readable type name for this attachment case.
  public var typeName: String {
    switch self {
    case .image: "image"
    case .pdf: "pdf"
    case .video: "video"
    case .audio: "audio"
    case .file: "file"
    case .drawing: "drawing"
    case .url: "url"
    case .table: "table"
    case .calendar: "calendar"
    case .vcard: "vcard"
    case .gallery: "gallery"
    case .scan: "scan"
    case .unknown: "unknown"
    case .deleted: "deleted"
    }
  }

  /// Filename from the inner type, if one exists.
  public var filename: String? {
    switch self {
    case .image(let a): a.filename
    case .pdf(let a): a.filename
    case .video(let a): a.filename
    case .audio(let a): a.filename
    case .file(let a): a.filename
    case .vcard(let a): a.filename
    default: nil
    }
  }

  /// File size in bytes, if known.
  public var fileSize: Int64? {
    switch self {
    case .image(let a): a.fileSize
    case .pdf(let a): a.fileSize
    case .video(let a): a.fileSize
    case .audio(let a): a.fileSize
    case .file(let a): a.fileSize
    default: nil
    }
  }

  /// UTI string, if the attachment type carries one.
  public var uti: String? {
    switch self {
    case .image(let a): a.uti
    case .pdf(let a): a.uti
    case .video(let a): a.uti
    case .audio(let a): a.uti
    case .file(let a): a.uti
    case .drawing(let a): a.uti
    case .url(let a): a.uti
    case .calendar(let a): a.uti
    case .vcard(let a): a.uti
    case .scan(let a): a.uti
    case .unknown(let a): a.uti
    case .deleted(let a): a.uti
    case .table, .gallery: nil
    }
  }
}

// MARK: - Metadata

extension NoteAttachment {

  /// Flat string dictionary of all type-specific metadata.
  ///
  /// Keys use snake_case. Only non-nil, non-empty values are included.
  /// Dates are ISO 8601. Dimensions are formatted as "WxH".
  public var metadata: [String: String] {
    var m: [String: String] = [:]
    m["type"] = typeName

    if let gen = generation { m["generation"] = gen }
    if let created = creationDate { m["created_at"] = created.ISO8601Format() }
    if let modified = modificationDate { m["modified_at"] = modified.ISO8601Format() }

    switch self {
    case .image(let img):
      if let w = img.width, let h = img.height {
        m["dimensions"] = "\(Int(w))×\(Int(h))"
      }
      if let ocr = img.ocrText, !ocr.isEmpty { m["ocr_text"] = ocr }
      if !img.imageClassifications.isEmpty {
        m["image_classifications"] = img.imageClassifications.joined(separator: ", ")
      }
      if let loc = img.location {
        m["latitude"] = String(loc.latitude)
        m["longitude"] = String(loc.longitude)
      }
      if let text = img.additionalIndexableText, !text.isEmpty {
        m["indexable_text"] = text
      }

    case .pdf(let pdf):
      if let ocr = pdf.ocrText, !ocr.isEmpty { m["ocr_text"] = ocr }
      if let text = pdf.additionalIndexableText, !text.isEmpty {
        m["indexable_text"] = text
      }

    case .video(let vid):
      if let d = vid.duration { m["duration"] = String(d) }
      if let w = vid.width, let h = vid.height {
        m["dimensions"] = "\(Int(w))×\(Int(h))"
      }

    case .audio(let aud):
      if let t = aud.title { m["title"] = t }
      if let d = aud.duration { m["duration"] = String(d) }

    case .drawing(let drw):
      if let w = drw.width, let h = drw.height {
        m["dimensions"] = "\(Int(w))×\(Int(h))"
      }
      if let s = drw.handwritingSummary, !s.isEmpty { m["handwriting_summary"] = s }
      if let t = drw.fallbackTitle, !t.isEmpty { m["fallback_title"] = t }
      if let text = drw.additionalIndexableText, !text.isEmpty {
        m["indexable_text"] = text
      }

    case .url(let link):
      if let u = link.urlString { m["url"] = u }
      if let t = link.title { m["title"] = t }
      if let s = link.summary, !s.isEmpty { m["summary"] = s }

    case .scan(let scan):
      if let ocr = scan.ocrText, !ocr.isEmpty { m["ocr_text"] = ocr }
      if let text = scan.additionalIndexableText, !text.isEmpty {
        m["indexable_text"] = text
      }

    case .file, .gallery, .table, .calendar, .vcard, .unknown, .deleted:
      break
    }

    return m
  }
}

// MARK: - Attachment Types

extension NoteAttachment {

  public struct Image: Equatable, Sendable, Codable {
    public let identifier: String
    public let uti: String
    public let filename: String?
    public let location: Location?
    public let creationDate: Date?
    public let modificationDate: Date?
    public let changeCounter: Int64
    public let generation: String?
    public let fileSize: Int64?
    public let width: Float?
    public let height: Float?
    public let ocrText: String?
    public let imageClassifications: [String]
    public let additionalIndexableText: String?

    private enum CodingKeys: String, CodingKey {
      case identifier, uti, filename, location
      case creationDate = "creation_date"
      case modificationDate = "modification_date"
      case changeCounter = "change_counter"
      case generation
      case fileSize = "file_size"
      case width, height
      case ocrText = "ocr_text"
      case imageClassifications = "image_classifications"
      case additionalIndexableText = "additional_indexable_text"
    }
  }

  public struct PDF: Equatable, Sendable, Codable {
    public let identifier: String
    public let uti: String
    public let filename: String?
    public let creationDate: Date?
    public let modificationDate: Date?
    public let changeCounter: Int64
    public let generation: String?
    public let fileSize: Int64?
    public let ocrText: String?
    public let additionalIndexableText: String?

    private enum CodingKeys: String, CodingKey {
      case identifier, uti, filename
      case creationDate = "creation_date"
      case modificationDate = "modification_date"
      case changeCounter = "change_counter"
      case generation
      case fileSize = "file_size"
      case ocrText = "ocr_text"
      case additionalIndexableText = "additional_indexable_text"
    }
  }

  public struct Video: Equatable, Sendable, Codable {
    public let identifier: String
    public let uti: String
    public let filename: String?
    public let creationDate: Date?
    public let modificationDate: Date?
    public let changeCounter: Int64
    public let generation: String?
    public let duration: Double?
    public let fileSize: Int64?
    public let width: Float?
    public let height: Float?

    private enum CodingKeys: String, CodingKey {
      case identifier, uti, filename
      case creationDate = "creation_date"
      case modificationDate = "modification_date"
      case changeCounter = "change_counter"
      case generation, duration
      case fileSize = "file_size"
      case width, height
    }
  }

  public struct Audio: Equatable, Sendable, Codable {
    public let identifier: String
    public let uti: String
    public let title: String?
    public let filename: String?
    public let creationDate: Date?
    public let modificationDate: Date?
    public let changeCounter: Int64
    public let generation: String?
    public let duration: Double?
    public let fileSize: Int64?

    private enum CodingKeys: String, CodingKey {
      case identifier, uti, title, filename
      case creationDate = "creation_date"
      case modificationDate = "modification_date"
      case changeCounter = "change_counter"
      case generation, duration
      case fileSize = "file_size"
    }
  }

  public struct File: Equatable, Sendable, Codable {
    public let identifier: String
    public let uti: String
    public let filename: String?
    public let creationDate: Date?
    public let modificationDate: Date?
    public let changeCounter: Int64
    public let generation: String?
    public let fileSize: Int64?

    private enum CodingKeys: String, CodingKey {
      case identifier, uti, filename
      case creationDate = "creation_date"
      case modificationDate = "modification_date"
      case changeCounter = "change_counter"
      case generation
      case fileSize = "file_size"
    }
  }

  public struct Drawing: Equatable, Sendable, Codable {
    public let identifier: String
    public let uti: String
    public let creationDate: Date?
    public let modificationDate: Date?
    public let changeCounter: Int64
    public let generation: String?
    public let width: Float?
    public let height: Float?
    public let fallbackTitle: String?
    public let handwritingSummary: String?
    public let additionalIndexableText: String?
    public let canvasBounds: CanvasBounds?

    private enum CodingKeys: String, CodingKey {
      case identifier, uti
      case creationDate = "creation_date"
      case modificationDate = "modification_date"
      case changeCounter = "change_counter"
      case generation, width, height
      case fallbackTitle = "fallback_title"
      case handwritingSummary = "handwriting_summary"
      case additionalIndexableText = "additional_indexable_text"
      case canvasBounds = "canvas_bounds"
    }
  }

  public struct URLLink: Equatable, Sendable, Codable {
    public let identifier: String
    public let uti: String
    public let creationDate: Date?
    public let modificationDate: Date?
    public let changeCounter: Int64
    public let generation: String?
    public let urlString: String?
    public let title: String?
    public let summary: String?

    private enum CodingKeys: String, CodingKey {
      case identifier, uti
      case creationDate = "creation_date"
      case modificationDate = "modification_date"
      case changeCounter = "change_counter"
      case generation
      case urlString = "url_string"
      case title, summary
    }
  }

  public struct Table: Equatable, Sendable, Codable {
    public let identifier: String
    public let creationDate: Date?
    public let modificationDate: Date?
    public let changeCounter: Int64
    public let generation: String?

    private enum CodingKeys: String, CodingKey {
      case identifier
      case creationDate = "creation_date"
      case modificationDate = "modification_date"
      case changeCounter = "change_counter"
      case generation
    }
  }

  public struct Calendar: Equatable, Sendable, Codable {
    public let identifier: String
    public let uti: String
    public let creationDate: Date?
    public let modificationDate: Date?
    public let changeCounter: Int64
    public let generation: String?

    private enum CodingKeys: String, CodingKey {
      case identifier, uti
      case creationDate = "creation_date"
      case modificationDate = "modification_date"
      case changeCounter = "change_counter"
      case generation
    }
  }

  public struct VCard: Equatable, Sendable, Codable {
    public let identifier: String
    public let uti: String
    public let creationDate: Date?
    public let modificationDate: Date?
    public let changeCounter: Int64
    public let generation: String?
    public let filename: String?

    private enum CodingKeys: String, CodingKey {
      case identifier, uti
      case creationDate = "creation_date"
      case modificationDate = "modification_date"
      case changeCounter = "change_counter"
      case generation, filename
    }
  }

  public struct Gallery: Equatable, Sendable, Codable {
    public let identifier: String
    public let creationDate: Date?
    public let modificationDate: Date?
    public let changeCounter: Int64
    public let generation: String?
    public let items: [NoteAttachment]

    private enum CodingKeys: String, CodingKey {
      case identifier
      case creationDate = "creation_date"
      case modificationDate = "modification_date"
      case changeCounter = "change_counter"
      case generation, items
    }
  }

  public struct Scan: Equatable, Sendable, Codable {
    public let identifier: String
    public let uti: String
    public let creationDate: Date?
    public let modificationDate: Date?
    public let changeCounter: Int64
    public let generation: String?
    public let ocrText: String?
    public let additionalIndexableText: String?

    private enum CodingKeys: String, CodingKey {
      case identifier, uti
      case creationDate = "creation_date"
      case modificationDate = "modification_date"
      case changeCounter = "change_counter"
      case generation
      case ocrText = "ocr_text"
      case additionalIndexableText = "additional_indexable_text"
    }
  }

  public struct Unknown: Equatable, Sendable, Codable {
    public let identifier: String
    public let uti: String
    public let creationDate: Date?
    public let modificationDate: Date?
    public let changeCounter: Int64
    public let generation: String?

    private enum CodingKeys: String, CodingKey {
      case identifier, uti
      case creationDate = "creation_date"
      case modificationDate = "modification_date"
      case changeCounter = "change_counter"
      case generation
    }
  }

  /// An attachment whose backing record was deleted from the database.
  public struct Deleted: Equatable, Sendable, Codable {
    public let identifier: String
    public let uti: String
    public let creationDate: Date?
    public let modificationDate: Date?
    public let changeCounter: Int64
    public let generation: String?

    private enum CodingKeys: String, CodingKey {
      case identifier, uti
      case creationDate = "creation_date"
      case modificationDate = "modification_date"
      case changeCounter = "change_counter"
      case generation
    }
  }
}

// MARK: - Supporting Types

extension NoteAttachment {

  /// Canvas bounds for a drawing attachment.
  public struct CanvasBounds: Equatable, Sendable, Codable {
    public let originX: Double
    public let originY: Double
    public let width: Double
    public let height: Double

    private enum CodingKeys: String, CodingKey {
      case originX = "origin_x"
      case originY = "origin_y"
      case width, height
    }
  }

  /// Geographic location for an attachment.
  public struct Location: Equatable, Sendable, Codable {
    public let latitude: Double
    public let longitude: Double
    public let placemarkData: Data?

    private enum CodingKeys: String, CodingKey {
      case latitude, longitude
      case placemarkData = "placemark_data"
    }
  }

  /// A thumbnail for an attachment.
  public struct Thumbnail: Equatable, Sendable, Codable {
    public let identifier: String
    public let scale: Int
    public let width: Int
    public let height: Int
    /// 0 = light, 1 = dark.
    public let appearanceType: Int
    public let data: Data?

    private enum CodingKeys: String, CodingKey {
      case identifier, scale, width, height
      case appearanceType = "appearance_type"
      case data
    }
  }
}
