import Foundation

// Plot objects and the bounded math they evaluate (ticket 016). Pure Foundation:
// the validator checks a plot's source with the same parser the renderer uses.

/// The editable source of a `plot` object, one item per line:
///
///     title: Parabola        (optional)
///     y = x^2                (1 to 4 functions of x; "f(x) =" or no prefix also work)
///     x: -5 .. 5             (optional, default -10 .. 10)
///     y: -2 .. 10            (optional, default fits the curves)
struct PlotSpec: Equatable, Sendable {
    static let maxFunctions = 4
    static let maxSourceBytes = 2 * 1024
    static let maxRangeMagnitude = 1e6
    static let defaultX = -10.0...10.0

    var title: String?
    var functions: [String]
    var xRange: ClosedRange<Double>
    var yRange: ClosedRange<Double>?

    enum ParseError: Error, Equatable { case empty, tooLong, tooManyFunctions, badRange(String), badExpression(String) }

    static func parse(_ source: String) throws -> PlotSpec {
        guard source.utf8.count <= maxSourceBytes else { throw ParseError.tooLong }
        var title: String?, functions: [String] = [], xRange: ClosedRange<Double>?, yRange: ClosedRange<Double>?
        for raw in source.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let lower = line.lowercased()
            if lower.hasPrefix("title:") {
                title = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if lower.hasPrefix("x:") {
                xRange = try range(String(line.dropFirst(2)))
            } else if lower.hasPrefix("y:") {
                let text = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                yRange = text.lowercased() == "auto" ? nil : try range(text)
            } else {
                let expression = stripLeftSide(line)
                do { _ = try MathExpression(expression) } catch { throw ParseError.badExpression(expression) }
                functions.append(expression)
            }
        }
        guard !functions.isEmpty else { throw ParseError.empty }
        guard functions.count <= maxFunctions else { throw ParseError.tooManyFunctions }
        return PlotSpec(title: title?.isEmpty == true ? nil : title, functions: functions,
                        xRange: xRange ?? defaultX, yRange: yRange)
    }

    /// "y = x^2" and "f(x) = x^2" become "x^2"; a bare expression stays as it is.
    private static func stripLeftSide(_ line: String) -> String {
        guard let equals = line.firstIndex(of: "=") else { return line }
        let left = line[..<equals].replacingOccurrences(of: " ", with: "")
        let isName = left.range(of: #"^[A-Za-z][A-Za-z0-9_]*(\(x\))?$"#, options: .regularExpression) != nil
        return isName ? line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces) : line
    }

    /// "a .. b", "a..b", "a to b" or "a, b"; finite, ordered and bounded.
    private static func range(_ text: String) throws -> ClosedRange<Double> {
        let parts = text.replacingOccurrences(of: "..", with: ",").replacingOccurrences(of: " to ", with: ",")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let low = try? MathExpression(parts[0]).evaluate(x: 0),
              let high = try? MathExpression(parts[1]).evaluate(x: 0),
              low.isFinite, high.isFinite, low < high,
              abs(low) <= maxRangeMagnitude, abs(high) <= maxRangeMagnitude else { throw ParseError.badRange(text) }
        return low...high
    }
}

/// A function of `x` built from numbers, `x`, `pi`, `e`, + − × ÷ ^, parentheses and
/// one-argument functions. Never evaluates code; unknown names are errors.
/// Implicit multiplication works: `2x`, `3sin(x)`, `(x+1)(x-1)`.
struct MathExpression: Sendable {
    static let maxLength = 256
    static let maxDepth = 32

    enum ParseError: Error, Equatable { case tooLong, unexpected(String), unknownName(String), tooDeep }

    private indirect enum Node: Sendable {
        case number(Double), variable
        case unary(Character, Node), binary(Character, Node, Node), call(String, Node)
    }

    static let functions: [String: @Sendable (Double) -> Double] = [
        "sin": sin, "cos": cos, "tan": tan, "asin": asin, "acos": acos, "atan": atan,
        "arcsin": asin, "arccos": acos, "arctan": atan, "sinh": sinh, "cosh": cosh, "tanh": tanh,
        "sqrt": { $0.squareRoot() }, "abs": { Swift.abs($0) }, "exp": exp, "ln": log, "log": log10,
        "log10": log10, "log2": log2, "floor": { $0.rounded(.down) }, "ceil": { $0.rounded(.up) },
        "sec": { 1 / cos($0) }, "csc": { 1 / sin($0) }, "cot": { 1 / tan($0) },
    ]

    private let root: Node

    init(_ text: String) throws {
        guard text.count <= Self.maxLength else { throw ParseError.tooLong }
        var parser = Parser(tokens: try Self.tokenize(text))
        root = try parser.expression(depth: 0)
        guard parser.index == parser.tokens.count else { throw ParseError.unexpected(parser.tokens[parser.index].text) }
    }

    func evaluate(x: Double) throws -> Double { Self.evaluate(root, x: x) }

    private static func evaluate(_ node: Node, x: Double) -> Double {
        switch node {
        case .number(let value): value
        case .variable: x
        case .unary(_, let operand): -evaluate(operand, x: x)
        case .call(let name, let argument): functions[name]!(evaluate(argument, x: x))
        case .binary(let op, let left, let right):
            switch op {
            case "+": evaluate(left, x: x) + evaluate(right, x: x)
            case "-": evaluate(left, x: x) - evaluate(right, x: x)
            case "*": evaluate(left, x: x) * evaluate(right, x: x)
            case "/": evaluate(left, x: x) / evaluate(right, x: x)
            default: pow(evaluate(left, x: x), evaluate(right, x: x))
            }
        }
    }

