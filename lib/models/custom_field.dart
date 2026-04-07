// lib/models/custom_field.dart
//
// Represents one custom field defined by the hospital.
// Stored in hospital_settings.custom_fields as a JSON array.

enum CustomFieldType { text, number, dropdown }

class CustomField {
  final String id;       // unique key, e.g. "field_abc123"
  final String label;    // display label
  final CustomFieldType type;
  final bool required;
  final List<String> options; // only used when type == dropdown

  const CustomField({
    required this.id,
    required this.label,
    required this.type,
    this.required = false,
    this.options = const [],
  });

  factory CustomField.fromJson(Map<String, dynamic> json) {
    return CustomField(
      id:    json['id']    as String? ?? '',
      label: json['label'] as String? ?? '',
      type:  _typeFromString(json['type'] as String? ?? 'text'),
      required: json['required'] as bool? ?? false,
      options: (json['options'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id':       id,
        'label':    label,
        'type':     _typeToString(type),
        'required': required,
        'options':  options,
      };

  CustomField copyWith({
    String? label,
    CustomFieldType? type,
    bool? required,
    List<String>? options,
  }) =>
      CustomField(
        id:       id,
        label:    label    ?? this.label,
        type:     type     ?? this.type,
        required: required ?? this.required,
        options:  options  ?? this.options,
      );

  static CustomFieldType _typeFromString(String s) => switch (s) {
        'number'   => CustomFieldType.number,
        'dropdown' => CustomFieldType.dropdown,
        _          => CustomFieldType.text,
      };

  static String _typeToString(CustomFieldType t) => switch (t) {
        CustomFieldType.number   => 'number',
        CustomFieldType.dropdown => 'dropdown',
        CustomFieldType.text     => 'text',
      };

  String get typeLabel => switch (type) {
        CustomFieldType.text     => 'Text',
        CustomFieldType.number   => 'Number',
        CustomFieldType.dropdown => 'Dropdown',
      };
}