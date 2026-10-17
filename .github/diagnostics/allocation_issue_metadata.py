"""Read failed audit object metadata without changing the actual-page layout."""
from pathlib import Path
import subprocess
import sys

scope = sys.argv[1]
assert scope in ('actual', 'positive-control')
if scope == 'positive-control':
    subprocess.run([sys.executable, str(Path(__file__).with_name('allocation_form_scope.py')), 'control'], check=True)

path = Path('CardPilotUITests/CoreFlowsUITests.swift')
source = path.read_text()
marker = 'import UIKit\n'
assert source.count(marker) == 1
source = source.replace(marker, marker + 'import ObjectiveC\nimport Darwin\n', 1)
marker = '            self.add(attachment)\n            // An issue can have no associated element.'
assert source.count(marker) == 1
source = source.replace(marker, '''            self.add(attachment)
            let raw = XCTAttachment(string: allocationAuditMetadata(issue))
            raw.name = "allocation.audit.raw-issue"
            raw.lifetime = .keepAlways
            self.add(raw)
            // An issue can have no associated element.''', 1)
source += r'''
// Diagnostic evidence only. Never include runtime reflection in delivery code.
@MainActor
private func allocationAuditMetadata(_ issue: XCUIAccessibilityAuditIssue) -> String {
    var lines: [String] = []
    var seen = Set<ObjectIdentifier>()
    func inspect(_ object: AnyObject, path: String, depth: Int) {
        guard lines.count < 240, seen.insert(ObjectIdentifier(object)).inserted else { return }
        let type = String(reflecting: Swift.type(of: object))
        if let data = object as? NSData {
            lines.append("\(path): \(type) bytes=\(data.length)")
            return
        }
        lines.append("\(path): \(type) \(String(describing: object).prefix(1800))")
        guard depth < 3 else { return }
        if object is NSString || object is NSNumber || object is NSValue { return }
        if let dictionary = object as? NSDictionary {
            for key in dictionary.allKeys.map({ String(describing: $0) }).sorted().prefix(32) {
                if let value = dictionary[key] {
                    inspect(value as AnyObject, path: "\(path)[\(key)]", depth: depth + 1)
                }
            }
            return
        }
        if let array = object as? NSArray {
            for (index, child) in array.prefix(16).enumerated() {
                inspect(child as AnyObject, path: "\(path)[\(index)]", depth: depth + 1)
            }
            return
        }
        var currentClass: AnyClass? = object_getClass(object)
        while let cls = currentClass, NSStringFromClass(cls) != "NSObject" {
            var count: UInt32 = 0
            if let ivars = class_copyIvarList(cls, &count) {
                defer { free(ivars) }
                for index in 0..<min(Int(count), 32) {
                    let ivar = ivars[index]
                    guard let rawName = ivar_getName(ivar), let rawType = ivar_getTypeEncoding(ivar) else { continue }
                    let name = String(cString: rawName)
                    let encoding = String(cString: rawType)
                    lines.append("\(path).\(name): encoding=\(encoding)")
                    if encoding.hasPrefix("@"), let child = object_getIvar(object, ivar) {
                        inspect(child as AnyObject, path: "\(path).\(name)", depth: depth + 1)
                    }
                }
            }
            currentClass = class_getSuperclass(cls)
        }
    }
    inspect(issue, path: "issue", depth: 0)
    return lines.joined(separator: "\n")
}
'''
path.write_text(source)
