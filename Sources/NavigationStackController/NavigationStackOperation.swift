/// The navigation operation associated with a display notification.
///
/// This value describes the attempted operation, including an interactive transition that was cancelled.
public enum NavigationStackOperation: Equatable, Sendable {
    /// A replacement of the navigation stack.
    case set

    /// A push of a new page onto the stack.
    case push

    /// A move backward in history.
    case back

    /// A move forward in history.
    case forward
}
