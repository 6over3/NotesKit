// This file is part of NotesKit.
// Copyright (c) 2025 6OVER3 Institute.
// Licensed under the GNU Affero General Public License v3.0.
// See LICENSE file for details.

import Foundation

/// Produce human-readable debug output for note content.
internal final class DebugVisitor: NoteVisitor {
  private var output = ""
  private var indentLevel = 0
  private let indentString = "  "
  private var numberedListCounters: [Int: Int] = [:]
  private var lastItemIndentLevel = 0
  private var lastItemType: ListType?
  private var note: Note?
  private var inlineAttachmentQueue: [String] = []

  init() {}

  /// Generate debug output for a note.
  static func debugString(from note: Note) throws -> String {
    let visitor = DebugVisitor()
    visitor.note = note
    try note.parse(visitor: visitor)
    return visitor.output
  }

  /// Print debug output for a note.
  static func printDebug(from note: Note) throws {
    print(try debugString(from: note))
  }

  // MARK: - NoteVisitor

  func willVisitNote() {
    appendLine("═══════════════════════════════════════")
    appendLine("NOTE START")
    appendLine("═══════════════════════════════════════")
    indentLevel += 1
  }

  func didVisitNote() {
    indentLevel -= 1
    appendLine("═══════════════════════════════════════")
    appendLine("NOTE END")
    appendLine("═══════════════════════════════════════")
  }

  func visitParagraph(_ paragraph: Paragraph) {
    appendLine("┌─ PARAGRAPH")
    indentLevel += 1

    if let styleType = paragraph.styleType {
      appendLine("Style Type: \(formatStyleType(styleType))")
    }
    if let alignment = paragraph.alignment {
      appendLine("Alignment: \(formatAlignment(alignment))")
    }
    if paragraph.indentLevel > 0 {
      appendLine("Indent Level: \(paragraph.indentLevel)")
    }
    if paragraph.isBlockQuote {
      appendLine("Block Quote: true")
    }

    appendLine("Text Runs: \(paragraph.runs.count)")
    for (index, run) in paragraph.runs.enumerated() {
      appendLine("├─ Run #\(index + 1)")
      indentLevel += 1

      let displayText = replaceInlineAttachments(in: run.text)
      let truncatedText =
        displayText.count > 60
        ? String(displayText.prefix(60)) + "..."
        : displayText

      appendLine("Text: \"\(normalizeAndEscape(truncatedText))\"")
      appendLine("Length: \(run.text.count) chars")

      if !run.styles.isEmpty {
        appendLine("Styles: [\(formatStyles(run.styles))]")
      }
      if let font = run.font {
        appendLine(
          "Font: \(font.name) @ \(font.size)pt"
            + (font.weight != nil ? " (weight: \(font.weight!))" : ""))
      }

      indentLevel -= 1
    }

    indentLevel -= 1
    appendLine("└─ END PARAGRAPH")
    appendLine("")
  }

  func willVisitList(_ list: List) {
    appendLine("┌─ LIST")
    indentLevel += 1
    appendLine("Items: \(list.items.count)")
    appendLine("")
    numberedListCounters.removeAll()
    lastItemIndentLevel = 0
    lastItemType = nil
  }

  func visitListItem(_ item: ListItem) {
    let bullet: String
    let displayNumber: Int?

    switch item.listType {
    case .checklist:
      bullet = item.isChecked == true ? "[✓]" : "[ ]"
      displayNumber = nil
    case .bullet:
      bullet = "•"
      displayNumber = nil
    case .dash:
      bullet = "-"
      displayNumber = nil
    case .numbered(let start):
      let currentIndent = item.indentLevel
      if currentIndent < lastItemIndentLevel {
        numberedListCounters = numberedListCounters.filter { $0.key <= currentIndent }
      }
      if currentIndent == lastItemIndentLevel,
        let lastType = lastItemType,
        !isNumberedType(lastType)
      {
        numberedListCounters[currentIndent] = nil
      }
      let currentNumber = numberedListCounters[currentIndent, default: start - 1] + 1
      numberedListCounters[currentIndent] = currentNumber
      bullet = "\(currentNumber)."
      displayNumber = currentNumber
    }

    lastItemIndentLevel = item.indentLevel
    lastItemType = item.listType

    indentLevel += item.indentLevel
    appendLine("\(bullet) LIST ITEM")
    indentLevel += 1

    appendLine("Type: \(formatListType(item.listType, displayNumber: displayNumber))")
    if item.indentLevel > 0 {
      appendLine("Indent Level: \(item.indentLevel)")
    }
    if let isChecked = item.isChecked {
      appendLine("Checked: \(isChecked)")
    }

    appendLine("Content Runs: \(item.content.count)")
    for (index, run) in item.content.enumerated() {
      indentLevel += 1
      let displayText = replaceInlineAttachments(in: run.text)
      let truncatedText =
        displayText.count > 50
        ? String(displayText.prefix(50)) + "..."
        : displayText
      appendLine("[\(index + 1)] \"\(normalizeAndEscape(truncatedText))\"")
      if !run.styles.isEmpty {
        appendLine("    Styles: \(formatStyles(run.styles))")
      }
      indentLevel -= 1
    }

    indentLevel -= 1
    indentLevel -= item.indentLevel
    appendLine("")
  }

