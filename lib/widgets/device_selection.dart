import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/meshtastic_service.dart';

class DeviceSelectionScreen extends StatefulWidget {
  final MeshtasticService service;
  final void Function(ScannedDevice device) onDeviceSelected;

  const DeviceSelectionScreen({
    super.key,
    required this.service,
    required this.onDeviceSelected,
  });

  @override
  State<DeviceSelectionScreen> createState() => _DeviceSelectionScreenState();
}

class _DeviceSelectionScreenState extends State<DeviceSelectionScreen> {
  final List<ScannedDevice> _devices = [];
  bool _isScanning = false;
  bool _isConnecting = false;
  String? _permissionError;
  StreamSubscription? _scanSubscription;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    try {
      if (Platform.isAndroid) {
        final statuses = await [
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.locationWhenInUse,
        ].request();

        final allGranted = statuses.values.every(
          (s) => s.isGranted || s.isLimited,
        );

        if (!allGranted) {
          setState(() {
            _permissionError = 'Se necesitan permisos de Bluetooth y ubicacion para conectar con la radio Meshtastic.';
          });
          return;
        }
      } else if (Platform.isIOS) {
        await Permission.bluetooth.request();
      }

      _startScan();
    } catch (e) {
      setState(() {
        _permissionError = 'Error al solicitar permisos: $e';
      });
    }
  }

  Future<void> _startScan() async {
    setState(() {
      _isScanning = true;
      _devices.clear();
    });

    try {
      _scanSubscription?.cancel();
      _scanSubscription = widget.service.scanDevices().listen(
        (device) {
          if (!_devices.any((d) => d.address == device.address)) {
            setState(() {
              _devices.add(device);
            });
          }
        },
        onError: (e) {
          setState(() {
            _isScanning = false;
          });
        },
        onDone: () {
          setState(() {
            _isScanning = false;
          });
        },
      );
    } catch (e) {
      setState(() {
        _isScanning = false;
      });
    }
  }

  Future<void> _selectDevice(ScannedDevice device) async {
    setState(() {
      _isConnecting = true;
    });

    try {
      await widget.service.connectToDevice(device);
      if (mounted) {
        widget.onDeviceSelected(device);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al conectar: $e')),
        );
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Conectar Radio'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: _permissionError != null
          ? _buildPermissionError()
          : _isConnecting
              ? _buildConnecting()
              : _buildDeviceList(),
    );
  }

  Widget _buildPermissionError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bluetooth_disabled, size: 80, color: Colors.grey),
            const SizedBox(height: 24),
            Text(
              _permissionError!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => openAppSettings(),
              icon: const Icon(Icons.settings),
              label: const Text('Abrir Configuracion'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnecting() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 24),
          Text('Conectando...', style: TextStyle(fontSize: 18)),
        ],
      ),
    );
  }

  Widget _buildDeviceList() {
    return Column(
      children: [
        if (_isScanning)
          const LinearProgressIndicator(),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _isScanning
                ? 'Buscando radios Meshtastic cercanas...'
                : _devices.isEmpty
                    ? 'No se encontraron dispositivos'
                    : 'Toca un dispositivo para conectar:',
            style: const TextStyle(fontSize: 16, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          child: _devices.isEmpty && !_isScanning
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.search_off, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text('No hay dispositivos', style: TextStyle(fontSize: 18, color: Colors.grey)),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _startScan,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Buscar de nuevo'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _devices.length,
                  itemBuilder: (context, index) {
                    final device = _devices[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: ListTile(
                        leading: const Icon(Icons.bluetooth, color: Colors.blue, size: 32),
                        title: Text(
                          device.name,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(device.address),
                        trailing: const Icon(Icons.chevron_right),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        onTap: () => _selectDevice(device),
                      ),
                    );
                  },
                ),
        ),
        if (!_isScanning && _devices.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: OutlinedButton.icon(
              onPressed: _startScan,
              icon: const Icon(Icons.refresh),
              label: const Text('Buscar de nuevo'),
            ),
          ),
      ],
    );
  }
}
