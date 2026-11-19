import Foundation

/// Interpreta las expresiones de split de la matriz respetando su estructura:
/// bloques separados por `/`, grupos entre paréntesis y multiplicadores `x2`/`x3`.
///
/// No existe ninguna tabla de equivalencias oculta: solo se aceptan los nombres
/// de rutina del catálogo y las variantes de escritura documentadas en la matriz
/// (`hamsting`, `hams`, `fullbody`, `chestback`, `lower/cames`).
enum SplitExpressionParser {
    /// Convierte una expresión en la lista ordenada de rutinas de la semana.
    /// Cada elemento representa una sesión; un multiplicador repite el bloque.
    static func parse(_ expression: String) throws -> [CatalogRoutine] {
        let compact: String = canonicalize(expression)
        guard !compact.isEmpty else {
            throw SplitGenerationError.unknownBlock(expression)
        }

        var sessions: [CatalogRoutine] = []

        for part in splitTopLevel(compact) {
            if part.hasPrefix("(") {
                guard let group = parseGroup(part) else {
                    throw SplitGenerationError.unknownBlock(part)
                }

                guard group.times >= 1, group.times <= 3 else {
                    throw SplitGenerationError.tooManyRepetitions(expression)
                }

                let innerTokens: [String] = splitTopLevel(group.body)
                guard !innerTokens.isEmpty else {
                    throw SplitGenerationError.unknownBlock(part)
                }

                for _ in 0..<group.times {
                    for token in innerTokens {
                        sessions.append(try routine(for: token))
                    }
                }
            } else {
                let split = splitMultiplier(part)
                guard split.times >= 1, split.times <= 3 else {
                    throw SplitGenerationError.tooManyRepetitions(expression)
                }

                let parsed: CatalogRoutine = try routine(for: split.base)
                for _ in 0..<split.times {
                    sessions.append(parsed)
                }
            }
        }

        guard !sessions.isEmpty else {
            throw SplitGenerationError.unknownBlock(expression)
        }

        return sessions
    }

    // MARK: - Normalización

    /// Minúsculas, sin acentos, sin espacios. Protege `Chest+Back` y
    /// `Lower/cames` antes de separar por `/` o `+`.
    private static func canonicalize(_ expression: String) -> String {
        let folded: String = expression.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )

        let withoutWhitespace: String = folded
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()

        return withoutWhitespace
            .replacingOccurrences(of: "lower/cames", with: "lower")
            .replacingOccurrences(of: "chest+back", with: "chestback")
    }

    /// Divide por `/` y `+` solo cuando no estamos dentro de un paréntesis.
    private static func splitTopLevel(_ text: String) -> [String] {
        var parts: [String] = []
        var current: String = ""
        var depth: Int = 0

        for character in text {
            if character == "(" {
                depth += 1
                current.append(character)
            } else if character == ")" {
                depth -= 1
                current.append(character)
            } else if (character == "/" || character == "+") && depth == 0 {
                if !current.isEmpty {
                    parts.append(current)
                }
                current = ""
            } else {
                current.append(character)
            }
        }

        if !current.isEmpty {
            parts.append(current)
        }

        return parts
    }

    /// `(Push/Pull) x2` → cuerpo `Push/Pull`, 2 repeticiones.
    private static func parseGroup(_ part: String) -> (body: String, times: Int)? {
        guard part.hasPrefix("("), let close: String.Index = part.firstIndex(of: ")") else {
            return nil
        }

        let body: String = String(part[part.index(after: part.startIndex)..<close])
        let suffix: String = String(part[part.index(after: close)...])

        if suffix.isEmpty {
            return (body, 1)
        }

        guard suffix.hasPrefix("x"), let times: Int = Int(suffix.dropFirst()) else {
            return nil
        }

        return (body, times)
    }

    /// `legsx3` → `legs`, 3 repeticiones. El multiplicador nunca se confunde
    /// con el número de ejercicios de una sesión.
    private static func splitMultiplier(_ token: String) -> (base: String, times: Int) {
        guard let xIndex: String.Index = token.lastIndex(of: "x") else {
            return (token, 1)
        }

        let suffix: String = String(token[token.index(after: xIndex)...])
        guard let times: Int = Int(suffix) else {
            return (token, 1)
        }

        let base: String = String(token[..<xIndex])
        guard !base.isEmpty else {
            return (token, 1)
        }

        return (base, times)
    }

    private static func routine(for token: String) throws -> CatalogRoutine {
        let normalized: String = token.replacingOccurrences(
            of: "[^a-z0-9]",
            with: "",
            options: .regularExpression
        )

        guard let routine: CatalogRoutine = CatalogRoutine.fromNormalizedToken(normalized) else {
            throw SplitGenerationError.unknownBlock(token)
        }

        return routine
    }
}
