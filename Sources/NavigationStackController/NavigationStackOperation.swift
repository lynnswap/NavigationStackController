/// The operation that caused a navigation stack controller to show a view controller.
public enum NavigationStackOperation: Equatable, Sendable {
    /// The stack was replaced with a new set of view controllers.
    case set

    /// A new view controller was pushed on top of the stack.
    case push

    /// The stack moved backward in its history.
    case back

    /// The stack moved forward in its history.
    case forward
}

