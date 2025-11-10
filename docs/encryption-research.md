# Apple Notes encryption research

Reverse-engineered on macOS 26 (Darwin 25.3.0).

## Three cipher strategies

The NotesShared private framework (`/System/Library/PrivateFrameworks/NotesShared.framework`) defines these strategy classes:

| Strategy Class | cipherVersion | Framework Name | Key Size | IV Size | Tag Size |
|---|---|---|---|---|---|
| `ICNoteCryptoStrategyV1` | 0 | Cipher v1 | 16 | 12 | 16 |
| `ICNoteCryptoStrategyV1Neo` | 2 | Cipher v1 Neo | 32 | 32 | 16 |
| `ICNoteCryptoStrategyV2` | 1 | Cipher v2 | 32 | 32 | 16 |

`ICCipherNameForCipherVersion()` maps the integer to the display name. Note the counterintuitive ordering: cipherVersion 1 = "Cipher v2", cipherVersion 2 = "Cipher v1 Neo".

## Detection logic

```swift
if ZDATA starts with "bplist00" {
    // New format: parse ICEncryptionObject from NSKeyedArchive
    if metadata contains accountKeyIdentifier → V2 (unsupported)
    else → V1 Neo
} else {
    // V1: raw encrypted data, params in DB columns
}
```

Implemented in `NoteDecrypter.detectFormat(data:)`.

## V1 -- legacy (iOS 16 and earlier) [supported]

Crypto parameters stored directly in database columns:

| Parameter | Source |
|-----------|--------|
| Salt (16 bytes) | `ZICCLOUDSYNCINGOBJECT.ZCRYPTOSALT` |
| Iteration count | `ZICCLOUDSYNCINGOBJECT.ZCRYPTOITERATIONCOUNT` |
| Wrapped key (24 bytes) | `ZICCLOUDSYNCINGOBJECT.ZCRYPTOWRAPPEDKEY` |
| IV (12 bytes) | `ZICNOTEDATA.ZCRYPTOINITIALIZATIONVECTOR` |
| Tag (16 bytes) | `ZICNOTEDATA.ZCRYPTOTAG` |
| Ciphertext | `ZICNOTEDATA.ZDATA` |

Decryption:
1. PBKDF2-HMAC-SHA256(password, salt, iterations) → 16-byte KEK
2. AES Key Unwrap RFC 3394(wrappedKey, KEK) → 16-byte DEK
3. AES-128-GCM(DEK, IV, tag, ciphertext) → gzip-compressed protobuf

