import production from '../../ios/TasteMap/TasteMap/Configuration/ProductionEnvironment.json'

// Signed release product policy, shared with Worker. No URL/local-storage/debug override.
export function referralAvailable(): boolean { return production.referralAvailable === true }
