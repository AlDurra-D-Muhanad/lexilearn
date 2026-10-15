/// Injected everywhere a "now" is needed, so tests can pin timestamps.
typedef Clock = DateTime Function();
