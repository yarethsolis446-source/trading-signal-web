import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  runApp(const TradingSignalApp());
}

// ============================================================
// APP
// ============================================================

class TradingSignalApp extends StatelessWidget {
  const TradingSignalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Trading Signal Bot',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF080B12),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00D4FF),
          brightness: Brightness.dark,
        ),
        cardTheme: const CardThemeData(
          color: Color(0xFF10151F),
          elevation: 0,
          margin: EdgeInsets.zero,
        ),
      ),
      home: const HomePage(),
    );
  }
}

// ============================================================
// CONFIGURACIÓN
// ============================================================

const String biquoteBase = 'https://biquote.io/api';

const List<String> supportedPairs = [
  'EUR/USD',
  'GBP/USD',
  'USD/JPY',
  'USD/CHF',
  'AUD/USD',
  'USD/CAD',
  'NZD/USD',
  'EUR/GBP',
  'EUR/JPY',
  'EUR/CHF',
  'EUR/AUD',
  'EUR/CAD',
  'EUR/NZD',
  'GBP/JPY',
  'GBP/CHF',
  'GBP/AUD',
  'GBP/CAD',
  'GBP/NZD',
  'AUD/JPY',
  'AUD/NZD',
  'AUD/CAD',
  'AUD/CHF',
  'NZD/JPY',
  'NZD/CAD',
  'NZD/CHF',
  'CAD/JPY',
  'CAD/CHF',
  'CHF/JPY',
];

const List<String> supportedTimeframes = ['1m', '5m', '15m', '30m', '1h'];

// Tiempo de oportunidad de entrada.
// Se inicia cuando aparece una señal nueva.
const int entryWindowSeconds = 15;

// ============================================================
// HELPERS
// ============================================================

double _avg(List<double> values) {
  if (values.isEmpty) return 0;

  return values.reduce((a, b) => a + b) / values.length;
}

double _highest(List<double> values) {
  if (values.isEmpty) return 0;

  return values.reduce(math.max);
}

double _lowest(List<double> values) {
  if (values.isEmpty) return 0;

  return values.reduce(math.min);
}

String normalizeSymbol(String symbol) {
  return symbol.replaceAll('/', '').toUpperCase();
}

int timeframeSeconds(String timeframe) {
  switch (timeframe) {
    case '1m':
      return 60;
    case '5m':
      return 300;
    case '15m':
      return 900;
    case '30m':
      return 1800;
    case '1h':
      return 3600;
    default:
      return 300;
  }
}

String formatPrice(double price, String pair) {
  if (pair.contains('JPY')) {
    return price.toStringAsFixed(3);
  }

  return price.toStringAsFixed(5);
}

double _toDouble(dynamic value) {
  if (value is num) {
    return value.toDouble();
  }

  return double.tryParse(value?.toString() ?? '') ?? 0;
}

int _toInt(dynamic value) {
  if (value is num) {
    return value.toInt();
  }

  return int.tryParse(value?.toString() ?? '') ?? 0;
}

// ============================================================
// CANDLE
// ============================================================

class Candle {
  final DateTime time;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;
  final double tickVolume;
  final bool isOpen;

  const Candle({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    this.volume = 0,
    this.tickVolume = 0,
    this.isOpen = false,
  });
}

// ============================================================
// TICK
// ============================================================

class LiveTick {
  final String symbol;
  final double bid;
  final double ask;
  final double mid;
  final double spread;
  final DateTime timestamp;
  final String direction;
  final String marketState;
  final bool stale;
  final int quoteAgeSeconds;

  const LiveTick({
    required this.symbol,
    required this.bid,
    required this.ask,
    required this.mid,
    required this.spread,
    required this.timestamp,
    required this.direction,
    required this.marketState,
    required this.stale,
    required this.quoteAgeSeconds,
  });

  factory LiveTick.fromJson(Map<String, dynamic> json) {
    return LiveTick(
      symbol: json['symbol']?.toString() ?? '',
      bid: _toDouble(json['bid']),
      ask: _toDouble(json['ask']),
      mid: _toDouble(json['mid']),
      spread: _toDouble(json['spread']),
      timestamp:
          DateTime.tryParse(json['timestamp']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
      direction: json['direction']?.toString() ?? 'FLAT',
      marketState: json['marketState']?.toString() ?? 'unknown',
      stale: json['stale'] == true,
      quoteAgeSeconds: _toInt(json['quoteAgeSeconds']),
    );
  }
}

// ============================================================
// RESULTADO
// ============================================================

class SignalResult {
  final String direction;
  final String arrow;
  final String strength;

  final int score;
  final int maxScore;

  final String setup;
  final String reason;

  final double referencePrice;
  final double support;
  final double resistance;
  final double atr;

  final double emaFast;
  final double emaSlow;

  final double momentum;

  final bool structureBullish;
  final bool structureBearish;

  final bool bosBullish;
  final bool bosBearish;

  final bool chochBullish;
  final bool chochBearish;

  final bool breakoutBullish;
  final bool breakoutBearish;

  final bool retestBullish;
  final bool retestBearish;

  final bool rejectionBullish;
  final bool rejectionBearish;

  final bool engulfBullish;
  final bool engulfBearish;

  final bool momentumBullish;
  final bool momentumBearish;

  final List<String> confirmations;
  final List<String> warnings;

