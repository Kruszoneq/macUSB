import Foundation

private let delegate = HelperListenerDelegate()
#if DEBUG
private let machServiceName = "com.kruszoneq.macusb.helper.debug"
#else
private let machServiceName = "com.kruszoneq.macusb.helper"
#endif
private let listener = NSXPCListener(machServiceName: machServiceName)
listener.delegate = delegate
listener.resume()
dispatchMain()
