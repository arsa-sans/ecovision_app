class WasteInfo {
  final String disposalMethod;
  final String recyclingIdeas;
  final String environmentalImpact;
  final String? notes;

  const WasteInfo({
    required this.disposalMethod,
    required this.recyclingIdeas,
    required this.environmentalImpact,
    this.notes,
  });

  factory WasteInfo.fromJson(Map<String, dynamic> json) {
    return WasteInfo(
      disposalMethod: json['disposal_method'] as String,
      recyclingIdeas: json['recycling_ideas'] as String,
      environmentalImpact: json['environmental_impact'] as String,
      notes: json['notes'] as String?,
    );
  }
}

class WasteResult {
  final String className;
  final double confidence;
  final WasteInfo? info;

  const WasteResult({
    required this.className,
    required this.confidence,
    this.info,
  });

  String get displayName => className[0].toUpperCase() + className.substring(1);

  bool get isHighConfidence => confidence >= 0.65;
}

const Map<String, int> wasteColors = {
  'glass': 0xFF00BCD4,    
  'hazardous': 0xFFFF5252,  
  'metal': 0xFF9E9E9E,      
  'organic': 0xFF66BB6A,    
  'paper': 0xFFFFCA28,      
  'plastic': 0xFF42A5F5,    
  'textile': 0xFFAB47BC,    
};

const Map<String, String> wasteEmojis = {
  'glass': '🫙',
  'hazardous': '☢️',
  'metal': '🔧',
  'organic': '🌿',
  'paper': '📄',
  'plastic': '♻️',
  'textile': '👕',
};
