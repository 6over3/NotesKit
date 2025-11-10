// This file is part of NotesKit.
// Copyright (c) 2025 6OVER3 Institute.
// Licensed under the GNU Affero General Public License v3.0.
// See LICENSE file for details.

/// Transcription of an audio recording.
public struct AudioTranscription: Equatable, Sendable {

  /// Individual transcript segments with timing information.
  public let segments: [TranscriptSegment]

  /// AI-generated summary of the recording.
  public let summary: String?

  /// Short/top-line summary of the recording.
  public let topLineSummary: String?

  /// Audio fragments (technical data about the recording).
  public let fragments: [AudioFragment]

  /// Full transcription text, concatenated from all segments.
  public var fullText: String {
    segments.map(\.text).joined(separator: " ")
  }

  /// Format the transcription as a readable string.
  public func formattedTranscript(
    includeTimestamps: Bool = true,
    includeSpeaker: Bool = true
  ) -> String {
    var result = ""

    if let summary = topLineSummary ?? summary {
      result += "Summary: \(summary)\n\n"
    }

    if includeTimestamps || includeSpeaker {
      for segment in segments {
        var line = ""
        if includeTimestamps {
          line += String(format: "[%.2fs] ", segment.timestamp)
        }
        if includeSpeaker, let speaker = segment.speaker, !speaker.isEmpty {
          line += "\(speaker): "
        }
        line += segment.text
        result += line + "\n"
      }
    } else {
      result = fullText
    }

    return result
  }

  /// Total duration based on the last segment.
  public var totalDuration: Double {
    guard let lastSegment = segments.last else { return 0.0 }
    return lastSegment.endTime
  }
}

/// A single segment of transcribed audio.
public struct TranscriptSegment: Equatable, Sendable {
  public let speaker: String?
  public let text: String
  public let timestamp: Double
  public let duration: Double

  public var endTime: Double { timestamp + duration }
}

/// An audio fragment (technical metadata).
public struct AudioFragment: Equatable, Sendable {
  public let timestamp: Double
  public let duration: Double
}
