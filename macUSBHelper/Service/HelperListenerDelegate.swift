import Foundation

final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        HelperConnectionSecurityPolicy.logAcceptedConnection(newConnection)

        let service = PrivilegedHelperService()
        service.connection = newConnection
        let connectionLease = HelperProcessLifecycle.shared.beginConnection()

        let disconnect: () -> Void = {
            service.handleClientDisconnection()
            connectionLease.finish()
        }

        newConnection.exportedInterface = NSXPCInterface(with: PrivilegedHelperToolXPCProtocol.self)
        newConnection.exportedObject = service
        newConnection.remoteObjectInterface = NSXPCInterface(with: PrivilegedHelperClientXPCProtocol.self)
        newConnection.interruptionHandler = disconnect
        newConnection.invalidationHandler = disconnect
        newConnection.resume()

        return true
    }
}