    // MARK: - Tokens

    private struct Token: Equatable {
        enum Kind: Equatable { case number(Double), name(String), op(Character), open, close }
        var kind: Kind
        var text: String
    }

    private static func tokenize(_ text: String) throws -> [Token] {
        let normalized = text.replacingOccurrences(of: "**", with: "^")
            .replacingOccurrences(of: "π", with: "pi").replacingOccurrences(of: "·", with: "*")
            .replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "\\", with: "")
        var tokens: [Token] = []
        var index = normalized.startIndex
        while index < normalized.endIndex {
            let character = normalized[index]
            if character.isWhitespace { index = normalized.index(after: index); continue }
            if character.isNumber || character == "." {
                var end = index
                while end < normalized.endIndex, normalized[end].isNumber || normalized[end] == "." { end = normalized.index(after: end) }
                let text = String(normalized[index..<end])
                guard let value = Double(text) else { throw ParseError.unexpected(text) }
                tokens.append(Token(kind: .number(value), text: text))
                index = end
            } else if character.isLetter {
                var end = index
                while end < normalized.endIndex, normalized[end].isLetter || normalized[end].isNumber { end = normalized.index(after: end) }
                tokens.append(contentsOf: try names(String(normalized[index..<end])))
                index = end
            } else if "+-*/^".contains(character) {
                tokens.append(Token(kind: .op(character), text: String(character)))
                index = normalized.index(after: index)
            } else if character == "(" || character == "[" || character == "{" {
                tokens.append(Token(kind: .open, text: "("))
                index = normalized.index(after: index)
            } else if character == ")" || character == "]" || character == "}" {
                tokens.append(Token(kind: .close, text: ")"))
                index = normalized.index(after: index)
            } else {
                throw ParseError.unexpected(String(character))
            }
        }
        return tokens
    }

    /// Splits a run of letters into known names, so "xsin" is x·sin and "2pix" is 2·pi·x.
    private static func names(_ word: String) throws -> [Token] {
        let known = Set(functions.keys).union(["x", "pi", "e"])
        if known.contains(word) { return [Token(kind: .name(word), text: word)] }
        var result: [Token] = [], rest = Substring(word)
        while !rest.isEmpty {
            guard let match = known.sorted(by: { $0.count > $1.count }).first(where: { rest.hasPrefix($0) }) else {
                throw ParseError.unknownName(word)
            }
            result.append(Token(kind: .name(match), text: match))
            rest = rest.dropFirst(match.count)
        }
        return result
    }

    // MARK: - Grammar
    // expression = term (("+" | "-") term)*
    // term       = unary (("*" | "/") unary | implicit-unary)*
    // unary      = "-" unary | "+" unary | power
    // power      = atom ("^" unary)?
    // atom       = number | "x" | "pi" | "e" | name atom | "(" expression ")"

    private struct Parser {
        let tokens: [Token]
        var index = 0

        mutating func expression(depth: Int) throws -> Node {
            guard depth <= MathExpression.maxDepth else { throw ParseError.tooDeep }
            var node = try term(depth: depth)
            while let token = peek, case .op(let op) = token.kind, op == "+" || op == "-" {
                index += 1
                node = .binary(op, node, try term(depth: depth))
            }
            return node
        }

        mutating func term(depth: Int) throws -> Node {
            var node = try unary(depth: depth)
            while let token = peek {
                if case .op(let op) = token.kind, op == "*" || op == "/" {
                    index += 1
                    node = .binary(op, node, try unary(depth: depth))
                } else if startsAtom(token) {
                    node = .binary("*", node, try power(depth: depth))
                } else { break }
            }
            return node
        }

        mutating func unary(depth: Int) throws -> Node {
            guard depth <= MathExpression.maxDepth else { throw ParseError.tooDeep }
            if let token = peek, case .op(let op) = token.kind, op == "-" || op == "+" {
                index += 1
                let operand = try unary(depth: depth + 1)
                return op == "-" ? .unary("-", operand) : operand
            }
            return try power(depth: depth)
        }

        mutating func power(depth: Int) throws -> Node {
            let base = try atom(depth: depth)
            if let token = peek, case .op("^") = token.kind {
                index += 1
                return .binary("^", base, try unary(depth: depth + 1))
            }
            return base
        }

        mutating func atom(depth: Int) throws -> Node {
            guard let token = peek else { throw ParseError.unexpected("end") }
            index += 1
            switch token.kind {
            case .number(let value): return .number(value)
            case .name("x"): return .variable
            case .name("pi"): return .number(.pi)
            case .name("e"): return .number(M_E)
            case .name(let name):
                // sin x, sin(x), sin 2x: the argument is the next atom, with any power.
                return .call(name, try power(depth: depth + 1))
            case .open:
                let inner = try expression(depth: depth + 1)
                guard let close = peek, close.kind == .close else { throw ParseError.unexpected(peek?.text ?? "end") }
                index += 1
                return inner
            default:
                throw ParseError.unexpected(token.text)
            }
        }

        var peek: Token? { index < tokens.count ? tokens[index] : nil }

        func startsAtom(_ token: Token) -> Bool {
            switch token.kind {
            case .number, .name, .open: true
            default: false
            }
        }
    }
}
