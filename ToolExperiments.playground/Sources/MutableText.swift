import Foundation

/// Holds mutable document text so mutation tools can modify it in place.
/// Use this in playground experiments to observe before/after state.
public class MutableText {
    public var content: String

    public init(_ content: String) {
        self.content = content
    }
}
