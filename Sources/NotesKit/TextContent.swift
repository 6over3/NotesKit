// This file is part of NotesKit.
// Copyright (c) 2025 6OVER3 Institute.
// Licensed under the GNU Affero General Public License v3.0.
// See LICENSE file for details.

// MARK: - Text Styling

/// A visual style applied to a text run.
public enum TextStyle: Equatable, Sendable {
  case bold
  case italic
  case underline
  case strikethrough
  case superscript
  case `subscript`
  case link(url: String)
  case color(red: Float, green: Float, blue: Float, alpha: Float)
  case backgroundColor(red: Float, green: Float, blue: Float, alpha: Float)
}

/// Font metadata for a text run.
public struct FontInfo: Equatable, Sendable {
  public let name: String
  public let size: Float
  public let weight: Int32?
}

/// A styled run of text within a paragraph or list item.
public struct TextRun: Equatable, Sendable {
  public let text: String
  public let styles: [TextStyle]
  public let font: FontInfo?
}

// MARK: - Paragraph

/// Text alignment for a paragraph.
public enum ParagraphAlignment: Equatable, Sendable {
  case left
  case center
  case right
  case justified
  case natural
}

/// The semantic style of a paragraph.
public enum ParagraphStyleType: Equatable, Sendable {
  case title
  case heading
  case subheading
  case body
  case monospaced
  case custom(Int32)
}

/// A paragraph of styled text.
public struct Paragraph: Equatable, Sendable {
  public let runs: [TextRun]
  public let styleType: ParagraphStyleType?
  public let alignment: ParagraphAlignment?
  public let indentLevel: Int
  public let isBlockQuote: Bool
}

// MARK: - List

/// The type of list.
public enum ListType: Equatable, Sendable {
  case bullet
  case dash
  case numbered(startingAt: Int)
  case checklist
}

/// A single item in a list.
public struct ListItem: Equatable, Sendable {
  public let content: [TextRun]
  public let indentLevel: Int
  public let isChecked: Bool?
  public let listType: ListType
}

/// A list of items.
public struct List: Equatable, Sendable {
  public let items: [ListItem]
}

// MARK: - Table

/// A single cell in a table.
public struct TableCell: Equatable, Sendable {
  public let content: [TextRun]
}

/// A table with rows and columns.
public struct Table: Equatable, Sendable {
  public let rows: [[TableCell]]
  public let columnCount: Int
  public let rowCount: Int
}

// MARK: - Inline Attachment

/// The type of inline attachment embedded in text.
public enum InlineAttachmentType: Equatable, Sendable {
  case hashtag
  case mention
  case link
  case calculateResult
  case calculateGraphExpression
  case unknown
}

/// An inline attachment embedded within paragraph text.
public struct InlineAttachment: Equatable, Sendable {
  public let identifier: String
  public let type: InlineAttachmentType
  public let text: String?
  public let tokenIdentifier: String?
}
