// lib/models/tv_display.dart

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
    );
  }
}
