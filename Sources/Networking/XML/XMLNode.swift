import Foundation

/// A minimal generic XML tree, built to mirror how the reference Node
/// server's `xml2js` parses Cotral's responses: every child tag becomes an
/// array under its tag name (so repeated elements — poles, transits,
/// positions — come back as lists), while a tag's own attributes and text
/// content are kept alongside its children. We don't need XML namespaces,
/// mixed content, or anything else beyond what Cotral's own responses use.
final class XMLNode {
    let name: String
    var attributes: [String: String] = [:]
    var text: String = ""
    var children: [String: [XMLNode]] = [:]

    init(name: String) {
        self.name = name
    }

    func firstChild(_ tag: String) -> XMLNode? {
        children[tag]?.first
    }

    /// Text content of the first child with this tag, or "" if absent —
    /// Cotral's own fields are consistently non-optional strings.
    func childText(_ tag: String) -> String {
        firstChild(tag)?.text ?? ""
    }
}

enum XMLNodeParser {
    /// Cotral sometimes returns just a dangling closing tag (e.g. `</transiti>`)
    /// for an unknown/no-data query — treat that (and a genuinely empty body)
    /// as "no data" instead of failing to parse, matching the reference
    /// server's own `parseCotralXmlResponse` handling.
    static func parse(_ data: Data) -> XMLNode? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.range(of: #"^</[A-Za-z][\w:.-]*>$"#, options: .regularExpression) != nil {
            return nil
        }

        let delegate = Delegate()
        let parser = Foundation.XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { return nil }
        return delegate.root
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        private var stack: [XMLNode] = []
        fileprivate var root: XMLNode?

        func parser(_ parser: Foundation.XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            let node = XMLNode(name: elementName)
            node.attributes = attributeDict
            stack.append(node)
        }

        func parser(_ parser: Foundation.XMLParser, foundCharacters string: String) {
            stack.last?.text += string
        }

        func parser(_ parser: Foundation.XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            guard let finished = stack.popLast() else { return }
            finished.text = finished.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let parent = stack.last {
                parent.children[elementName, default: []].append(finished)
            } else {
                root = finished
            }
        }
    }
}
