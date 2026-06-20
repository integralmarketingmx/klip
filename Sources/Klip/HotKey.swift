import Carbon.HIToolbox
import AppKit

/// Atajo de teclado GLOBAL (funciona aunque la app no esté en primer plano),
/// usando la API Carbon RegisterEventHotKey. No requiere permisos de Accesibilidad.
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let id: UInt32
    private let callback: () -> Void

    /// Mapa estático para que el callback en C (sin captura) pueda localizar la instancia.
    /// El handler de Carbon corre en el main thread (igual que init/deinit), pero protegemos el
    /// acceso con un lock para que sea correcto por construcción y no dependa de esa suposición.
    private static var instances: [UInt32: HotKey] = [:]
    private static let instancesLock = NSLock()
    private static var handlerInstalled = false

    private static func setInstance(_ id: UInt32, _ hk: HotKey?) {
        instancesLock.lock(); defer { instancesLock.unlock() }
        instances[id] = hk
    }
    private static func instance(_ id: UInt32) -> HotKey? {
        instancesLock.lock(); defer { instancesLock.unlock() }
        return instances[id]
    }

    /// - Parameters:
    ///   - keyCode: código de tecla virtual (p. ej. kVK_ANSI_V).
    ///   - modifiers: combinación Carbon (p. ej. cmdKey | shiftKey).
    init?(keyCode: UInt32, modifiers: UInt32, id: UInt32 = 1, callback: @escaping () -> Void) {
        self.id = id
        self.callback = callback
        HotKey.setInstance(id, self)

        HotKey.installHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: OSType(0x50415354), id: id) // 'PAST'
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            HotKey.setInstance(id, nil)
            return nil
        }
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(event,
                              EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID),
                              nil,
                              MemoryLayout<EventHotKeyID>.size,
                              nil,
                              &hkID)
            if let instance = HotKey.instance(hkID.id) {
                DispatchQueue.main.async { instance.callback() }
            }
            return noErr
        }, 1, &eventType, nil, nil)
    }

    /// Re-registra en caliente con una nueva combinación, reusando id y callback.
    /// El handler global ya instalado sigue válido; no se reinstala.
    @discardableResult
    func reRegister(keyCode: UInt32, modifiers: UInt32) -> Bool {
        // Registrar el NUEVO en una ref temporal; solo soltar el viejo si tuvo éxito,
        // para no quedarnos sin atajo si la combinación colisiona.
        let hotKeyID = EventHotKeyID(signature: OSType(0x50415354), id: id) // 'PAST'
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &newRef)
        guard status == noErr, let newRef else { return false }
        if let old = hotKeyRef { UnregisterEventHotKey(old) }
        hotKeyRef = newRef
        return true
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        HotKey.setInstance(id, nil)
    }
}
