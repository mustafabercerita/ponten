import Foundation

let fm = FileManager.default
let scriptPath = fm.temporaryDirectory.appendingPathComponent("test_script.sh").path

let scriptContent = """
#!/bin/bash
sleep 2
echo "I am alive!" > /tmp/test_process_output.txt
"""
try! scriptContent.write(toFile: scriptPath, atomically: true, encoding: .utf8)

var attributes = [FileAttributeKey: Any]()
attributes[.posixPermissions] = NSNumber(value: 0o755)
try! fm.setAttributes(attributes, ofItemAtPath: scriptPath)

let process = Process()
process.executableURL = URL(fileURLWithPath: "/bin/bash")
process.arguments = [scriptPath]
try! process.run()

print("Process launched. Exiting parent...")
exit(0)
