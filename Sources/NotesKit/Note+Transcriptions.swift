// This file is part of NotesKit.
// Copyright (c) 2025 6OVER3 Institute.
// Licensed under the GNU Affero General Public License v3.0.
// See LICENSE file for details.

import Foundation
import SwiftProtobuf

// MARK: - Audio Transcription Extension

extension Note {

  /// Get the audio transcription for an audio recording attachment.
  ///
  /// - Parameter identifier: The audio attachment identifier.
  /// - Returns: The transcription data if available.
  /// - Throws: ``NotesError/queryFailed`` if parsing fails.
  internal func audioTranscription(for identifier: String) throws -> AudioTranscription? {
    guard let record = try database.fetchAttachment(identifier: identifier),
      let mergeableData = record.mergeableData
    else {
      return nil
    }

    let decompressed: Data
    if let gunzipped = mergeableData.gunzipped() {
      decompressed = gunzipped
    } else {
      decompressed = mergeableData
    }

    let objectData = try Notes_MergeableDataObjectData(
      serializedBytes: decompressed,
      extensions: nil,
      partial: true
    )

    return try parseAudioTranscription(from: objectData)
  }

  private func parseAudioTranscription(
    from objectData: Notes_MergeableDataObjectData
  ) throws -> AudioTranscription? {
    let keyItems = objectData.mergeableDataObjectKeyItem
    let typeItems = objectData.mergeableDataObjectTypeItem
    let objects = objectData.mergeableDataObjectEntry

    let audioRecording = findAudioRecordingObject(objects: objects, typeItems: typeItems)

    var transcriptSegments: [TranscriptSegment] = []
    var summary: String?
    var topLineSummary: String?
    var fragments: [AudioFragment] = []

    if let audioRecording = audioRecording {
      for mapEntry in audioRecording.customMap.mapEntry {
        let keyIndex = Int(mapEntry.key)
        guard keyIndex >= 0 && keyIndex < keyItems.count else { continue }
        let keyName = keyItems[keyIndex]

        if mapEntry.value.hasObjectIndex {
          let objectIndex = Int(mapEntry.value.objectIndex)
          guard objectIndex > 0 && objectIndex < objects.count else { continue }
          let valueObject = objects[objectIndex]

          switch keyName {
          case "summary":
            summary = extractString(from: valueObject, objects: objects)

          case "topLineSummary":
            topLineSummary = extractString(from: valueObject, objects: objects)

          default:
            break
          }
        }
      }
    }

    for object in objects {
      guard object.hasCustomMap else { continue }

      let typeIndex = Int(object.customMap.type)
      guard typeIndex >= 0 && typeIndex < typeItems.count else { continue }
      let typeName = typeItems[typeIndex]

      if typeName == "com.apple.notes.ICTTTranscriptSegment" {
        if let segment = parseSegmentDirect(
          from: object,
          objects: objects,
          keyItems: keyItems
        ) {
          transcriptSegments.append(segment)
        }
      }
    }

    for object in objects {
      guard object.hasCustomMap else { continue }

      let typeIndex = Int(object.customMap.type)
      guard typeIndex >= 0 && typeIndex < typeItems.count else { continue }
      let typeName = typeItems[typeIndex]

      if typeName == "com.apple.notes.ICTTAudioRecording.Fragment" {
        if let fragment = parseFragmentDirect(
          from: object,
          objects: objects,
          keyItems: keyItems
        ) {
          fragments.append(fragment)
        }
      }
    }

    transcriptSegments.sort { $0.timestamp < $1.timestamp }
    fragments.sort { $0.timestamp < $1.timestamp }

    guard !transcriptSegments.isEmpty || summary != nil else {
      return nil
    }

    return AudioTranscription(
      segments: transcriptSegments,
      summary: summary,
      topLineSummary: topLineSummary,
      fragments: fragments
    )
  }

