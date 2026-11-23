import Foundation
import CoreBluetooth
import Combine

/// Lee la frecuencia cardíaca del dispositivo configurado en Ajustes.
///
/// - AirPods Pro (o Apple Watch): las lecturas llegan por HealthKit.
/// - Pulsera / banda / sensor óptico (Amazfit, Polar, Garmin, Coospo...): se
///   conecta por Bluetooth Low Energy al servicio estándar de frecuencia
///   cardíaca (`0x180D`) y a su característica de medida (`0x2A37`), que es la
///   que exponen prácticamente todos los sensores BLE del mercado.
final class BPMManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let shared = BPMManager()

    @Published var currentBPM: Int = 0
    @Published var isConnected: Bool = false
    @Published var statusText: String = "Sin pulso"
    /// Nombre del dispositivo del que llegan las lecturas.
    @Published var connectedDeviceName: String = ""

    /// Tipo de sensor configurado en Ajustes.
    @Published private(set) var deviceType: HeartRateDeviceType = UserSettingsManager.heartRateDeviceType
    /// Interruptor maestro de Ajustes: sin él no se escanea ni se registra nada.
    @Published private(set) var isTrackingEnabled: Bool = UserSettingsManager.isHeartRateTrackingEnabled

    /// Marca o modelo configurado para la pulsera (etiqueta de la interfaz).
    private var deviceBrand: String = UserSettingsManager.heartRateDeviceBrand

    /// Identificador de restauración del `CBCentralManager`. Gracias a él iOS
    /// mantiene la conexión BLE viva en segundo plano y con la pantalla
    /// apagada, e incluso puede relanzar la app para entregar las lecturas.
    private static let restoreIdentifier: String = "AppGymHeartRateCentral"
    /// Último sensor conectado: permite reconectar sin volver a buscarlo.
    private static let lastPeripheralKey: String = "lastHeartRatePeripheralIdentifier"
    private static let heartRateService: CBUUID = CBUUID(string: "180D")
    private static let heartRateMeasurement: CBUUID = CBUUID(string: "2A37")
    /// Segundos de búsqueda con filtro antes de ampliar el escaneo a todos los
    /// anuncios BLE. Algunas pulseras (Amazfit/Zepp) no incluyen el servicio
    /// `0x180D` en el paquete de descubrimiento inicial.
    private static let broadScanDelay: TimeInterval = 8.0

    /// Callback con cada lectura válida, provenga del pulsómetro BLE o de
    /// HealthKit. Es el único punto de entrada para registrar la sesión y
    /// refrescar la Live Activity, esté la app en primer plano o no.
    var onBPMReceived: ((Int) -> Void)?

    private var centralManager: CBCentralManager?
    private var heartRatePeripheral: CBPeripheral?
    /// El entrenamiento (o el usuario) quiere lecturas ahora mismo.
    private var wantsHeartRate: Bool = false
    /// El escaneo ampliado está activo (sin filtro de servicio).
    private var isBroadScanActive: Bool = false
    /// Evita reintentar en bucle el último sensor si ya no responde.
    private var didAttemptAutoReconnect: Bool = false
    private var fallbackScanWorkItem: DispatchWorkItem?
    private var reconnectWorkItem: DispatchWorkItem?
    private var connectionTimeoutWorkItem: DispatchWorkItem?

    let healthKitManager = HealthKitManager.shared
    private var cancellables = Set<AnyCancellable>()

    override init() {
        super.init()

        // HealthKit (AirPods / Apple Watch)
        healthKitManager.$currentBPM
            .receive(on: DispatchQueue.main)
            .sink { [weak self] bpm in
                guard let self, bpm > 0, self.isTrackingEnabled else { return }
                // HealthKit solo es la fuente cuando el dispositivo configurado
                // son los AirPods; con pulsera manda el sensor BLE.
                guard self.deviceType == .airPods else { return }

                let source: String = self.healthKitManager.dataSourceName
                let name: String? = source == "Buscando..." ? nil : source
                self.publishBPM(bpm, deviceName: name)
            }
            .store(in: &cancellables)

        // Inicialización tardía para asegurar permisos
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.centralManager = CBCentralManager(
                delegate: self,
                queue: nil,
                options: [CBCentralManagerOptionRestoreIdentifierKey: Self.restoreIdentifier]
            )
        }
    }

    // MARK: - Ajustes

    /// Relee los ajustes de Ajustes y aplica los cambios de interruptor o de
    /// tipo de dispositivo. Lo llama la propia app al cambiar los ajustes y
    /// también el observador de `UserDefaults`.
    func applySettings() {
        let newEnabled: Bool = UserSettingsManager.isHeartRateTrackingEnabled
        let newType: HeartRateDeviceType = UserSettingsManager.heartRateDeviceType
        let newBrand: String = UserSettingsManager.heartRateDeviceBrand

        let enabledChanged: Bool = newEnabled != isTrackingEnabled
        let typeChanged: Bool = newType != deviceType

        deviceBrand = newBrand
        guard enabledChanged || typeChanged else { return }

        isTrackingEnabled = newEnabled
        deviceType = newType

        guard newEnabled else {
            stopHardware()
            healthKitManager.stopHeartRateQuery()
            currentBPM = 0
            isConnected = false
            connectedDeviceName = ""
            statusText = "Pulsómetro desactivado"
            return
        }

        if typeChanged {
            disconnectCurrentPeripheral()
        }

        switch newType {
        case .airPods:
            cancelScheduledScans()
            centralManager?.stopScan()
            isBroadScanActive = false
            isConnected = false
            connectedDeviceName = healthKitManager.isAuthorized ? healthKitManager.dataSourceName : ""
            statusText = healthKitManager.currentBPM > 0 ? "\(healthKitManager.currentBPM) BPM" : "Esperando AirPods..."
            healthKitManager.requestAuthorization()

        case .heartRateBand:
            // HealthKit solo se usa con los AirPods: si veníamos de ese modo,
            // cerramos su consulta para no seguir leyendo en segundo plano.
            healthKitManager.stopHeartRateQuery()
            statusText = "Sin pulso"
            didAttemptAutoReconnect = false
            if wantsHeartRate {
                startScanning()
            }
        }
    }

    // MARK: - Escaneo

    func startScanning() {
        wantsHeartRate = true

        guard isTrackingEnabled else {
            statusText = "Pulsómetro desactivado"
            return
        }

        guard deviceType == .heartRateBand else {
            centralManager?.stopScan()
            statusText = healthKitManager.currentBPM > 0 ? "\(healthKitManager.currentBPM) BPM" : "Esperando AirPods..."
            return
        }

        guard let cm = centralManager else {
            statusText = "Iniciando Bluetooth..."
            return
        }

        switch cm.state {
        case .poweredOn:
            reconnectLastKnownPeripheral(using: cm)
            guard heartRatePeripheral == nil else { return }

            statusText = "Buscando..."
            isBroadScanActive = false
            cm.scanForPeripherals(
                withServices: [Self.heartRateService],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
            )
            scheduleBroadScanFallback()
        case .unauthorized:
            statusText = "Sin Permiso BT"
        case .poweredOff:
            statusText = "BT Apagado"
        default:
            statusText = "Bluetooth no listo"
        }
    }

    func stopScanning() {
        wantsHeartRate = false
        didAttemptAutoReconnect = false
        cancelScheduledScans()
        centralManager?.stopScan()
        isBroadScanActive = false
        statusText = isTrackingEnabled ? "Sin pulso" : "Pulsómetro desactivado"
    }

    /// Reconexión manual desde Ajustes. Reinicia también HealthKit cuando el
    /// dispositivo configurado son los AirPods.
    func reconnect() {
        stopHardware()
        currentBPM = 0
        isConnected = false
        connectedDeviceName = ""
        applySettings()

        guard isTrackingEnabled else { return }

        wantsHeartRate = true
        didAttemptAutoReconnect = false
        switch deviceType {
        case .airPods:
            statusText = "Esperando AirPods..."
            healthKitManager.requestAuthorization()
        case .heartRateBand:
            startScanning()
        }
    }

    private func stopHardware() {
        cancelScheduledScans()
        centralManager?.stopScan()
        isBroadScanActive = false

        if let peripheral = heartRatePeripheral {
            heartRatePeripheral = nil
            peripheral.delegate = nil
            centralManager?.cancelPeripheralConnection(peripheral)
        }
    }

    private func disconnectCurrentPeripheral() {
        guard let peripheral = heartRatePeripheral else { return }
        heartRatePeripheral = nil
        peripheral.delegate = nil
        centralManager?.cancelPeripheralConnection(peripheral)
        isConnected = false
    }

    /// Reengancha el último sensor conocido sin esperar a que se anuncie. La
    /// mayoría de pulseras solo se anuncian en modo emparejamiento, así que
    /// esta reconexión es la vía habitual para volver a enlazar.
    private func reconnectLastKnownPeripheral(using central: CBCentralManager) {
        guard !didAttemptAutoReconnect else { return }
        guard heartRatePeripheral == nil,
              let stored = UserDefaults.standard.string(forKey: Self.lastPeripheralKey),
              let identifier = UUID(uuidString: stored) else { return }

        guard let peripheral = central.retrievePeripherals(withIdentifiers: [identifier]).first else { return }

        didAttemptAutoReconnect = true
        heartRatePeripheral = peripheral
        peripheral.delegate = self
        statusText = "Reconectando..."
        connectedDeviceName = peripheral.name ?? displayDeviceName
        central.connect(peripheral, options: nil)
        scheduleConnectionTimeout(for: peripheral)
    }

    /// CoreBluetooth no expira las conexiones pendientes. Si el sensor no
    /// responde (fuera de rango, apagado...), liberamos el intento y volvemos a
    /// buscar para no quedarnos bloqueados en "Reconectando...".
    private func scheduleConnectionTimeout(for peripheral: CBPeripheral) {
        connectionTimeoutWorkItem?.cancel()

        let item = DispatchWorkItem { [weak self] in
            guard let self,
                  let current = self.heartRatePeripheral,
                  current.identifier == peripheral.identifier,
                  current.state != .connected else { return }

            current.delegate = nil
            self.centralManager?.cancelPeripheralConnection(current)
            self.heartRatePeripheral = nil
            self.isConnected = false
            self.statusText = "Sin respuesta del sensor"

            guard self.wantsHeartRate, self.isTrackingEnabled, self.deviceType == .heartRateBand else { return }
            self.startScanning()
        }

        connectionTimeoutWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 12.0, execute: item)
    }

    /// Tras `broadScanDelay` segundos sin resultados, busca entre todos los
    /// anuncios BLE y acepta los que incluyan el servicio de pulso.
    private func scheduleBroadScanFallback() {
        fallbackScanWorkItem?.cancel()

        let item = DispatchWorkItem { [weak self] in
            guard let self,
                  self.isTrackingEnabled,
                  self.deviceType == .heartRateBand,
                  self.wantsHeartRate,
                  self.heartRatePeripheral == nil,
                  let central = self.centralManager,
                  central.state == .poweredOn else { return }

            self.isBroadScanActive = true
            self.statusText = "Buscando sensor BPM..."
            central.scanForPeripherals(
                withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
        }

        fallbackScanWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.broadScanDelay, execute: item)
    }

    private func scheduleReconnect() {
        reconnectWorkItem?.cancel()

        let item = DispatchWorkItem { [weak self] in
            guard let self,
                  self.wantsHeartRate,
                  self.isTrackingEnabled,
                  self.deviceType == .heartRateBand else { return }
            self.startScanning()
        }

        reconnectWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: item)
    }

    private func cancelScheduledScans() {
        fallbackScanWorkItem?.cancel()
        fallbackScanWorkItem = nil
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        connectionTimeoutWorkItem?.cancel()
        connectionTimeoutWorkItem = nil
    }

    // MARK: - Estado del sensor

    /// Nombre mostrado cuando el sensor no anuncia el suyo.
    private var displayDeviceName: String {
        switch deviceType {
        case .airPods:
            return "AirPods"
        case .heartRateBand:
            return deviceBrand.isEmpty ? deviceType.title : deviceBrand
        }
    }

    /// Publica una lectura válida de BPM: actualiza el estado observable y
    /// avisa al callback único de recepción. Es el único punto por el que
    /// pasan tanto el sensor BLE como HealthKit.
    private func publishBPM(_ bpm: Int, deviceName: String? = nil) {
        guard isTrackingEnabled, bpm > 0 else { return }

        currentBPM = bpm
        isConnected = true

        if let deviceName, !deviceName.isEmpty {
            connectedDeviceName = deviceName
        } else if connectedDeviceName.isEmpty {
            connectedDeviceName = displayDeviceName
        }

        statusText = "\(bpm) BPM"
        onBPMReceived?(bpm)
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch central.state {
            case .poweredOn:
                if self.isTrackingEnabled, self.deviceType == .heartRateBand {
                    self.startScanning()
                }
            case .unauthorized:
                self.statusText = "Sin Permiso BT"
            case .poweredOff:
                self.statusText = "BT Apagado"
            default:
                self.statusText = "Bluetooth no listo"
            }
        }
    }

    /// iOS nos devuelve la conexión BLE que seguía activa en segundo plano:
    /// reenganchamos el pulsómetro y reactivamos las notificaciones.
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        guard isTrackingEnabled, deviceType == .heartRateBand else { return }

        let restoredPeripherals: [CBPeripheral] = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        guard let peripheral = restoredPeripherals.first else { return }

        heartRatePeripheral = peripheral
        peripheral.delegate = self

        if peripheral.state == .connected {
            peripheral.discoverServices([Self.heartRateService])
        } else {
            central.connect(peripheral, options: nil)
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String : Any],
        rssi RSSI: NSNumber
    ) {
        guard isTrackingEnabled, deviceType == .heartRateBand else { return }

        if let current = heartRatePeripheral,
           current.state == .connected || current.state == .connecting {
            return
        }

        if isBroadScanActive {
            let advertised: [CBUUID] = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
            guard advertised.contains(Self.heartRateService) else { return }
        }

        heartRatePeripheral = peripheral
        peripheral.delegate = self
        cancelScheduledScans()
        isBroadScanActive = false
        central.stopScan()
        central.connect(peripheral, options: nil)
        scheduleConnectionTimeout(for: peripheral)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.statusText = "Conectando..."
            self.connectedDeviceName = peripheral.name ?? self.displayDeviceName
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        cancelScheduledScans()
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: Self.lastPeripheralKey)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isConnected = true
            self.statusText = "Conectado"
            self.connectedDeviceName = peripheral.name ?? self.displayDeviceName
        }

        peripheral.discoverServices([Self.heartRateService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if heartRatePeripheral?.identifier == peripheral.identifier {
            heartRatePeripheral = nil
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isConnected = false
            self.statusText = "No se pudo conectar"
        }

        scheduleReconnect()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard heartRatePeripheral?.identifier == peripheral.identifier else { return }

        heartRatePeripheral = nil

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isConnected = false
            self.currentBPM = 0
            self.statusText = self.isTrackingEnabled ? "Sin pulso" : "Pulsómetro desactivado"
        }

        guard isTrackingEnabled, deviceType == .heartRateBand, wantsHeartRate else { return }
        scheduleReconnect()
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }

        guard let heartRateService = services.first(where: { (service: CBService) -> Bool in
            return service.uuid == Self.heartRateService
        }) else {
            // La pulsera está enlazada pero no expone el servicio estándar de
            // pulso: hay que activar su emisión por Bluetooth en la app del
            // fabricante (Zepp, Polar Flow, Garmin Connect...).
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isConnected = false
                self.statusText = "Sensor sin servicio HR"
            }
            centralManager?.cancelPeripheralConnection(peripheral)
            return
        }

        peripheral.discoverCharacteristics([Self.heartRateMeasurement], for: heartRateService)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }

        let measurement = characteristics.first { (characteristic: CBCharacteristic) -> Bool in
            return characteristic.uuid == Self.heartRateMeasurement
        }

        guard let measurement else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isConnected = false
                self.statusText = "Sin medida de pulso"
            }
            return
        }

        peripheral.setNotifyValue(true, for: measurement)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == Self.heartRateMeasurement else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let error {
                self.isConnected = false
                self.statusText = "Error al suscribirse"
                print("[BPM] Error al suscribirse a la medida de pulso: \(error.localizedDescription)")
            } else if characteristic.isNotifying {
                self.isConnected = true
                self.statusText = "Conectado"
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Self.heartRateMeasurement,
              let data = characteristic.value,
              !data.isEmpty else { return }

        let buffer = [UInt8](data)
        let flags = buffer[0]
        let is16Bit = (flags & 0x01) != 0

        var bpm: Int = 0
        if is16Bit {
            if buffer.count >= 3 {
                bpm = Int(buffer[1]) | (Int(buffer[2]) << 8)
            }
        } else {
            if buffer.count >= 2 {
                bpm = Int(buffer[1])
            }
        }

        guard bpm > 0 else { return }

        let sourceName: String = peripheral.name ?? displayDeviceName
        DispatchQueue.main.async { [weak self] in
            self?.publishBPM(bpm, deviceName: sourceName)
        }
    }
}
