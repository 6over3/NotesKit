# NotesKit

Read and decrypt Apple Notes databases from Swift.

## Usage

```swift
import NotesKit

let library = try NotesLibrary()

for note in try library.notes {
    let markdown = try note.markdown()
    print(markdown)
}
```

### Encrypted notes

```swift
let markdown = try note.markdown(password: "secret")
```

Or with the visitor API:

```swift
try note.parse(visitor: myVisitor, password: "secret")
```

### Visitor API

Implement `NoteVisitor` to process note content:

```swift
class MyVisitor: NoteVisitor {
    func visitParagraph(_ paragraph: Paragraph) { ... }
    func visitListItem(_ item: ListItem) { ... }
    func visitAttachment(_ attachment: NoteAttachment) { ... }
}
```

A built-in `MarkdownVisitor` converts notes to Markdown.

### Folders and accounts

```swift
let folders = try library.folders
let accounts = try library.accounts
```

## Encryption support

| Format | Versions | Status |
|--------|----------|--------|
| V1 | iOS 16 and earlier | Supported |
| V1 Neo | macOS 15+ | Supported |
| V2 (Keychain) | macOS 15+ | Not supportable |

V2 notes are encrypted with a key stored in the system Keychain, not derivable from a password. See [docs/encryption-research.md](docs/encryption-research.md) for details.

## Requirements

- Swift 6.2+
- macOS 13+ / iOS 16+

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/6over3/noteskit", from: "1.0.0"),
]
```

## License

GNU Affero General Public License v3.0. See [LICENSE](LICENSE).
