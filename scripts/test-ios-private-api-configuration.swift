import Foundation
@main struct Check { static func main() {
let c = APIConfiguration.current()
precondition(c.environment == .development)
precondition(c.baseURL?.absoluteString == "https://api-dev.tastemap.cn")
precondition(TasteMapAppEnvironment.current == .production, "Keep existing private device local store")
print("PASS: Private Preview uses development API with retained local persistence namespace")
} }
