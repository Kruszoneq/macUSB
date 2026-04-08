import Foundation

private let delegate = HelperListenerDelegate()
private let listener = NSXPCListener(machServiceName: "com.kruszoneq.macusb.helper")
listener.delegate = delegate
listener.resume()
dispatchMain()
