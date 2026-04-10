// lib/models/tv_display.dart

import 'hospital_full.dart';

class TvNextToken {
  final int tokenNumber;
  final String patientName;
  final String? reason;

  const TvNextToken({
    required this.tokenNumber,
    required this.patientName,
    this.reason,
  });

  factory TvNextToken.fromJson(Map<String, dynamic> json) => TvNextToken(
        tokenNumber: (json['token_number'] as num?)?.toInt() ?? 0,
        patientName: json['patient_name'] as String? ?? '',
        reason:      json['reason'] as String?,
      );
}

class TvDisplay {
  final String hospitalName;
  final String? hospitalAddress;
  final int currentTokenNumber;
  final TvNextToken? currentToken;
  final List<TvNextToken> nextTokens;
  final int moreWaiting;
  final int totalWaiting;
  final int totalDone;
  final int avgWaitMins;
  final String tokenPrefix;
  final TokenFormat tokenFormat;
  final int tokenPadding;

  const TvDisplay({
    required this.hospitalName,
    this.hospitalAddress,
    required this.currentTokenNumber,
    this.currentToken,
    required this.nextTokens,
    required this.moreWaiting,
    required this.totalWaiting,
    required this.totalDone,
    required this.avgWaitMins,
    this.tokenPrefix = '',
    this.tokenFormat = TokenFormat.numeric,
    this.tokenPadding = 2,
  });

  factory TvDisplay.fromJson(Map<String, dynamic> json) {
    TvNextToken? currentToken;
    final ct = json['current_token'];
    if (ct is Map<String, dynamic>) {
      currentToken = TvNextToken.fromJson(ct);
    }

    final rawNext = json['next_tokens'];
    final nextTokens = rawNext is List
        ? rawNext
            .whereType<Map<String, dynamic>>()
            .map(TvNextToken.fromJson)
            .toList()
        : <TvNextToken>[];

    // Parse token format
    final formatStr = json['token_format'] as String? ?? 'numeric';
    final tokenFormat = TokenFormat.values.firstWhere(
      (f) => f.value == formatStr,
      orElse: () => TokenFormat.numeric,
    );

    return TvDisplay(
      hospitalName:        json['hospital_name'] as String? ?? '',
      hospitalAddress:     json['hospital_address'] as String?,
      currentTokenNumber:  (json['current_token_number'] as num?)?.toInt() ?? 0,
      currentToken:        currentToken,
      nextTokens:          nextTokens,
      moreWaiting:         (json['more_waiting'] as num?)?.toInt() ?? 0,
      totalWaiting:        (json['total_waiting'] as num?)?.toInt() ?? 0,
      totalDone:           (json['total_done'] as num?)?.toInt() ?? 0,
      avgWaitMins:         (json['avg_wait_mins'] as num?)?.toInt() ?? 0,
      tokenPrefix:         json['token_prefix'] as String? ?? '',
      tokenFormat:         tokenFormat,
      tokenPadding:        (json['token_padding'] as num?)?.toInt() ?? 2,
    );
  }

  /// Format a raw token number using this TV display's settings.
  String formatToken(int number) {
    if (number <= 0) return '—';
    switch (tokenFormat) {
      case TokenFormat.numeric:
        return '$number';
      case TokenFormat.prefix:
      case TokenFormat.custom:
        final padded = number.toString().padLeft(tokenPadding, '0');
        return '$tokenPrefix$padded';
    }
  }
}