Reference: [elusivedata.io](https://elusivedata.io/decrypt-apple-notes-ios16/), [apple_cloud_notes_parser](https://github.com/threeplanetssoftware/apple_cloud_notes_parser)

## V1 Neo -- per-note password (macOS 15+) [supported]

Used when `ICAccountData.ZSUPPORTSV1NEO = 1`. Each note carries its own passphrase salt, iteration count, and wrapped key inside an `ICCryptoEncryptionObject` plist embedded in `ZICNOTEDATA.ZDATA`. No Keychain dependency, the password alone is enough.

### NSKeyedArchiver plist structure

`ZDATA` is an NSKeyedArchive. The `$objects` array contains:

| Index | UID Key | Contents |
|---|---|---|
| 0 | — | `$null` sentinel |
| 1 | — | Main dict (ICCryptoEncryptionObject) with UID refs |
| 2 | `unauthenticatedMetadata` | bplist: `passphraseSalt`, `passphraseIterationCount`, `passphraseHint` |
| 3 | `metadata` | bplist: `cipherVersion`, `objectIdentifier` — **this is the AAD** |
| 4 | `wrappedEncryptionKey` | 40-byte wrapped DEK |
| 5 | `encryptedData` | ciphertext + IV(32) + tag(16) |
| 6 | `$class` | Class name dict |

DB columns (`ZCRYPTOSALT`, `ZCRYPTOITERATIONCOUNT`, etc.) are stale placeholders on macOS 15+, all zeros or 16-byte fillers.

### encryptedData layout

```
encryptedData = [ ciphertext (N bytes) | IV (32 bytes) | tag (16 bytes) ]
where N = encryptedData.length - 48
```

Discovered by swizzling `ICAESCipherUtils._ic_decrypt:...` to intercept the actual parameters.

### Decryption

```
1. PBKDF2-HMAC-SHA256(password, salt_32, iterations) → 32-byte KEK
2. AES Key Unwrap RFC 3394(wrappedEncryptionKey_40, KEK) → 32-byte DEK
3. AES-256-GCM(DEK, IV, ciphertext, tag, AAD=metadata) → gzip-compressed protobuf
```

CryptoKit's `AES.GCM.Nonce` accepts 32-byte nonces.

### Test data (V1 Neo note "Needleinahaystack")

```
password: "jjkhehe"
salt (32): 1faf405b502ebdb2796842e6217fa4ca274b69ac1efae128bb09dfb04989c96d
iterations: 20000
KEK (32): 66c2ed1de7e3e94b63a39048edbb540b375b364ce9ffedce93d7dee4f930d576
wrappedKey (40): 3e7cc8825082cd508d4f51328a287b4df4c3763eb20bacd6748adc956d44d82071f34b4039c90fe5
DEK (32): e1d12f49ace8816f7334da221f0f7f149a266d6386de576b4d59a395d78afba2
encryptedData (195): 4c55d288a38c0600...
AAD (124): 62706c6973743030d2010203045d63697068657256657273696f6e...
decrypted (147): 1f8b0800... (gzip)
```

## V2 -- account key + Keychain (not supportable)

Used when `accountKeyIdentifier` is present in the metadata. These notes are encrypted with the device passcode, not a custom password. The per-note wrapped key is wrapped with a key from the Data Protection Keychain, not derivable from any password.

### Why V2 can't be supported

The password only verifies identity via the account passphrase verifier. It never touches the note encryption key. The actual key hierarchy:

```
Password → PBKDF2 → KEK → unwraps account verifier (password check only)
Per-note wrappedEncryptionKey → wrapped with Keychain key (accountKeyIdentifier)
```

The `accountKeyIdentifier` (e.g., `9F250D2D-E176-4140-B2A1-67D272B56D3C`) references a key in the Data Protection Keychain (`kSecUseDataProtectionKeychain`). Accessing it requires the `group.com.apple.notes` Keychain access group entitlement, which Apple won't grant to third-party apps.

Confirmed via `SecItemCopyMatching`:
- Regular keychain: `-25300` (errSecItemNotFound) — key isn't there
- Data Protection Keychain with access group: `-34018` (errSecMissingEntitlement)

The framework's `ICNoteCryptoStrategyV2` returns `canAuthenticate: NO` without the Keychain key.

### Possible alternative: iOS backup extraction

Unencrypted iTunes/Finder backups include keychain items as files. The `apple_cloud_notes_parser` project is [exploring this](https://github.com/threeplanetssoftware/apple_cloud_notes_parser/issues/158) but hit bugs in the Ruby OpenSSL gem. Only useful for backup forensics, not live database access.

### Database entities

| Entity | Key Columns |
|---|---|
| `ICAccount` (Z_ENT=14) | `ZCRYPTOSALT` (16B), `ZCRYPTOITERATIONCOUNT` (20000), `ZCRYPTOVERIFIER` (24B) |
| `ICAccountData` (Z_ENT=4) | `ZCRYPTOPASSPHRASEVERIFIER` (446B) — protobuf header + bplist with salt, iterations, hint, wrapped verifier |
| `ZICNOTEDATA` | `ZDATA` — NSKeyedArchive of ICEncryptionObject (same format as V1 Neo, but with `accountKeyIdentifier` set) |

## Implementation

`NoteDecrypter.swift` handles V1 and V1 Neo through a unified `Parameters` struct and `decrypt(password:parameters:)`. Format detection is automatic. V2 notes throw `unsupportedEncryption`.

```swift
note.parse(visitor: myVisitor, password: "secret")
note.markdown(password: "secret")
```

Errors:
- `passwordProtected` — no password provided for an encrypted note
- `wrongPassword` — password doesn't unwrap the key
- `unsupportedEncryption` — V2 note, requires Keychain access
- `decryptionFailed` — corrupt data or other crypto failure
