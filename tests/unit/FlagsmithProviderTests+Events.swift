import Combine
import FlagsmithClient
import FlagsmithOpenFeatureTestSupport
import OpenFeature
import Testing

@testable import FlagsmithOpenFeature

extension FlagsmithProviderTests {
    /// Provider events as they arrive, replayed status first.
    func events(from provider: FlagsmithProvider) -> AsyncStream<ProviderEvent> {
        AsyncStream { continuation in
            let subscription = provider.observe().sink { continuation.yield($0) }
            continuation.onTermination = { _ in subscription.cancel() }
        }
    }

    @Test
    func test_observe__initialized_provider__replays_ready_event() async {
        // Given
        let provider = await initialized(Flag(featureName: "feature", enabled: true))

        // When
        var events = events(from: provider).makeAsyncIterator()

        // Then
        #expect(await events.next() == .ready(nil))
        #expect(logs.entries.map(\.level) == [.info, .info])
    }

    @Test
    func test_observe__genuine_flag_update__emits_configuration_changed_and_refreshes_snapshot() async throws {
        // Given
        let source = FlagSourceMock(.success([Flag(featureName: "feature", stringValue: "old", enabled: true)]))
        let provider = provider(source)
        await provider.initialize(initialContext: nil).value
        var events = events(from: provider).makeAsyncIterator()
        _ = await events.next()

        // When
        source.push.yield([
            Flag(featureName: "feature", stringValue: "new", enabled: true),
            Flag(featureName: "added", stringValue: "x", enabled: true),
        ])

        // Then
        #expect(await events.next() == .configurationChanged(ProviderEventDetails(flagsChanged: ["added", "feature"])))
        #expect(try provider.getStringEvaluation(key: "feature", defaultValue: "default", context: nil).value == "new")
        let updated = LogCapture.Entry(
            level: .info,
            message: "Flags updated from Flagsmith",
            metadata: ["changed": #"["added", "feature"]"#]
        )
        #expect(logs.entries.last == updated)
    }

    @Test
    func test_observe__empty_or_unchanged_emissions__emit_nothing_and_keep_snapshot() async throws {
        // Given
        let source = FlagSourceMock(.success([Flag(featureName: "feature", stringValue: "keep", enabled: true)]))
        let provider = provider(source)
        await provider.initialize(initialContext: nil).value
        var events = events(from: provider).makeAsyncIterator()
        _ = await events.next()

        // When
        source.push.yield([])
        source.push.yield([Flag(featureName: "feature", stringValue: "keep", enabled: true)])
        source.push.yield([Flag(featureName: "feature", stringValue: "changed", enabled: true)])

        // Then
        #expect(await events.next() == .configurationChanged(ProviderEventDetails(flagsChanged: ["feature"])))
        #expect(
            try provider.getStringEvaluation(key: "feature", defaultValue: "default", context: nil).value == "changed")
        #expect(
            logs.entries.filter { $0.message == "Ignored flag update from Flagsmith" }.map(\.metadata) == [
                ["reason": "empty"],
                ["reason": "unchanged"],
            ])
    }

    @Test
    func test_onContextSet__called_again_before_completion__ignores_the_superseded_fetch() async throws {
        // Given
        let source = FlagSourceMock(.success([Flag(featureName: "feature", stringValue: "first", enabled: true)]))
        source.holdCompletions = true
        let provider = provider(source)
        let first = provider.onContextSet(oldContext: nil, newContext: ImmutableContext(targetingKey: "user-1"))
        source.result = .success([Flag(featureName: "feature", stringValue: "second", enabled: true)])
        let second = provider.onContextSet(oldContext: nil, newContext: ImmutableContext(targetingKey: "user-2"))

        // When
        source.completeHeldFetches()
        await first.value
        await second.value

        // Then
        #expect(
            try provider.getStringEvaluation(key: "feature", defaultValue: "default", context: nil).value == "second")
        #expect(provider.status == .ready)
        let superseded = LogCapture.Entry(
            level: .debug,
            message: "Ignored superseded flags fetch from Flagsmith",
            metadata: ["identity": "user-1", "traits": "0"]
        )
        #expect(logs.entries.contains(superseded))
    }

    @Test
    func test_initialize__superseded_by_a_context_change__reports_only_the_context_change() async throws {
        // Given
        let source = FlagSourceMock(.success([Flag(featureName: "feature", stringValue: "initial", enabled: true)]))
        source.holdCompletions = true
        let provider = provider(source)
        var events = events(from: provider).makeAsyncIterator()
        let initialization = provider.initialize(initialContext: nil)
        source.result = .success([Flag(featureName: "feature", stringValue: "contextual", enabled: true)])
        let contextChange = provider.onContextSet(oldContext: nil, newContext: ImmutableContext(targetingKey: "user"))

        // When
        source.completeHeldFetches()
        await initialization.value
        await contextChange.value

        // Then
        #expect(await events.next() == .reconciling(nil))
        #expect(await events.next() == .contextChanged(nil))
        #expect(
            try provider.getStringEvaluation(key: "feature", defaultValue: "default", context: nil).value
                == "contextual")
        #expect(logs.entries.contains { $0.message == "Ignored superseded flags fetch from Flagsmith" })
    }

    @Test
    func test_observe__flag_update_before_the_first_fetch_completes__reports_every_pushed_flag_as_changed() async {
        // Given
        let source = FlagSourceMock(.success([Flag(featureName: "feature", stringValue: "fetched", enabled: true)]))
        source.holdCompletions = true
        let provider = provider(source)
        var events = events(from: provider).makeAsyncIterator()
        let initialization = provider.initialize(initialContext: nil)

        // When
        source.push.yield([Flag(featureName: "pushed", stringValue: "early", enabled: true)])

        // Then
        #expect(await events.next() == .configurationChanged(ProviderEventDetails(flagsChanged: ["pushed"])))
        source.completeHeldFetches()
        await initialization.value
        #expect(await events.next() == .ready(nil))
        #expect(logs.entries.contains { $0.message == "Flags updated from Flagsmith" })
    }
}
