# Investigating the Notes database

How to poke around the Apple Notes SQLite database -- finding undocumented fields, verifying assumptions, debugging parsing.

## Opening the database

```bash
DB=~/Library/Group\ Containers/group.com.apple.notes/NoteStore.sqlite
sqlite3 "$DB"
```

Open read-only to avoid corruption:
```bash
sqlite3 "file:$DB?mode=ro"
```

## Orientation

### tables

```sql
.tables
```

Two tables matter: `ZICCLOUDSYNCINGOBJECT` (everything) and `ZICNOTEDATA` (note content blobs). Also useful: `ZICLOCATION` (GPS coords), `Z_PRIMARYKEY` (entity type mapping).

### Entity types

Everything lives in `ZICCLOUDSYNCINGOBJECT`, `Z_ENT` tells you what kind of thing it is:

```sql
SELECT Z_ENT, Z_NAME FROM Z_PRIMARYKEY ORDER BY Z_ENT;
```

| Z_ENT | Name | Description |
|-------|------|-------------|
| 5 | ICAttachment | File/media attachments |
| 6 | ICAttachmentPreviewImage | Thumbnails |
| 9 | ICInlineAttachment | Hashtags, mentions, math results |
| 11 | ICMedia | Media file records (filename, dimensions) |
| 12 | ICNote | Notes |
| 14 | ICAccount | iCloud/Exchange accounts |
| 15 | ICFolder | Folders and smart folders |

Count records by type:
```sql
SELECT pk.Z_NAME, COUNT(o.Z_PK)
FROM ZICCLOUDSYNCINGOBJECT o
JOIN Z_PRIMARYKEY pk ON o.Z_ENT = pk.Z_ENT
GROUP BY pk.Z_NAME
ORDER BY COUNT(o.Z_PK) DESC;
```

## Exploring the schema

### List all columns

```sql
PRAGMA table_info(ZICCLOUDSYNCINGOBJECT);
```

The schema changes with each iOS release. Columns are never removed, only added. New columns appear at the end.

### Find columns you might be missing

Check for non-null blob columns you aren't reading:

```sql
SELECT name FROM pragma_table_info('ZICCLOUDSYNCINGOBJECT')
WHERE type = 'BLOB'
AND name NOT IN ('ZMERGEABLEDATA', 'ZMERGEABLEDATA1', 'ZSERVERRECORDDATA', ...);
```

Find columns with actual data:
```sql
-- For a specific entity type (e.g. notes = 12)
SELECT name, COUNT(*) as non_null
FROM pragma_table_info('ZICCLOUDSYNCINGOBJECT') AS cols,
     ZICCLOUDSYNCINGOBJECT AS obj
WHERE obj.Z_ENT = 12
  AND CASE WHEN cols.type = 'BLOB' THEN obj.[name] IS NOT NULL
           WHEN cols.type = 'VARCHAR' THEN obj.[name] IS NOT NULL AND obj.[name] != ''
           ELSE obj.[name] IS NOT NULL AND obj.[name] != 0
      END
GROUP BY name
ORDER BY non_null DESC;
```

This doesn't work as a single query because SQLite can't dynamically reference columns. Instead, generate checks:

```bash
DB=~/Library/Group\ Containers/group.com.apple.notes/NoteStore.sqlite
sqlite3 "$DB" "PRAGMA table_info(ZICCLOUDSYNCINGOBJECT);" | while IFS='|' read -r _ name type _ _ _; do
  count=$(sqlite3 "$DB" "SELECT COUNT(*) FROM ZICCLOUDSYNCINGOBJECT WHERE Z_ENT=12 AND \"$name\" IS NOT NULL AND \"$name\" != 0 AND \"$name\" != '';" 2>/dev/null)
  if [ "$count" -gt 0 ] 2>/dev/null; then
    echo "$count	$name	$type"
  fi
done | sort -rn
```

This shows every column that has data for notes (Z_ENT=12), sorted by how many records use it.

## Common investigations

### What UTI types exist?

```sql
SELECT COALESCE(ZTYPEUTI1, ZTYPEUTI) as UTI, COUNT(*)
FROM ZICCLOUDSYNCINGOBJECT
WHERE UTI IS NOT NULL
GROUP BY UTI
ORDER BY COUNT(*) DESC;
```

### How are attachments linked to notes?

Through protobuf content, not SQL foreign keys. The protobuf `AttachmentInfo.attachmentIdentifier` matches `ZICCLOUDSYNCINGOBJECT.ZIDENTIFIER`.

To find which note owns an attachment:
```sql
-- Via the ZNOTE foreign key on attachment records
SELECT a.ZIDENTIFIER as ATTACHMENT_ID,
       COALESCE(a.ZTYPEUTI1, a.ZTYPEUTI) as UTI,
       n.ZIDENTIFIER as NOTE_ID,
       COALESCE(n.ZTITLE1, n.ZTITLE) as NOTE_TITLE
FROM ZICCLOUDSYNCINGOBJECT a
JOIN ZICCLOUDSYNCINGOBJECT n ON a.ZNOTE = n.Z_PK
WHERE a.Z_ENT = 5;
```

### How does media link to attachments?


```sql
SELECT a.ZIDENTIFIER as ATTACHMENT,
       COALESCE(a.ZTYPEUTI1, a.ZTYPEUTI) as UTI,
       m.ZIDENTIFIER as MEDIA_ID,
       m.ZFILENAME
FROM ZICCLOUDSYNCINGOBJECT a
JOIN ZICCLOUDSYNCINGOBJECT m ON a.ZMEDIA = m.Z_PK
WHERE a.Z_ENT = 5;
```