  const SignalResult({
    required this.direction,
    required this.arrow,
    required this.strength,
    required this.score,
    required this.maxScore,
    required this.setup,
    required this.reason,
    required this.referencePrice,
    required this.support,
    required this.resistance,
    required this.atr,
    required this.emaFast,
    required this.emaSlow,
    required this.momentum,
    required this.structureBullish,
    required this.structureBearish,
    required this.bosBullish,
    required this.bosBearish,
    required this.chochBullish,
    required this.chochBearish,
    required this.breakoutBullish,
    required this.breakoutBearish,
    required this.retestBullish,
    required this.retestBearish,
    required this.rejectionBullish,
    required this.rejectionBearish,
    required this.engulfBullish,
    required this.engulfBearish,
    required this.momentumBullish,
    required this.momentumBearish,
    required this.confirmations,
    required this.warnings,
  });
}

// ============================================================
// EMA
// ============================================================

List<double> _ema(List<double> values, int period) {
  if (values.isEmpty) return [];

  final result = List<double>.filled(values.length, 0);

  if (values.length < period) {
    result[0] = values[0];

    final alpha = 2 / (period + 1);

    for (int i = 1; i < values.length; i++) {
      result[i] = values[i] * alpha + result[i - 1] * (1 - alpha);
    }

    return result;
  }

  double seed = 0;

  for (int i = 0; i < period; i++) {
    seed += values[i];
  }

  seed /= period;

  for (int i = 0; i < period; i++) {
    result[i] = seed;
  }

  final alpha = 2 / (period + 1);

  for (int i = period; i < values.length; i++) {
    result[i] = values[i] * alpha + result[i - 1] * (1 - alpha);
  }

  return result;
}

// ============================================================
// ATR
// ============================================================

double _atr(List<Candle> candles, int period) {
  if (candles.length < 2) return 0;

  final trs = <double>[];

  for (int i = 1; i < candles.length; i++) {
    final current = candles[i];
    final previous = candles[i - 1];

    final tr1 = current.high - current.low;
    final tr2 = (current.high - previous.close).abs();
    final tr3 = (current.low - previous.close).abs();

    trs.add(math.max(tr1, math.max(tr2, tr3)));
  }

  if (trs.isEmpty) return 0;

  final count = math.min(period, trs.length);

  return _avg(trs.sublist(trs.length - count));
}

// ============================================================
// MOMENTUM
// ============================================================

double _momentum(List<double> closes, int period) {
  if (closes.length <= period) return 0;

  final previous = closes[closes.length - 1 - period];
  final current = closes.last;

  if (previous == 0) return 0;

  return ((current - previous) / previous) * 100;
}

// ============================================================
// BIQUOTE REST
// ============================================================

class BiquoteService {
  Future<List<Candle>> getCandles({
    required String symbol,
    required String timeframe,
    int limit = 200,
  }) async {
    final normalized = normalizeSymbol(symbol);

    final uri = Uri.parse(
      '$biquoteBase/$normalized/ohlc'
      '?interval=$timeframe'
      '&limit=$limit',
    );

    final response = await http
        .get(uri, headers: const {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('Biquote respondió ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);

    if (decoded is! Map<String, dynamic>) {
      throw Exception('Respuesta inválida de Biquote');
    }

    final bars = decoded['bars'];

    if (bars is! List) {
      throw Exception('Biquote no devolvió barras');
    }

    final candles = <Candle>[];

    for (final item in bars) {
      if (item is! Map) continue;

      final map = Map<String, dynamic>.from(item);

      if (map['isOpen'] == true) continue;

      final date = DateTime.tryParse(map['openTime']?.toString() ?? '');

      if (date == null) continue;

      final open = _toDouble(map['open']);
      final high = _toDouble(map['high']);
      final low = _toDouble(map['low']);
      final close = _toDouble(map['close']);

      if (open <= 0 || high <= 0 || low <= 0 || close <= 0) {
        continue;
      }

      candles.add(
        Candle(
          time: date.toLocal(),
          open: open,
          high: high,
          low: low,
          close: close,
          volume: _toDouble(map['volume']),
          tickVolume: _toDouble(map['tickVolume']),
        ),
      );
    }

    candles.sort((a, b) => a.time.compareTo(b.time));

    return candles;
  }

  Future<LiveTick> getLatestTick(String symbol) async {
    final normalized = normalizeSymbol(symbol);

    final uri = Uri.parse('$biquoteBase/$normalized?allowStale=false');

    final response = await http
        .get(uri, headers: const {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 5));

    if (response.statusCode != 200) {
      throw Exception('No hay tick disponible (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);

    if (decoded is! Map<String, dynamic>) {
      throw Exception('Tick inválido');
    }

    return LiveTick.fromJson(decoded);
  }
}

// ============================================================
// BIQUOTE REALTIME
// ============================================================

class BiquoteRealtime {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  bool connected = false;

  String? _symbol;

  int _invocationId = 0;

  void Function(LiveTick tick)? onTick;
  void Function(bool online)? onConnectionChanged;
  void Function(String error)? onError;

  Future<void> connect(String symbol) async {
    await disconnect();

    _symbol = normalizeSymbol(symbol);

    try {
      final uri = Uri.parse('wss://biquote.io/hubs/tick');

      final channel = WebSocketChannel.connect(uri);

      _channel = channel;

      await channel.ready;

      _subscription = channel.stream.listen(
        _handleMessage,
        onError: (Object error) {
          connected = false;
          onConnectionChanged?.call(false);
          onError?.call(error.toString());
        },
        onDone: () {
          connected = false;
          onConnectionChanged?.call(false);
        },
        cancelOnError: false,
      );

      _sendHandshake();

      await Future.delayed(const Duration(milliseconds: 500));

      await _subscribe();

      connected = true;
      onConnectionChanged?.call(true);
    } catch (e) {
      connected = false;
      onConnectionChanged?.call(false);
      onError?.call(e.toString());
    }
  }

  void _sendHandshake() {
    _sendRaw(jsonEncode({'protocol': 'json', 'version': 1}));
  }

  Future<void> _subscribe() async {
    final symbol = _symbol;

    if (symbol == null) return;

    _invocationId++;

    _sendRaw(
      jsonEncode({
        'type': 1,
        'invocationId': _invocationId.toString(),
        'target': 'Subscribe',
        'arguments': [
          [symbol],
        ],
      }),
    );
  }

  void _sendRaw(String message) {
    final channel = _channel;

    if (channel == null) return;

    channel.sink.add('$message\u001e');
  }

  void _handleMessage(dynamic data) {
    try {
      String text;

      if (data is String) {
        text = data;
      } else if (data is Uint8List) {
        text = utf8.decode(data);
      } else {
        text = data.toString();
      }

      final messages = text.split('\u001e');

      for (final raw in messages) {
        if (raw.trim().isEmpty) continue;

        final decoded = jsonDecode(raw);

        if (decoded is! Map) continue;

        if (decoded['type'] == 1 && decoded['target'] == 'ReceiveTick') {
          final args = decoded['arguments'];

          if (args is List && args.isNotEmpty) {
            final tickData = args.first;

            if (tickData is Map) {
              final tick = LiveTick.fromJson(
                Map<String, dynamic>.from(tickData),
              );

              onTick?.call(tick);
            }
          }
        }
      }
    } catch (e) {
      onError?.call('Error procesando tick: $e');
    }
  }

  Future<void> disconnect() async {
    connected = false;

    await _subscription?.cancel();

    _subscription = null;

    try {
      await _channel?.sink.close();
    } catch (_) {}

    _channel = null;

    onConnectionChanged?.call(false);
  }
}

// ============================================================
// PRICE ACTION ENGINE
// ============================================================

class PriceActionEngine {
  SignalResult analyze({
    required List<Candle> candles,
    required double livePrice,
  }) {
    if (candles.length < 40) {
      return _waitResult(
        candles.isNotEmpty ? candles.last.close : livePrice,
        'No hay suficientes velas.',
      );
    }

    final data = candles.length > 100
        ? candles.sublist(candles.length - 100)
        : List<Candle>.from(candles);

    final closes = data.map((e) => e.close).toList();

    final emaFastList = _ema(closes, 9);
    final emaSlowList = _ema(closes, 21);

    final emaFast = emaFastList.last;
    final emaSlow = emaSlowList.last;

    final atr = _atr(data, 14);

    final support = _findSupport(data);
    final resistance = _findResistance(data);

    final structure = _detectStructure(data);

    final bosBullish = _bullishBos(data);
    final bosBearish = _bearishBos(data);

    final chochBullish = _bullishChoch(data);
    final chochBearish = _bearishChoch(data);

    final breakoutBullish = _bullishBreakout(data, resistance);

    final breakoutBearish = _bearishBreakout(data, support);

    final retestBullish = _bullishRetest(data, resistance);

    final retestBearish = _bearishRetest(data, support);

    final rejectionBullish = _bullishRejection(data.last);

    final rejectionBearish = _bearishRejection(data.last);

    final engulfBullish = _bullishEngulfing(data);

    final engulfBearish = _bearishEngulfing(data);

    final momentum = _momentum(closes, 5);

    final momentumBullish = momentum > 0.008;
    final momentumBearish = momentum < -0.008;

    final body = (data.last.close - data.last.open).abs();

    final range = data.last.high - data.last.low;

    final bodyRatio = range <= 0 ? 0 : body / range;

    final doji = bodyRatio < 0.16;

    final nearResistance =
        atr > 0 && (resistance - livePrice).abs() <= atr * 0.30;

    final nearSupport = atr > 0 && (livePrice - support).abs() <= atr * 0.30;

    final bullishTrend = emaFast > emaSlow;
    final bearishTrend = emaFast < emaSlow;

    int bullishScore = 0;
    int bearishScore = 0;

    final confirmations = <String>[];
    final warnings = <String>[];

    // ==========================================================
    // ESTRUCTURA — PESO PRINCIPAL
    // ==========================================================

    if (structure == 'BULLISH') {
      bullishScore += 18;
      confirmations.add('Estructura HH/HL');
    }

    if (structure == 'BEARISH') {
      bearishScore += 18;
      confirmations.add('Estructura LH/LL');
    }

    // ==========================================================
    // EMA — CONFIRMACIÓN, NO PROTAGONISTA
    // ==========================================================

    if (bullishTrend) {
      bullishScore += 5;
      confirmations.add('Contexto EMA alcista');
    }

    if (bearishTrend) {
      bearishScore += 5;
      confirmations.add('Contexto EMA bajista');
    }

    // ==========================================================
    // BOS
    // ==========================================================

    if (bosBullish) {
      bullishScore += 17;
      confirmations.add('BOS alcista');
    }

    if (bosBearish) {
      bearishScore += 17;
      confirmations.add('BOS bajista');
    }

    // ==========================================================
    // CHOCH
    // ==========================================================

    if (chochBullish) {
      bullishScore += 13;
      confirmations.add('CHoCH alcista');
    }

    if (chochBearish) {
      bearishScore += 13;
      confirmations.add('CHoCH bajista');
    }

    // ==========================================================
    // BREAKOUT
    // ==========================================================

    if (breakoutBullish) {
      bullishScore += 13;
      confirmations.add('Ruptura alcista');
    }

    if (breakoutBearish) {
      bearishScore += 13;
      confirmations.add('Ruptura bajista');
    }

    // ==========================================================
    // RETEST
    // ==========================================================

    if (retestBullish) {
      bullishScore += 14;
      confirmations.add('Retest alcista');
    }

    if (retestBearish) {
      bearishScore += 14;
      confirmations.add('Retest bajista');
    }

    // ==========================================================
    // RECHAZO
    // ==========================================================

    if (rejectionBullish) {
      bullishScore += 11;
      confirmations.add('Rechazo comprador');
    }

    if (rejectionBearish) {
      bearishScore += 11;
      confirmations.add('Rechazo vendedor');
    }

    // ==========================================================
    // ENGULFING
    // ==========================================================

    if (engulfBullish) {
      bullishScore += 11;
      confirmations.add('Engulfing alcista');
    }

    if (engulfBearish) {
      bearishScore += 11;
      confirmations.add('Engulfing bajista');
    }

    // ==========================================================
    // MOMENTUM
    // ==========================================================

    if (momentumBullish) {
      bullishScore += 8;
      confirmations.add('Momentum positivo');
    }

    if (momentumBearish) {
      bearishScore += 8;
      confirmations.add('Momentum negativo');
    }

    // ==========================================================
    // PRECIO LIVE
    // ==========================================================

    if (livePrice > data.last.close) {
      bullishScore += 5;
    }

    if (livePrice < data.last.close) {
      bearishScore += 5;
    }

    // ==========================================================
    // DOJI
    // ==========================================================

    if (doji) {
      bullishScore -= 4;
      bearishScore -= 4;

      warnings.add('Vela de indecisión');
    }

    // ==========================================================
    // SOPORTE / RESISTENCIA
    // Ahora es advertencia moderada, no bloqueo fuerte.
    // ==========================================================

    if (nearResistance && bullishScore > bearishScore) {
      bullishScore -= 6;

      warnings.add('Cerca de resistencia');
    }

    if (nearSupport && bearishScore > bullishScore) {
      bearishScore -= 6;

      warnings.add('Cerca de soporte');
    }

    // ==========================================================
    // SOBREEXTENSIÓN
    // ==========================================================

    if (atr > 0) {
      final distanceFromEma = (livePrice - emaFast).abs();

      if (distanceFromEma > atr * 2.5) {
        if (livePrice > emaFast) {
          bullishScore -= 8;

          warnings.add('Movimiento alcista extendido');
        } else {
          bearishScore -= 8;

          warnings.add('Movimiento bajista extendido');
        }
      }
    }

    bullishScore = math.max(0, bullishScore);

    bearishScore = math.max(0, bearishScore);

    // ==========================================================
    // PUNTUACIÓN
    // ==========================================================

    const int maxScore = 139;

    final finalScore = math.max(bullishScore, bearishScore);

    final difference = (bullishScore - bearishScore).abs();

    // Antes: 42.
    // Ahora: más frecuente.
    int threshold = 30;

    // ==========================================================
    // VOLATILIDAD ADAPTATIVA
    // ==========================================================

    if (atr > 0) {
      final recentRanges = data
          .sublist(math.max(0, data.length - 15))
          .map((e) => e.high - e.low)
          .toList();

      final averageRange = _avg(recentRanges);

      if (averageRange > 0) {
        if (atr > averageRange * 1.45) {
          threshold = 36;
        }

        if (atr < averageRange * 0.70) {
          threshold = 27;
        }
      }
    }

    // ==========================================================
    // DIFERENCIA DIRECCIONAL
    // Más flexible que antes.
    // ==========================================================

    if (difference < 6) {
      warnings.add('Direcciones muy equilibradas');
    }

    String direction = 'WAIT';
    String arrow = '⏸';

    String strength = 'WEAK';

    String setup = 'Sin setup confirmado';

    // ==========================================================
    // SEÑAL ALCISTA
    // ==========================================================

    if (bullishScore >= threshold &&
        bullishScore > bearishScore &&
        difference >= 6) {
      direction = 'UP';
      arrow = '↑';

      if (retestBullish) {
        setup = 'BREAKOUT + RETEST';
      } else if (bosBullish) {
        setup = 'BOS + PRICE ACTION';
      } else if (chochBullish) {
        setup = 'CHoCH + PRICE ACTION';
      } else if (engulfBullish) {
        setup = 'BULLISH ENGULFING';
      } else if (rejectionBullish) {
        setup = 'BULLISH REJECTION';
      } else if (structure == 'BULLISH') {
        setup = 'BULLISH STRUCTURE';
      } else {
        setup = 'BULLISH MOMENTUM';
      }
    }

    // ==========================================================
    // SEÑAL BAJISTA
    // ==========================================================

    if (bearishScore >= threshold &&
        bearishScore > bullishScore &&
        difference >= 6) {
      direction = 'DOWN';
      arrow = '↓';

      if (retestBearish) {
        setup = 'BREAKOUT + RETEST';
      } else if (bosBearish) {
        setup = 'BOS + PRICE ACTION';
      } else if (chochBearish) {
        setup = 'CHoCH + PRICE ACTION';
      } else if (engulfBearish) {
        setup = 'BEARISH ENGULFING';
      } else if (rejectionBearish) {
        setup = 'BEARISH REJECTION';
      } else if (structure == 'BEARISH') {
        setup = 'BEARISH STRUCTURE';
      } else {
        setup = 'BEARISH MOMENTUM';
      }
    }

    // ==========================================================
    // FUERZA
    // ==========================================================

    if (direction == 'WAIT') {
      strength = finalScore >= threshold - 5 ? 'FILTERED' : 'WEAK';
    } else if (finalScore >= 75) {
      strength = 'STRONG';
    } else if (finalScore >= 58) {
      strength = 'GOOD';
    } else if (finalScore >= threshold) {
      strength = 'MODERATE';
    } else {
      strength = 'WEAK';
    }

    // ==========================================================
    // RAZÓN
    // ==========================================================

    String reason;

    if (direction == 'UP') {
      reason = 'Predominio de acción de precio alcista con suficiente ventaja.';
    } else if (direction == 'DOWN') {
      reason = 'Predominio de acción de precio bajista con suficiente ventaja.';
    } else {
      reason = 'La acción del precio todavía no tiene ventaja suficiente.';
    }

    return SignalResult(
      direction: direction,
      arrow: arrow,
      strength: strength,
      score: finalScore,
      maxScore: maxScore,
      setup: setup,
      reason: reason,
      referencePrice: livePrice,
      support: support,
      resistance: resistance,
      atr: atr,
      emaFast: emaFast,
      emaSlow: emaSlow,
      momentum: momentum,
      structureBullish: structure == 'BULLISH',
      structureBearish: structure == 'BEARISH',
      bosBullish: bosBullish,
      bosBearish: bosBearish,
      chochBullish: chochBullish,
      chochBearish: chochBearish,
      breakoutBullish: breakoutBullish,
      breakoutBearish: breakoutBearish,
      retestBullish: retestBullish,
      retestBearish: retestBearish,
      rejectionBullish: rejectionBullish,
      rejectionBearish: rejectionBearish,
      engulfBullish: engulfBullish,
      engulfBearish: engulfBearish,
      momentumBullish: momentumBullish,
      momentumBearish: momentumBearish,
      confirmations: confirmations,
      warnings: warnings,
    );
  }

  SignalResult _waitResult(double price, String reason) {
    return SignalResult(
      direction: 'WAIT',
      arrow: '⏸',
      strength: 'FILTERED',
      score: 0,
      maxScore: 139,
      setup: 'Esperando setup',
      reason: reason,
      referencePrice: price,
      support: price,
      resistance: price,
      atr: 0,
      emaFast: price,
      emaSlow: price,
      momentum: 0,
      structureBullish: false,
      structureBearish: false,
      bosBullish: false,
      bosBearish: false,
      chochBullish: false,
      chochBearish: false,
      breakoutBullish: false,
      breakoutBearish: false,
      retestBullish: false,
      retestBearish: false,
      rejectionBullish: false,
      rejectionBearish: false,
      engulfBullish: false,
      engulfBearish: false,
      momentumBullish: false,
      momentumBearish: false,
      confirmations: const [],
      warnings: const [],
    );
  }

  // ==========================================================
  // SUPPORT
  // ==========================================================

  double _findSupport(List<Candle> candles) {
    final recent = candles.length > 40
        ? candles.sublist(candles.length - 40)
        : candles;

    return _lowest(recent.map((e) => e.low).toList());
  }

  // ==========================================================
  // RESISTANCE
  // ==========================================================

  double _findResistance(List<Candle> candles) {
    final recent = candles.length > 40
        ? candles.sublist(candles.length - 40)
        : candles;

    return _highest(recent.map((e) => e.high).toList());
  }

  // ==========================================================
  // STRUCTURE
  // ==========================================================

  String _detectStructure(List<Candle> candles) {
    if (candles.length < 15) {
      return 'NEUTRAL';
    }

    final recent = candles.sublist(math.max(0, candles.length - 25));

    final highs = <double>[];
    final lows = <double>[];

    for (int i = 2; i < recent.length - 2; i++) {
      final candle = recent[i];

      if (candle.high > recent[i - 1].high &&
          candle.high > recent[i - 2].high &&
          candle.high > recent[i + 1].high &&
          candle.high > recent[i + 2].high) {
        highs.add(candle.high);
      }

      if (candle.low < recent[i - 1].low &&
          candle.low < recent[i - 2].low &&
          candle.low < recent[i + 1].low &&
          candle.low < recent[i + 2].low) {
        lows.add(candle.low);
      }
    }

    if (highs.length >= 2 && lows.length >= 2) {
      final higherHigh = highs.last > highs[highs.length - 2];

      final higherLow = lows.last > lows[lows.length - 2];

      final lowerHigh = highs.last < highs[highs.length - 2];

      final lowerLow = lows.last < lows[lows.length - 2];

      if (higherHigh && higherLow) {
        return 'BULLISH';
      }

      if (lowerHigh && lowerLow) {
        return 'BEARISH';
      }
    }

    return 'NEUTRAL';
  }

  // ============================================================
  // BOS
  // ============================================================

  bool _bullishBos(List<Candle> candles) {
    if (candles.length < 10) return false;

    final current = candles.last;

    final previous = candles.sublist(
      math.max(0, candles.length - 12),
      candles.length - 1,
    );

    final resistance = _highest(previous.map((e) => e.high).toList());

    return current.close > resistance;
  }

  bool _bearishBos(List<Candle> candles) {
    if (candles.length < 10) return false;

    final current = candles.last;

    final previous = candles.sublist(
      math.max(0, candles.length - 12),
      candles.length - 1,
    );

    final support = _lowest(previous.map((e) => e.low).toList());

    return current.close < support;
  }

  // ============================================================
  // CHOCH
  // ============================================================

  bool _bullishChoch(List<Candle> candles) {
    if (candles.length < 20) return false;

    final mid = candles.length - 8;

    final earlier = candles.sublist(math.max(0, mid - 8), mid);

    final later = candles.sublist(mid, candles.length - 1);

    if (earlier.isEmpty || later.isEmpty) {
      return false;
    }

    final earlierLow = _lowest(earlier.map((e) => e.low).toList());

    final laterHigh = _highest(later.map((e) => e.high).toList());

    final laterLow = _lowest(later.map((e) => e.low).toList());

    final current = candles.last;

    return laterLow < earlierLow && current.close > laterHigh;
  }

  bool _bearishChoch(List<Candle> candles) {
    if (candles.length < 20) return false;

    final mid = candles.length - 8;

    final earlier = candles.sublist(math.max(0, mid - 8), mid);

    final later = candles.sublist(mid, candles.length - 1);

    if (earlier.isEmpty || later.isEmpty) {
      return false;
    }

    final earlierHigh = _highest(earlier.map((e) => e.high).toList());

    final laterHigh = _highest(later.map((e) => e.high).toList());

    final laterLow = _lowest(later.map((e) => e.low).toList());

    final current = candles.last;

    return laterHigh > earlierHigh && current.close < laterLow;
  }

  // ============================================================
  // BREAKOUT
  // ============================================================

  bool _bullishBreakout(List<Candle> candles, double resistance) {
    if (candles.length < 3) return false;

    final current = candles.last;
    final previous = candles[candles.length - 2];

    return previous.close <= resistance &&
        current.close > resistance &&
        current.close > current.open;
  }

  bool _bearishBreakout(List<Candle> candles, double support) {
    if (candles.length < 3) return false;

    final current = candles.last;
    final previous = candles[candles.length - 2];

    return previous.close >= support &&
        current.close < support &&
        current.close < current.open;
  }

  // ============================================================
  // RETEST
  // ============================================================

  bool _bullishRetest(List<Candle> candles, double resistance) {
    if (candles.length < 5) return false;

    final current = candles.last;
    final previous = candles[candles.length - 2];

    final distance = (current.low - resistance).abs();

    final atr = _atr(candles, 14);

    if (atr <= 0) return false;

    return previous.close > resistance &&
        distance <= atr * 0.55 &&
        current.close > resistance &&
        current.close > current.open;
  }

  bool _bearishRetest(List<Candle> candles, double support) {
    if (candles.length < 5) return false;

    final current = candles.last;
    final previous = candles[candles.length - 2];

    final distance = (current.high - support).abs();

    final atr = _atr(candles, 14);

    if (atr <= 0) return false;

    return previous.close < support &&
        distance <= atr * 0.55 &&
        current.close < support &&
        current.close < current.open;
  }

  // ============================================================
  // REJECTION
  // ============================================================

  bool _bullishRejection(Candle candle) {
    final body = (candle.close - candle.open).abs();

    final lowerWick = math.min(candle.open, candle.close) - candle.low;

    final upperWick = candle.high - math.max(candle.open, candle.close);

    if (body <= 0) {
      return lowerWick > upperWick * 1.5;
    }

    return lowerWick >= body * 1.5 &&
        lowerWick > upperWick &&
        candle.close >= candle.open;
  }

  bool _bearishRejection(Candle candle) {
    final body = (candle.close - candle.open).abs();

    final lowerWick = math.min(candle.open, candle.close) - candle.low;

    final upperWick = candle.high - math.max(candle.open, candle.close);

    if (body <= 0) {
      return upperWick > lowerWick * 1.5;
    }

    return upperWick >= body * 1.5 &&
        upperWick > lowerWick &&
        candle.close <= candle.open;
  }

  // ============================================================
  // ENGULFING
  // ============================================================

  bool _bullishEngulfing(List<Candle> candles) {
    if (candles.length < 2) return false;

    final previous = candles[candles.length - 2];

    final current = candles.last;

    return previous.close < previous.open &&
        current.close > current.open &&
        current.open <= previous.close &&
        current.close >= previous.open;
  }

  bool _bearishEngulfing(List<Candle> candles) {
    if (candles.length < 2) return false;

    final previous = candles[candles.length - 2];

    final current = candles.last;

    return previous.close > previous.open &&
        current.close < current.open &&
        current.open >= previous.close &&
        current.close <= previous.open;
  }
}

// ============================================================
// HOME PAGE
// ============================================================

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final BiquoteService _service = BiquoteService();

  final PriceActionEngine _engine = PriceActionEngine();

  final BiquoteRealtime _realtime = BiquoteRealtime();

  Timer? _refreshTimer;
  Timer? _countdownTimer;

  String selectedPair = 'EUR/USD';
  String selectedTimeframe = '5m';

  List<Candle> candles = [];

  SignalResult? signal;
  LiveTick? liveTick;

  bool loading = true;
  bool analyzingNow = false;

  bool online = false;
  bool realtimeOnline = false;

  String errorMessage = '';

  int secondsToNextCandle = 0;

  // ==========================================================
  // TEMPORIZADOR DE ENTRADA
  // ==========================================================

  int entrySecondsRemaining = 0;

  bool entryTimerActive = false;

  String entrySignalDirection = '';

  String? lastSignalKey;

  double get currentPrice {
    if (liveTick != null && liveTick!.mid > 0) {
      return liveTick!.mid;
    }

    if (candles.isNotEmpty) {
      return candles.last.close;
    }

    return 0;
  }

  // ==========================================================
  // INIT
  // ==========================================================

  @override
  void initState() {
    super.initState();

    _setupRealtime();

    _loadData();

    _refreshTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _refreshCandles(),
    );

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;

      setState(() {
        _updateCountdown();

        _updateEntryTimer();
      });
    });
  }

  // ==========================================================
  // REALTIME
  // ==========================================================

  Future<void> _setupRealtime() async {
    _realtime.onConnectionChanged = (value) {
      if (!mounted) return;

      setState(() {
        realtimeOnline = value;
      });
    };

    _realtime.onTick = (tick) {
      if (!mounted) return;

      if (normalizeSymbol(selectedPair) != tick.symbol.toUpperCase()) {
        return;
      }

      setState(() {
        liveTick = tick;
        online = true;

        if (candles.isNotEmpty) {
          signal = _engine.analyze(candles: candles, livePrice: tick.mid);
        }
      });
    };

    _realtime.onError = (_) {};

    await _realtime.connect(selectedPair);
  }

  // ==========================================================
  // ANALIZAR AHORA
  // ==========================================================

  Future<void> _analyzeNow() async {
    if (analyzingNow) return;

    setState(() {
      analyzingNow = true;
      errorMessage = '';
    });

    try {
      final loadedCandles = await _service.getCandles(
        symbol: selectedPair,
        timeframe: selectedTimeframe,
        limit: 200,
      );

      LiveTick? tick;

      try {
        tick = await _service.getLatestTick(selectedPair);
      } catch (_) {
        tick = liveTick;
      }

      if (loadedCandles.length < 30) {
        throw Exception(
          'Biquote devolvió '
          '${loadedCandles.length} velas cerradas.',
        );
      }

      final price =
          tick?.mid ??
          (loadedCandles.isNotEmpty ? loadedCandles.last.close : 0);

      final result = _engine.analyze(candles: loadedCandles, livePrice: price);

      if (!mounted) return;

      setState(() {
        candles = loadedCandles;

        if (tick != null) {
          liveTick = tick;
        }

        signal = result;

        online = true;

        analyzingNow = false;
      });

      _updateCountdown();

      _handleSignal(result, forceEntryTimer: true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        analyzingNow = false;
        errorMessage = e.toString();
        online = false;
      });
    }
  }

