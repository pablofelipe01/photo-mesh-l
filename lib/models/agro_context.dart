class AgroOptions {
  static const Map<String, String> categorias = {
    'hortalizas': 'Hortalizas',
    'frutales': 'Frutales',
    'granos': 'Granos',
    'flores': 'Flores',
    'hierbas': 'Hierbas',
    'pastos': 'Pastos',
    'tuberculos': 'Tubérculos',
    'leguminosas': 'Leguminosas',
    'industriales': 'Industriales',
    'otro': 'Otro',
  };

  static const Map<String, String> ambientes = {
    'exterior': 'Exterior',
    'invernadero': 'Invernadero',
    'jardin': 'Jardín',
    'interior': 'Interior',
    'hidroponico': 'Hidropónico',
  };

  static const Map<String, String> problemas = {
    'manchas_hojas': 'Manchas en hojas',
    'hojas_secas': 'Hojas secas',
    'plagas': 'Plagas',
    'hongos': 'Hongos',
    'marchitamiento': 'Marchitamiento',
    'frutos_danados': 'Frutos dañados',
    'raiz_danada': 'Raíz dañada',
    'crecimiento_anormal': 'Crecimiento anormal',
    'evaluacion_general': 'Evaluación general',
  };

  static const Map<String, String> etapas = {
    'germinacion': 'Germinación',
    'vegetativo': 'Vegetativo',
    'floracion': 'Floración',
    'fructificacion': 'Fructificación',
    'cosecha': 'Cosecha',
    'no_se': 'No sé',
  };

  static const Map<String, String> altitudes = {
    '0-500m': '0-500m',
    '500-1000m': '500-1000m',
    '1000-1500m': '1000-1500m',
    '1500-2000m': '1500-2000m',
    '2000-2500m': '2000-2500m',
    '2500-3000m': '2500-3000m',
    '>3000m': '>3000m',
  };

  static const Map<String, String> climas = {
    'tropical_humedo': 'Tropical húmedo',
    'tropical_seco': 'Tropical seco',
    'templado': 'Templado',
    'frio': 'Frío',
    'arido': 'Árido',
  };

  /// Maps the type selector (Plaga/Suelo/Cultivo/General) to a default problema key.
  static String problemaFromTipo(String tipo) {
    switch (tipo) {
      case 'Plaga':
        return 'plagas';
      case 'Suelo':
      case 'Cultivo':
      case 'General':
      default:
        return 'evaluacion_general';
    }
  }
}

class AgroContext {
  final String categoria;
  final String detalle;
  final String ambiente;
  final String problema;
  final String etapa;
  final String altitud;
  final String clima;

  AgroContext({
    required this.categoria,
    required this.detalle,
    required this.ambiente,
    required this.problema,
    required this.etapa,
    required this.altitud,
    required this.clima,
  });

  /// Encodes to wire format: CTX|cat|det|amb|prob|eta|alt|cli
  /// All keys are ASCII without accents for predictable byte count (< 237 bytes).
  String toWireFormat() {
    // Truncate detalle to 50 chars max
    final det = detalle.length > 50 ? detalle.substring(0, 50) : detalle;
    return 'CTX|$categoria|$det|$ambiente|$problema|$etapa|$altitud|$clima';
  }
}
