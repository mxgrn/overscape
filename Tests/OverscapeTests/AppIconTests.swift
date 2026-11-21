import Testing
@testable import Overscape

struct AppIconTests {
    @Test func theAppIconIsInThePackageResources() {
        #expect(AppIcon.image != nil)
    }
}
