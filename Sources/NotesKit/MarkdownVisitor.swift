// This file is part of NotesKit.
// Copyright (c) 2025 6OVER3 Institute.
// Licensed under the GNU Affero General Public License v3.0.
// See LICENSE file for details.

import Foundation

/// Convert note content to Markdown matching Apple's export format.
public final class MarkdownVisitor: NoteVisitor {
  private var output = ""
  private var inlineAttachmentQueue: [String] = []
  private var tableRows: [[String]] = []
  private var tableColumnCount = 0
  private var numberedListCounters: [Int: Int] = [:]
  private var lastItemIndentLevel = 0

  public init() {}

  /// Convert a note to Markdown.
  public static func markdown(from note: Note, password: String? = nil) throws -> String {
    let visitor = MarkdownVisitor()
    try note.parse(visitor: visitor, password: password)
    return visitor.finalize()
  }

  // MARK: - NoteVisitor

  public func willVisitNote() {}
  public func didVisitNote() {}

  public func visitParagraph(_ paragraph: Paragraph) {
    if paragraph.styleType == .monospaced {
      var codeText = ""
      for run in paragraph.runs {
        codeText += replaceInlineAttachments(in: run.text)
      }
      output += "```\n" + codeText + "\n```\n"
      return
    }

    var prefix = ""
    if let styleType = paragraph.styleType {
      switch styleType {
      case .title: prefix = "# "
      case .heading: prefix = "## "
      case .subheading: prefix = "### "
      case .body, .custom, .monospaced: break
      }
    }

    if paragraph.isBlockQuote {
      prefix = "> " + prefix
    }

    let indentSpaces = String(repeating: "    ", count: paragraph.indentLevel)

    var paragraphText = ""
    for run in paragraph.runs {
      let processedText = replaceInlineAttachments(in: run.text)
      if !run.styles.isEmpty {
        paragraphText += applyStyles(text: processedText, styles: run.styles)
      } else {
        paragraphText += processedText
      }
    }

    // Merge adjacent bold/italic spans
    paragraphText = paragraphText.replacingOccurrences(of: "** **", with: " ")
    paragraphText = paragraphText.replacingOccurrences(of: "* *", with: " ")

    // Emit leading newlines as blank lines
    let leadingNewlines = paragraphText.prefix(while: { $0 == "\n" }).count
    for _ in 0..<leadingNewlines {
      output += "  \n"
    }

    let trimmed = paragraphText.trimmingCharacters(in: .newlines)

    if trimmed.isEmpty {
      output += "  \n"
      return
    }

    let lines = trimmed.components(separatedBy: "\n")
    for (index, line) in lines.enumerated() {
      let linePrefix: String
      if index == 0 {
        linePrefix = prefix
      } else if paragraph.isBlockQuote {
        linePrefix = "> "
      } else {
        linePrefix = ""
      }
      output += indentSpaces + linePrefix + line + "  \n"
    }

    // Trailing newlines beyond the paragraph terminator
    let trailingNewlines = paragraphText.reversed().prefix(while: { $0 == "\n" }).count
    for _ in 0..<max(0, trailingNewlines - 1) {
      output += "  \n"
    }
  }

  public func willVisitList(_ list: List) {
    numberedListCounters.removeAll()
    lastItemIndentLevel = 0
  }

  public func visitListItem(_ item: ListItem) {
    let indentSpaces = String(repeating: "    ", count: item.indentLevel)

    var bullet: String
    switch item.listType {
    case .bullet:
      bullet = "* "
    case .dash:
      bullet = "- "
    case .numbered(let startingAt):
      let currentIndent = item.indentLevel
      if currentIndent < lastItemIndentLevel {
        numberedListCounters = numberedListCounters.filter { $0.key <= currentIndent }
      }
      let currentNumber = numberedListCounters[currentIndent, default: startingAt - 1] + 1
      numberedListCounters[currentIndent] = currentNumber
      bullet = "\(currentNumber). "
    case .checklist:
      bullet = item.isChecked == true ? "- [x] " : "- [ ] "
    }

    lastItemIndentLevel = item.indentLevel

    var itemText = ""
    for run in item.content {
      let processedText = replaceInlineAttachments(in: run.text)
      if !run.styles.isEmpty {
        itemText += applyStyles(text: processedText, styles: run.styles)
      } else {
        itemText += processedText
      }
    }

    let trimmedItem = itemText.trimmingCharacters(in: .whitespacesAndNewlines)
    output += indentSpaces + bullet + trimmedItem + "  \n"
  }

