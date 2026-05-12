import Foundation
import MPCore

let listener = NSXPCListener(machServiceName: "com.macpolish.helper")
let delegate = HelperListener()
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
