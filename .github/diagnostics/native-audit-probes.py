import re
from pathlib import Path
path = Path('CardPilotUITests/CoreFlowsUITests.swift')
source = path.read_text().replace('import UIKit\n', 'import UIKit\nimport ObjectiveC\n', 1)
helper = '''
    private func inspectNativeAuditIssue(_ issue: XCUIAccessibilityAuditIssue) {
        var entries = ["Issue reflection: \\(String(reflecting: issue))"]
        var visited = Set<ObjectIdentifier>()
        func inspect(_ object: AnyObject, depth: Int) {
            guard depth < 4, visited.insert(ObjectIdentifier(object)).inserted else { return }
            entries.append("Depth \\(depth): \\(String(reflecting: type(of: object)))")
            let mirror = Mirror(reflecting: object)
            for child in mirror.children {
                entries.append("mirror \\(child.label ?? "?"): \\(String(reflecting: child.value).prefix(4000))")
            }
            var currentClass: AnyClass? = object_getClass(object)
            while let type = currentClass, type != NSObject.self {
                var count: UInt32 = 0
                if let ivars = class_copyIvarList(type, &count) {
                    defer { free(ivars) }
                    for index in 0..<Int(count) {
                        let ivar = ivars[index]
                        let name = ivar_getName(ivar).map { String(cString: $0) } ?? "?"
                        let encoding = ivar_getTypeEncoding(ivar).map { String(cString: $0) } ?? "?"
                        if encoding.hasPrefix("@"), let value = object_getIvar(object, ivar) {
                            entries.append("ivar \\(name) [\\(encoding)]: \\(String(reflecting: value).prefix(8000))")
                            let className = String(reflecting: Swift.type(of: value))
                            if className.contains("Audit") || className.contains("AX") {
                                inspect(value as AnyObject, depth: depth + 1)
                            }
                        } else {
                            entries.append("ivar \\(name) [\\(encoding)]: nil or scalar")
                        }
                    }
                }
                var methodCount: UInt32 = 0
                if let methods = class_copyMethodList(type, &methodCount) {
                    defer { free(methods) }
                    entries.append("Selectors: " + (0..<Int(methodCount)).map {
                        NSStringFromSelector(method_getName(methods[$0]))
                    }.joined(separator: ", "))
                }
                currentClass = class_getSuperclass(type)
            }
        }
        inspect(issue, depth: 0)
        let attachment = XCTAttachment(string: entries.joined(separator: "\\n"))
        attachment.name = "原生审计内部诊断"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
'''
anchor = '    private func captureAccessibilityAuditContext(_ name: String) {'
assert source.count(anchor) == 1
source = source.replace(anchor, helper + '\n' + anchor, 1)
lines = source.splitlines(keepends=True)
source = ''.join((' ' * (len(line) - len(line.lstrip())) + 'self.inspectNativeAuditIssue(issue)\n' if line.lstrip().startswith('let details =') and 'issue.compactDescription' in line else '') + line for line in lines)
assert source.count('self.inspectNativeAuditIssue(issue)') >= 2
path.write_text(source)
print('Added read-only native issue reflection; no app source/layout changes.')
