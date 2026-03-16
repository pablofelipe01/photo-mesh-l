import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/agro_context.dart';
import '../models/chat_message.dart';
import '../models/image_transmission.dart';
import '../models/session.dart';
import '../services/image_service.dart';
import '../services/meshtastic_service.dart';
import '../widgets/context_form.dart';
import '../widgets/transmission_progress.dart';

class ChatScreen extends StatefulWidget {
  final MeshtasticService service;

  const ChatScreen({super.key, required this.service});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _imagePicker = ImagePicker();
  StreamSubscription<ChatMessage>? _messageSubscription;
  StreamSubscription<Map<String, String>>? _sessionSubscription;
  int _currentByteCount = 0;
  bool _isSending = false;
  int? _selectedDestinationId;
  ConsultaSession? _activeSession;

  MeshtasticService get _service => widget.service;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
    _messageSubscription = _service.messageStream.listen((_) {
      _scrollToBottom();
    });
    _sessionSubscription = _service.sessionStream.listen((event) {
      if (event['event'] == 'ended') {
        final sesId = event['sessionId'];
        if (_activeSession != null && _activeSession!.sessionId == sesId) {
          setState(() {
            _activeSession?.isActive = false;
            _activeSession = null;
          });
        }
      }
    });
    _textController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    _messageSubscription?.cancel();
    _sessionSubscription?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  void _onTextChanged() {
    setState(() {
      _currentByteCount = MeshtasticService.getUtf8ByteLength(_textController.text);
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty || !_service.isConnected) return;
    if (_currentByteCount > maxMessageBytes) return;

    setState(() => _isSending = true);
    _textController.clear();

    await _service.sendChatMessage(text, destinationId: _selectedDestinationId);

    setState(() => _isSending = false);
    _scrollToBottom();
  }

  void _onCameraPressed() {
    if (!_service.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Conecta la radio primero')),
      );
      return;
    }

    if (_service.savedGatewayNodeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configura un gateway en Configuracion')),
      );
      return;
    }

