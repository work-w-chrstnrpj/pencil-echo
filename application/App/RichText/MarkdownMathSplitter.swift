import Foundation

/// Delimiters inside code spans/fences or escaped with a backslash stay literal.
/// Unclosed delimiters also stay literal; source is never rewritten on disk.
enum MarkdownMathSplitter {
    enum Segment: Equatable {
        case markdown(String)
        case math(String, display: Bool)
    }

    static func split(_ source: String) -> [Segment] {
        let chars = Array(source)
        var result: [Segment] = [], text = ""
        var index = 0
        func escaped(_ i: Int) -> Bool {
            var cursor = i, count = 0
            while cursor > 0, chars[cursor - 1] == "\\" { cursor -= 1; count += 1 }
            return count % 2 == 1
        }
        func flush() { if !text.isEmpty { result.append(.markdown(text)); text = "" } }
        while index < chars.count {
            let c = chars[index]
            if (c == "`" || c == "~"), !escaped(index) {
                var end = index
                while end < chars.count, chars[end] == c { end += 1 }
                let count = end - index
                if c == "`" || count >= 3 {
                    var closing = end
                    while closing < chars.count {
                        if chars[closing] == c, !escaped(closing) {
                            var next = closing
                            while next < chars.count, chars[next] == c { next += 1 }
                            if next - closing == count {
                                text += String(chars[index..<next]); index = next; break
                            }
                            closing = next
                        } else { closing += 1 }
                    }
                    if closing == chars.count { text += String(chars[index...]); index = chars.count }
                    continue
                }
            }
            guard c == "$", !escaped(index) else { text.append(c); index += 1; continue }
            let display = index + 1 < chars.count && chars[index + 1] == "$"
            let delimiter = display ? 2 : 1
            let start = index + delimiter
            if start >= chars.count || (!display && chars[start].isWhitespace) {
                text.append(c); index += 1; continue
            }
            var end = start, found: Int?
            while end < chars.count {
                if !display && chars[end] == "\n" { break }
                if chars[end] == "$", !escaped(end) {
                    let doubled = end + 1 < chars.count && chars[end + 1] == "$"
                    if display && doubled { found = end; break }
                    if !display && !doubled && end > start && !chars[end - 1].isWhitespace { found = end; break }
                    end += doubled ? 2 : 1
                } else { end += 1 }
            }
            if let end = found {
                flush()
                result.append(.math(String(chars[start..<end]), display: display))
                index = end + delimiter
            } else if display {
                text += String(chars[index...]); index = chars.count
            } else {
                // No closing delimiter before this line ends. Consume the scanned
                // range once, avoiding quadratic rescans of repeated unmatched dollars.
                text += String(chars[index..<end]); index = end
            }
        }
        flush()
        return result
    }
}
