/// Build metadata for DataGrail's own test/demo apps. SPI, not public API:
/// importers must opt in with `@_spi(Diagnostics) import DataGrailConsent`.
@_spi(Diagnostics) public extension DataGrailConsent {
    static var sdkVersion: String { ConsentService.sdkVersion }
    static var schemaVersion: String { ConsentService.schemaVersion }
}
