// This file is part of NotesKit.
// Copyright (c) 2025 6OVER3 Institute.
// Licensed under the GNU Affero General Public License v3.0.
// See LICENSE file for details.

import Foundation
import SwiftProtobuf

// MARK: - Note Parser

package struct NoteParser {
  private let database: NotesDatabase

  init(database: NotesDatabase) {
    self.database = database
  }

  func parse<V: NoteVisitor>(_ record: NoteRecord, visitor: V) throws {
    try parse(data: record.compressedData, visitor: visitor)
  }

  func parse<V: NoteVisitor>(data: Data, visitor: V) throws {
    visitor.willVisitNote()

    let decompressedData = try decompressData(data)
    let proto = try parseProtobuf(decompressedData)
    try parseAndEmit(proto.document.note, visitor: visitor)

    visitor.didVisitNote()
  }

  private func decompressData(_ data: Data) throws -> Data {
    guard let decompressed = data.gunzipped() else {
      throw NotesError.decompressionFailed
    }
    return decompressed
  }

  private func parseProtobuf(_ data: Data) throws -> Notes_NoteStoreProto {
    do {
      return try Notes_NoteStoreProto(serializedBytes: data)
    } catch {
      throw NotesError.protobufDecodingFailed(error)
    }
  }

  private func shouldSplitParagraph(
    _ runs: [TextRun],
    newRun: TextRun,
    newStyle: Notes_ParagraphStyle?
  ) -> Bool {
    guard !runs.isEmpty else { return false }

    let lastRun = runs.last!
    let text = lastRun.text

    if text.hasSuffix("\n\n") || text.hasSuffix("\n\n\n") {
      return true
    }

    if text.hasSuffix("\n") && lastRun.styles != newRun.styles {
      return true
    }

    return false
  }

  private func parseAndEmit<V: NoteVisitor>(_ note: Notes_Note, visitor: V) throws {
    guard note.hasNoteText else { return }

    let noteText = note.noteText
    let attributeRuns = note.attributeRun

    var textIndex = noteText.startIndex
    var currentParagraphRuns: [TextRun] = []
    var currentParagraphStyle: Notes_ParagraphStyle?
    var currentListItems: [ListItem] = []
    var isInList = false

    for run in attributeRuns {
      let runLength = Int(run.length)
      guard textIndex < noteText.endIndex else { break }

      let endIndex =
        noteText.index(
          textIndex,
          offsetBy: runLength,
          limitedBy: noteText.endIndex
        ) ?? noteText.endIndex
      let runText = String(noteText[textIndex..<endIndex])
      textIndex = endIndex

      if run.hasAttachmentInfo {
        let attachmentInfo = run.attachmentInfo

        // Handle inline attachments differently - they should be part of the text flow
        if attachmentInfo.hasTypeUti
          && attachmentInfo.typeUti.hasPrefix("com.apple.notes.inlinetextattachment")
        {
          // For inline attachments, add the object replacement character to the current paragraph
          let textRun = buildTextRun(text: runText, run: run)

          if isInList && !currentListItems.isEmpty {
            var lastItem = currentListItems.removeLast()
            lastItem = ListItem(
              content: lastItem.content + [textRun],
              indentLevel: lastItem.indentLevel,
              isChecked: lastItem.isChecked,
              listType: lastItem.listType
            )
            currentListItems.append(lastItem)
          } else {
            currentParagraphRuns.append(textRun)
          }

          // Also emit the inline attachment for visitors to handle
          try emitInlineAttachment(
            identifier: attachmentInfo.attachmentIdentifier,
            uti: attachmentInfo.typeUti,
            visitor: visitor
          )
        } else {
          // For regular attachments, flush current content first
          flushParagraph(
            &currentParagraphRuns, style: currentParagraphStyle, visitor: visitor)
          flushList(&currentListItems, isInList: &isInList, visitor: visitor)

          let attachment = try buildAttachment(from: attachmentInfo)

          if case .table = attachment {
            try emitTable(identifier: attachment.identifier, visitor: visitor)
          } else if case .gallery(let gallery) = attachment {
            try emitGallery(gallery: gallery, visitor: visitor)
          } else {
            visitor.visitAttachment(attachment)
          }

          currentParagraphStyle = nil
        }
        continue
      }

      let textRun = buildTextRun(text: runText, run: run)

      if run.hasParagraphStyle {
        let paraStyle = run.paragraphStyle

        if isListItem(paraStyle) {
          if !isInList {
            flushParagraph(
              &currentParagraphRuns, style: currentParagraphStyle, visitor: visitor)
            isInList = true
          }

          let shouldStartNewItem =
            currentListItems.isEmpty
            || (currentListItems.last?.content.last?.text.hasSuffix("\n") ?? false)

          if shouldStartNewItem {
            let listItem = createListItem(runs: [textRun], style: paraStyle)
            currentListItems.append(listItem)
          } else {
            var lastItem = currentListItems.removeLast()
            lastItem = ListItem(
              content: lastItem.content + [textRun],
              indentLevel: lastItem.indentLevel,
              isChecked: lastItem.isChecked,
              listType: lastItem.listType
            )
            currentListItems.append(lastItem)
          }

          currentParagraphStyle = nil
        } else {
          flushList(&currentListItems, isInList: &isInList, visitor: visitor)

          if let prevStyle = currentParagraphStyle {
            if !isSameParagraph(prevStyle, paraStyle) {
              flushParagraph(
                &currentParagraphRuns, style: prevStyle, visitor: visitor)
            } else if shouldSplitParagraph(
              currentParagraphRuns, newRun: textRun, newStyle: paraStyle)
            {
              flushParagraph(
                &currentParagraphRuns, style: currentParagraphStyle,
                visitor: visitor)
            }
          } else if shouldSplitParagraph(
            currentParagraphRuns, newRun: textRun, newStyle: paraStyle)
          {
            flushParagraph(
              &currentParagraphRuns, style: currentParagraphStyle, visitor: visitor)
          }

          currentParagraphStyle = paraStyle
          currentParagraphRuns.append(textRun)
        }
      } else {
        if isInList && !currentListItems.isEmpty {
          var lastItem = currentListItems.removeLast()
          lastItem = ListItem(
            content: lastItem.content + [textRun],
            indentLevel: lastItem.indentLevel,
            isChecked: lastItem.isChecked,
            listType: lastItem.listType
          )
          currentListItems.append(lastItem)
        } else {
          if shouldSplitParagraph(currentParagraphRuns, newRun: textRun, newStyle: nil) {
            flushParagraph(
              &currentParagraphRuns, style: currentParagraphStyle, visitor: visitor)
            currentParagraphStyle = nil
          }
          currentParagraphRuns.append(textRun)
        }
      }
    }

    flushList(&currentListItems, isInList: &isInList, visitor: visitor)
    flushParagraph(&currentParagraphRuns, style: currentParagraphStyle, visitor: visitor)
  }

  private func flushParagraph<V: NoteVisitor>(
    _ runs: inout [TextRun],
    style: Notes_ParagraphStyle?,
    visitor: V
  ) {
    guard !runs.isEmpty else { return }

    let condensedRuns = condenseRuns(runs)

    var styleType: ParagraphStyleType?
    var alignment: ParagraphAlignment?
    var indentLevel: Int = 0
    var isBlockQuote: Bool = false

    if let style = style {
      if style.hasStyleType {
        styleType = mapStyleType(style.styleType)
      }
      if style.hasAlignment {
        alignment = mapAlignment(style.alignment)
      }
      if style.hasIndentAmount {
        let rawIndent = Int(style.indentAmount)
        indentLevel = max(0, rawIndent - 1)
      }
      if style.hasBlockQuote {
        isBlockQuote = style.blockQuote != 0
      }

    }

    let paragraph = Paragraph(
      runs: condensedRuns,
      styleType: styleType,
      alignment: alignment,
      indentLevel: indentLevel,
      isBlockQuote: isBlockQuote
    )

    visitor.visitParagraph(paragraph)
    runs.removeAll()
  }

  private func flushList<V: NoteVisitor>(
    _ items: inout [ListItem], isInList: inout Bool, visitor: V
  ) {
    guard !items.isEmpty else { return }

    let condensedItems = items.map { item in
      ListItem(
        content: condenseRuns(item.content),
        indentLevel: item.indentLevel,
        isChecked: item.isChecked,
        listType: item.listType
      )
    }

    let list = List(items: condensedItems)

    visitor.willVisitList(list)
    for item in condensedItems {
      visitor.visitListItem(item)
    }
    visitor.didVisitList(list)

    items.removeAll()
    isInList = false
  }

  private func condenseRuns(_ runs: [TextRun]) -> [TextRun] {
    guard runs.count > 1 else { return runs }

    var condensed: [TextRun] = []
    var current = runs[0]

    for i in 1..<runs.count {
      let next = runs[i]

      if current.styles == next.styles && current.font == next.font {
        if current.text.hasSuffix("\n\n") || current.text.hasSuffix("\n\n\n") {
          condensed.append(current)
          current = next
        } else {
          current = TextRun(
            text: current.text + next.text,
            styles: current.styles,
            font: current.font
          )
        }
      } else {
        condensed.append(current)
        current = next
      }
    }

    condensed.append(current)
    return condensed
  }

  private func buildTextRun(text: String, run: Notes_AttributeRun) -> TextRun {
    var styles: [TextStyle] = []

    if run.hasFontWeight {
      if run.fontWeight == 1 || run.fontWeight == 3 {
        styles.append(.bold)
      }
      if run.fontWeight == 2 || run.fontWeight == 3 {
        styles.append(.italic)
      }
    }

    if run.hasEmphasisStyle && run.emphasisStyle != 0 {
      switch run.emphasisStyle {
      case 1:  // Purple
        styles.append(.color(red: 1.0, green: 0.0, blue: 1.0, alpha: 1.0))
        styles.append(.backgroundColor(red: 0.729, green: 0.333, blue: 0.827, alpha: 0.2))
      case 2:  // Pink
        styles.append(.color(red: 1.0, green: 0.251, blue: 0.506, alpha: 1.0))
        styles.append(.backgroundColor(red: 0.835, green: 0.0, blue: 0.0, alpha: 0.267))
      case 3:  // Orange
        styles.append(.color(red: 0.984, green: 0.753, blue: 0.176, alpha: 1.0))
        styles.append(.backgroundColor(red: 1.0, green: 0.435, blue: 0.0, alpha: 0.133))
      case 4:  // Mint
        styles.append(.color(red: 0.553, green: 0.898, blue: 0.859, alpha: 1.0))
        styles.append(.backgroundColor(red: 0.161, green: 0.612, blue: 0.557, alpha: 0.8))
      case 5:  // Blue
        styles.append(.color(red: 0.733, green: 0.871, blue: 0.984, alpha: 1.0))
        styles.append(.backgroundColor(red: 0.129, green: 0.588, blue: 0.953, alpha: 1.0))
      default:
        break
      }
    } else if run.hasColor {
      styles.append(
        .color(
          red: run.color.red,
          green: run.color.green,
          blue: run.color.blue,
          alpha: run.color.alpha
        ))
    }

    if run.hasUnderlined && run.underlined != 0 {
      styles.append(.underline)
    }

    if run.hasStrikethrough && run.strikethrough != 0 {
      styles.append(.strikethrough)
    }

    if run.hasSuperscript {
      if run.superscript > 0 {
        styles.append(.superscript)
      } else if run.superscript < 0 {
        styles.append(.subscript)
      }
    }

    if run.hasLink && !run.link.isEmpty {
      styles.append(.link(url: run.link))
    }

    var fontInfo: FontInfo?
    if run.hasFont {
      fontInfo = FontInfo(
        name: run.font.fontName,
        size: run.font.pointSize,
        weight: run.hasFontWeight ? run.fontWeight : nil
      )
    }

    return TextRun(text: text, styles: styles, font: fontInfo)
  }

  private func mapStyleType(_ type: Int32) -> ParagraphStyleType {
    switch type {
    case 0: return .title
    case 1: return .heading
    case 2: return .subheading
    case 4: return .monospaced
    case -1: return .body
    default: return .custom(type)
    }
  }

  private func mapAlignment(_ alignment: Int32) -> ParagraphAlignment {
    switch alignment {
    case 0: return .left
    case 1: return .center
    case 2: return .right
    case 3: return .justified
    case 4: return .natural
    default: return .natural
    }
  }

  private func isListItem(_ style: Notes_ParagraphStyle) -> Bool {
    if style.hasChecklist {
      return true
    }

    if style.hasStyleType && style.styleType >= 100 && style.styleType <= 103 {
      return true
    }

    return false
  }

  private func createListItem(runs: [TextRun], style: Notes_ParagraphStyle) -> ListItem {
    let listType = determineListType(from: style)
    let isChecked = style.hasChecklist ? (style.checklist.done != 0) : nil
    let indentLevel = style.hasIndentAmount ? Int(style.indentAmount) : 0

    return ListItem(
      content: runs,
      indentLevel: indentLevel,
      isChecked: isChecked,
      listType: listType
    )
  }

  private func determineListType(from style: Notes_ParagraphStyle) -> ListType {
    if style.hasChecklist {
      return .checklist
    }

    if style.hasStyleType {
      switch style.styleType {
      case 100: return .bullet
      case 101: return .dash
      case 102:
        return .numbered(
          startingAt: style.hasStartingListItemNumber
            ? Int(style.startingListItemNumber)
            : 1)
      case 103: return .checklist
      default: break
      }
    }

    return .bullet
  }

  private func isSameParagraph(_ style1: Notes_ParagraphStyle, _ style2: Notes_ParagraphStyle)
    -> Bool
  {
    return style1.styleType == style2.styleType
      && style1.alignment == style2.alignment
      && style1.indentAmount == style2.indentAmount
      && style1.blockQuote == style2.blockQuote
  }

  private func parseDrawingCanvasBounds(_ json: String?) -> NoteAttachment.CanvasBounds? {
    guard let json = json,
      let data = json.data(using: .utf8),
      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return nil
    }

    // Helper to get numeric value as Double (handles both Int and Double)
    func getDouble(_ key: String) -> Double? {
      if let value = dict[key] as? Double {
        return value
      } else if let value = dict[key] as? Int {
        return Double(value)
      }
      return nil
    }

    guard let originX = getDouble("paperContentBoundsOriginXKey"),
      let originY = getDouble("paperContentBoundsOriginYKey"),
      let width = getDouble("paperContentBoundsWidthKey"),
      let height = getDouble("paperContentBoundsHeightKey")
    else {
      return nil
    }

    return NoteAttachment.CanvasBounds(
      originX: originX,
      originY: originY,
      width: width,
      height: height
    )
  }

  private func buildAttachment(from info: Notes_AttachmentInfo) throws -> NoteAttachment {
    let identifier = info.attachmentIdentifier
    let uti = info.typeUti

    let attachmentRecord = try database.fetchAttachment(identifier: identifier)

    // Record was deleted from the database but still referenced in note content
    if attachmentRecord == nil {
      return .deleted(
        NoteAttachment.Deleted(
          identifier: identifier, uti: uti, creationDate: nil, modificationDate: nil))
    }

    let type = classifyAttachmentType(uti)

    var filename: String?
    var urlString: String?
    var userTitle: String?
    var duration: Double?
    var fileSize: Int64?
    var width: Int?
    var height: Int?
    var ocrText: String?
    var handwritingSummary: String?
    var imageClassifications: [String] = []
    var additionalIndexableText: String?
    var fallbackTitle: String?
    var fallbackSubtitle: String?
    var metadataJSON: String?

    if let record = attachmentRecord {
      urlString = record.urlString
      userTitle = record.userTitle
      duration = record.duration
      fileSize = record.fileSize
      ocrText = record.ocrSummary
      handwritingSummary = record.handwritingSummary
      imageClassifications = record.imageClassifications
      additionalIndexableText = record.additionalIndexableText
      fallbackTitle = record.fallbackTitle
      fallbackSubtitle = record.fallbackSubtitleMac ?? record.fallbackSubtitleIOS
      metadataJSON = record.metadataJSON

      if let mediaFK = record.mediaForeignKey {
        if let mediaRecord = try? database.fetchMedia(primaryKey: mediaFK) {
          filename = mediaRecord.filename
          width = mediaRecord.width
          height = mediaRecord.height
        }
      }
    }

    let creationDate = attachmentRecord?.creationDate
    let modificationDate = attachmentRecord?.modificationDate

    switch type {
    case .image:
      return .image(
        NoteAttachment.Image(
          identifier: identifier,
          uti: uti,
          filename: filename,
          location: nil,
          creationDate: creationDate,
          modificationDate: modificationDate,
          fileSize: fileSize,
          width: width.map(Float.init),
          height: height.map(Float.init),
          ocrText: ocrText,
          imageClassifications: imageClassifications,
          additionalIndexableText: additionalIndexableText
        ))

    case .pdf:
      return .pdf(
        NoteAttachment.PDF(
          identifier: identifier,
          uti: uti,
          filename: filename,
          creationDate: creationDate,
          modificationDate: modificationDate,
          fileSize: fileSize,
          ocrText: ocrText,
          additionalIndexableText: additionalIndexableText
        ))

    case .video:
      return .video(
        NoteAttachment.Video(
          identifier: identifier,
          uti: uti,
          filename: filename,
          creationDate: creationDate,
          modificationDate: modificationDate,
          duration: duration,
          fileSize: fileSize,
          width: width.map(Float.init),
          height: height.map(Float.init)
        ))

    case .audio:
      return .audio(
        NoteAttachment.Audio(
          identifier: identifier,
          uti: uti,
          title: attachmentRecord?.title ?? userTitle ?? fallbackSubtitle ?? fallbackTitle,
          filename: filename,
          creationDate: creationDate,
          modificationDate: modificationDate,
          duration: duration,
          fileSize: fileSize
        ))

    case .drawing:
      let canvasBounds = parseDrawingCanvasBounds(metadataJSON)

      return .drawing(
        NoteAttachment.Drawing(
          identifier: identifier,
          uti: uti,
          creationDate: creationDate,
          modificationDate: modificationDate,
          width: width.map(Float.init),
          height: height.map(Float.init),
          fallbackTitle: fallbackTitle,
          handwritingSummary: handwritingSummary,
          additionalIndexableText: additionalIndexableText,
          canvasBounds: canvasBounds
        ))

    case .url:
      let linkCardData = try? database.fetchURLLinkCard(identifier: identifier)
      return .url(
        NoteAttachment.URLLink(
          identifier: identifier,
          uti: uti,
          creationDate: creationDate,
          modificationDate: modificationDate,
          urlString: linkCardData?.url ?? urlString,
          title: linkCardData?.title ?? userTitle,
          summary: nil
        ))

    case .table:
      return .table(
        NoteAttachment.Table(
          identifier: identifier,
          creationDate: creationDate,
          modificationDate: modificationDate
        ))

    case .calendar:
      return .calendar(
        NoteAttachment.Calendar(
          identifier: identifier,
          uti: uti,
          creationDate: creationDate,
          modificationDate: modificationDate
        ))

    case .vcard:
      return .vcard(
        NoteAttachment.VCard(
          identifier: identifier,
          uti: uti,
          creationDate: creationDate,
          modificationDate: modificationDate,
          filename: filename
        ))

    case .gallery:
      return .gallery(
        NoteAttachment.Gallery(
          identifier: identifier,
          creationDate: creationDate,
          modificationDate: modificationDate,
          items: []
        ))

    case .scan:
      return .scan(
        NoteAttachment.Scan(
          identifier: identifier,
          uti: uti,
          creationDate: creationDate,
          modificationDate: modificationDate,
          ocrText: ocrText,
          additionalIndexableText: additionalIndexableText
        ))

    case .file, .unknown:
      return .unknown(
        NoteAttachment.Unknown(
          identifier: identifier,
          uti: uti,
          creationDate: creationDate,
          modificationDate: modificationDate
        ))
    }
  }

  private func classifyAttachmentType(_ uti: String) -> AttachmentTypeClassification {
    if uti.hasPrefix("public.image") || uti.hasPrefix("public.jpeg")
      || uti.hasPrefix("public.png") || uti.hasPrefix("public.heic")
      || uti == "com.compuserve.gif" || uti == "public.tiff"
      || uti == "com.apple.quicktime-image" || uti == "org.webmproject.webp"
      || uti == "public.bmp" || uti == "com.adobe.raw-image"
    {
      return .image
    }

    if uti.hasPrefix("com.adobe.pdf") || uti.hasPrefix("public.pdf") {
      return .pdf
    }

    if uti.hasPrefix("public.movie") || uti.hasPrefix("public.video")
      || uti.hasPrefix("com.apple.quicktime-movie") || uti == "public.avi"
      || uti.hasPrefix("public.mpeg") || uti == "com.apple.m4v-video"
    {
      return .video
    }

    if uti.hasPrefix("public.audio") || uti.hasPrefix("public.mp3")
      || uti == "com.apple.m4a-audio" || uti == "public.aiff-audio"
      || uti == "public.midi-audio"
    {
      return .audio
    }

    if uti == "com.apple.notes.table" {
      return .table
    }

    if uti == "public.url" {
      return .url
    }

    if uti == "com.apple.drawing" || uti == "com.apple.drawing.2"
      || uti == "com.apple.paper" || uti == "com.apple.notes.sketch"
      || uti.hasPrefix("com.apple.paper")
    {
      return .drawing
    }

    if uti == "com.apple.notes.gallery" {
      return .gallery
    }

    if uti == "com.apple.paper.doc.scan" || uti == "com.apple.paper.doc.pdf" {
      return .scan
    }

    if uti == "com.apple.ical.ics" {
      return .calendar
    }

    if uti == "public.vcard" {
      return .vcard
    }

    return uti.hasPrefix("public.") ? .file : .unknown
  }

  private func fetchMergeableProto(identifier: String) throws -> Notes_MergableDataProto? {
    guard let data = try database.fetchMergeableData(identifier: identifier) else { return nil }
    let decompressed = data.gunzipped() ?? data
    return try Notes_MergableDataProto(
      serializedBytes: decompressed, extensions: nil, partial: true)
  }

  private func emitTable<V: NoteVisitor>(identifier: String, visitor: V) throws {
    guard let proto = try fetchMergeableProto(identifier: identifier),
      let table = try buildTable(from: proto)
    else { return }

    visitor.willVisitTable(table)
    for (rowIndex, row) in table.rows.enumerated() {
      for (colIndex, cell) in row.enumerated() {
        visitor.visitTableCell(cell, row: rowIndex, column: colIndex)
      }
    }
    visitor.didVisitTable(table)
  }

  private func emitGallery<V: NoteVisitor>(gallery: NoteAttachment.Gallery, visitor: V) throws {
    guard let proto = try fetchMergeableProto(identifier: gallery.identifier),
      let updatedGallery = try buildGallery(from: proto, identifier: gallery.identifier)
    else { return }

    visitor.willVisitGallery(updatedGallery)
    for item in updatedGallery.items {
      visitor.visitGalleryItem(item)
    }
    visitor.didVisitGallery(updatedGallery)
  }

  private func emitInlineAttachment<V: NoteVisitor>(
    identifier: String,
    uti: String,
    visitor: V
  ) throws {
    guard let record = try database.fetchAttachment(identifier: identifier) else {
      return
    }

    let type: InlineAttachmentType
    if uti == "com.apple.notes.inlinetextattachment.hashtag" {
      type = .hashtag
    } else if uti == "com.apple.notes.inlinetextattachment.mention" {
      type = .mention
    } else if uti == "com.apple.notes.inlinetextattachment.link" {
      type = .link
    } else if uti == "com.apple.notes.inlinetextattachment.calculateresult" {
      type = .calculateResult
    } else if uti == "com.apple.notes.inlinetextattachment.calculategraphexpression" {
      type = .calculateGraphExpression
    } else {
      type = .unknown
    }

    let inlineAttachment = InlineAttachment(
      identifier: identifier,
      type: type,
      text: record.altText,
      tokenIdentifier: record.tokenIdentifier
    )

    visitor.visitInlineAttachment(inlineAttachment)
  }

  private func buildGallery(
    from proto: Notes_MergableDataProto,
    identifier: String
  ) throws -> NoteAttachment.Gallery? {
    let objectData = proto.mergableDataObject.mergeableDataObjectData
    let uuidItems = objectData.mergeableDataObjectUuidItem
    let objects = objectData.mergeableDataObjectEntry

    var galleryItems: [NoteAttachment] = []
    var itemOrder: [(Int, String)] = []

    for entry in objects {
      if entry.hasOrderedSet {
        let ordering = entry.orderedSet.ordering

        for attachment in ordering.array.attachment {
          if uuidItems.firstIndex(of: attachment.uuid) != nil {
            let uuidString = attachment.uuid.base64EncodedString()
            itemOrder.append((Int(attachment.index), uuidString))
          }
        }
      }
    }

    itemOrder.sort { $0.0 < $1.0 }

    for (_, childLookupKey) in itemOrder {
      if let childRecord = try? database.fetchAttachment(identifier: childLookupKey) {
        let childId = childRecord.identifier
        let uti = childRecord.uti ?? ""
        let type = classifyAttachmentType(uti)
        var filename: String?
        var width: Int?
        var height: Int?

        if let mediaFK = childRecord.mediaForeignKey,
          let mediaRecord = try? database.fetchMedia(primaryKey: mediaFK)
        {
          filename = mediaRecord.filename
          width = mediaRecord.width
          height = mediaRecord.height
        }

        let attachment: NoteAttachment
        switch type {
        case .image:
          attachment = .image(
            NoteAttachment.Image(
              identifier: childId,
              uti: uti,
              filename: filename,
              location: nil,
              creationDate: childRecord.creationDate,
              modificationDate: childRecord.modificationDate,
              fileSize: childRecord.fileSize,
              width: width.map(Float.init),
              height: height.map(Float.init),
              ocrText: childRecord.ocrSummary,
              imageClassifications: childRecord.imageClassifications,
              additionalIndexableText: childRecord.additionalIndexableText
            ))
        case .video:
          attachment = .video(
            NoteAttachment.Video(
              identifier: childId,
              uti: uti,
              filename: filename,
              creationDate: childRecord.creationDate,
              modificationDate: childRecord.modificationDate,
              duration: childRecord.duration,
              fileSize: childRecord.fileSize,
              width: width.map(Float.init),
              height: height.map(Float.init)
            ))
        default:
          attachment = .unknown(
            NoteAttachment.Unknown(
              identifier: childId,
              uti: uti,
              creationDate: childRecord.creationDate,
              modificationDate: childRecord.modificationDate
            ))
        }

        galleryItems.append(attachment)
      }
    }

    let galleryRecord = try database.fetchAttachment(identifier: identifier)
    return NoteAttachment.Gallery(
      identifier: identifier,
      creationDate: galleryRecord?.creationDate,
      modificationDate: galleryRecord?.modificationDate,
      items: galleryItems
    )
  }

  private func buildTable(from proto: Notes_MergableDataProto) throws -> Table? {
    let objectData = proto.mergableDataObject.mergeableDataObjectData
    let keyItems = objectData.mergeableDataObjectKeyItem
    let typeItems = objectData.mergeableDataObjectTypeItem
    let uuidItems = objectData.mergeableDataObjectUuidItem
    let objects = objectData.mergeableDataObjectEntry

    guard let tableObject = findTableObject(objects: objects, typeItems: typeItems) else {
      return nil
    }

    var rowIndices: [Int: Int] = [:]
    var columnIndices: [Int: Int] = [:]
    var totalRows = 0
    var totalColumns = 0

    for mapEntry in tableObject.customMap.mapEntry {
      let keyIndex = Int(mapEntry.key)
      guard keyIndex >= 0 && keyIndex < keyItems.count else { continue }
      let keyName = keyItems[keyIndex]

      let objectIndex = Int(mapEntry.value.objectIndex)
      guard objectIndex >= 0 && objectIndex < objects.count else { continue }
      var targetObject = objects[objectIndex]

      let regObjectIndex = Int(targetObject.registerLatest.contents.objectIndex)
      if regObjectIndex > 0 && regObjectIndex < objects.count {
        let regObject = objects[regObjectIndex]
        if regObject.hasOrderedSet || regObject.hasCustomMap {
          targetObject = regObject
        }
      }

      switch keyName {
      case "crRows":
        if targetObject.hasOrderedSet {
          (rowIndices, totalRows) = parseOrderedSet(
            targetObject,
            uuidItems: uuidItems,
            objects: objects,
            keyItems: keyItems,
            typeItems: typeItems
          )
        } else if targetObject.hasCustomMap {
          if let orderedSetObj = findOrderedSetInMap(targetObject, objects: objects) {
            (rowIndices, totalRows) = parseOrderedSet(
              orderedSetObj,
              uuidItems: uuidItems,
              objects: objects,
              keyItems: keyItems,
              typeItems: typeItems
            )
          }
        }

      case "crColumns":
        if targetObject.hasOrderedSet {
          (columnIndices, totalColumns) = parseOrderedSet(
            targetObject,
            uuidItems: uuidItems,
            objects: objects,
            keyItems: keyItems,
            typeItems: typeItems
          )
        } else if targetObject.hasCustomMap {
          if let orderedSetObj = findOrderedSetInMap(targetObject, objects: objects) {
            (columnIndices, totalColumns) = parseOrderedSet(
              orderedSetObj,
              uuidItems: uuidItems,
              objects: objects,
              keyItems: keyItems,
              typeItems: typeItems
            )
          }
        }

      case "UUIDIndex", "self":
        if targetObject.hasOrderedSet {
          if totalRows == 0 {
            (rowIndices, totalRows) = parseOrderedSet(
              targetObject,
              uuidItems: uuidItems,
              objects: objects,
              keyItems: keyItems,
              typeItems: typeItems
            )
          } else if totalColumns == 0 {
            (columnIndices, totalColumns) = parseOrderedSet(
              targetObject,
              uuidItems: uuidItems,
              objects: objects,
              keyItems: keyItems,
              typeItems: typeItems
            )
          }
        }

      default:
        break
      }
    }

    guard totalRows > 0 && totalColumns > 0 else {
      return nil
    }

    var table = Array(
      repeating: Array(repeating: [TextRun](), count: totalColumns),
      count: totalRows
    )

    for mapEntry in tableObject.customMap.mapEntry {
      let keyIndex = Int(mapEntry.key)
      guard keyIndex >= 0 && keyIndex < keyItems.count else { continue }

      let objectIndex = Int(mapEntry.value.objectIndex)
      guard objectIndex >= 0 && objectIndex < objects.count else { continue }
      let cellColumnsObject = objects[objectIndex]

      if cellColumnsObject.hasDictionary && cellColumnsObject.dictionary.element.count > 0 {
        let firstElement = cellColumnsObject.dictionary.element.first!
        let firstValueIndex = Int(firstElement.value.objectIndex)
        if firstValueIndex >= 0 && firstValueIndex < objects.count {
          let firstValueObj = objects[firstValueIndex]
          if firstValueObj.hasDictionary {
            parseCellColumns(
              cellColumnsObject,
              into: &table,
              rowIndices: rowIndices,
              columnIndices: columnIndices,
              objects: objects,
              uuidItems: uuidItems
            )
            break
          }
        }
      }
    }

    let rows = table.map { row in
      row.map { cellRuns in
        TableCell(content: cellRuns.isEmpty ? [] : condenseRuns(cellRuns))
      }
    }

    return Table(rows: rows, columnCount: totalColumns, rowCount: totalRows)
  }

  private func findTableObject(
    objects: [Notes_MergeableDataObjectEntry],
    typeItems: [String]
  ) -> Notes_MergeableDataObjectEntry? {
    for object in objects {
      if object.hasCustomMap {
        let typeIndex = Int(object.customMap.type)
        if typeIndex >= 0 && typeIndex < typeItems.count {
          if typeItems[typeIndex] == "com.apple.notes.ICTable" {
            return object
          }
        }
      }
    }
    return nil
  }

  private func findOrderedSetInMap(
    _ object: Notes_MergeableDataObjectEntry,
    objects: [Notes_MergeableDataObjectEntry]
  ) -> Notes_MergeableDataObjectEntry? {
    guard object.hasCustomMap else { return nil }

    for entry in object.customMap.mapEntry {
      let idx = Int(entry.value.objectIndex)
      if idx >= 0 && idx < objects.count {
        let obj = objects[idx]
        if obj.hasOrderedSet {
          return obj
        }
      }
    }
    return nil
  }

  private func parseOrderedSet(
    _ object: Notes_MergeableDataObjectEntry,
    uuidItems: [Data],
    objects: [Notes_MergeableDataObjectEntry],
    keyItems: [String] = [],
    typeItems: [String] = []
  ) -> ([Int: Int], Int) {
    var indices: [Int: Int] = [:]
    var count = 0

    let actualObjectIndex = Int(object.registerLatest.contents.objectIndex)
    if actualObjectIndex > 0 && actualObjectIndex < objects.count {
      let actualObject = objects[actualObjectIndex]
      if actualObject.hasOrderedSet || actualObject.hasCustomMap {
        return parseOrderedSet(
          actualObject,
          uuidItems: uuidItems,
          objects: objects,
          keyItems: keyItems,
          typeItems: typeItems
        )
      }
    }

    if object.hasCustomMap {
      for entry in object.customMap.mapEntry {
        let nestedObjectIndex = Int(entry.value.objectIndex)
        if nestedObjectIndex > 0 && nestedObjectIndex < objects.count {
          let nestedObject = objects[nestedObjectIndex]
          if nestedObject.hasOrderedSet {
            return parseOrderedSet(
              nestedObject,
              uuidItems: uuidItems,
              objects: objects,
              keyItems: keyItems,
              typeItems: typeItems
            )
          }
        }
      }
    }

    guard object.hasOrderedSet else {
      return (indices, count)
    }

    let ordering = object.orderedSet.ordering

    for attachment in ordering.array.attachment {
      if let uuidIndex = uuidItems.firstIndex(of: attachment.uuid) {
        indices[uuidIndex] = count
        count += 1
      }
    }

    for element in ordering.contents.element {
      let keyObjectIndex = Int(element.key.objectIndex)
      let valueObjectIndex = Int(element.value.objectIndex)

      if keyObjectIndex < objects.count && valueObjectIndex < objects.count {
        if let keyUUID = getTargetUUID(from: objects[keyObjectIndex]),
          let valueUUID = getTargetUUID(from: objects[valueObjectIndex]),
          let keyIndex = indices[keyUUID]
        {
          indices[valueUUID] = keyIndex
        }
      }
    }

    return (indices, count)
  }

  private func getTargetUUID(from object: Notes_MergeableDataObjectEntry) -> Int? {
    guard object.hasCustomMap else { return nil }
    guard let firstEntry = object.customMap.mapEntry.first else { return nil }
    return Int(firstEntry.value.unsignedIntegerValue)
  }

  private func parseCellColumns(
    _ object: Notes_MergeableDataObjectEntry,
    into table: inout [[[TextRun]]],
    rowIndices: [Int: Int],
    columnIndices: [Int: Int],
    objects: [Notes_MergeableDataObjectEntry],
    uuidItems: [Data]
  ) {
    guard object.hasDictionary else { return }

    for columnElement in object.dictionary.element {
      let columnObjectIndex = Int(columnElement.key.objectIndex)
      guard columnObjectIndex < objects.count else { continue }

      let currentColumn = getTargetUUID(from: objects[columnObjectIndex])
      guard let column = currentColumn, let colIndex = columnIndices[column] else { continue }

      let rowDictIndex = Int(columnElement.value.objectIndex)
      guard rowDictIndex < objects.count else { continue }
      let rowDict = objects[rowDictIndex]

      guard rowDict.hasDictionary else { continue }

      for rowElement in rowDict.dictionary.element {
        let rowObjectIndex = Int(rowElement.key.objectIndex)
        guard rowObjectIndex < objects.count else { continue }

        let currentRow = getTargetUUID(from: objects[rowObjectIndex])
        guard let row = currentRow, let rowIndex = rowIndices[row] else { continue }

        let cellObjectIndex = Int(rowElement.value.objectIndex)
        guard cellObjectIndex < objects.count else { continue }
        let cellObject = objects[cellObjectIndex]

        if cellObject.hasNote {
          let cellNote = cellObject.note
          var cellRuns: [TextRun] = []

          let text = cellNote.noteText
          var currentIndex = text.startIndex

          for run in cellNote.attributeRun {
            let length = Int(run.length)
            guard currentIndex < text.endIndex else { break }

            let endIndex =
              text.index(
                currentIndex,
                offsetBy: length,
                limitedBy: text.endIndex
              ) ?? text.endIndex
            let runText = String(text[currentIndex..<endIndex])
            currentIndex = endIndex

            let textRun = buildTextRun(text: runText, run: run)
            cellRuns.append(textRun)
          }

          table[rowIndex][colIndex] = cellRuns
        }
      }
    }
  }
}
