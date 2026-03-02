import 'package:flutter/material.dart';

import '../services/meshtastic_service.dart';

class SettingsScreen extends StatefulWidget {
  final MeshtasticService service;
  final VoidCallback onChangeDevice;

  const SettingsScreen({
    super.key,
    required this.service,
    required this.onChangeDevice,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  MeshtasticService get _service => widget.service;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildDeviceCard(),
        const SizedBox(height: 12),
        _buildGatewayCard(),
        const SizedBox(height: 12),
        _buildPhotoQualityCard(),
        const SizedBox(height: 12),
        _buildInfoCard(),
      ],
    );
  }

  Widget _buildDeviceCard() {
    final isConnected = _service.isConnected;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.bluetooth,
                  color: isConnected ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Dispositivo BLE',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            _buildInfoRow('Nombre', _service.connectedDeviceName ?? 'Sin conectar'),
            _buildInfoRow('Estado', _service.statusMessage),
            if (_service.connectedDeviceMac != null)
              _buildInfoRow('MAC', _service.connectedDeviceMac!),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await _service.disconnectAndClear();
                  widget.onChangeDevice();
                },
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Cambiar dispositivo'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGatewayCard() {
    final nodes = _service.knownNodes;
    final selectedId = _service.savedGatewayNodeId;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.router, color: Colors.orange),
                SizedBox(width: 8),
                Text(
                  'Gateway (Raspberry Pi)',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            const Text(
              'Selecciona el nodo gateway que procesara las fotos:',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: selectedId,
              isExpanded: true,
              decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: nodes.entries.map((entry) {
                return DropdownMenuItem<int>(
                  value: entry.key,
                  child: Text(
                    '${entry.value.nodeName} (${entry.value.nodeIdHex})',
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  _service.saveGatewayNodeId(value);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoQualityCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.photo_camera, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  'Calidad de foto',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            SwitchListTile(
              title: Text(
                _service.detailedQuality ? 'Detallada (200x200)' : 'Rapida (160x120)',
                style: const TextStyle(fontSize: 16),
              ),
              subtitle: Text(
                _service.detailedQuality
                    ? 'Mejor calidad, mas tiempo de envio'
                    : 'Envio rapido, calidad basica',
              ),
              value: _service.detailedQuality,
              activeThumbColor: Colors.green,
              onChanged: (value) {
                _service.setDetailedQuality(value);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.grey),
                SizedBox(width: 8),
                Text(
                  'Informacion',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            _buildInfoRow('Mi nodo ID', _service.myNodeId != 0
                ? '0x${_service.myNodeId.toRadixString(16).padLeft(8, '0')}'
                : 'Desconocido'),
            _buildInfoRow('Version app', '1.0.0'),
            _buildInfoRow('Protocolo', 'IMG v1.0'),
            _buildInfoRow('Max mensaje', '$maxMessageBytes bytes'),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
