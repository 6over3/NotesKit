// This file is part of NotesKit.
// Copyright (c) 2025 6OVER3 Institute.
// Licensed under the GNU Affero General Public License v3.0.
// See LICENSE file for details.

/// Protocol for visiting note content elements during parsing.
///
/// Implement the methods you care about — all have default no-op implementations.
public protocol NoteVisitor {
  func willVisitNote()
  func didVisitNote()
  func visitParagraph(_ paragraph: Paragraph)
  func willVisitList(_ list: List)
  func visitListItem(_ item: ListItem)
  func didVisitList(_ list: List)
  func willVisitTable(_ table: Table)
  func visitTableCell(_ cell: TableCell, row: Int, column: Int)
  func didVisitTable(_ table: Table)
  func visitAttachment(_ attachment: NoteAttachment)
  func willVisitGallery(_ gallery: NoteAttachment.Gallery)
  func visitGalleryItem(_ item: NoteAttachment)
  func didVisitGallery(_ gallery: NoteAttachment.Gallery)
  func visitInlineAttachment(_ inlineAttachment: InlineAttachment)
}

extension NoteVisitor {
  public func willVisitNote() {}
  public func didVisitNote() {}
  public func visitParagraph(_ paragraph: Paragraph) {}
  public func willVisitList(_ list: List) {}
  public func visitListItem(_ item: ListItem) {}
  public func didVisitList(_ list: List) {}
  public func willVisitTable(_ table: Table) {}
  public func visitTableCell(_ cell: TableCell, row: Int, column: Int) {}
  public func didVisitTable(_ table: Table) {}
  public func visitAttachment(_ attachment: NoteAttachment) {}
  public func willVisitGallery(_ gallery: NoteAttachment.Gallery) {}
  public func visitGalleryItem(_ item: NoteAttachment) {}
  public func didVisitGallery(_ gallery: NoteAttachment.Gallery) {}
  public func visitInlineAttachment(_ inlineAttachment: InlineAttachment) {}
}
