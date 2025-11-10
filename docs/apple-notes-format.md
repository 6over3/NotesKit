# Apple Notes internal format

Reverse-engineered from the iCloud Notes database and protobuf schemas. Covers macOS and iOS Notes as synced through iCloud.

## Database

Notes are stored in a SQLite database at:

- **macOS**: `~/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite`
- **iOS (iTunes backup)**: Hashed path `4f/4f98687d8ab0d6d1a371110e6b7300f6e465bef2` (SHA1 of `AppDomainGroup-group.com.apple.notes/NoteStore.sqlite`)
- **iOS (physical backup)**: `private/var/mobile/Containers/Shared/AppGroup/<UUID>/NoteStore.sqlite`

The database is a CoreData store. Two tables matter:

### ZICCLOUDSYNCINGOBJECT

The main table. Everything lives here -- notes, attachments, folders, accounts. Key columns:

| Column | Purpose |
|--------|---------|
| `ZIDENTIFIER` | UUID string identifying the object |
| `ZTITLE` / `ZTITLE1` | Note title (column name varies by version) |
| `ZNOTEDATA` | Foreign key to `ZICNOTEDATA.Z_PK` |
| `ZTYPEUTI` / `ZTYPEUTI1` | Uniform Type Identifier for attachments |
| `ZMEDIA` | Foreign key to media record |
| `ZMERGEABLEDATA` / `ZMERGEABLEDATA1` | Protobuf blob for tables, drawings, galleries |
| `ZACCOUNT` / `ZACCOUNT4` | Foreign key to account record |
| `ZFOLDER` | Foreign key to folder record |
| `ZISPINNED` | Whether the note is pinned |
| `ZISPASSWORDPROTECTED` | Whether the note is encrypted |
| `ZMARKEDFORDELETION` | Soft delete flag |
| `ZSMARTFOLDERQUERYJSON` | Smart folder filter criteria (iOS 15+) |
| `ZHANDWRITINGSUMMARY` | Recognized handwriting text from drawings |
| `ZOCRSUMMARY` | OCR text from images/scans |
| `ZIMAGECLASSIFICATION` | Space-separated image classification labels |
| `ZADDITIONALINDEXABLETEXT` | Extra searchable text |
| `ZGENERATION` / `ZGENERATION1` | Version generation for fallback images/PDFs |
| `ZDURATION` | Duration for audio/video attachments |
| `ZFILESIZE` | File size in bytes |
| `ZURLSTRING` | URL for link attachments |
| `ZUSERTITLE` | User-provided title for attachments |

### ZICNOTEDATA

The note content blobs:

| Column | Purpose |
|--------|---------|
| `Z_PK` | Primary key |
| `ZDATA` | gzip-compressed protobuf blob containing the note text and formatting |

### Version detection

The schema changes with each iOS release. NotesKit detects the version by checking for columns added in specific releases:

| Version | Indicator Column |
|---------|-----------------|
| iOS 18 | `ZUNAPPLIEDENCRYPTEDRECORDDATA` |
| iOS 17 | `ZGENERATION` |
| iOS 16 | `ZTYPEUTI1` |
| iOS 15 | `ZSERVERRECORDDATA` |
| iOS 14 | `ZCREATIONDATE` (on note data) |
| iOS 13 | `ZACCOUNT4` |
| Legacy | Everything else |

## Protobuf structure

Note content is gzip-compressed protobuf. Three schema layers.

### Layer 1: Note content (topotext)

The text and formatting. Stored in `ZICNOTEDATA.ZDATA`.

```
NoteStoreProto
 └─ Document (version, note)
     └─ Note
         ├─ string note_text      // Full plain text of the note
         └─ AttributeRun[]        // Formatting runs (length + styles)
```

Each `AttributeRun` covers a span of UTF-16 characters and carries:

- **Paragraph style**: heading level, list type, alignment, indent, block quote
- **Inline styles**: bold/italic (via `font_weight`), underline, strikethrough, superscript
- **Font override**: name, size, hints
- **Color**: RGBA float values
- **Link**: URL string
- **Attachment reference**: identifier + UTI pointing to a `ZICCLOUDSYNCINGOBJECT` record

#### Paragraph style types

| Value | Type |
|-------|------|
| 0 | Title |
| 1 | Heading |
| 2 | Subheading |
| 4 | Monospaced (code block) |
| 100 | Bullet list item (dot) |
| 101 | Dash list item |
| 102 | Numbered list item |
| 103 | Checklist item |

#### Font weight hints

| Value | Meaning |
|-------|---------|
| 1 | Bold |
| 2 | Italic |
| 3 | Bold + Italic |

### Layer 2: Mergeable data (CRDT)

Tables, galleries, and drawing metadata. Stored in `ZICCLOUDSYNCINGOBJECT.ZMERGEABLEDATA`. Also gzip-compressed protobuf.

```
MergableDataProto
 └─ MergableDataObject (version, data)
     └─ MergeableDataObjectData
         ├─ MergeableDataObjectEntry[]    // The objects
         ├─ string[] keyItem              // Key name lookup table
         ├─ string[] typeItem             // Type name lookup table
         └─ bytes[] uuidItem              // UUID lookup table
```

This is an NSKeyedArchiver-style object graph built on protobuf. Objects reference each other by index via `ObjectID.object_index`. The first entry is the root object.

Each `MergeableDataObjectEntry` can be one of:

- `RegisterLatest` — Last-write-wins register (a single value with a clock)
- `Dictionary` — Key-value pairs (keys are usually UUIDs)
- `Note` — A topotext String (used for cell content)
- `CustomObject` — Typed object with named fields (type/key indices into lookup tables)
- `OrderedSet` — CRDT ordered set (used for row/column ordering)

#### Decoding tables

The root `CustomObject` for a table has fields:

| Field | Value |
|-------|-------|
| `crRows` | `OrderedSet` of row UUIDs |
| `crColumns` | `OrderedSet` of column UUIDs |
| `cellColumns` | `Dictionary` of column UUID -> `Dictionary` of row UUID -> `Note` (cell text) |

To get ordered UUIDs from an `OrderedSet`:
1. Take `ordering.array.attachments` — these map string positions to UUIDs
2. Filter to UUIDs that appear as keys in `elements` (removes deleted items)
3. Look up each UUID in `ordering.contents` to get the content UUID

#### Decoding galleries

The root object has an `OrderedSet` mapping indices to child attachment identifiers. Each child is looked up from `ZICCLOUDSYNCINGOBJECT` by identifier.

### Layer 3: Versioned document wrapper

Both note content and mergeable data are wrapped in a versioned document:

```
Document
 └─ Version[] (usually just one)
     ├─ serializationVersion
     ├─ minimumSupportedVersion
     └─ bytes data    // The actual protobuf content
```

## Attachments

Records in `ZICCLOUDSYNCINGOBJECT` referenced by UUID from the note's protobuf `AttachmentInfo`. The `ZTYPEUTI` column determines the type:

| UTI Pattern | Type |
|-------------|------|
| `public.image/*`, `public.jpeg`, `public.png`, `public.heic`, `com.adobe.raw-image`, etc. | Image |
| `com.adobe.pdf` | PDF |
| `public.movie/*`, `public.mpeg-4`, `com.apple.quicktime-movie` | Video |
| `public.audio/*`, `com.apple.m4a-audio` | Audio |
| `com.apple.drawing`, `com.apple.drawing.2`, `com.apple.paper` | Drawing |
| `com.apple.notes.table` | Table |
| `public.url` | URL bookmark |
| `com.apple.notes.gallery` | Gallery (collection of images/videos) |
| `com.apple.paper.doc.scan` | Document scan |
| `com.apple.ical.ics` | Calendar event |
| `public.vcard` | Contact card |
| `com.apple.notes.inlinetextattachment.*` | Inline (hashtag, mention, link, math result) |

### File resolution

Attachment files live under the Notes group container:

- **Media files**: `Accounts/<account-UUID>/Media/<media-UUID>/<generation>/<filename>`
- **Fallback images** (drawings): `Accounts/<account-UUID>/FallbackImages/<attachment-UUID>/<generation>/FallbackImage.{jpeg,png}`
- **Fallback PDFs** (scanned docs): `Accounts/<account-UUID>/FallbackPDFs/<attachment-UUID>/<generation>/FallbackPDF.pdf`

The `generation` comes from the `ZGENERATION`/`ZGENERATION1` column (iOS 17+). On older versions, files may be at the root level without a generation subdirectory.

### Inline attachments

Inline attachments appear in text as `U+FFFC` (object replacement character), referenced via `AttachmentInfo` in the attribute run. Known types:

| UTI | Type |
|-----|------|
| `com.apple.notes.inlinetextattachment.hashtag` | #hashtag |
| `com.apple.notes.inlinetextattachment.mention` | @mention |
| `com.apple.notes.inlinetextattachment.link` | Smart link |
| `com.apple.notes.inlinetextattachment.calculateresult` | Math result |
| `com.apple.notes.inlinetextattachment.calculategraphexpression` | Math graph |

The display text is stored in the attachment record's `ZALTTEXT` column.

### Audio transcriptions

Audio attachments (`com.apple.m4a-audio`) may have transcription data in `ZMERGEABLEDATA` as protobuf. Contains a top-line summary, a longer summary, and timestamped segments with speaker labels.

### Drawings

Vector stroke data lives in `ZMERGEABLEDATA`, but Apple also generates a rasterized fallback image that's usually good enough for export. The vector data uses a compact binary encoding for stroke points (position, pressure, azimuth, altitude).

## Smart folders

iOS 15+. A folder with a non-null `ZSMARTFOLDERQUERYJSON` column is a smart folder. The query is a JSON filter:

```json
{
  "type": {
    "and": [
      {"deleted": false},
      {"and": [{"modificationDateRelativeRange": {"type": 0}}]}
    ]
  },
  "entity": "note"
}
```

## Encryption

Password-protected notes have `ZISPASSWORDPROTECTED = 1`. The note content in `ZICNOTEDATA.ZDATA` is encrypted. Decryption requires deriving a key from the user's password using PBKDF2, then unwrapping an AES-wrapped key, then decrypting the content with AES-GCM. The encrypted data, salt, iteration count, and wrapped key are stored in the database.

## Prior art

- [dunhamsteve/notesutils](https://github.com/dunhamsteve/notesutils) -- Early reverse engineering (2016), particularly the CRDT table structure and drawing stroke format
- [threeplanetssoftware/apple_cloud_notes_parser](https://github.com/threeplanetssoftware/apple_cloud_notes_parser) -- Ruby parser with encryption, iTunes/physical backup handling, and attachment support
