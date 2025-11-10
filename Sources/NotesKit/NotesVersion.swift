// This file is part of NotesKit.
// Copyright (c) 2025 6OVER3 Institute.
// Licensed under the GNU Affero General Public License v3.0.
// See LICENSE file for details.

/// The schema version of the Notes database.
public enum NotesVersion: Int, Sendable {
  case v9 = 9
  case v10 = 10
  case v11 = 11
  case v12 = 12
  case v13 = 13
  case v14 = 14
  case v15 = 15
  case v16 = 16
  case v17 = 17
  case v18 = 18
  case unknown = -1

  public var displayName: String {
    if self == .unknown { return "Unknown" }
    return "Schema \(rawValue)"
  }
}
