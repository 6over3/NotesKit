# Extracting protobuf schemas from iCloud Notes

Apple ships the protobuf schemas to the iCloud web client. When they update the Notes format, new fields show up here first.

## Steps

1. Sign into [icloud.com/notes](https://www.icloud.com/notes)
2. Open browser Developer Tools (F12 or Cmd+Option+I)
3. Go to the Sources or Network tab
4. Search across all scripts for `proto2` or `TOPOTEXT_DEFINITION`

You'll find three schema definitions embedded as string literals in the JavaScript:

### TOPOTEXT_DEFINITION

The note content schema. Has `String`, `AttributeRun`, `ParagraphStyle`, `Font`, `Color`, `AttachmentInfo`, `Attachment`, `Location`, `Media`, `PreviewImage`, `Todo`, `BoxedValue`, `WallClockMergeableValue`.

Look for: `t.TOPOTEXT_DEFINITION = '\nsyntax = "proto2";`

### TOPOTEXT_DEFINITION_REMINDERS

A variant used for Reminders integration. Nearly identical to `TOPOTEXT_DEFINITION` but with a `HashtagInfo` message instead of system attachment fields.

Look for: `t.TOPOTEXT_DEFINITION_REMINDERS = '\nsyntax = "proto2";`

### CRDT document schema

The CRDT/mergeable data schema for tables, galleries, and other structured content. Has `ObjectID`, `Timestamp`, `RegisterLatest`, `VectorTimestamp`, `Dictionary`, `Index`, `OneOf`, `StringArray`, `Array`, `OrderedSet`, `Document`.

Look for: the third proto2 string, loaded via `loadProto(` with `"crframework.proto"`

### Versioned document wrapper

Small envelope schema wrapping all protobuf blobs:

```protobuf
message Document {
    optional uint32 serializationVersion = 1;
    repeated Version version = 2;
}
message Version {
    optional uint32 serializationVersion = 1;
    optional uint32 minimumSupportedVersion = 2;
    optional bytes data = 3;
}
```

Look for: loaded via `loadProto(` with `"versioned-document.proto"`

## Merging updates into NotesKit

When you find new fields:

1. Compare the extracted `.proto` definitions against `protos/notes.proto`
2. Add new fields to `notes.proto` using snake_case naming (matching our convention, not Apple's camelCase)
3. Run `swift build` — the Swift Protobuf plugin auto-generates `Sources/NotesKit/Generated/notes.pb.swift`
4. Update `NoteParser.swift` to handle any new fields

### Differences to watch for

The iCloud schemas use camelCase field names (`attachmentIdentifier`), ours use snake_case (`attachment_identifier`). Protobuf wire format only cares about field numbers, so this doesn't matter.

Fields we've added beyond what Apple ships:
- `system_attachment_class_name` (field 3) and `system_attachment_data` (field 4) on `AttachmentInfo` — for system-provided inline attachments
- `emphasis_style` (field 14) on `AttributeRun` — emphasis formatting
- `system_attachment_info` (field 15) on `AttributeRun` — system attachment reference
- `writing_direction` on `ParagraphStyle` and `AttributeRun`
- `paragraph_hints`, `starting_list_item_number`, `block_quote`, `uuid` on `ParagraphStyle`

The schema lives at `protos/notes.proto`. The Swift Protobuf plugin generates `Sources/NotesKit/Generated/notes.pb.swift` from it at build time.

## Schema versions

What changed per release:

| iOS version | Additions |
|-------------|-------------------|
| 15 | Smart folder queries, paragraph UUID |
| 16 | `ZTYPEUTI1` column split |
| 17 | Generation-based file paths, `ZGENERATION` column |
| 18 | Encryption record data, system attachments, emphasis style |

## References

- The iCloud web client always has schemas from the latest shipping Notes version
- [dunhamsteve/notesutils](https://github.com/dunhamsteve/notesutils/blob/master/notes.md) -- original format docs (2016)
- [threeplanetssoftware/apple_cloud_notes_parser](https://github.com/threeplanetssoftware/apple_cloud_notes_parser) -- proto files derived from the web client
