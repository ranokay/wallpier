import XCTest
import AppKit
@testable import wallpier

@MainActor
final class WallpaperServiceTests: XCTestCase {

    func testDesktopOptionsTileDisablesClippingAndSetsFillColor() {
        let service = WallpaperService()
        let options = WallpaperService.desktopOptions(for: .tile)

        let allowClipping = options[.allowClipping] as? Bool
        let fillColor = options[.fillColor] as? NSColor

        XCTAssertEqual(allowClipping, false)
        XCTAssertEqual(fillColor, NSColor.black)
    }

    func testDesktopOptionsCenterDisablesClipping() {
        let service = WallpaperService()
        let options = WallpaperService.desktopOptions(for: .center)

        let allowClipping = options[.allowClipping] as? Bool
        XCTAssertEqual(allowClipping, false)
    }

    func testDesktopOptionsFillAllowsClipping() {
        let service = WallpaperService()
        let options = WallpaperService.desktopOptions(for: .fill)

        let allowClipping = options[.allowClipping] as? Bool
        XCTAssertEqual(allowClipping, true)
    }

    func testResolvedScalingModeUsesOverridesAndDefaults() {
        var settings = MultiMonitorSettings()
        settings.perMonitorScaling["Display 1"] = .fit

        let override = WallpaperService.resolvedScalingMode(
            for: "Display 1",
            settings: settings,
            defaultScalingMode: .fill
        )
        let fallback = WallpaperService.resolvedScalingMode(
            for: "Unknown Display",
            settings: settings,
            defaultScalingMode: .center
        )

        XCTAssertEqual(override, .fit)
        XCTAssertEqual(fallback, .center)
    }
}
