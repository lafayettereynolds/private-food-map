import Foundation
import Testing
@testable import TasteMap

@Suite("Task 11 sharing hardening")
struct Task11SharingHardeningTests {
    private let shareID = "12345678901234567890123456789012"

    @Test("Apple Maps, AMap, generic URLs, text, address and coordinates share one acquisition parser")
    func sharedRestaurantEvidence() throws {
        let apple = try #require(try ExternalRestaurantLinkParser.parse(
            "https://maps.apple.com/?q=Sushi&address=Broadway&ll=40.7,-73.9&place-id=apple-11",
            currentCity: "New York"
        ))
        let amap = try #require(try ExternalRestaurantLinkParser.parse(
            "高德地图 https://uri.amap.com/marker?position=120.1,30.2&name=Noodle&poiid=B0TASK11",
            currentCity: "杭州"
        ))
        let generic = try #require(try ExternalRestaurantLinkParser.parse(
            "https://restaurant.example/menu?name=Table&address=1%20Main%20Street&ll=51.5,-0.1&id=generic-11",
            currentCity: "London"
        ))
        let nameAndAddress = try #require(try ExternalRestaurantLinkParser.parse(
            "湖边餐厅\n杭州市西湖区北山街 1 号",
            currentCity: "杭州"
        ))
        let address = try #require(try ExternalRestaurantLinkParser.parse(
            "杭州市西湖区满觉陇路 2 号",
            currentCity: "杭州"
        ))
        let coordinate = try #require(try ExternalRestaurantLinkParser.parse(
            "30.2741,120.1551",
            currentCity: "杭州"
        ))

        #expect(apple.source == .appleMaps)
        #expect(apple.identity?.provider == .appleMaps)
        #expect(amap.source == .amap)
        #expect(amap.identity?.provider == .amap)
        #expect(generic.source == .genericURL)
        #expect(nameAndAddress.name == "湖边餐厅")
        #expect(nameAndAddress.address.contains("北山街"))
        #expect(address.address.contains("满觉陇路"))
        #expect(coordinate.coordinate == RestaurantCoordinate(latitude: 30.2741, longitude: 120.1551))
    }

    @Test("Universal Link route is opaque, HTTPS-only and maps all public entity contracts")
    func universalLinkAndEntityMapping() throws {
        let url = try #require(URL(string: "https://public.example/share/\(shareID)"))
        #expect(PublicShareRoute.shareID(from: url) == shareID)
        #expect(PublicShareRoute.shareID(from: URL(string: "http://public.example/share/\(shareID)")!) == nil)
        #expect(PublicShareRoute.shareID(from: URL(string: "https://public.example/share/internal-restaurant-id")!) == nil)

        for (type, entity) in [
            ("restaurant", #"{"shareId":"12345678901234567890123456789012","name":"餐厅","address":"地址","city":"杭州","cuisines":[],"pricePerPerson":null,"merchantImageUrl":null}"#),
            ("profile", #"{"shareId":"12345678901234567890123456789012","displayName":"用户","bio":null,"city":null,"statistics":{"restaurantCount":1,"visitCount":2}}"#),
            ("list", #"{"shareId":"12345678901234567890123456789012","title":"食单","description":"","ownerDisplayName":"用户","isRanked":false,"restaurantCount":0,"restaurants":[]}"#),
        ] {
            let data = Data(#"{"apiVersion":1,"shareId":"\#(shareID)","entityType":"\#(type)","entity":\#(entity)}"#.utf8)
            let response = try JSONDecoder().decode(PublicShareResponseV1.self, from: data)
            #expect(response.shareId == shareID)
        }
    }

    @Test("Poster QR configuration fails closed for missing or Development-only release destinations")
    func posterShareConfiguration() {
        #expect(SharePosterBrandConfiguration.resolve(environment: .production, rawValue: nil).qrDestinationURL == nil)
        #expect(SharePosterBrandConfiguration.resolve(
            environment: .production,
            rawValue: "https://api-dev.tastemap.cn/share"
        ).qrDestinationURL == nil)
        #expect(SharePosterBrandConfiguration.resolve(
            environment: .production,
            rawValue: "https://tastemap.example/share"
        ).qrDestinationURL?.host == "tastemap.example")
    }
}