  func didVisitList(_ list: List) {
    indentLevel -= 1
    appendLine("└─ END LIST")
    appendLine("")
    numberedListCounters.removeAll()
    lastItemIndentLevel = 0
    lastItemType = nil
  }

  func willVisitTable(_ table: Table) {
    appendLine("┌─ TABLE")
    indentLevel += 1
    appendLine("Dimensions: \(table.rowCount) rows × \(table.columnCount) columns")
    appendLine("Total Cells: \(table.rowCount * table.columnCount)")
    appendLine("")
  }

  func visitTableCell(_ cell: TableCell, row: Int, column: Int) {
    appendLine("├─ CELL [\(row), \(column)]")
    indentLevel += 1

    if cell.content.isEmpty {
      appendLine("(empty)")
    } else {
      for (index, run) in cell.content.enumerated() {
        let displayText = replaceInlineAttachments(in: run.text)
        let truncatedText =
          displayText.count > 40
          ? String(displayText.prefix(40)) + "..."
          : displayText
        let prefix = index == 0 ? "" : "+ "
        appendLine("\(prefix)\"\(normalizeAndEscape(truncatedText))\"")
        if !run.styles.isEmpty {
          appendLine("  Styles: \(formatStyles(run.styles))")
        }
      }
    }

    indentLevel -= 1
  }

  func didVisitTable(_ table: Table) {
    indentLevel -= 1
    appendLine("└─ END TABLE")
    appendLine("")
  }

