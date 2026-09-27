// The two sides of a relay, named apart from the loop because settings, the
// panel and the run all speak in it.

/// Which side of the relay a message belongs to. Only the opening message
/// needs naming — every turn after it goes to whoever did not just speak —
/// so this is what `config.first` holds and what the panel nominates before
/// a run starts.
enum Speaker: String {
    case chatgpt
    case claude
}