  // ==========================================================
  // LOAD
  // ==========================================================

  Future<void> _loadData() async {
    if (!mounted) return;

    setState(() {
      loading = true;
      errorMessage = '';
    });

    try {
      final results = await Future.wait([
        _service.getCandles(
          symbol: selectedPair,
          timeframe: selectedTimeframe,
          limit: 200,
        ),
        _service.getLatestTick(selectedPair),
      ]);

      final loadedCandles = results[0] as List<Candle>;

      final tick = results[1] as LiveTick;

      if (loadedCandles.length < 30) {
        throw Exception(
          'Biquote devolvió '
          '${loadedCandles.length} velas cerradas.',
        );
      }

      final result = _engine.analyze(
        candles: loadedCandles,
        livePrice: tick.mid,
      );

      if (!mounted) return;

      setState(() {
        candles = loadedCandles;
        liveTick = tick;
        signal = result;

        online = true;
        loading = false;
      });

      _updateCountdown();

      _handleSignal(result, forceEntryTimer: true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loading = false;
        online = false;
        errorMessage = e.toString();
      });
    }
  }

  // ==========================================================
  // REFRESH
  // ==========================================================

  Future<void> _refreshCandles() async {
    try {
      final loadedCandles = await _service.getCandles(
        symbol: selectedPair,
        timeframe: selectedTimeframe,
        limit: 200,
      );

      if (loadedCandles.isEmpty) return;

      final result = _engine.analyze(
        candles: loadedCandles,
        livePrice: currentPrice,
      );

      if (!mounted) return;

      setState(() {
        candles = loadedCandles;
        signal = result;
        online = true;
      });

      _handleSignal(result);
    } catch (_) {
      if (!mounted) return;

      setState(() {
        online = false;
      });
    }
  }

