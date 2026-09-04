<img width="100%" src="https://github.com/Flagsmith/flagsmith/raw/main/static-files/hero.png"/>

![build](https://github.com/Flagsmith/flagsmith-openfeature-swift-provider/actions/workflows/verify-pull-request.yml/badge.svg)

# Flagsmith OpenFeature Provider for Swift

> Flagsmith allows you to manage feature flags and remote config across multiple projects, environments and organisations.

The Flagsmith provider allows you to connect to your Flagsmith instance through the
[OpenFeature Swift SDK](https://openfeature.dev/docs/reference/sdks/client/swift) in iOS, macOS, watchOS and tvOS
applications.

## Install dependencies

Add the provider to your `Package.swift` dependencies; the OpenFeature SDK and the Flagsmith iOS client come with it:

```swift
platforms: [.iOS(.v15), .macOS(.v12), .watchOS(.v8), .tvOS(.v15)],
dependencies: [
    .package(url: "https://github.com/Flagsmith/flagsmith-openfeature-swift-provider.git", from: "<latest version>"),
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "FlagsmithOpenFeature", package: "flagsmith-openfeature-swift-provider"),
    ]),
]
```

The package requires iOS 15, macOS 12, watchOS 8 or tvOS 15, matching the OpenFeature Swift SDK.

## Using the Flagsmith Provider with the OpenFeature SDK

To create a Flagsmith provider you will need to provide a number of arguments. These are shown and described
below. See the [Flagsmith docs](https://docs.flagsmith.com/clients/ios) for further information on the
configuration options available for the Flagsmith iOS client.

```swift
import FlagsmithClient
import FlagsmithOpenFeature
import Logging

// The Flagsmith iOS client is a singleton; configure it before creating the provider.
Flagsmith.shared.apiKey = "<your environment key>"

let provider = FlagsmithProvider(
    // The Flagsmith client instance used to fetch flags.
    // Required: false
    // Default: Flagsmith.shared
    flagsmith: .shared,

    // By default, when evaluating the boolean value of a feature in the OpenFeature SDK, the Flagsmith
    // OpenFeature Provider will use the 'Enabled' state of the feature as defined in Flagsmith. This
    // behaviour can be changed to use the 'value' field defined in the Flagsmith feature instead by
    // enabling the useBooleanConfigValue setting.
    // Note: this relies on the value being defined as a Boolean in Flagsmith. If the value is not a
    // Boolean, an error will occur and the default value provided as part of the evaluation will be
    // returned instead. When enabled, boolean evaluation also honours returnValueForDisabledFlags
    // below; when disabled, the flag's 'Enabled' state is returned directly regardless of it.
    // Required: false
    // Default: false
    useBooleanConfigValue: false,

    // By default, the Flagsmith OpenFeature Provider will raise an error (triggering the
    // OpenFeature SDK to return the provided default value) if the flag is disabled. This behaviour
    // can be configured by enabling this flag so that the Flagsmith OpenFeature provider ignores
    // the enabled state of a flag when returning a value.
    // Required: false
    // Default: false
    returnValueForDisabledFlags: false,

    // A swift-log logger receiving structured provider diagnostics.
    // Required: false
    // Default: Logger(label: "com.flagsmith.openfeature")
    logger: Logger(label: "com.flagsmith.openfeature")
)
```

A failed flags fetch surfaces as an OpenFeature error status: the provider does not become ready, and
evaluations return the provided defaults with a `providerNotReady` error. The Flagsmith client
substitutes its configured `defaultFlags` or cached flags on a failed fetch when those are configured,
in which case the provider becomes ready with them.

Register the provider and evaluate flags through the OpenFeature client:

```swift
import OpenFeature

await OpenFeatureAPI.shared.setProviderAndWait(
    provider: provider,
    initialContext: ImmutableContext(targetingKey: "user-123")
)

let client = OpenFeatureAPI.shared.getClient()
let enabled = client.getBooleanValue(key: "my-feature", defaultValue: false)
let colour = client.getStringValue(key: "banner-colour", defaultValue: "blue")
```

Flags are fetched from Flagsmith when the provider is initialized and whenever the evaluation
context changes; evaluations then resolve synchronously from the in-memory flags.

When the Flagsmith client pushes new flags (for example through realtime updates, enabled with
`Flagsmith.shared.enableRealtimeUpdates = true`), the provider refreshes its in-memory flags and
surfaces a configuration-changed event carrying the names of the flags that changed. The provider
consumes the client's `flagStream`, which supports a single consumer. Subscribe through the
OpenFeature SDK:

```swift
import Combine
import OpenFeature

let subscription = OpenFeatureAPI.shared.observe().sink { event in
    if case .configurationChanged(let details) = event {
        let changed = details?.flagsChanged
    }
}
```

### Evaluation Context

The evaluation context maps to Flagsmith as follows:

| OpenFeature context             | Flagsmith                                        |
| ------------------------------- | ------------------------------------------------ |
| `targetingKey`                  | Identity identifier                              |
| Flat attributes                 | Traits                                           |
| Nested `traits` structure       | Traits (overriding flat attributes on conflict)  |
| No `targetingKey`               | Environment flags are fetched; attributes are ignored |

Attribute values must be strings, booleans, integers or doubles; any other value kind raises an
`invalidContextError`. Doubles are sent as the Flagsmith client's single-precision `Float`.

Each successful evaluation reports a reason:

| Reason            | Condition                                                                 |
| ----------------- | ------------------------------------------------------------------------- |
| `DISABLED`        | The flag is disabled and only returned because `returnValueForDisabledFlags` is enabled |
| `TARGETING_MATCH` | The in-memory flags were fetched for an identity (a `targetingKey` was set) |
| `STATIC`          | Environment flags were fetched (no `targetingKey`)                        |

Each successful evaluation also carries string metadata identifying the Flagsmith feature: `feature_name`.

```swift
// Traits sent to Flagsmith: {"abc": "def", "foo": "bar2"}
let context = ImmutableContext(
    targetingKey: "user-123",
    structure: ImmutableStructure(attributes: [
        "foo": .string("bar"),
        "abc": .string("def"),
        "traits": .structure(["foo": .string("bar2")]),
    ])
)
```

## Contributing

Please read [CONTRIBUTING.md](https://gist.github.com/kyle-ssg/c36a03aebe492e45cbd3eefb21cb0486) for details on our code of conduct, and the process for submitting pull requests

## Getting Help

If you encounter a bug or feature request we would like to hear about it. Before you submit an issue please search existing issues in order to prevent duplicates.

## Get in touch

If you have any questions about our projects you can email <a href="mailto:support@flagsmith.com">support@flagsmith.com</a>.

## Useful links

[Website](https://www.flagsmith.com/)

[Documentation](https://docs.flagsmith.com/)
