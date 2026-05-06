class Prediction {
  String? id;
  String? mainText;
  String? subtitle;
  double? lat;
  double? lng;

  Prediction({
    required this.id,
    required this.mainText,
    required this.subtitle,
    this.lat,
    this.lng,
  });

  // Old Google Places JSON factory (kept for compatibility)
  factory Prediction.fromJson(Map<String, dynamic> json) {
    return Prediction(
      id:       json['place_id']?.toString(),
      mainText: json['structured_formatting']?['main_text'],
      subtitle: json['structured_formatting']?['secondary_text'],
    );
  }
}