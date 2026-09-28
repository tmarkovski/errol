/// The console and native windows share these rules. A requested pause
/// confers no focus permission until the worker has granted it.
struct ConsoleAccess {
    var running: Bool
    var steering: Bool
    var pending: Bool
    var stopping: Bool
    var showingWindow: Bool
    var focusOperationActive = false

    var pauseGranted: Bool { running && steering && !pending && !stopping }
    // Reading controls between handoffs is safe. A copy or delivery owns
    // the keyboard until its completion fence; showing an external window
    // still requires the stronger, persistent steering hold.
    var canTakeFocus: Bool { !showingWindow && (!running || !focusOperationActive) }
    var canShowWindow: Bool { (!running || pauseGranted) && !stopping && !showingWindow }
    var canChangeDestination: Bool { !running && !showingWindow }
    var canResume: Bool { pauseGranted && !showingWindow }
}