  func visitAttachment(_ attachment: NoteAttachment) {
    appendLine("┌─ ATTACHMENT")
    indentLevel += 1

    let identifier = attachment.identifier
    appendLine("Type: \(formatAttachmentType(attachment))")
    appendLine("Identifier: \(identifier)")

    switch attachment {
    case .image(let img):
      appendLine("Type UTI: \(img.uti)")
      if let filename = img.filename { appendLine("Filename: \(filename)") }
      if let width = img.width, let height = img.height {
        appendLine("Dimensions: \(width) × \(height)")
      }
      if let fileSize = img.fileSize { appendLine("File Size: \(formatFileSize(fileSize))") }
      if let created = img.creationDate { appendLine("Created: \(formatDate(created))") }
      if let modified = img.modificationDate { appendLine("Modified: \(formatDate(modified))") }
      if let location = img.location {
        appendLine("Location:")
        indentLevel += 1
        appendLine("Latitude: \(location.latitude)")
        appendLine("Longitude: \(location.longitude)")
        if let placemarkData = location.placemarkData {
          appendLine("Placemark Data: \(placemarkData.count) bytes")
        }
        indentLevel -= 1
      }
      if let ocrText = img.ocrText { appendLine("OCR Text: \(truncate(ocrText, max: 100))") }
      if !img.imageClassifications.isEmpty {
        appendLine("Classifications: \(img.imageClassifications.joined(separator: ", "))")
      }
      if let text = img.additionalIndexableText {
        appendLine("Additional Text: \(truncate(text, max: 100))")
      }

    case .pdf(let pdf):
      appendLine("Type UTI: \(pdf.uti)")
      if let filename = pdf.filename { appendLine("Filename: \(filename)") }
      if let fileSize = pdf.fileSize { appendLine("File Size: \(formatFileSize(fileSize))") }
      if let ocrText = pdf.ocrText { appendLine("OCR Text: \(truncate(ocrText, max: 100))") }
      if let text = pdf.additionalIndexableText {
        appendLine("Additional Text: \(truncate(text, max: 100))")
      }

    case .video(let video):
      appendLine("Type UTI: \(video.uti)")
      if let filename = video.filename { appendLine("Filename: \(filename)") }
      if let width = video.width, let height = video.height {
        appendLine("Dimensions: \(width) × \(height)")
      }
      if let duration = video.duration { appendLine("Duration: \(formatDuration(duration))") }
      if let fileSize = video.fileSize { appendLine("File Size: \(formatFileSize(fileSize))") }

    case .audio(let audio):
      appendLine("Type UTI: \(audio.uti)")
      if let title = audio.title { appendLine("Title: \(title)") }
      if let filename = audio.filename { appendLine("Filename: \(filename)") }
      if let duration = audio.duration { appendLine("Duration: \(formatDuration(duration))") }
      if let fileSize = audio.fileSize { appendLine("File Size: \(formatFileSize(fileSize))") }
      if let transcription = try? note?.transcription(for: audio) {
        appendLine("Transcription:")
        indentLevel += 1
        if let summary = transcription.topLineSummary ?? transcription.summary {
          appendLine("Summary: \(truncate(summary, max: 100))")
        }
        appendLine("Segments: \(transcription.segments.count)")
        appendLine("Duration: \(formatDuration(transcription.totalDuration))")
        indentLevel -= 1
      }

    case .file(let file):
      appendLine("Type UTI: \(file.uti)")
      if let filename = file.filename { appendLine("Filename: \(filename)") }
      if let fileSize = file.fileSize { appendLine("File Size: \(formatFileSize(fileSize))") }

    case .drawing(let drawing):
      guard let bounds = drawing.canvasBounds else {
        appendLine("Drawing data missing canvas bounds")
        break
      }
      appendLine("Type UTI: \(drawing.uti)")
      if let width = drawing.width, let height = drawing.height {
        appendLine("Dimensions: \(width) × \(height)")
      }
      if let text = drawing.fallbackTitle { appendLine("Recognized Text: \"\(text)\"") }
      if let text = drawing.handwritingSummary {
        appendLine("Handwriting Summary: \(truncate(text, max: 100))")
      }
      if let text = drawing.additionalIndexableText {
        appendLine("Additional Text: \(truncate(text, max: 100))")
      }
      appendLine("Canvas Bounds:")
      indentLevel += 1
      appendLine("Origin: (\(bounds.originX), \(bounds.originY))")
      appendLine("Size: \(bounds.width) × \(bounds.height)")
      indentLevel -= 1

    case .url(let url):
      appendLine("Type UTI: \(url.uti)")
      if let urlString = url.urlString {
        let display = urlString.count > 60 ? String(urlString.prefix(60)) + "..." : urlString
        appendLine("URL: \(display)")
      }
      if let title = url.title { appendLine("Title: \(title)") }
      if let summary = url.summary {
        let display = summary.count > 60 ? String(summary.prefix(60)) + "..." : summary
        appendLine("Summary: \(display)")
      }

    case .table(let table):
      appendLine("Table ID: \(table.identifier)")

    case .calendar(let cal):
      appendLine("Type UTI: \(cal.uti)")

    case .vcard(let vcard):
      appendLine("Type UTI: \(vcard.uti)")
      if let filename = vcard.filename { appendLine("Filename: \(filename)") }

    case .gallery(let gallery):
      appendLine("Gallery ID: \(gallery.identifier)")
      appendLine("Items: \(gallery.items.count)")

    case .scan(let scan):
      appendLine("Type UTI: \(scan.uti)")
      if let ocrText = scan.ocrText { appendLine("OCR Text: \(truncate(ocrText, max: 100))") }
      if let text = scan.additionalIndexableText {
        appendLine("Additional Text: \(truncate(text, max: 100))")
      }

    case .unknown(let unknown):
      appendLine("Type UTI: \(unknown.uti)")

    case .deleted(let deleted):
      appendLine("Type UTI: \(deleted.uti)")
      appendLine("Status: DELETED (record removed from database)")
    }

    if let note = self.note {
      if let thumbnails = try? note.thumbnails(for: attachment), !thumbnails.isEmpty {
        appendLine("Thumbnails: \(thumbnails.count)")
        indentLevel += 1
        for thumbnail in thumbnails {
          let mode = thumbnail.appearanceType == 0 ? "light" : "dark"
          appendLine("\(thumbnail.width)×\(thumbnail.height) @\(thumbnail.scale)x (\(mode))")
        }
        indentLevel -= 1
      }

      if case .drawing(let drawing) = attachment {
        if let fallbackPDF = try? note.fallbackPDF(for: drawing), fallbackPDF.count > 0 {
          appendLine("Fallback PDF: \(formatFileSize(Int64(fallbackPDF.count)))")
        }
        if let fallbackImage = try? note.fallbackImage(for: drawing), fallbackImage.count > 0 {
          appendLine("Fallback Image: \(formatFileSize(Int64(fallbackImage.count)))")
          let tempFileURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "\(identifier)-fallback.png")
          try? fallbackImage.write(to: tempFileURL)
          appendLine("Fallback Image Path: \(tempFileURL.path)")
        }
      }

      let needsFilePath: Bool
      switch attachment {
      case .image, .video, .audio, .pdf, .scan, .vcard: needsFilePath = true
      default: needsFilePath = false
      }

      if needsFilePath {
        if let filePath = try? note.url(for: attachment) {
          appendLine("File Path: \(filePath.path)")
          appendLine("File Exists: \(FileManager.default.fileExists(atPath: filePath.path))")
        } else {
          appendLine("File Path: (not found)")
          if let data = try? note.data(for: attachment) {
            appendLine("Attachment Data Size: \(formatFileSize(Int64(data.count)))")
          } else {
            appendLine("Attachment Data: (not found)")
          }
        }
      }
    }

