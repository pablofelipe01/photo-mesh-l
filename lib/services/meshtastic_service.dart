import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:meshtastic_flutter/meshtastic_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

import '../models/chat_message.dart';
import '../models/image_transmission.dart';

const int maxMessageBytes = 237;
const String _savedDeviceAddressKey = 'saved_device_address';
const String _savedDeviceNameKey = 'saved_device_name';
const String _gatewayNodeIdKey = 'gateway_node_id';
const String _photoQualityKey = 'photo_quality';
const String _messageHistoryKey = 'message_history';
const int _maxMessageHistory = 100;
const int _maxReconnectAttempts = 10;
const Duration _reconnectDelay = Duration(seconds: 2);
const Duration _keepaliveInterval = Duration(seconds: 15);

enum ConnectionStatus { disconnected, scanning, connecting, connected, error }

class ScannedDevice {
  final String name;
  final String address;
  final dynamic rawDevice;

  ScannedDevice({required this.name, required this.address, this.rawDevice});
}

class MeshtasticService extends ChangeNotifier {
  MeshtasticClient? _client;
  ConnectionStatus _status = ConnectionStatus.disconnected;
  String _statusMessage = 'Desconectado';
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _packetSubscription;
  String? _connectedDeviceName;
  String? _connectedDeviceMac;

  // Auto-reconnect
  bool _autoReconnectEnabled = false;
  bool _isReconnecting = false;

  // Keepalive
  Timer? _keepaliveTimer;

  // Chat
  final List<ChatMessage> _messageHistory = [];
  final Map<int, MeshNode> _knownNodes = {};
  final Set<int> _processedPacketIds = {};
  final int _myNodeId = 0;

  // Streams
  final _messageController = StreamController<ChatMessage>.broadcast();
  final _imageResultController = StreamController<ImageResult>.broadcast();

  // Image transmission
  ImageTransmission? _activeTransmission;
  Timer? _imageTimeoutTimer;

  // Preloaded nodes
  static final Map<int, MeshNode> _preloadedNodes = {
    0x9ea29bc4: MeshNode(nodeId: 0x9ea29bc4, nodeName: 'Mission Pack'),
    0x7c1a5974: MeshNode(nodeId: 0x7c1a5974, nodeName: 'Pablo A'),
    0xf515b946: MeshNode(nodeId: 0xf515b946, nodeName: 'Pablo Long'),
    0x455250c3: MeshNode(nodeId: 0x455250c3, nodeName: 'David_Inge'),
    0x4190dee3: MeshNode(nodeId: 0x4190dee3, nodeName: 'Test David'),
    0x4bf18b6e: MeshNode(nodeId: 0x4bf18b6e, nodeName: 'Mac Commander'),
  };

  MeshtasticService() {
    _knownNodes.addAll(_preloadedNodes);
    _loadSavedGatewayNodeId();
    _loadMessageHistory();
  }

  // Getters
  ConnectionStatus get status => _status;
  String get statusMessage => _statusMessage;
  bool get isConnected => _status == ConnectionStatus.connected;
  String? get connectedDeviceName => _connectedDeviceName;
  String? get connectedDeviceMac => _connectedDeviceMac;
  List<ChatMessage> get messageHistory => List.unmodifiable(_messageHistory);
  Stream<ChatMessage> get messageStream => _messageController.stream;
  Stream<ImageResult> get imageResultStream => _imageResultController.stream;
  Map<int, MeshNode> get knownNodes => Map.unmodifiable(_knownNodes);
  int get myNodeId => _client?.myNodeInfo?.myNodeNum ?? _myNodeId;
  ImageTransmission? get activeTransmission => _activeTransmission;

  int? _savedGatewayNodeId;
  int? get savedGatewayNodeId => _savedGatewayNodeId;

  // Photo quality: false = fast (160x120), true = detailed (200x200)
  bool _detailedQuality = false;
  bool get detailedQuality => _detailedQuality;

  void _updateStatus(ConnectionStatus newStatus, String message) {
    _status = newStatus;
    _statusMessage = message;
    notifyListeners();
  }

  // --- Persistence ---

