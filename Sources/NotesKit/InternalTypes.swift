// This file is part of NotesKit.
// Copyright (c) 2025 6OVER3 Institute.
// Licensed under the GNU Affero General Public License v3.0.
// See LICENSE file for details.

import Foundation

internal struct NoteRecord {
  let identifier: String
  let title: String
  let compressedData: Data
  let modificationDate: Date?
  let creationDate: Date?
  let isPinned: Bool
  let isPasswordProtected: Bool
  let folderIdentifier: String?
  let accountIdentifier: String?
}

internal struct CryptoParameters {
  let salt: Data
  let iterations: Int
  let wrappedKey: Data
  let iv: Data
  let tag: Data
}

internal struct AttachmentRecord {
  let identifier: String
  let title: String?
  let uti: String?
  let mediaForeignKey: Int64?
  let mergeableData: Data?
  let urlString: String?
  let altText: String?
  let tokenIdentifier: String?
  let userTitle: String?
  let duration: Double?
  let fileSize: Int64?
  let ocrSummary: String?
  let handwritingSummary: String?
  let imageClassifications: [String]
  let additionalIndexableText: String?
  let fallbackTitle: String?
  let fallbackSubtitleIOS: String?
  let fallbackSubtitleMac: String?
  let metadataJSON: String?
  let creationDate: Date?
  let modificationDate: Date?
}

internal struct MediaRecord {
  let identifier: String
  let filename: String?
  let width: Int?
  let height: Int?
}

internal enum AttachmentTypeClassification {
  case image
  case pdf
  case video
  case audio
  case file
  case drawing
  case url
  case table
  case calendar
  case vcard
  case gallery
  case scan
  case unknown
}
