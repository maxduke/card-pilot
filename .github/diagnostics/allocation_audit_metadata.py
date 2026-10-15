"""Preserve audit object metadata without invoking private getters or changing UI."""
from pathlib import Path

path = Path('CardPilotUITests/CoreFlowsUITests.swift')
source = path.read_text()
assert 'import ObjectiveC' not in source
source = source.replace('import UIKit\n', 'import UIKit\nimport ObjectiveC\n', 1)
marker = '    func testAllocationErrorLocationAndCompletePromptAtLargestTextSize() throws {'
start = source.index(marker)
end = source.index('    func testTransactionAllocationPersistsAndUpdatesPromotion()', start)
case = source[start:end]
old = '            self.add(attachment)\n'
assert case.count(old) == 1
extra = '''            let metadata = XCTAttachment(string: self.auditObjectMetadata(issue))
            metadata.name = "裁切审计对象原始元数据"
            metadata.lifetime = .keepAlways
            self.add(metadata)
'''
case = case.replace(old, old + extra, 1)
source = source[:start] + case + source[end:]
helper_marker = '    private func allocationError(_ title: String) -> XCUIElement {'
assert source.count(helper_marker) == 1
helper = '''    private func auditObjectMetadata(_ issue: XCUIAccessibilityAuditIssue) -> String {
        var lines = ["Swift mirror: \\(String(reflecting: type(of: issue)))"]
        for child in Mirror(reflecting: issue).children {
            lines.append("mirror \\(child.label ?? "?"): \\(String(reflecting: type(of: child.value)))")
        }
        var visited: Set<ObjectIdentifier> = []
        func record(_ object: NSObject, path: String, depth: Int) {
            guard depth <= 4, visited.count < 60 else { return }
            guard visited.insert(ObjectIdentifier(object)).inserted else { return }
            lines.append("\\(path): \\(String(reflecting: type(of: object)))")
            if object is NSString || object is NSNumber || object is NSValue || object is NSDate {
                lines.append(String(describing: object).prefix(3000).description)
                return
            }
            if let dictionary = object as? NSDictionary {
                for key in dictionary.allKeys.prefix(20) {
                    guard let value = dictionary[key] as? NSObject else { continue }
                    record(value, path: path + "." + String(describing: key), depth: depth + 1)
                }
                return
            }
            if let array = object as? NSArray {
                for (index, value) in array.prefix(20).enumerated() {
                    if let value = value as? NSObject {
                        record(value, path: path + ".\\(index)", depth: depth + 1)
                    }
                }
                return
            }
            var currentClass: AnyClass? = type(of: object)
            while let objectClass = currentClass, objectClass != NSObject.self {
                var count: UInt32 = 0
                if let ivars = class_copyIvarList(objectClass, &count) {
                    defer { free(ivars) }
                    for index in 0..<Int(count) {
                        let ivar = ivars[index]
                        guard let rawName = ivar_getName(ivar), let rawType = ivar_getTypeEncoding(ivar) else { continue }
                        let name = String(cString: rawName)
                        let encoding = String(cString: rawType)
                        lines.append("\\(path).\\(name) [\\(encoding)]")
                        if encoding.hasPrefix("@"), let value = object_getIvar(object, ivar) as? NSObject {
                            record(value, path: path + "." + name, depth: depth + 1)
                        }
                    }
                }
                currentClass = class_getSuperclass(objectClass)
            }
        }
        if let object = issue as? NSObject { record(object, path: "issue", depth: 0) }
        return lines.joined(separator: "\\n")
    }

'''
path.write_text(source.replace(helper_marker, helper + helper_marker, 1))