### Inline attachments

```sql
SELECT COALESCE(ZTYPEUTI1, ZTYPEUTI) as UTI,
       ZALTTEXT,
       ZTOKENCONTENTIDENTIFIER
FROM ZICCLOUDSYNCINGOBJECT
WHERE Z_ENT = 9;
```

### Which title column has data?

Column name varies by version (`ZTITLE`, `ZTITLE1`, `ZTITLE2`):
```sql
SELECT ZIDENTIFIER,
       ZTITLE, ZTITLE1, ZTITLE2
FROM ZICCLOUDSYNCINGOBJECT
WHERE Z_ENT = 12
AND (ZTITLE IS NOT NULL OR ZTITLE1 IS NOT NULL OR ZTITLE2 IS NOT NULL)
LIMIT 5;
```

### Smart folders


```sql
SELECT COALESCE(ZTITLE2, ZTITLE1, ZTITLE) as NAME,
       ZFOLDERTYPE,
       ZSMARTFOLDERQUERYJSON
FROM ZICCLOUDSYNCINGOBJECT
WHERE Z_ENT = 15;
```

`ZFOLDERTYPE`: 0 = regular, 1 = trash, 2 = smart folder.

### Encryption columns


```sql
SELECT ZIDENTIFIER,
       ZCRYPTOITERATIONCOUNT,
       length(ZCRYPTOSALT) as SALT_LEN,
       length(ZCRYPTOWRAPPEDKEY) as KEY_LEN,
       length(ZCRYPTOINITIALIZATIONVECTOR) as IV_LEN,
       length(ZCRYPTOTAG) as TAG_LEN
FROM ZICCLOUDSYNCINGOBJECT
WHERE ZISPASSWORDPROTECTED = 1;
```

For encrypted note data:
```sql
SELECT nd.Z_PK,
       length(nd.ZDATA) as DATA_LEN,
       length(nd.ZCRYPTOINITIALIZATIONVECTOR) as IV_LEN,
       length(nd.ZCRYPTOTAG) as TAG_LEN
FROM ZICNOTEDATA nd
JOIN ZICCLOUDSYNCINGOBJECT n ON n.ZNOTEDATA = nd.Z_PK
WHERE n.ZISPASSWORDPROTECTED = 1;
```

## Inspecting protobuf blobs

### Dump raw protobuf

Extract and decompress:
```bash
sqlite3 "$DB" "SELECT hex(ZDATA) FROM ZICNOTEDATA WHERE Z_PK = 1;" | xxd -r -p | python3 -c "import sys,zlib; sys.stdout.buffer.write(zlib.decompress(sys.stdin.buffer.read(), 16+zlib.MAX_WBITS))" > note.bin
```

Decode with protoc:
```bash
protoc --decode_raw < note.bin
```

Or decode with the schema:
```bash
protoc --decode=notes.NoteStoreProto -I protos protos/notes.proto < note.bin
```

### Dump mergeable data (tables/drawings)


```bash
# Get the ZMERGEABLEDATA for a specific attachment
sqlite3 "$DB" "SELECT hex(COALESCE(ZMERGEABLEDATA1, ZMERGEABLEDATA)) FROM ZICCLOUDSYNCINGOBJECT WHERE ZIDENTIFIER = 'YOUR-UUID';" | xxd -r -p | python3 -c "import sys,zlib; sys.stdout.buffer.write(zlib.decompress(sys.stdin.buffer.read(), 16+zlib.MAX_WBITS))" > mergeable.bin
protoc --decode_raw < mergeable.bin
```

### Find unknown protobuf fields

`--decode_raw` shows all field numbers. Compare against the `.proto` schema -- unknown fields show up as bare numbers:
```bash
protoc --decode_raw < note.bin | grep -E "^[0-9]+:"
# vs
protoc --decode=notes.NoteStoreProto -I protos protos/notes.proto < note.bin
```

Fields that appear in `--decode_raw` but not in the typed decode are candidates for schema updates.

## Version detection

Check which version-specific columns exist:
```sql
-- iOS 18
SELECT COUNT(*) FROM pragma_table_info('ZICCLOUDSYNCINGOBJECT') WHERE name = 'ZUNAPPLIEDENCRYPTEDRECORDDATA';

-- iOS 17
SELECT COUNT(*) FROM pragma_table_info('ZICCLOUDSYNCINGOBJECT') WHERE name = 'ZGENERATION';

-- iOS 16
SELECT COUNT(*) FROM pragma_table_info('ZICCLOUDSYNCINGOBJECT') WHERE name = 'ZTYPEUTI1';
```

## Tips

- Always open read-only. Notes.app holds a write lock and WAL checkpointing can corrupt if both write.
- `ZMARKEDFORDELETION = 1` means "Recently Deleted" or pending permanent deletion. Filter these unless you want deleted items.
- Dates are Core Data timestamps (seconds since 2001-01-01). Convert: `datetime(ZMODIFICATIONDATE1 + 978307200, 'unixepoch')`.
- `Z_OPT` is CoreData's optimistic locking counter. Higher = more edits.
- Preview images (Z_ENT=6) are stored on disk, not in the database. `ZATTACHMENT` links back to the attachment's `Z_PK`.