    if (_service.activeTransmission != null &&
        _service.activeTransmission!.state != ImageTransmissionState.completed &&
        _service.activeTransmission!.state != ImageTransmissionState.error &&
        _service.activeTransmission!.state != ImageTransmissionState.cancelled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ya hay un envio en progreso')),
      );
      return;
    }

    _showTypeSelector();
  }

  void _showTypeSelector() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _TypeSelectorSheet(
        onTypeSelected: (tipo) {
          Navigator.pop(ctx);
          _capturePhoto(tipo);
        },
      ),
    );
  }

  Future<void> _capturePhoto(String tipo) async {
    try {
      final photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
      );

      if (photo == null) return;

      final imageBytes = await File(photo.path).readAsBytes();

      if (!mounted) return;

      _showContextForm(imageBytes, tipo);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al tomar foto: $e')),
        );
      }
    }
  }

  void _showContextForm(dynamic imageBytes, String tipo) {
    final transmission = ImageService.prepareTransmission(
      imageBytes,
      tipo,
      detailed: _service.detailedQuality,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollController) => SingleChildScrollView(
          controller: scrollController,
          child: ContextFormSheet(
            transmission: transmission,
            detailedQuality: _service.detailedQuality,
            tipo: tipo,
            onSend: _startSendingWithContext,
            onRetake: _capturePhoto,
          ),
        ),
      ),
    );
  }

  Future<void> _startSendingWithContext(ImageTransmission transmission, AgroContext agroContext) async {
    transmission.context = agroContext;

    // Send structured context message first
    final ctxMessage = agroContext.toWireFormat();
    await _service.sendChatMessage(
      ctxMessage,
      destinationId: _service.savedGatewayNodeId,
    );

    // Wait for context to arrive before sending image
    await Future.delayed(const Duration(seconds: 2));

    _service.sendImage(transmission);
    _scrollToBottom();
  }

  // --- Session methods ---

  void _startSession(String imageId, String sessionId) {
    setState(() {
      _activeSession = ConsultaSession(
        sessionId: sessionId,
        imageId: imageId,
      );
    });
  }

  Future<void> _sendSessionQuestion() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _activeSession == null || !_activeSession!.canAskMore) return;

    final session = _activeSession!;
    setState(() => _isSending = true);
    _textController.clear();

    session.questionCount++;
    session.messages.add(SessionMessage(text: text, isQuestion: true));

    final msg = 'SES_${session.sessionId}|$text';
    await _service.sendChatMessage(msg, destinationId: _service.savedGatewayNodeId);

    setState(() => _isSending = false);
    _scrollToBottom();
  }

  Future<void> _endSession() async {
    if (_activeSession == null) return;
    final sesId = _activeSession!.sessionId;

    await _service.sendChatMessage(
      'SES_END|$sesId',
      destinationId: _service.savedGatewayNodeId,
    );

    setState(() {
      _activeSession?.isActive = false;
      _activeSession = null;
    });
  }

  Widget _buildDestinationBar() {
    final nodes = _service.knownNodes;
    String destinationLabel;
    if (_selectedDestinationId == null) {
      destinationLabel = 'Todos (broadcast)';
    } else if (nodes.containsKey(_selectedDestinationId)) {
      destinationLabel = nodes[_selectedDestinationId]!.nodeName;
    } else {
      destinationLabel = '!${_selectedDestinationId!.toRadixString(16).padLeft(8, '0')}';
    }

    return GestureDetector(
      onTap: _showDestinationPicker,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          border: Border(
            bottom: BorderSide(color: Colors.grey.shade300, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.near_me, size: 16, color: Colors.grey.shade600),
            const SizedBox(width: 8),
            Text(
              'Para: ',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            Expanded(
              child: Text(
                destinationLabel,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.arrow_drop_down, size: 20, color: Colors.grey.shade600),
          ],
        ),
      ),
    );
  }

  void _showDestinationPicker() {
    final nodes = _service.knownNodes;
    final nodeList = nodes.values.toList();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Enviar a',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              // Broadcast option
              ListTile(
                leading: const Icon(Icons.cell_tower),
                title: const Text('Todos (broadcast)'),
                subtitle: const Text('Mensaje a todos los nodos'),
                selected: _selectedDestinationId == null,
                selectedTileColor: Colors.green.shade50,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onTap: () {
                  setState(() => _selectedDestinationId = null);
                  Navigator.pop(ctx);
                },
              ),
              const Divider(),
              // Known nodes
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.35,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: nodeList.length,
                  itemBuilder: (context, index) {
                    final node = nodeList[index];
                    return ListTile(
                      leading: Icon(
                        Icons.router,
                        color: node.isOnline ? Colors.green.shade600 : Colors.grey,
                      ),
                      title: Text(node.nodeName),
                      subtitle: Text(node.nodeIdHex),
                      selected: _selectedDestinationId == node.nodeId,
                      selectedTileColor: Colors.green.shade50,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      onTap: () {
                        setState(() => _selectedDestinationId = node.nodeId);
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final messages = _service.messageHistory;
    final isOverLimit = _currentByteCount > maxMessageBytes;
    final activeTransmission = _service.activeTransmission;
    final showTransmission = activeTransmission != null &&
        activeTransmission.state != ImageTransmissionState.idle &&
        activeTransmission.state != ImageTransmissionState.completed &&
        activeTransmission.state != ImageTransmissionState.cancelled;

    return Column(
      children: [
        _buildConnectionBar(),
        Expanded(
          child: messages.isEmpty && !showTransmission
              ? _buildEmptyState()
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  itemCount: messages.length + (showTransmission ? 1 : 0),
                  itemBuilder: (context, index) {
                    // Show transmission progress at the bottom
                    if (showTransmission && index == messages.length) {
                      return TransmissionProgressCard(
                        transmission: activeTransmission,
                        onCancel: () => _service.cancelImageTransmission(),
                      );
                    }

                    final msg = messages[index];
                    final showDate = index == 0 ||
                        !_isSameDay(messages[index - 1].timestamp, msg.timestamp);
                    return Column(
                      children: [
                        if (showDate) _buildDateSeparator(msg.timestamp),
                        _buildMessageBubble(msg),
                      ],
                    );
                  },
                ),
        ),
        _buildInputArea(isOverLimit),
      ],
    );
  }

  Widget _buildConnectionBar() {
    Color bgColor;
    IconData icon;
    switch (_service.status) {
      case ConnectionStatus.connected:
        bgColor = Colors.green.shade700;
        icon = Icons.bluetooth_connected;
      case ConnectionStatus.connecting:
        bgColor = Colors.orange.shade700;
        icon = Icons.bluetooth_searching;
      case ConnectionStatus.scanning:
        bgColor = Colors.blue.shade700;
        icon = Icons.search;
      case ConnectionStatus.error:
        bgColor = Colors.red.shade700;
        icon = Icons.bluetooth_disabled;
      case ConnectionStatus.disconnected:
        bgColor = Colors.grey.shade700;
        icon = Icons.bluetooth_disabled;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: bgColor,
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _service.statusMessage,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          if (_service.status == ConnectionStatus.disconnected ||
              _service.status == ConnectionStatus.error)
            GestureDetector(
              onTap: () => _service.connectToSavedDevice(),
              child: const Text(
                'Reconectar',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            'No hay mensajes',
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
          SizedBox(height: 8),
          Text(
            'Envia un mensaje o toma una foto',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSeparator(DateTime date) {
    final now = DateTime.now();
    String label;
    if (_isSameDay(date, now)) {
      label = 'Hoy';
    } else if (_isSameDay(date, now.subtract(const Duration(days: 1)))) {
      label = 'Ayer';
    } else {
      label = '${date.day}/${date.month}/${date.year}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        ),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Widget _buildMessageBubble(ChatMessage msg) {
    if (msg.type == ChatMessageType.system) {
      return _buildSystemMessage(msg);
    }
    if (msg.type == ChatMessageType.imageResult) {
      return _buildImageResultMessage(msg);
    }
    if (msg.type == ChatMessageType.sessionResult) {
      return _buildSessionResultMessage(msg);
    }
    if (msg.type == ChatMessageType.sessionEnd) {
      return _buildSystemMessage(msg);
    }
    if (msg.type == ChatMessageType.imageError) {
      return _buildImageErrorMessage(msg);
    }

    final isMe = msg.isMine;
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          left: isMe ? 48 : 8,
          right: isMe ? 8 : 48,
          top: 2,
          bottom: 2,
        ),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 2),
                child: Text(
                  msg.fromNodeName,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMe ? Colors.blue.shade100 : Colors.green.shade100,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(msg.messageText, style: const TextStyle(fontSize: 15)),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(msg.timestamp),
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemMessage(ChatMessage msg) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          msg.messageText,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontStyle: FontStyle.italic),
        ),
      ),
    );
  }

  Widget _buildImageResultMessage(ChatMessage msg) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(left: 8, right: 48, top: 2, bottom: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Text(
                msg.fromNodeName,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.green.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.eco, color: Colors.green.shade700, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Diagnostico',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(msg.messageText, style: const TextStyle(fontSize: 15)),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (msg.sessionId != null && _activeSession == null)
                        TextButton.icon(
                          onPressed: () => _startSession(msg.imageId ?? '', msg.sessionId!),
                          icon: Icon(Icons.question_answer, size: 16, color: Colors.green.shade700),
                          label: Text(
                            'Consultar mas',
                            style: TextStyle(fontSize: 12, color: Colors.green.shade700),
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        )
                      else
                        const SizedBox(),
                      Text(
                        _formatTime(msg.timestamp),
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionResultMessage(ChatMessage msg) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(left: 8, right: 48, top: 2, bottom: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Text(
                msg.fromNodeName,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blue.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.question_answer, color: Colors.blue.shade700, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Consulta',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(msg.messageText, style: const TextStyle(fontSize: 15)),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Text(
                      _formatTime(msg.timestamp),
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageErrorMessage(ChatMessage msg) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade700, size: 16),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                msg.messageText,
                style: TextStyle(fontSize: 13, color: Colors.red.shade700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildSessionBar() {
    if (_activeSession == null) return const SizedBox.shrink();
    final session = _activeSession!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        border: Border(
          bottom: BorderSide(color: Colors.blue.shade200, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.question_answer, size: 16, color: Colors.blue.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Sesion activa — Pregunta ${session.questionCount}/${ConsultaSession.maxQuestions}',
              style: TextStyle(fontSize: 13, color: Colors.blue.shade700, fontWeight: FontWeight.w500),
            ),
          ),
          GestureDetector(
            onTap: _endSession,
            child: Text(
              'Terminar',
              style: TextStyle(
                fontSize: 13,
                color: Colors.red.shade600,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea(bool isOverLimit) {
    final inSession = _activeSession != null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4, offset: const Offset(0, -1)),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (inSession) _buildSessionBar() else _buildDestinationBar(),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Row(
                children: [
                  // Camera button (disabled during session)
                  Material(
                    color: inSession ? Colors.grey.shade400 : Colors.green.shade600,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: inSession ? null : _onCameraPressed,
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(Icons.camera_alt, color: Colors.white, size: 24),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Text field
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      maxLines: 3,
                      minLines: 1,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => inSession ? _sendSessionQuestion() : _sendMessage(),
                      decoration: InputDecoration(
                        hintText: inSession ? 'Escribe tu pregunta...' : 'Escribe un mensaje...',
                        filled: true,
                        fillColor: isOverLimit ? Colors.red.shade50 : Colors.grey.shade100,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: isOverLimit
                              ? BorderSide(color: Colors.red.shade400)
                              : BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: isOverLimit
                              ? BorderSide(color: Colors.red.shade400)
                              : BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Send button
                  Material(
                    color: _service.isConnected && _textController.text.trim().isNotEmpty && !isOverLimit
                        ? (inSession ? Colors.blue.shade600 : Colors.green.shade600)
                        : Colors.grey.shade400,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _isSending ? null : (inSession ? _sendSessionQuestion : _sendMessage),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: _isSending
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send, color: Colors.white, size: 24),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_textController.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '$_currentByteCount/$maxMessageBytes bytes',
                  style: TextStyle(
                    fontSize: 11,
                    color: isOverLimit ? Colors.red : Colors.grey.shade500,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Type selector bottom sheet
class _TypeSelectorSheet extends StatelessWidget {
  final void Function(String tipo) onTypeSelected;

  const _TypeSelectorSheet({required this.onTypeSelected});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Que quieres analizar?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                _buildTypeButton(context, 'Plaga', Icons.bug_report, Colors.red),
                const SizedBox(width: 12),
                _buildTypeButton(context, 'Suelo', Icons.landscape, Colors.brown),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildTypeButton(context, 'Cultivo', Icons.grass, Colors.green),
                const SizedBox(width: 12),
                _buildTypeButton(context, 'General', Icons.search, Colors.blue),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeButton(BuildContext context, String label, IconData icon, Color color) {
    return Expanded(
      child: Material(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => onTypeSelected(label),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              children: [
                Icon(icon, size: 40, color: color),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
