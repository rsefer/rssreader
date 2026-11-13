import Foundation

enum ArticleSummaryText {
	static let maximumChunkBytes = 2_400

	static func chunks(_ text: String) -> [String] {
		var chunks: [String] = []
		let scalars = text.unicodeScalars
		var start = scalars.startIndex

		while start < scalars.endIndex {
			var end = start
			var lastWhitespace: String.Index?
			var byteCount = 0

			while end < scalars.endIndex {
				let scalar = scalars[end]
				let size = String(scalar).utf8.count
				if byteCount + size > maximumChunkBytes { break }
				byteCount += size
				end = scalars.index(after: end)
				if scalar.properties.isWhitespace { lastWhitespace = end }
			}

			if end < scalars.endIndex, let lastWhitespace, lastWhitespace > start {
				end = lastWhitespace
			}
			chunks.append(String(text[start..<end]))
			start = end
		}

		return chunks
	}
}
