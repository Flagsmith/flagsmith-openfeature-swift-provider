import FlagsmithClient
import OpenFeature

extension FlagsmithProvider {
    // The identity-with-traits fetch never yields to flagStream, and the provider's own fetches yield
    // flags equal to the snapshot; empty and unchanged emissions are ignored.
    func observeFlagUpdates() {
        flagUpdates = Task { [weak self, flagSource] in
            for await flags in flagSource.flagStream {
                self?.handle(update: flags)
            }
        }
    }

    private func handle(update flags: [Flag]) {
        guard !flags.isEmpty else {
            logger.debug("Ignored flag update from Flagsmith", metadata: ["reason": "empty"])
            return
        }
        guard let changed = state.apply(update: flags.byName) else {
            logger.debug("Ignored flag update from Flagsmith", metadata: ["reason": "unchanged"])
            return
        }
        let changedNames = changed.sorted()
        logger.info("Flags updated from Flagsmith", metadata: ["changed": "\(changedNames)"])
        statusTracker.send(.configurationChanged(ProviderEventDetails(flagsChanged: changedNames)))
    }
}
