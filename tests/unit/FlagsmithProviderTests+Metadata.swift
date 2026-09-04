import FlagsmithClient
import FlagsmithOpenFeatureTestSupport
import OpenFeature
import Testing

@testable import FlagsmithOpenFeature

extension FlagsmithProviderTests {
    @Test
    func test_metadata__any_provider__is_named_FlagsmithProvider() {
        // Given / When
        let provider = provider(FlagSourceMock(.success([])))

        // Then
        #expect(provider.metadata.name == "FlagsmithProvider")
        #expect(logs.entries.isEmpty)
    }

    @Test
    func test_hooks__any_provider__are_empty() {
        // Given / When
        let provider = provider(FlagSourceMock(.success([])))

        // Then
        #expect(provider.hooks.isEmpty)
        #expect(logs.entries.isEmpty)
    }

    @Test
    func test_track__any_event__does_not_throw() throws {
        // Given
        let provider = provider(FlagSourceMock(.success([])))

        // When / Then
        try provider.track(key: "event", context: nil, details: nil)
        #expect(logs.entries.isEmpty)
    }
}
