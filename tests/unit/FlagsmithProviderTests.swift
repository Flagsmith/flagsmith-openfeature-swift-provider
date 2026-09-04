import Combine
import FlagsmithClient
import FlagsmithOpenFeatureTestSupport
import Foundation
import Logging
import OpenFeature
import Testing

@testable import FlagsmithOpenFeature

struct FlagsmithProviderTests {
    let logs = LogCapture()

    func provider(
        _ source: FlagSourceMock,
        useBooleanConfigValue: Bool = false,
        returnValueForDisabledFlags: Bool = false
    ) -> FlagsmithProvider {
        FlagsmithProvider(
            flagSource: source,
            useBooleanConfigValue: useBooleanConfigValue,
            returnValueForDisabledFlags: returnValueForDisabledFlags,
            logger: logs.logger
        )
    }

    func initialized(
        _ flags: Flag...,
        context: EvaluationContext? = nil,
        useBooleanConfigValue: Bool = false,
        returnValueForDisabledFlags: Bool = false
    ) async -> FlagsmithProvider {
        let provider = provider(
            FlagSourceMock(.success(flags)),
            useBooleanConfigValue: useBooleanConfigValue,
            returnValueForDisabledFlags: returnValueForDisabledFlags
        )
        await provider.initialize(initialContext: context).value
        return provider
    }