  Future<String?> getSavedDeviceAddress() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_savedDeviceAddressKey);
  }

  Future<String?> getSavedDeviceName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_savedDeviceNameKey);
  }

  Future<void> saveDeviceInfo(String address, String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_savedDeviceAddressKey, address);
    await prefs.setString(_savedDeviceNameKey, name);
  }

  Future<void> clearSavedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_savedDeviceAddressKey);
    await prefs.remove(_savedDeviceNameKey);
  }

  Future<void> _loadSavedGatewayNodeId() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt(_gatewayNodeIdKey);
    if (saved != null) {
      _savedGatewayNodeId = saved;
    } else {
      // Default to Mission Pack
      _savedGatewayNodeId = 0x9ea29bc4;
    }
    _detailedQuality = prefs.getBool(_photoQualityKey) ?? false;
    notifyListeners();
  }

  Future<void> saveGatewayNodeId(int nodeId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_gatewayNodeIdKey, nodeId);
    _savedGatewayNodeId = nodeId;
    notifyListeners();
  }

  Future<void> setDetailedQuality(bool detailed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_photoQualityKey, detailed);
    _detailedQuality = detailed;
    notifyListeners();
  }

  // --- Connection ---

  Stream<ScannedDevice> scanDevices() async* {
    _client ??= MeshtasticClient();
    await _client!.initialize();
    _updateStatus(ConnectionStatus.scanning, 'Buscando dispositivos...');

    await for (final device in _client!.scanForDevices(timeout: const Duration(seconds: 15))) {
      yield ScannedDevice(
        name: device.platformName.isNotEmpty ? device.platformName : 'Desconocido',
        address: device.remoteId.str,
        rawDevice: device,
      );
    }
  }

  Future<void> connectToSavedDevice() async {
    if (_status == ConnectionStatus.connected || _status == ConnectionStatus.connecting) return;

    final address = await getSavedDeviceAddress();
    if (address == null) return;

    await connectToDeviceByAddress(address);
  }

  Future<void> connectToDeviceByAddress(String address) async {
    _updateStatus(ConnectionStatus.connecting, 'Conectando...');

    try {
      _client ??= MeshtasticClient();
      await _client!.initialize();

      await _connectionSubscription?.cancel();
      await _packetSubscription?.cancel();

      _setupConnectionListener();
      _setupPacketListener();

      // Scan for the specific device
      await for (final device in _client!.scanForDevices(timeout: const Duration(seconds: 10))) {
        if (device.remoteId.str == address) {
          await _client!.connectToDevice(device);
          _connectedDeviceMac = address;
          _connectedDeviceName = device.platformName.isNotEmpty ? device.platformName : await getSavedDeviceName();
          return;
        }
      }

      _updateStatus(ConnectionStatus.error, 'Dispositivo no encontrado');
    } catch (e) {
      _updateStatus(ConnectionStatus.error, 'Error: $e');
      if (_autoReconnectEnabled) {
        _attemptReconnect();
      }
    }
  }

  Future<void> connectToDevice(ScannedDevice device) async {
    _updateStatus(ConnectionStatus.connecting, 'Conectando a ${device.name}...');

    try {
      _client ??= MeshtasticClient();
      await _client!.initialize();

      await _connectionSubscription?.cancel();
      await _packetSubscription?.cancel();

      _setupConnectionListener();
      _setupPacketListener();

      await _client!.connectToDevice(device.rawDevice);
      _connectedDeviceName = device.name;
      _connectedDeviceMac = device.address;
      await saveDeviceInfo(device.address, device.name);
    } catch (e) {
      _updateStatus(ConnectionStatus.error, 'Error: $e');
    }
  }

  void _setupConnectionListener() {
    _connectionSubscription = _client!.connectionStream.listen((status) {
      final stateStr = status.state.toString().toLowerCase();
      if (stateStr.contains('connected') && !stateStr.contains('dis')) {
        _updateStatus(ConnectionStatus.connected, 'Conectado');
        _autoReconnectEnabled = true;
        _startKeepalive();
        _addSystemMessage('Conectado a ${_connectedDeviceName ?? "dispositivo"}');
      } else if (stateStr.contains('disconnect')) {
        _onUnexpectedDisconnect();
      }
    });
  }

  void _setupPacketListener() {
    _packetSubscription = _client!.packetStream.listen((packet) {
      _handlePacket(packet);
    });
  }

  void _onUnexpectedDisconnect() {
    _stopKeepalive();
    _updateStatus(ConnectionStatus.disconnected, 'Desconectado');
    _addSystemMessage('Conexion perdida');
    if (_autoReconnectEnabled) {
      _attemptReconnect();
    }
  }

  Future<void> _attemptReconnect() async {
    if (_isReconnecting) return;
    _isReconnecting = true;

    final address = _connectedDeviceMac ?? await getSavedDeviceAddress();
    if (address == null) {
      _isReconnecting = false;
      return;
    }

    for (int i = 0; i < _maxReconnectAttempts; i++) {
      if (_status == ConnectionStatus.connected) break;

      _updateStatus(ConnectionStatus.connecting, 'Reconectando (${i + 1}/$_maxReconnectAttempts)...');
      await Future.delayed(_reconnectDelay);

      try {
        _client = MeshtasticClient();
        await _client!.initialize();

        _setupConnectionListener();
        _setupPacketListener();

        await for (final device in _client!.scanForDevices(timeout: const Duration(seconds: 8))) {
          if (device.remoteId.str == address) {
            await _client!.connectToDevice(device);
            _isReconnecting = false;
            return;
          }
        }
      } catch (_) {
        // Continue trying
      }
    }

    _isReconnecting = false;
    if (_status != ConnectionStatus.connected) {
      _updateStatus(ConnectionStatus.error, 'No se pudo reconectar');
    }
  }

  void _startKeepalive() {
    _keepaliveTimer?.cancel();
    _keepaliveTimer = Timer.periodic(_keepaliveInterval, (_) {
      try {
        _client?.keepAlive();
      } catch (_) {}
    });
  }

  void _stopKeepalive() {
    _keepaliveTimer?.cancel();
    _keepaliveTimer = null;
  }

  Future<void> disconnect() async {
    _autoReconnectEnabled = false;
    _stopKeepalive();
    await _connectionSubscription?.cancel();
    await _packetSubscription?.cancel();
    _connectionSubscription = null;
    _packetSubscription = null;

    try {
      await _client?.disconnect();
    } catch (_) {}
    _client = null;

    _connectedDeviceName = null;
    _connectedDeviceMac = null;
    _updateStatus(ConnectionStatus.disconnected, 'Desconectado');
  }

  Future<void> disconnectAndClear() async {
    await disconnect();
    await clearSavedDevice();
  }

  // --- Messaging ---

  static int getUtf8ByteLength(String text) {
    return utf8.encode(text).length;
  }

  Future<void> sendChatMessage(String text, {int? destinationId}) async {
    if (_client == null || !isConnected) return;
    if (text.isEmpty) return;

    final byteLen = getUtf8ByteLength(text);
    if (byteLen > maxMessageBytes) return;

    try {
      await _client!.sendTextMessage(
        text,
        destinationId: destinationId,
        channel: 0,
      );

      final message = ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        messageText: text,
        fromNodeId: myNodeId,
        fromNodeName: 'Yo',
        isMine: true,
        type: ChatMessageType.text,
      );

      _addMessage(message);
    } catch (e) {
      debugPrint('Error enviando mensaje: $e');
    }
  }

  Future<void> sendDirectMessage(String text, int destinationId) async {
    if (_client == null || !isConnected) return;
    if (text.isEmpty) return;

    try {
      await _client!.sendTextMessage(
        text,
        destinationId: destinationId,
        channel: 0,
      );
    } catch (e) {
      debugPrint('Error enviando mensaje directo: $e');
    }
  }

  void _addMessage(ChatMessage message) {
    _messageHistory.add(message);
    if (_messageHistory.length > _maxMessageHistory) {
      _messageHistory.removeAt(0);
    }
    _messageController.add(message);
    _saveMessageHistory();
    notifyListeners();
  }

  void _addSystemMessage(String text) {
    _addMessage(ChatMessage(
      id: 'sys_${DateTime.now().millisecondsSinceEpoch}',
      messageText: text,
      fromNodeId: 0,
      fromNodeName: 'Sistema',
      type: ChatMessageType.system,
    ));
  }

  // --- Packet Handling ---

  void _handlePacket(dynamic packet) {
    try {
      final packetId = packet.id as int? ?? 0;

      // Deduplication
      if (packetId != 0 && _processedPacketIds.contains(packetId)) return;
      _processedPacketIds.add(packetId);
      if (_processedPacketIds.length > 100) {
        _processedPacketIds.remove(_processedPacketIds.first);
      }

      final fromNodeId = packet.from as int? ?? 0;

      // Skip own messages
      if (fromNodeId == myNodeId && myNodeId != 0) return;

      // Update known nodes
      if (packet.isNodeInfo == true) {
        _updateKnownNode(fromNodeId, null);
        return;
      }

      // Skip non-text
      if (packet.isTextMessage != true) return;

      // Extract text
      String? text;
      try {
        final payload = packet.decoded?.payload;
        if (payload != null) {
          text = utf8.decode(payload, allowMalformed: true);
        }
      } catch (_) {}
      text ??= packet.textMessage as String?;
      if (text == null || text.isEmpty) return;

      final nodeName = _getNodeName(fromNodeId);

      // Route by prefix
      if (text.startsWith('IMG_ACK:')) {
        _handleImageAck(text);
      } else if (text.startsWith('IMG_RETRY:')) {
        _handleImageRetry(text);
      } else if (text.startsWith('IMG_OK:')) {
        _handleImageOk(text);
      } else if (text.startsWith('IMG_RESULT:')) {
        _handleImageResult(text);
      } else if (text.startsWith('IMG_ERROR:')) {
        _handleImageError(text);
      } else {
        // Normal chat message
        final message = ChatMessage(
          id: packetId.toString(),
          messageText: text,
          fromNodeId: fromNodeId,
          fromNodeName: nodeName,
          type: ChatMessageType.text,
        );
        _addMessage(message);
      }
    } catch (e) {
      debugPrint('Error handling packet: $e');
    }
  }

  String _getNodeName(int nodeId) {
    if (_knownNodes.containsKey(nodeId)) {
      return _knownNodes[nodeId]!.nodeName;
    }

    // Check client nodes
    final clientNodes = _client?.nodes;
    if (clientNodes != null && clientNodes.containsKey(nodeId)) {
      final node = clientNodes[nodeId]!;
      final name = node.displayName;
      _updateKnownNode(nodeId, name);
      return name;
    }

    return '!${nodeId.toRadixString(16).padLeft(8, '0')}';
  }

  void _updateKnownNode(int nodeId, String? nodeName) {
    final existing = _knownNodes[nodeId];
    if (existing != null) {
      existing.isOnline = true;
      existing.lastSeen = DateTime.now();
    } else {
      _knownNodes[nodeId] = MeshNode(
        nodeId: nodeId,
        nodeName: nodeName ?? '!${nodeId.toRadixString(16).padLeft(8, '0')}',
      );
    }
    notifyListeners();
  }

  // --- Image Protocol Handlers ---

  void _handleImageAck(String text) {
    // IMG_ACK:<imageId>:<chunkIndex>
    final parts = text.split(':');
    if (parts.length < 3) return;
    final imageId = parts[1];
    if (_activeTransmission == null || _activeTransmission!.imageId != imageId) return;

    _activeTransmission!.chunksConfirmed++;
    notifyListeners();
  }

  void _handleImageRetry(String text) {
    // IMG_RETRY:<imageId>:<chunk1>,<chunk2>,...
    final parts = text.split(':');
    if (parts.length < 3) return;
    final imageId = parts[1];
    if (_activeTransmission == null || _activeTransmission!.imageId != imageId) return;

    final missing = parts[2].split(',').map((s) => int.tryParse(s) ?? -1).where((i) => i >= 0).toList();
    _activeTransmission!.missingChunks = missing;
    _activeTransmission!.state = ImageTransmissionState.retransmitting;
    _activeTransmission!.retryRound++;
    notifyListeners();

    if (_activeTransmission!.retryRound <= 2) {
      _retransmitChunks();
    } else {
      _activeTransmission!.state = ImageTransmissionState.error;
      _activeTransmission!.errorMessage = 'Maximo de reintentos alcanzado';
      _addImageErrorMessage('No se pudo enviar la foto despues de 2 reintentos');
      notifyListeners();
    }
  }

  void _handleImageOk(String text) {
    // IMG_OK:<imageId>
    final parts = text.split(':');
    if (parts.length < 2) return;
    final imageId = parts[1];
    if (_activeTransmission == null || _activeTransmission!.imageId != imageId) return;

    _activeTransmission!.state = ImageTransmissionState.waitingResult;
    _cancelImageTimeout();
    _startResultTimeout();
    notifyListeners();

    _addMessage(ChatMessage(
      id: 'img_ok_${DateTime.now().millisecondsSinceEpoch}',
      messageText: 'Foto recibida por el gateway. Analizando...',
      fromNodeId: 0,
      fromNodeName: 'Sistema',
      type: ChatMessageType.system,
    ));
  }

  void _handleImageResult(String text) {
    // IMG_RESULT:<imageId>:<partIndex>/<totalParts>:<text>
    final firstColon = text.indexOf(':');
    final secondColon = text.indexOf(':', firstColon + 1);
    final thirdColon = text.indexOf(':', secondColon + 1);

    if (thirdColon < 0) return;

    final imageId = text.substring(firstColon + 1, secondColon);
    final partInfo = text.substring(secondColon + 1, thirdColon);
    final resultText = text.substring(thirdColon + 1);

    final partParts = partInfo.split('/');
    final partIndex = int.tryParse(partParts[0]) ?? 0;
    final totalParts = int.tryParse(partParts.length > 1 ? partParts[1] : '1') ?? 1;

    if (_activeTransmission != null && _activeTransmission!.imageId == imageId) {
      _activeTransmission!.totalResultParts = totalParts;

      // Store part
      while (_activeTransmission!.resultParts.length <= partIndex) {
        _activeTransmission!.resultParts.add('');
      }
      _activeTransmission!.resultParts[partIndex] = resultText;

      // Check if all parts received
      final receivedCount = _activeTransmission!.resultParts.where((p) => p.isNotEmpty).length;
      if (receivedCount >= totalParts) {
        final fullResult = _activeTransmission!.resultParts.join('');
        _activeTransmission!.resultText = fullResult;
        _activeTransmission!.state = ImageTransmissionState.completed;
        _cancelImageTimeout();

        _addMessage(ChatMessage(
          id: 'img_result_${DateTime.now().millisecondsSinceEpoch}',
          messageText: fullResult,
          fromNodeId: _savedGatewayNodeId ?? 0,
          fromNodeName: 'AgroCam IA',
          type: ChatMessageType.imageResult,
          imageId: imageId,
        ));

        _imageResultController.add(ImageResult(
          imageId: imageId,
          text: fullResult,
          isComplete: true,
        ));

        // Vibrate on result received
        Vibration.vibrate(duration: 500);
      }

      notifyListeners();
    }
  }

  void _handleImageError(String text) {
    // IMG_ERROR:<imageId>:<errorMessage>
    final parts = text.split(':');
    if (parts.length < 3) return;
    final imageId = parts[1];
    final errorMsg = parts.sublist(2).join(':');

    if (_activeTransmission != null && _activeTransmission!.imageId == imageId) {
      _activeTransmission!.state = ImageTransmissionState.error;
      _activeTransmission!.errorMessage = errorMsg;
      _cancelImageTimeout();
      notifyListeners();
    }

    _addImageErrorMessage(errorMsg);
  }

  void _addImageErrorMessage(String errorMsg) {
    _addMessage(ChatMessage(
      id: 'img_err_${DateTime.now().millisecondsSinceEpoch}',
      messageText: 'Error: $errorMsg',
      fromNodeId: 0,
      fromNodeName: 'Sistema',
      type: ChatMessageType.imageError,
    ));
  }

  // --- Image Sending ---

  Future<void> sendImage(ImageTransmission transmission) async {
    if (_client == null || !isConnected) return;
    if (_savedGatewayNodeId == null) return;

    _activeTransmission = transmission;
    _activeTransmission!.state = ImageTransmissionState.sending;
    notifyListeners();

    final gatewayId = _savedGatewayNodeId!;

    // Send IMG_START
    final startMsg = 'IMG_START:${transmission.imageId}:${transmission.tipo}:${transmission.chunks.length}:${transmission.checksum}';
    await sendDirectMessage(startMsg, gatewayId);
    await Future.delayed(const Duration(milliseconds: 2500));

    // Send chunks
    for (int i = 0; i < transmission.chunks.length; i++) {
      if (_activeTransmission == null || _activeTransmission!.state == ImageTransmissionState.cancelled) {
        return;
      }

      final chunkMsg = 'IMG_DATA:${transmission.imageId}:$i:${transmission.chunks[i]}';
      await sendDirectMessage(chunkMsg, gatewayId);
      _activeTransmission!.chunksSent = i + 1;
      notifyListeners();

      // Update progress message
      _updateImageProgressInChat();

      await Future.delayed(const Duration(milliseconds: 2500));
    }

    // Send IMG_END
    final endMsg = 'IMG_END:${transmission.imageId}:${transmission.chunks.length}:${transmission.checksum}';
    await sendDirectMessage(endMsg, gatewayId);

    _activeTransmission!.state = ImageTransmissionState.waitingAck;
    notifyListeners();

    // Timeout: 60s without IMG_OK -> resend IMG_END
    _startAckTimeout();
  }

  Future<void> _retransmitChunks() async {
    if (_activeTransmission == null) return;
    final gatewayId = _savedGatewayNodeId!;

    for (final chunkIdx in _activeTransmission!.missingChunks) {
      if (_activeTransmission == null || _activeTransmission!.state == ImageTransmissionState.cancelled) {
        return;
      }
      if (chunkIdx < _activeTransmission!.chunks.length) {
        final chunkMsg = 'IMG_DATA:${_activeTransmission!.imageId}:$chunkIdx:${_activeTransmission!.chunks[chunkIdx]}';
        await sendDirectMessage(chunkMsg, gatewayId);
        await Future.delayed(const Duration(milliseconds: 2500));
      }
    }

    // Re-send IMG_END
    final endMsg = 'IMG_END:${_activeTransmission!.imageId}:${_activeTransmission!.chunks.length}:${_activeTransmission!.checksum}';
    await sendDirectMessage(endMsg, gatewayId);
    _activeTransmission!.state = ImageTransmissionState.waitingAck;
    notifyListeners();
  }

  void cancelImageTransmission() {
    if (_activeTransmission != null) {
      _activeTransmission!.state = ImageTransmissionState.cancelled;
      _cancelImageTimeout();
      notifyListeners();
      _addSystemMessage('Envio de foto cancelado');
    }
  }

  void _updateImageProgressInChat() {
    // Progress updates are handled via notifyListeners - the widget observes activeTransmission
  }

  void _startAckTimeout() {
    _cancelImageTimeout();
    _imageTimeoutTimer = Timer(const Duration(seconds: 60), () {
      if (_activeTransmission != null &&
          _activeTransmission!.state == ImageTransmissionState.waitingAck) {
        // Resend IMG_END
        final endMsg = 'IMG_END:${_activeTransmission!.imageId}:${_activeTransmission!.chunks.length}:${_activeTransmission!.checksum}';
        sendDirectMessage(endMsg, _savedGatewayNodeId!);

        // After another 60s, give up
        _imageTimeoutTimer = Timer(const Duration(seconds: 60), () {
          if (_activeTransmission != null &&
              _activeTransmission!.state == ImageTransmissionState.waitingAck) {
            _activeTransmission!.state = ImageTransmissionState.error;
            _activeTransmission!.errorMessage = 'Sin respuesta del gateway';
            notifyListeners();
            _addImageErrorMessage('No se recibio confirmacion del gateway');
          }
        });
      }
    });
  }

  void _startResultTimeout() {
    _cancelImageTimeout();
    _imageTimeoutTimer = Timer(const Duration(seconds: 120), () {
      if (_activeTransmission != null &&
          _activeTransmission!.state == ImageTransmissionState.waitingResult) {
        _activeTransmission!.state = ImageTransmissionState.error;
        _activeTransmission!.errorMessage = 'Tiempo de espera agotado';
        notifyListeners();
        _addImageErrorMessage('No se recibio el diagnostico (tiempo agotado)');
      }
    });
  }

  void _cancelImageTimeout() {
    _imageTimeoutTimer?.cancel();
    _imageTimeoutTimer = null;
  }

  // --- Message Persistence ---

  Future<void> _loadMessageHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_messageHistoryKey);
      if (saved == null) return;

      for (final json in saved) {
        try {
          final map = jsonDecode(json) as Map<String, dynamic>;
          _messageHistory.add(ChatMessage(
            id: map['id'] as String,
            messageText: map['text'] as String,
            fromNodeId: map['fromNodeId'] as int,
            fromNodeName: map['fromNodeName'] as String? ?? '',
            timestamp: DateTime.fromMillisecondsSinceEpoch(map['ts'] as int),
            isMine: map['isMine'] as bool? ?? false,
            type: ChatMessageType.values[map['type'] as int? ?? 0],
          ));
        } catch (_) {}
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _saveMessageHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Save last 50 messages
      final toSave = _messageHistory.length > 50
          ? _messageHistory.sublist(_messageHistory.length - 50)
          : _messageHistory;

      final encoded = toSave.map((m) => jsonEncode({
        'id': m.id,
        'text': m.messageText,
        'fromNodeId': m.fromNodeId,
        'fromNodeName': m.fromNodeName,
        'ts': m.timestamp.millisecondsSinceEpoch,
        'isMine': m.isMine,
        'type': m.type.index,
      })).toList();

      await prefs.setStringList(_messageHistoryKey, encoded);
    } catch (_) {}
  }

  @override
  void dispose() {
    _stopKeepalive();
    _cancelImageTimeout();
    _connectionSubscription?.cancel();
    _packetSubscription?.cancel();
    _messageController.close();
    _imageResultController.close();
    try {
      _client?.disconnect();
    } catch (_) {}
    super.dispose();
  }
}
