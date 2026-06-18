import Foundation
import Combine

/// Fuente de verdad de la navegación por teclado, compartida entre el monitor
/// AppKit (PanelController) y la vista SwiftUI (HistoryView).
final class SelectionModel: ObservableObject {
    /// IDs en el MISMO orden que muestra la lista filtrada del View.
    @Published var visibleIDs: [UUID] = []
    /// Índice seleccionado dentro de visibleIDs (-1 = nada).
    @Published var selectedIndex: Int = 0
    /// Se incrementa en cada apertura del panel para que la vista resetee búsqueda y foco.
    @Published var openToken: Int = 0
    /// Se incrementa para devolver el foco al buscador SIN limpiar búsqueda/filtro (p.ej. tras renombrar).
    @Published var focusToken: Int = 0
    /// true mientras el panel está en modo multi-selección por lote: el teclado (Return / ⌘1-9) NO debe
    /// pegar ni cerrar el panel (rompería el lote que el usuario está armando). Lo sincroniza HistoryView.
    @Published var selecting: Bool = false

    var visibleCount: Int { visibleIDs.count }

    var selectedID: UUID? {
        guard visibleIDs.indices.contains(selectedIndex) else { return nil }
        return visibleIDs[selectedIndex]
    }

    /// El View llama a esto cuando cambia la lista filtrada.
    func updateVisible(_ ids: [UUID]) {
        // Re-anclar por ID: si el elemento seleccionado sigue visible, conservar su selección
        // (evita que la selección "salte" al entrar capturas nuevas); si no, ir al primero.
        let prev = selectedID
        visibleIDs = ids
        if let prev, let i = ids.firstIndex(of: prev) { selectedIndex = i }
        else { selectedIndex = ids.isEmpty ? -1 : 0 }
    }

    func moveDown() {
        guard !visibleIDs.isEmpty else { return }
        selectedIndex = min(selectedIndex + 1, visibleIDs.count - 1)
    }

    func moveUp() {
        guard !visibleIDs.isEmpty else { return }
        selectedIndex = max(selectedIndex - 1, 0)
    }

    /// ⌘1..⌘9 → índice 0..8 (si existe).
    func selectQuick(_ n: Int) {
        let i = n - 1
        if visibleIDs.indices.contains(i) { selectedIndex = i }
    }

    func reset() {
        selectedIndex = visibleIDs.isEmpty ? -1 : 0
    }

    private func clamp() {
        if visibleIDs.isEmpty { selectedIndex = -1 }
        else { selectedIndex = max(0, min(selectedIndex, visibleIDs.count - 1)) }
    }
}
