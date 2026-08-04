struct CmuxFeatureFlagResolution: Equatable, Sendable {
    let effectiveValue: Bool
    let source: CmuxFeatureFlagSource

    init(overrideValue: Bool?, defaultValue: Bool) {
        if let overrideValue {
            effectiveValue = overrideValue
            source = .override
        } else {
            effectiveValue = defaultValue
            source = .default
        }
    }
}