    indentLevel -= 1
    appendLine("└─ END ATTACHMENT")
    appendLine("")
  }

  func willVisitGallery(_ gallery: NoteAttachment.Gallery) {
    appendLine("┌─ GALLERY")
    indentLevel += 1
    appendLine("Identifier: \(gallery.identifier)")
    appendLine("Items: \(gallery.items.count)")
    appendLine("")
  }

  func visitGalleryItem(_ item: NoteAttachment) {
    appendLine("├─ GALLERY ITEM")
    indentLevel += 1

    let identifier = item.identifier
    appendLine("Type: \(formatAttachmentType(item))")
    appendLine("Identifier: \(identifier)")

    switch item {
    case .image(let img):
      if let filename = img.filename { appendLine("Filename: \(filename)") }
      if let width = img.width, let height = img.height {
        appendLine("Dimensions: \(width) × \(height)")
      }
      if let fileSize = img.fileSize { appendLine("File Size: \(formatFileSize(fileSize))") }
      if let ocrText = img.ocrText { appendLine("OCR Text: \(truncate(ocrText, max: 80))") }
      if !img.imageClassifications.isEmpty {
        appendLine("Classifications: \(img.imageClassifications.joined(separator: ", "))")
      }
    case .video(let video):
      if let filename = video.filename { appendLine("Filename: \(filename)") }
      if let width = video.width, let height = video.height {
        appendLine("Dimensions: \(width) × \(height)")
      }
      if let duration = video.duration { appendLine("Duration: \(formatDuration(duration))") }
      if let fileSize = video.fileSize { appendLine("File Size: \(formatFileSize(fileSize))") }
    default:
      break
    }

    if let note = self.note {
      if let filePath = try? note.url(for: item) {
        let pathString = filePath.path
        let displayPath =
          pathString.count > 80
          ? "..." + String(pathString.suffix(77))
          : pathString
        appendLine("File Path: \(displayPath)")
        appendLine("File Exists: \(FileManager.default.fileExists(atPath: pathString))")
      }
    }

    indentLevel -= 1
    appendLine("")
  }

  func didVisitGallery(_ gallery: NoteAttachment.Gallery) {
    indentLevel -= 1
    appendLine("└─ END GALLERY")
    appendLine("")
  }

  func visitInlineAttachment(_ inlineAttachment: InlineAttachment) {
    let text = inlineAttachment.text ?? "[inline:\(inlineAttachment.identifier)]"
    inlineAttachmentQueue.append(text)
  }

  // MARK: - Private

  private func appendLine(_ text: String) {
    output += String(repeating: indentString, count: indentLevel) + text + "\n"
  }

  private func replaceInlineAttachments(in text: String) -> String {
    var result = text
    let replacementChar = "\u{FFFC}"
    while result.contains(replacementChar) && !inlineAttachmentQueue.isEmpty {
      let next = inlineAttachmentQueue.removeFirst()
      if let range = result.range(of: replacementChar) {
        result.replaceSubrange(range, with: next)
      }
    }
    return result
  }

  private func normalizeAndEscape(_ text: String) -> String {
    text
      .replacingOccurrences(of: "\u{2028}", with: "\n")
      .replacingOccurrences(of: "\u{2029}", with: "\n")
      .replacingOccurrences(of: "\u{00A0}", with: " ")
      .replacingOccurrences(of: "\u{200B}", with: "")
      .replacingOccurrences(of: "\u{200C}", with: "")
      .replacingOccurrences(of: "\u{200D}", with: "")
      .replacingOccurrences(of: "\u{FEFF}", with: "")
      .replacingOccurrences(of: "\u{2009}", with: " ")
      .replacingOccurrences(of: "\n", with: "\\n")
      .replacingOccurrences(of: "\r", with: "\\r")
      .replacingOccurrences(of: "\t", with: "\\t")
  }

  private func isNumberedType(_ type: ListType) -> Bool {
    if case .numbered = type { return true }
    return false
  }

  private func truncate(_ text: String, max: Int) -> String {
    text.count > max ? String(text.prefix(max)) + "..." : text
  }

  private func formatStyleType(_ styleType: ParagraphStyleType) -> String {
    switch styleType {
    case .title: "Title"
    case .heading: "Heading"
    case .subheading: "Subheading"
    case .body: "Body"
    case .monospaced: "Monospaced"
    case .custom(let value): "Custom(\(value))"
    }
  }

  private func formatAlignment(_ alignment: ParagraphAlignment) -> String {
    switch alignment {
    case .left: "Left"
    case .center: "Center"
    case .right: "Right"
    case .justified: "Justified"
    case .natural: "Natural"
    }
  }

  private func formatListType(_ type: ListType, displayNumber: Int? = nil) -> String {
    switch type {
    case .bullet: "Bullet"
    case .dash: "Dash"
    case .numbered(let startingAt):
      if let num = displayNumber {
        "Numbered (item \(num), starts at \(startingAt))"
      } else {
        "Numbered (starting at \(startingAt))"
      }
    case .checklist: "Checklist"
    }
  }

  private func formatAttachmentType(_ attachment: NoteAttachment) -> String {
    switch attachment {
    case .image: "Image"
    case .pdf: "PDF"
    case .video: "Video"
    case .audio: "Audio"
    case .file: "File"
    case .drawing: "Drawing"
    case .url: "URL"
    case .table: "Table"
    case .calendar: "Calendar"
    case .vcard: "vCard"
    case .gallery: "Gallery"
    case .scan: "Scan"
    case .unknown: "Unknown"
    case .deleted: "Deleted"
    }
  }

  private func formatStyles(_ styles: [TextStyle]) -> String {
    styles.map { style in
      switch style {
      case .bold: return "Bold"
      case .italic: return "Italic"
      case .underline: return "Underline"
      case .strikethrough: return "Strikethrough"
      case .superscript: return "Superscript"
      case .subscript: return "Subscript"
      case .link(let url):
        let display = url.count > 30 ? String(url.prefix(30)) + "..." : url
        return "Link(\(display))"
      case .color(let r, let g, let b, let a):
        return String(format: "Color(r:%.2f g:%.2f b:%.2f a:%.2f)", r, g, b, a)
      case .backgroundColor(let r, let g, let b, let a):
        return String(format: "BackgroundColor(r:%.2f g:%.2f b:%.2f a:%.2f)", r, g, b, a)
      }
    }.joined(separator: ", ")
  }

  private func formatDuration(_ duration: Double) -> String {
    let minutes = Int(duration) / 60
    let seconds = Int(duration) % 60
    if minutes > 0 {
      return String(format: "%d:%02d", minutes, seconds)
    }
    return String(format: "%.1f seconds", duration)
  }

  private func formatFileSize(_ bytes: Int64) -> String {
    let kb = Double(bytes) / 1024.0
    let mb = kb / 1024.0
    let gb = mb / 1024.0
    if gb >= 1.0 { return String(format: "%.2f GB", gb) }
    if mb >= 1.0 { return String(format: "%.2f MB", mb) }
    if kb >= 1.0 { return String(format: "%.2f KB", kb) }
    return "\(bytes) bytes"
  }

  private func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
  }
}
