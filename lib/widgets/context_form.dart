import 'package:flutter/material.dart';

import '../models/agro_context.dart';
import '../models/image_transmission.dart';

class ContextFormSheet extends StatefulWidget {
  final ImageTransmission transmission;
  final bool detailedQuality;
  final String tipo;
  final void Function(ImageTransmission transmission, AgroContext context) onSend;
  final void Function(String tipo) onRetake;

  const ContextFormSheet({
    super.key,
    required this.transmission,
    required this.detailedQuality,
    required this.tipo,
    required this.onSend,
    required this.onRetake,
  });

  @override
  State<ContextFormSheet> createState() => _ContextFormSheetState();
}

class _ContextFormSheetState extends State<ContextFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _detalleController = TextEditingController();

  String? _categoria;
  String? _ambiente;
  late String _problema;
  String? _etapa;
  String? _altitud;
  String? _clima;

  @override
  void initState() {
    super.initState();
    _problema = AgroOptions.problemaFromTipo(widget.tipo);
  }

  @override
  void dispose() {
    _detalleController.dispose();
    super.dispose();
  }

  bool get _isFormValid {
    return _categoria != null &&
        _detalleController.text.trim().isNotEmpty &&
        _ambiente != null &&
        _etapa != null &&
        _altitud != null &&
        _clima != null;
  }

  @override
  Widget build(BuildContext context) {
    final transmission = widget.transmission;
    final sizeKb = (transmission.compressedImage!.length / 1024).toStringAsFixed(1);
    final estimatedSeconds = (transmission.chunks.length * 3.5).ceil();
    final minutes = estimatedSeconds ~/ 60;
    final seconds = estimatedSeconds % 60;
    final timeStr = minutes > 0 ? '${minutes}m ${seconds}s' : '${seconds}s';

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24, 16, 24, 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Enviar foto - ${widget.tipo}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                // Image info card
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      _infoRow(Icons.straighten, 'Tamano', '$sizeKb KB'),
                      const Divider(height: 8),
                      _infoRow(Icons.message, 'Mensajes', '${transmission.chunks.length}'),
                      const Divider(height: 8),
                      _infoRow(Icons.timer, 'Tiempo est.', '~$timeStr'),
                      const Divider(height: 8),
                      _infoRow(Icons.high_quality, 'Calidad',
                          widget.detailedQuality ? 'Detallada' : 'Rapida'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Context form fields
                _buildDropdown(
                  label: 'Categoria *',
                  value: _categoria,
                  items: AgroOptions.categorias,
                  onChanged: (v) => setState(() => _categoria = v),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _detalleController,
                  maxLength: 50,
                  decoration: InputDecoration(
                    labelText: 'Detalle (ej: tomate cherry) *',
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    counterText: '',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                _buildDropdown(
                  label: 'Ambiente *',
                  value: _ambiente,
                  items: AgroOptions.ambientes,
                  onChanged: (v) => setState(() => _ambiente = v),
                ),
                const SizedBox(height: 12),
                _buildDropdown(
                  label: 'Problema *',
                  value: _problema,
                  items: AgroOptions.problemas,
                  onChanged: (v) => setState(() => _problema = v!),
                ),
                const SizedBox(height: 12),
                _buildDropdown(
                  label: 'Etapa *',
                  value: _etapa,
                  items: AgroOptions.etapas,
                  onChanged: (v) => setState(() => _etapa = v),
                ),
                const SizedBox(height: 12),
                _buildDropdown(
                  label: 'Altitud *',
                  value: _altitud,
                  items: AgroOptions.altitudes,
                  onChanged: (v) => setState(() => _altitud = v),
                ),
                const SizedBox(height: 12),
                _buildDropdown(
                  label: 'Clima *',
                  value: _clima,
                  items: AgroOptions.climas,
                  onChanged: (v) => setState(() => _clima = v),
                ),
                const SizedBox(height: 12),

                // Warning
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber, color: Colors.orange.shade700, size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'No minimices la app durante el envio',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          widget.onRetake(widget.tipo);
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('REPETIR'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isFormValid
                            ? () {
                                final agroContext = AgroContext(
                                  categoria: _categoria!,
                                  detalle: _detalleController.text.trim(),
                                  ambiente: _ambiente!,
                                  problema: _problema,
                                  etapa: _etapa!,
                                  altitud: _altitud!,
                                  clima: _clima!,
                                );
                                Navigator.pop(context);
                                widget.onSend(widget.transmission, agroContext);
                              }
                            : null,
                        icon: const Icon(Icons.send),
                        label: const Text('ENVIAR'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: Colors.green.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required Map<String, String> items,
    required void Function(String?) onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.grey.shade100,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      items: items.entries
          .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
          .toList(),
      onChanged: onChanged,
      isExpanded: true,
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade700))),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