    @Test
    func test_initialize__no_context__fetches_environment_flags() async {
        // Given
        let source = FlagSourceMock(.success([Flag(featureName: "feature", enabled: true)]))
        let provider = provider(source)

        // When
        await provider.initialize(initialContext: nil).value

        // Then
        #expect(source.fetches.count == 1)
        #expect(source.fetches.first?.identity == nil)
        #expect(source.fetches.first?.traits == nil)
        #expect(provider.status == .ready)
        #expect(
            logs.entries == [
                LogCapture.Entry(level: .info, message: "Fetching flags from Flagsmith", metadata: ["traits": "0"]),
                LogCapture.Entry(level: .info, message: "Flags fetched from Flagsmith", metadata: ["count": "1"]),
            ])
    }

    @Test
    func test_initialize__empty_targeting_key__fetches_environment_flags() async {
        // Given
        let source = FlagSourceMock(.success([Flag(featureName: "feature", enabled: true)]))
        let provider = provider(source)

        // When
        await provider.initialize(initialContext: ImmutableContext()).value

        // Then
        #expect(source.fetches.first?.identity == nil)
        #expect(
            logs.entries.first
                == LogCapture.Entry(level: .info, message: "Fetching flags from Flagsmith", metadata: ["traits": "0"]))
    }

    @Test
    func test_initialize__targeting_key_without_attributes__fetches_identity_flags_without_traits() async {
        // Given
        let source = FlagSourceMock(.success([Flag(featureName: "feature", enabled: true)]))
        let provider = provider(source)

        // When
        await provider.initialize(initialContext: ImmutableContext(targetingKey: "user-123")).value

        // Then
        #expect(source.fetches.first?.identity == "user-123")
        #expect(source.fetches.first?.traits == nil)
        #expect(
            logs.entries.first
                == LogCapture.Entry(
                    level: .info,
                    message: "Fetching flags from Flagsmith",
                    metadata: ["identity": "user-123", "traits": "0"]
                ))
    }

    @Test
    func test_initialize__flat_attributes__sends_traits_of_each_supported_kind() async {
        // Given
        let source = FlagSourceMock(.success([Flag(featureName: "feature", enabled: true)]))
        let provider = provider(source)
        let context = ImmutableContext(
            targetingKey: "user-123",
            structure: ImmutableStructure(attributes: [
                "name": .string("jane"),
                "age": .integer(30),
                "height": .double(1.68),
                "subscribed": .boolean(true),
            ]))

        // When
        await provider.initialize(initialContext: context).value

        // Then
        #expect(
            source.fetches.first?.traits == [
                "name": .string("jane"),
                "age": .int(30),
                "height": .float(1.68),
                "subscribed": .bool(true),
            ])
        #expect(
            logs.entries.first
                == LogCapture.Entry(
                    level: .info,
                    message: "Fetching flags from Flagsmith",
                    metadata: ["identity": "user-123", "traits": "4"]
                ))
    }

    @Test
    func test_initialize__nested_traits_conflicting_with_flat_attributes__nested_wins() async {
        // Given
        let source = FlagSourceMock(.success([Flag(featureName: "feature", enabled: true)]))
        let provider = provider(source)
        let context = ImmutableContext(
            targetingKey: "user-123",
            structure: ImmutableStructure(attributes: [
                "foo": .string("bar"),
                "abc": .string("def"),
                "traits": .structure(["foo": .string("bar2")]),
            ]))

        // When
        await provider.initialize(initialContext: context).value

        // Then
        #expect(source.fetches.first?.traits == ["foo": .string("bar2"), "abc": .string("def")])
        #expect(
            logs.entries.first
                == LogCapture.Entry(
                    level: .info,
                    message: "Fetching flags from Flagsmith",
                    metadata: ["identity": "user-123", "traits": "2"]
                ))
    }

    @Test
    func test_initialize__unsupported_attribute_value__reports_invalid_context_error() async {
        // Given
        let source = FlagSourceMock(.success([]))
        let provider = provider(source)
        let context = ImmutableContext(
            targetingKey: "user-123",
            structure: ImmutableStructure(attributes: [
                "tags": .list([.string("a")])
            ]))

        // When
        await provider.initialize(initialContext: context).value

        // Then
        #expect(provider.status == .error)
        #expect(source.fetches.isEmpty)
        let failure = LogCapture.Entry(
            level: .error,
            message: "Invalid evaluation context",
            metadata: ["reason": "Unsupported value for trait 'tags'"]
        )
        #expect(logs.entries == [failure])
    }

    @Test
    func test_initialize__non_structure_traits_attribute__reports_invalid_context_error() async {
        // Given
        let source = FlagSourceMock(.success([]))
        let provider = provider(source)
        let context = ImmutableContext(
            targetingKey: "user-123",
            structure: ImmutableStructure(attributes: [
                "traits": .string("not-a-structure")
            ]))

        // When
        await provider.initialize(initialContext: context).value

        // Then
        #expect(provider.status == .error)
        let failure = LogCapture.Entry(
            level: .error,
            message: "Invalid evaluation context",
            metadata: ["reason": "Attribute 'traits' must be a structure"]
        )
        #expect(logs.entries == [failure])
    }

    @Test
    func test_initialize__client_failure__reports_general_error() async {
        // Given
        let provider = provider(FlagSourceMock(.failure(URLError(.badServerResponse))))

        // When
        await provider.initialize(initialContext: nil).value

        // Then
        #expect(provider.status == .error)
        #expect(
            logs.entries.last
                == LogCapture.Entry(
                    level: .error,
                    message: "Failed to fetch flags from Flagsmith",
                    metadata: ["error": URLError(.badServerResponse).localizedDescription]
                ))
    }

    @Test
    func test_onContextSet__new_targeting_key__refetches_identity_flags_and_reports_context_changed() async {
        // Given
        let source = FlagSourceMock(.success([Flag(featureName: "feature", enabled: true)]))
        let provider = provider(source)
        await provider.initialize(initialContext: nil).value

        // When
        await provider.onContextSet(oldContext: nil, newContext: ImmutableContext(targetingKey: "user-456")).value

        // Then
        #expect(source.fetches.map(\.identity) == [nil, "user-456"])
        #expect(provider.status == .ready)
        #expect(
            logs.entries.last
                == LogCapture.Entry(level: .info, message: "Flags fetched from Flagsmith", metadata: ["count": "1"]))
    }

    @Test
    func test_onContextSet__targeting_key_removed__reason_reverts_to_static() async throws {
        // Given
        let provider = await initialized(
            Flag(featureName: "feature", stringValue: "some value", enabled: true),
            context: ImmutableContext(targetingKey: "user-123")
        )

        // When
        await provider.onContextSet(oldContext: nil, newContext: ImmutableContext()).value

        // Then
        let evaluation = try provider.getStringEvaluation(key: "feature", defaultValue: "default", context: nil)
        #expect(evaluation.reason == Reason.staticReason.rawValue)
        #expect(logs.entries.filter { $0.message == "Fetching flags from Flagsmith" }.count == 2)
    }

    @Test
    func test_getStringEvaluation__string_value__returns_value_with_metadata() async throws {
        // Given
        let provider = await initialized(Flag(featureName: "feature", stringValue: "some value", enabled: true))

        // When
        let evaluation = try provider.getStringEvaluation(key: "feature", defaultValue: "default", context: nil)

        // Then
        #expect(evaluation.value == "some value")
        #expect(evaluation.reason == Reason.staticReason.rawValue)
        #expect(evaluation.flagMetadata == ["feature_name": .string("feature")])
        #expect(logs.entries.map(\.level) == [.info, .info])
    }

    @Test
    func test_onContextSet__client_failure__reports_error_and_keeps_previous_flags() async throws {
        // Given
        let source = FlagSourceMock(.success([Flag(featureName: "feature", stringValue: "kept", enabled: true)]))
        let provider = provider(source)
        await provider.initialize(initialContext: nil).value
        source.result = .failure(URLError(.notConnectedToInternet))

        // When
        await provider.onContextSet(oldContext: nil, newContext: ImmutableContext(targetingKey: "user-456")).value

        // Then
        #expect(provider.status == .error)
        #expect(try provider.getStringEvaluation(key: "feature", defaultValue: "default", context: nil).value == "kept")
        #expect(
            logs.entries.last
                == LogCapture.Entry(
                    level: .error,
                    message: "Failed to fetch flags from Flagsmith",
                    metadata: ["error": URLError(.notConnectedToInternet).localizedDescription]
                ))
    }
}