  private func parseSegmentDirect(
    from object: Notes_MergeableDataObjectEntry,
    objects: [Notes_MergeableDataObjectEntry],
    keyItems: [String]
  ) -> TranscriptSegment? {
    var speaker: String?
    var text: String = ""
    var timestamp: Double = 0.0
    var duration: Double = 0.0

    guard object.hasCustomMap else { return nil }

    for mapEntry in object.customMap.mapEntry {
      let keyIndex = Int(mapEntry.key)
      guard keyIndex >= 0 && keyIndex < keyItems.count else { continue }
      let keyName = keyItems[keyIndex]

      if mapEntry.value.hasObjectIndex {
        let objectIndex = Int(mapEntry.value.objectIndex)
        guard objectIndex > 0 && objectIndex < objects.count else { continue }
        let valueObject = objects[objectIndex]

        switch keyName {
        case "speaker":
          speaker = extractString(from: valueObject, objects: objects)

        case "text":
          if let extracted = extractString(from: valueObject, objects: objects) {
            text = extracted
          }

        case "timestamp":
          timestamp = extractDouble(from: valueObject, objects: objects)

        case "duration":
          duration = extractDouble(from: valueObject, objects: objects)

        default:
          break
        }
      }
    }

    return TranscriptSegment(
      speaker: speaker,
      text: text,
      timestamp: timestamp,
      duration: duration
    )
  }

  private func parseFragmentDirect(
    from object: Notes_MergeableDataObjectEntry,
    objects: [Notes_MergeableDataObjectEntry],
    keyItems: [String]
  ) -> AudioFragment? {
    var timestamp: Double = 0.0
    var duration: Double = 0.0

    guard object.hasCustomMap else { return nil }

    for mapEntry in object.customMap.mapEntry {
      let keyIndex = Int(mapEntry.key)
      guard keyIndex >= 0 && keyIndex < keyItems.count else { continue }
      let keyName = keyItems[keyIndex]

      if mapEntry.value.hasObjectIndex {
        let objectIndex = Int(mapEntry.value.objectIndex)
        guard objectIndex > 0 && objectIndex < objects.count else { continue }
        let valueObject = objects[objectIndex]

        switch keyName {
        case "timestamp":
          timestamp = extractDouble(from: valueObject, objects: objects)

        case "duration":
          duration = extractDouble(from: valueObject, objects: objects)

        default:
          break
        }
      }
    }

    return AudioFragment(timestamp: timestamp, duration: duration)
  }

  private func findAudioRecordingObject(
    objects: [Notes_MergeableDataObjectEntry],
    typeItems: [String]
  ) -> Notes_MergeableDataObjectEntry? {
    for object in objects {
      if object.hasCustomMap {
        let typeIndex = Int(object.customMap.type)
        if typeIndex >= 0 && typeIndex < typeItems.count {
          if typeItems[typeIndex] == "com.apple.notes.ICTTAudioRecording" {
            return object
          }
        }
      }
    }
    return nil
  }

  private func extractString(
    from object: Notes_MergeableDataObjectEntry,
    objects: [Notes_MergeableDataObjectEntry]
  ) -> String? {
    var current = object

    if current.hasRegisterLatest, current.registerLatest.contents.hasObjectIndex {
      let idx = Int(current.registerLatest.contents.objectIndex)
      if idx > 0 && idx < objects.count {
        current = objects[idx]
      }
    }

    if current.hasNote {
      let text = current.note.noteText
      return text.isEmpty ? nil : text
    }

    if current.hasCustomMap {
      for entry in current.customMap.mapEntry {
        if entry.value.hasStringValue {
          let str = entry.value.stringValue
          return str.isEmpty ? nil : str
        }

        if entry.value.hasObjectIndex {
          let idx = Int(entry.value.objectIndex)
          if idx > 0 && idx < objects.count {
            if let nested = extractString(from: objects[idx], objects: objects) {
              return nested
            }
          }
        }
      }
    }

    return nil
  }

  private func extractDouble(
    from object: Notes_MergeableDataObjectEntry,
    objects: [Notes_MergeableDataObjectEntry]
  ) -> Double {
    var current = object

    if current.hasRegisterLatest, current.registerLatest.contents.hasObjectIndex {
      let idx = Int(current.registerLatest.contents.objectIndex)
      if idx > 0 && idx < objects.count {
        current = objects[idx]
      }
    }

    if current.hasCustomMap {
      for entry in current.customMap.mapEntry {
        if entry.value.hasDoubleValue {
          return entry.value.doubleValue
        }

        if entry.value.hasUnsignedIntegerValue {
          return Double(bitPattern: entry.value.unsignedIntegerValue)
        }

        if entry.value.hasObjectIndex {
          let idx = Int(entry.value.objectIndex)
          if idx > 0 && idx < objects.count {
            return extractDouble(from: objects[idx], objects: objects)
          }
        }
      }
    }

    return 0.0
  }
}
