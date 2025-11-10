// This file is part of NotesKit.
// Copyright (c) 2025 6OVER3 Institute.
// Licensed under the GNU Affero General Public License v3.0.
// See LICENSE file for details.

/// Broad category for a Uniform Type Identifier.
public enum UTICategory: Sendable {
  case audio
  case video
  case image
  case document
  case inlineAttachment
  case dynamic
  case other
}

/// Classify a UTI string into a broad category.
public enum UTIClassifier {

  /// Determine the broad category for a UTI string.
  public static func category(for uti: String) -> UTICategory {
    if uti.hasPrefix("dyn.") { return .dynamic }
    if uti.hasPrefix("com.apple.notes.inlinetextattachment") { return .inlineAttachment }
    if conformsToAudio(uti) { return .audio }
    if conformsToVideo(uti) { return .video }
    if conformsToImage(uti) { return .image }
    if conformsToDocument(uti) { return .document }
    return .other
  }

  private static func conformsToAudio(_ uti: String) -> Bool {
    switch uti {
    case "com.apple.m4a-audio",
      "com.microsoft.waveform-audio",
      "public.aiff-audio",
      "public.midi-audio",
      "public.mp3",
      "org.xiph.ogg-audio",
      "public.audio":
      true
    default:
      uti.hasPrefix("public.audio")
    }
  }

  private static func conformsToVideo(_ uti: String) -> Bool {
    switch uti {
    case "com.apple.m4v-video",
      "com.apple.protected-mpeg-4-video",
      "com.apple.protected-mpeg-4-audio",
      "com.apple.quicktime-movie",
      "public.avi",
      "public.mpeg",
      "public.mpeg-2-video",
      "public.mpeg-2-transport-stream",
      "public.mpeg-4",
      "public.mpeg-4-audio":
      true
    default:
      uti.hasPrefix("public.movie") || uti.hasPrefix("public.video")
    }
  }

  private static func conformsToImage(_ uti: String) -> Bool {
    switch uti {
    case "com.adobe.illustrator.ai-image",
      "com.adobe.photoshop-image",
      "com.adobe.raw-image",
      "com.apple.icns",
      "com.apple.macpaint-image",
      "com.apple.pict",
      "com.apple.quicktime-image",
      "com.apple.notes.sketch",
      "com.compuserve.gif",
      "com.ilm.openexr-image",
      "com.kodak.flashpix.image",
      "com.microsoft.bmp",
      "com.microsoft.ico",
      "com.sgi.sgi-image",
      "com.truevision.tga-image",
      "public.camera-raw-image",
      "public.fax",
      "public.heic",
      "public.jpeg",
      "public.jpeg-2000",
      "public.png",
      "public.svg-image",
      "public.tiff",
      "public.xbitmap-image",
      "org.webmproject.webp":
      true
    default:
      uti.hasPrefix("public.image")
    }
  }

  private static func conformsToDocument(_ uti: String) -> Bool {
    switch uti {
    case "com.apple.iwork.numbers.sffnumbers",
      "com.apple.iwork.pages.sffpages",
      "com.apple.iwork.keynote.sffkey",
      "com.apple.log",
      "com.apple.rtfd",
      "com.microsoft.word.doc",
      "com.microsoft.excel.xls",
      "com.microsoft.powerpoint.ppt",
      "com.netscape.javascript-source",
      "net.daringfireball.markdown",
      "net.openvpn.formats.ovpn",
      "org.idpf.epub-container",
      "org.oasis-open.opendocument.text",
      "org.openxmlformats.wordprocessingml.document",
      "com.adobe.pdf",
      "public.rtf",
      "public.plain-text":
      true
    default:
      false
    }
  }
}