  // ==========================================================
  // SIGNAL KEY + ENTRY TIMER
  // ==========================================================

  void _handleSignal(SignalResult result, {bool forceEntryTimer = false}) {
    final candleTime = candles.isNotEmpty
        ? candles.last.time.millisecondsSinceEpoch
        : 0;

    final key =
        '${selectedPair}_'
        '${selectedTimeframe}_'
        '${result.direction}_'
        '${result.setup}_'
        '$candleTime';

    final isNewSignal = key != lastSignalKey;

    if (isNewSignal) {
      lastSignalKey = key;
    }

    if (result.direction != 'WAIT' && (isNewSignal || forceEntryTimer)) {
      _startEntryTimer(result.direction);
    }

    if (result.direction == 'WAIT' && forceEntryTimer) {
      _stopEntryTimer();
    }
  }

  void _startEntryTimer(String direction) {
    setState(() {
      entrySecondsRemaining = entryWindowSeconds;

      entryTimerActive = true;

      entrySignalDirection = direction;
    });
  }

  void _stopEntryTimer() {
    entrySecondsRemaining = 0;
    entryTimerActive = false;
    entrySignalDirection = '';
  }

  void _updateEntryTimer() {
    if (!entryTimerActive) return;

    if (entrySecondsRemaining > 0) {
      entrySecondsRemaining--;
    }

    if (entrySecondsRemaining <= 0) {
      entryTimerActive = false;
      entrySignalDirection = '';
    }
  }

