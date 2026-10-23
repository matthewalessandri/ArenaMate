// Run on the macOS release runner after generating the appcast. Verify against
// the PUBLIC key embedded in the application, independently of the signing tool.
import Foundation
import CryptoKit

guard CommandLine.arguments.count == 4,
      let publicKey = Data(base64Encoded: CommandLine.arguments[1]),
      let signature = Data(base64Encoded: CommandLine.arguments[2]) else {
    fatalError("Expected public key, signature and archive path")
}
let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
let archive = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]), options: .mappedIfSafe)
guard key.isValidSignature(signature, for: archive) else {
    fatalError("Update archive signature does not match the application's public key")
}
print("Update archive signature verified.")
