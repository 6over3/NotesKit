// This file is part of NotesKit.
// Copyright (c) 2025 6OVER3 Institute.
// Licensed under the GNU Affero General Public License v3.0.
// See LICENSE file for details.

import Foundation
import zlib

extension Data {
  internal func gunzipped() -> Data? {
    guard !isEmpty else { return self }

    var decompressed = Data()
    let bufferSize = 4096
    var buffer = [UInt8](repeating: 0, count: bufferSize)

    return self.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> Data? in
      guard let baseAddress = bytes.baseAddress else { return nil }

      var stream = z_stream()
      stream.next_in = UnsafeMutablePointer<UInt8>(
        mutating: baseAddress.assumingMemoryBound(to: UInt8.self)
      )
      stream.avail_in = UInt32(self.count)

      let windowBits: Int32 = 15 + 16
      guard
        inflateInit2_(
          &stream,
          windowBits,
          ZLIB_VERSION,
          Int32(MemoryLayout<z_stream>.size)
        ) == Z_OK
      else {
        return nil
      }
      defer { inflateEnd(&stream) }

      repeat {
        let status = buffer.withUnsafeMutableBytes { bufferPtr -> Int32 in
          stream.next_out = bufferPtr.baseAddress?.assumingMemoryBound(to: UInt8.self)
          stream.avail_out = UInt32(bufferSize)
          return inflate(&stream, Z_NO_FLUSH)
        }

        if status == Z_STREAM_END || status == Z_OK {
          let decompressedSize = bufferSize - Int(stream.avail_out)
          decompressed.append(buffer, count: decompressedSize)
        } else if status != Z_BUF_ERROR {
          return nil
        }
      } while stream.avail_out == 0

      return decompressed
    }
  }
}
