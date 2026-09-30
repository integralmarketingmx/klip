import SwiftUI

/// The macOS 27 SDK turns `@StateVar` into a macro whose plugin (SwiftUIMacros) only
/// ships with full Xcode, so Command Line Tools builds fail. This alias points
/// straight at the `State` property wrapper, which compiles with either toolchain.
typealias StateVar<Value> = SwiftUI.State<Value>