  public func didVisitList(_ list: List) {
    numberedListCounters.removeAll()
  }

  public func willVisitTable(_ table: Table) {
    output += "\n"
    tableRows.removeAll()
    tableColumnCount = table.columnCount
  }

  public func visitTableCell(_ cell: TableCell, row: Int, column: Int) {
    var cellText = ""
    for run in cell.content {
      cellText += replaceInlineAttachments(in: run.text)
    }

    while tableRows.count <= row {
      tableRows.append([])
    }

    tableRows[row].append(cellText.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  public func didVisitTable(_ table: Table) {
    guard !tableRows.isEmpty else { return }

    var columnWidths = [Int](repeating: 5, count: tableColumnCount)
    for row in tableRows {
      for (col, cell) in row.enumerated() where col < tableColumnCount {
        columnWidths[col] = max(columnWidths[col], cell.count)
      }
    }

    if let headerRow = tableRows.first {
      let paddedCells = headerRow.enumerated().map { (col, cell) in
        cell.padding(toLength: columnWidths[col], withPad: " ", startingAt: 0)
      }
      output += "| " + paddedCells.joined(separator: " | ") + " |\n"

      let separators = columnWidths.map { String(repeating: "-", count: $0) }
      output += "| " + separators.joined(separator: " | ") + " |\n"
    }

    for row in tableRows.dropFirst() {
      let paddedCells = row.enumerated().map { (col, cell) in
        cell.padding(toLength: columnWidths[col], withPad: " ", startingAt: 0)
      }
      output += "| " + paddedCells.joined(separator: " | ") + " |\n"
    }

    tableRows.removeAll()
  }

  public func visitAttachment(_ attachment: NoteAttachment) {
    switch attachment {
    case .image(let img):
      let altText: String
      if let ocrText = img.ocrText, !ocrText.isEmpty {
        let firstLine = ocrText.components(separatedBy: .newlines).first ?? ""
        altText = firstLine.trimmingCharacters(in: CharacterSet.punctuationCharacters)
      } else {
        altText = img.filename ?? ""
      }
      let path = attachmentPath(identifier: img.identifier, filename: img.filename)
      output += "![\(altText)](\(path))  \n"

    case .pdf(let pdf):
      let displayName = pdf.filename ?? "document.pdf"
      let path = attachmentPath(
        identifier: pdf.identifier, filename: pdf.filename, fallbackExtension: "pdf")
      output += "[\(displayName)](\(path))  \n"

    case .video(let video):
      let displayName = video.filename ?? "video.mov"
      let path = attachmentPath(
        identifier: video.identifier, filename: video.filename, fallbackExtension: "mov")
      output += "[\(displayName)](\(path))  \n"

    case .audio(let audio):
      let displayName = audio.title ?? audio.filename ?? "audio.m4a"
      let path = attachmentPath(
        identifier: audio.identifier, filename: audio.filename, fallbackExtension: "m4a")
      output += "[\(displayName)](\(path))  \n"

    case .file(let file):
      let displayName = file.filename ?? "attachment"
      let path = attachmentPath(identifier: file.identifier, filename: file.filename)
      output += "[\(displayName)](\(path))  \n"

    case .drawing(let drawing):
      let altText = (drawing.handwritingSummary ?? drawing.fallbackTitle ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      let path = attachmentPath(
        identifier: drawing.identifier, filename: nil, fallbackExtension: "png")
      output += "![\(altText)](\(path))  \n"

    case .scan(let scan):
      let altText = scan.ocrText?.components(separatedBy: .newlines).first ?? "scan"
      let path = attachmentPath(
        identifier: scan.identifier, filename: nil, fallbackExtension: "jpg")
      output += "![\(altText)](\(path))  \n"

    case .url(let url):
      if let urlString = url.urlString {
        let title = url.title?.isEmpty == false ? url.title! : urlString
        output += "[\(title)](\(urlString))  \n"
      }

    case .vcard(let vcard):
      let displayName = vcard.filename ?? "contact.vcf"
      let path = attachmentPath(
        identifier: vcard.identifier, filename: vcard.filename, fallbackExtension: "vcf")
      output += "[\(displayName)](\(path))  \n"

    case .table, .gallery, .calendar, .unknown, .deleted:
      break
    }
  }

  public func willVisitGallery(_ gallery: NoteAttachment.Gallery) {}

  public func visitGalleryItem(_ item: NoteAttachment) {
    visitAttachment(item)
  }

  public func didVisitGallery(_ gallery: NoteAttachment.Gallery) {}

  public func visitInlineAttachment(_ inlineAttachment: InlineAttachment) {
    let text = inlineAttachment.text ?? "[inline:\(inlineAttachment.identifier)]"
    inlineAttachmentQueue.append(text)
  }

  // MARK: - Private

  /// Collapse excessive blank lines and return final output.
  private func finalize() -> String {
    var result: [String] = []
    var consecutiveBlanks = 0
    for line in output.components(separatedBy: "\n") {
      if line.trimmingCharacters(in: .whitespaces).isEmpty {
        consecutiveBlanks += 1
        if consecutiveBlanks <= 2 {
          result.append(line)
        }
      } else {
        consecutiveBlanks = 0
        result.append(line)
      }
    }
    return result.joined(separator: "\n")
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

  private func applyStyles(text: String, styles: [TextStyle]) -> String {
    guard !text.isEmpty else { return text }

    let leading = String(text.prefix(while: { $0 == " " || $0 == "\t" }))
    let trailing = String(text.reversed().prefix(while: { $0 == " " || $0.isNewline }).reversed())
    let contentStart = text.index(text.startIndex, offsetBy: leading.count)
    let contentEnd = text.index(text.endIndex, offsetBy: -trailing.count)

    // Whitespace-only text: apply underline/highlight to the whole thing
    if contentStart >= contentEnd {
      var result = text
      var isUnderline = false
      var hasBackgroundColor = false
      for style in styles {
        switch style {
        case .underline: isUnderline = true
        case .backgroundColor: hasBackgroundColor = true
        default: break
        }
      }
      if hasBackgroundColor { result = "==\(result)==" }
      if isUnderline { result = "++\(result)++" }
      return result
    }

    var result = String(text[contentStart..<contentEnd])

    var isBold = false
    var isItalic = false
    var isUnderline = false
    var isStrikethrough = false
    var linkURL: String?
    var hasBackgroundColor = false

    for style in styles {
      switch style {
      case .bold: isBold = true
      case .italic: isItalic = true
      case .underline: isUnderline = true
      case .strikethrough: isStrikethrough = true
      case .link(let url): linkURL = url
      case .backgroundColor: hasBackgroundColor = true
      default: break
      }
    }

    if hasBackgroundColor { result = "==\(result)==" }
    if isStrikethrough { result = "~~\(result)~~" }
    if isUnderline { result = "++\(result)++" }

    if isBold && isItalic {
      result = "***\(result)***"
    } else if isBold {
      result = "**\(result)**"
    } else if isItalic {
      result = "*\(result)*"
    }

    if let url = linkURL {
      result = "[\(result)](\(url))"
    }

    return leading + result + trailing
  }

  private func attachmentPath(identifier: String, filename: String?, fallbackExtension: String = "")
    -> String
  {
    let ext: String
    if let filename = filename, let dotIndex = filename.lastIndex(of: ".") {
      ext = String(filename[filename.index(after: dotIndex)...])
    } else {
      ext = fallbackExtension
    }
    if ext.isEmpty {
      return "Attachments/\(identifier)"
    }
    return "Attachments/\(identifier).\(ext)"
  }
}