  // ==========================================================
  // COUNTDOWN VELA
  // ==========================================================

  void _updateCountdown() {
    if (candles.isEmpty) {
      secondsToNextCandle = 0;
      return;
    }

    final last = candles.last.time.toUtc();

    final duration = timeframeSeconds(selectedTimeframe);

    final nextTimestamp =
        ((last.millisecondsSinceEpoch ~/ 1000) + duration) * 1000;

    final remaining =
        nextTimestamp - DateTime.now().toUtc().millisecondsSinceEpoch;

    secondsToNextCandle = math.max(0, remaining ~/ 1000);
  }

  // ==========================================================
  // DISPOSE
  // ==========================================================

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _countdownTimer?.cancel();

    _realtime.disconnect();

    super.dispose();
  }

  // ==========================================================
  // PAIR
  // ==========================================================

  Future<void> _changePair(String? value) async {
    if (value == null || value == selectedPair) {
      return;
    }

    setState(() {
      selectedPair = value;

      candles = [];

      signal = null;

      liveTick = null;

      online = false;

      loading = true;

      errorMessage = '';

      lastSignalKey = null;

      _stopEntryTimer();
    });

    await _realtime.connect(selectedPair);

    await _loadData();
  }

  // ==========================================================
  // TIMEFRAME
  // ==========================================================

  Future<void> _changeTimeframe(String? value) async {
    if (value == null || value == selectedTimeframe) {
      return;
    }

    setState(() {
      selectedTimeframe = value;

      candles = [];

      signal = null;

      loading = true;

      errorMessage = '';

      lastSignalKey = null;

      _stopEntryTimer();
    });

    await _loadData();
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    final result = signal;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF080B12),
        title: const Row(
          children: [
            Icon(Icons.candlestick_chart, color: Color(0xFF00D4FF)),
            SizedBox(width: 10),
            Text(
              'Trading Signal Bot',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: analyzingNow || loading ? null : _analyzeNow,
            tooltip: 'Analizar ahora',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            _buildConnectionCard(),

            const SizedBox(height: 12),

            _buildSelectors(),

            const SizedBox(height: 12),

            // ==================================================
            // BOTÓN ANALIZAR AHORA
            // ==================================================
            _buildAnalyzeButton(),

            const SizedBox(height: 12),

            if (errorMessage.isNotEmpty) _buildErrorCard(),

            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 50),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              if (result != null) _buildSignalCard(result),

              const SizedBox(height: 12),

              // =================================================
              // TEMPORIZADOR DE ENTRADA
              // =================================================
              if (result != null) _buildEntryTimer(result),

              const SizedBox(height: 12),

              _buildLivePriceCard(),

              const SizedBox(height: 12),

              _buildCountdownCard(),

              const SizedBox(height: 12),

              _buildChart(),

              const SizedBox(height: 12),

              if (result != null) _buildAnalysis(result),

              const SizedBox(height: 12),

              if (result != null) _buildLevels(result),

              const SizedBox(height: 12),

              if (result != null) _buildConfirmations(result),

              const SizedBox(height: 24),

              _buildFooter(),
            ],
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // BOTÓN ANALIZAR
  // ==========================================================

  Widget _buildAnalyzeButton() {
    return SizedBox(
      height: 54,
      child: FilledButton.icon(
        onPressed: analyzingNow || loading ? null : _analyzeNow,
        icon: analyzingNow
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.analytics_outlined),
        label: Text(
          analyzingNow ? 'ANALIZANDO...' : 'ANALIZAR AHORA',
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // CONNECTION
  // ==========================================================

  Widget _buildConnectionCard() {
    final Color statusColor = realtimeOnline
        ? const Color(0xFF00E676)
        : online
        ? Colors.orange
        : Colors.red;

    final String title = realtimeOnline
        ? 'ONLINE • TICKS EN TIEMPO REAL'
        : online
        ? 'ONLINE • REST'
        : 'OFFLINE';

    final String subtitle = realtimeOnline
        ? 'Biquote SignalR conectado'
        : online
        ? 'Datos de Biquote disponibles'
        : 'No se pudo conectar';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (realtimeOnline)
              const Icon(Icons.wifi, color: Color(0xFF00E676)),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // SELECTORS
  // ==========================================================

  Widget _buildSelectors() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: selectedPair,
                decoration: const InputDecoration(
                  labelText: 'Par',
                  border: OutlineInputBorder(),
                ),
                items: supportedPairs
                    .map(
                      (pair) =>
                          DropdownMenuItem(value: pair, child: Text(pair)),
                    )
                    .toList(),
                onChanged: _changePair,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: selectedTimeframe,
                decoration: const InputDecoration(
                  labelText: 'Temporalidad',
                  border: OutlineInputBorder(),
                ),
                items: supportedTimeframes
                    .map(
                      (timeframe) => DropdownMenuItem(
                        value: timeframe,
                        child: Text(timeframe),
                      ),
                    )
                    .toList(),
                onChanged: _changeTimeframe,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // ERROR
  // ==========================================================

  Widget _buildErrorCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                errorMessage.replaceFirst('Exception: ', ''),
                style: const TextStyle(color: Colors.orange),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // SIGNAL CARD
  // ==========================================================

  Widget _buildSignalCard(SignalResult result) {
    final isUp = result.direction == 'UP';

    final isDown = result.direction == 'DOWN';

    final color = isUp
        ? const Color(0xFF00E676)
        : isDown
        ? const Color(0xFFFF5252)
        : Colors.orange;

    final title = isUp
        ? 'ALZA'
        : isDown
        ? 'BAJA'
        : 'ESPERAR';

    return Card(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          children: [
            const Text(
              'SEÑAL',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  result.arrow,
                  style: TextStyle(
                    fontSize: 44,
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text(
                result.strength,
                style: TextStyle(color: color, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 15),
            Text(
              result.setup,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              result.reason,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _stat('SCORE', '${result.score}/${result.maxScore}'),
                _stat(
                  'PRECIO',
                  formatPrice(result.referencePrice, selectedPair),
                ),
                _stat('MOMENTUM', '${result.momentum.toStringAsFixed(3)}%'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String title, String value) {
    return Column(
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 10, color: Colors.white38),
        ),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }

  // ==========================================================
  // TEMPORIZADOR DE ENTRADA
  // ==========================================================

  Widget _buildEntryTimer(SignalResult result) {
    final active = entryTimerActive && result.direction != 'WAIT';

    final isUp = entrySignalDirection == 'UP';

    final color = isUp ? const Color(0xFF00E676) : const Color(0xFFFF5252);

    final percentage = entryWindowSeconds <= 0
        ? 0.0
        : entrySecondsRemaining / entryWindowSeconds;

    return Card(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? color.withValues(alpha: 0.45) : Colors.white10,
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  active ? Icons.bolt : Icons.timer_off_outlined,
                  color: active ? color : Colors.white38,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'PUNTO DE ENTRADA',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                if (active)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      entrySignalDirection == 'UP' ? 'ALZA' : 'BAJA',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 15),
            Text(
              active ? '$entrySecondsRemaining s' : 'ESPERANDO NUEVA SEÑAL',
              style: TextStyle(
                fontSize: active ? 34 : 16,
                fontWeight: FontWeight.w900,
                color: active ? color : Colors.white38,
              ),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LinearProgressIndicator(
                minHeight: 7,
                value: active ? percentage : 0,
                backgroundColor: Colors.white10,
                valueColor: AlwaysStoppedAnimation<Color>(
                  active ? color : Colors.white24,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              active
                  ? 'Ventana inicial de entrada detectada'
                  : 'El temporizador se activa cuando aparece una nueva señal.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // LIVE PRICE
  // ==========================================================

  Widget _buildLivePriceCard() {
    final tick = liveTick;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.flash_on, color: Color(0xFF00D4FF)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'PRECIO EN TIEMPO REAL',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (tick != null)
                  Text(
                    tick.direction,
                    style: TextStyle(
                      color: tick.direction == 'UP'
                          ? Colors.greenAccent
                          : tick.direction == 'DOWN'
                          ? Colors.redAccent
                          : Colors.white54,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              currentPrice > 0 ? formatPrice(currentPrice, selectedPair) : '--',
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
            ),
            if (tick != null) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'BID ${formatPrice(tick.bid, selectedPair)}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(width: 15),
                  Text(
                    'ASK ${formatPrice(tick.ask, selectedPair)}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                tick.stale ? 'PRECIO DESACTUALIZADO' : 'TICK RECIBIDO EN VIVO',
                style: TextStyle(
                  color: tick.stale ? Colors.orange : const Color(0xFF00E676),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // COUNTDOWN VELA
  // ==========================================================

  Widget _buildCountdownCard() {
    final mins = secondsToNextCandle ~/ 60;

    final secs = secondsToNextCandle % 60;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.timer_outlined, color: Colors.orange),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'PRÓXIMA VELA',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Text(
              '${mins.toString().padLeft(2, '0')}:'
              '${secs.toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // CHART
  // ==========================================================

  Widget _buildChart() {
    if (candles.isEmpty) {
      return const SizedBox();
    }

    final chartCandles = candles.length > 70
        ? candles.sublist(candles.length - 70)
        : candles;

    return Card(
      child: Padding(
        padding: const EdgeInsets.only(top: 15, right: 8, bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 14, bottom: 12),
              child: Text(
                'ACCIÓN DEL PRECIO',
                style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
            ),
            SizedBox(
              height: 360,
              child: SfCartesianChart(
                backgroundColor: Colors.transparent,
                plotAreaBorderWidth: 0,
                primaryXAxis: DateTimeAxis(
                  majorGridLines: const MajorGridLines(width: 0),
                  dateFormat: DateFormat('HH:mm'),
                  labelStyle: const TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                  ),
                ),
                primaryYAxis: NumericAxis(
                  opposedPosition: true,
                  majorGridLines: const MajorGridLines(width: 0.25),
                  labelStyle: const TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                  ),
                  numberFormat: _chartNumberFormat(),
                ),
                series: [
                  CandleSeries<Candle, DateTime>(
                    dataSource: chartCandles,
                    xValueMapper: (Candle candle, _) => candle.time,
                    lowValueMapper: (Candle candle, _) => candle.low,
                    highValueMapper: (Candle candle, _) => candle.high,
                    openValueMapper: (Candle candle, _) => candle.open,
                    closeValueMapper: (Candle candle, _) => candle.close,
                    enableTooltip: true,
                  ),
                ],
                tooltipBehavior: TooltipBehavior(enable: true),
              ),
            ),
          ],
        ),
      ),
    );
  }

  NumberFormat _chartNumberFormat() {
    return NumberFormat(selectedPair.contains('JPY') ? '0.000' : '0.00000');
  }

  // ==========================================================
  // ANALYSIS
  // ==========================================================

  Widget _buildAnalysis(SignalResult result) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ANÁLISIS',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
            const SizedBox(height: 14),
            _analysisRow(
              'Estructura',
              result.structureBullish
                  ? 'ALCISTA'
                  : result.structureBearish
                  ? 'BAJISTA'
                  : 'NEUTRAL',
            ),
            _analysisRow(
              'BOS',
              result.bosBullish
                  ? 'ALCISTA'
                  : result.bosBearish
                  ? 'BAJISTA'
                  : 'NO',
            ),
            _analysisRow(
              'CHoCH',
              result.chochBullish
                  ? 'ALCISTA'
                  : result.chochBearish
                  ? 'BAJISTA'
                  : 'NO',
            ),
            _analysisRow('EMA 9', formatPrice(result.emaFast, selectedPair)),
            _analysisRow('EMA 21', formatPrice(result.emaSlow, selectedPair)),
            _analysisRow('ATR', formatPrice(result.atr, selectedPair)),
            _analysisRow('Momentum', '${result.momentum.toStringAsFixed(3)}%'),
          ],
        ),
      ),
    );
  }

  Widget _analysisRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: Colors.white54)),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // ==========================================================
  // LEVELS
  // ==========================================================

  Widget _buildLevels(SignalResult result) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'NIVELES',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
            const SizedBox(height: 14),
            _levelRow(
              Icons.vertical_align_bottom,
              'SOPORTE',
              formatPrice(result.support, selectedPair),
              Colors.greenAccent,
            ),
            const SizedBox(height: 10),
            _levelRow(
              Icons.vertical_align_top,
              'RESISTENCIA',
              formatPrice(result.resistance, selectedPair),
              Colors.redAccent,
            ),
          ],
        ),
      ),
    );
  }

  Widget _levelRow(IconData icon, String title, String value, Color color) {
    return Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(title, style: const TextStyle(color: Colors.white54)),
        ),
        Text(
          value,
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  // ==========================================================
  // CONFIRMATIONS
  // ==========================================================

  Widget _buildConfirmations(SignalResult result) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'CONFIRMACIONES',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
            const SizedBox(height: 12),
            if (result.confirmations.isEmpty)
              const Text(
                'Todavía no hay suficientes confirmaciones.',
                style: TextStyle(color: Colors.white54),
              )
            else
              ...result.confirmations.map(
                (item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle,
                        size: 17,
                        color: Color(0xFF00E676),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(item)),
                    ],
                  ),
                ),
              ),
            if (result.warnings.isNotEmpty) ...[
              const SizedBox(height: 15),
              const Text(
                'FILTROS',
                style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 7),
              ...result.warnings.map(
                (item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.remove_circle_outline,
                        size: 16,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item,
                          style: const TextStyle(color: Colors.white60),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // FOOTER
  // ==========================================================

  Widget _buildFooter() {
    return const Column(
      children: [
        Text(
          'Trading Signal Bot • Price Action Adaptive V11',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white38, fontSize: 12),
        ),
        SizedBox(height: 5),
        Text(
          'Datos: Biquote • Análisis automatizado',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white24, fontSize: 10),
        ),
      ],
    );
  }
}
