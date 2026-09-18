import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:signalr_netcore/signalr_client.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

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
      debugShowCheckedModeBanner: false,
      title: 'Trading Signal Bot',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF070B14),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const TradingHomePage(),
    );
  }
}

// ============================================================
// CANDLE
// ============================================================

class Candle {
  final DateTime time;

  double open;
  double high;
  double low;
  double close;

  bool isOpen;

  Candle({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    this.isOpen = false,
  });

  factory Candle.fromJson(Map<String, dynamic> json) {
    final rawTime =
        json['openTime'] ??
        json['open_time'] ??
        json['time'] ??
        json['timestamp'] ??
        json['date'] ??
        json['datetime'];

    DateTime parsedTime;

    if (rawTime is int) {
      parsedTime = rawTime < 1000000000000
          ? DateTime.fromMillisecondsSinceEpoch(rawTime * 1000)
          : DateTime.fromMillisecondsSinceEpoch(rawTime);
    } else if (rawTime is double) {
      final value = rawTime.toInt();

      parsedTime = value < 1000000000000
          ? DateTime.fromMillisecondsSinceEpoch(value * 1000)
          : DateTime.fromMillisecondsSinceEpoch(value);
    } else {
      parsedTime =
          DateTime.tryParse(rawTime?.toString() ?? '') ?? DateTime.now();
    }

    return Candle(
      time: parsedTime.toLocal(),
      open: _number(json['open']),
      high: _number(json['high']),
      low: _number(json['low']),
      close: _number(json['close']),
      isOpen: json['isOpen'] == true || json['is_open'] == true,
    );
  }

  static double _number(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}

// ============================================================
// SIGNAL RESULT
// ============================================================

class SignalResult {
  final String action;
  final String direction;
  final String strength;

  final int score;

  final double ema20;
  final double ema50;
  final double rsi;
  final double macd;
  final double macdSignal;
  final double adx;
  final double atr;

  final double entryPrice;

  final String trend;
  final String higherTrend;
  final String structure;
  final String priceAction;
  final String levelStatus;

  final String setup;
  final String setupStatus;

  final List<String> reasons;

  final String entryTiming;
  final DateTime? plannedEntryTime;

  final int confirmations;

  final double callScore;
  final double putScore;

  final double support;
  final double resistance;

  SignalResult({
    required this.action,
    required this.direction,
    required this.strength,
    required this.score,
    required this.ema20,
    required this.ema50,
    required this.rsi,
    required this.macd,
    required this.macdSignal,
    required this.adx,
    required this.atr,
    required this.entryPrice,
    required this.trend,
    required this.higherTrend,
    required this.structure,
    required this.priceAction,
    required this.levelStatus,
    required this.setup,
    required this.setupStatus,
    required this.reasons,
    required this.entryTiming,
    required this.plannedEntryTime,
    required this.confirmations,
    required this.callScore,
    required this.putScore,
    required this.support,
    required this.resistance,
  });

  factory SignalResult.wait({
    double price = 0,
    String reason = 'Esperando configuración válida',
  }) {
    return SignalResult(
      action: 'WAIT',
      direction: 'NEUTRAL',
      strength: 'WAIT',
      score: 0,
      ema20: 0,
      ema50: 0,
      rsi: 50,
      macd: 0,
      macdSignal: 0,
      adx: 0,
      atr: 0,
      entryPrice: price,
      trend: 'NEUTRAL',
      higherTrend: 'NEUTRAL',
      structure: 'LATERAL',
      priceAction: 'SIN CONFIRMACIÓN',
      levelStatus: 'NEUTRAL',
      setup: 'MONITOREANDO',
      setupStatus: 'WAIT',
      reasons: [reason],
      entryTiming: 'ESPERAR',
      plannedEntryTime: null,
      confirmations: 0,
      callScore: 0,
      putScore: 0,
      support: 0,
      resistance: 0,
    );
  }
}

// ============================================================
// BIQUOTE SERVICE
// ============================================================

class BiquoteService {
  static const String baseUrl = 'https://biquote.io/api';

  static const String signalRUrl = 'https://biquote.io/hubs/tick';

  static const List<String> supportedTimeframes = [
    '1m',
    '2m',
    '5m',
    '15m',
    '30m',
    '1h',
    '4h',
    '1d',
  ];

  static String normalizeSymbol(String symbol) {
    return symbol.replaceAll('/', '').toUpperCase();
  }

  // ----------------------------------------------------------
  // GET CANDLES
  // ----------------------------------------------------------

  static Future<List<Candle>> getCandles(
    String symbol,
    String timeframe, {
    int limit = 200,
  }) async {
    // --------------------------------------------------------
    // 2M
    //
    // Biquote trabaja con 1m y construimos 2m.
    // --------------------------------------------------------

    if (timeframe == '2m') {
      final oneMinute = await getCandles(
        symbol,
        '1m',
        limit: min(limit * 2 + 20, 1000),
      );

      final aggregated = aggregateCandles(
        oneMinute,
        const Duration(minutes: 2),
      );

      if (aggregated.isEmpty) {
        throw Exception('No se pudieron construir velas de 2m');
      }

      return aggregated;
    }

    final normalized = normalizeSymbol(symbol);

    final uri = Uri.parse(
      '$baseUrl/$normalized/ohlc'
      '?interval=$timeframe'
      '&limit=$limit',
    );

    final response = await http
        .get(uri, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      String detail = '';

      try {
        final decoded = jsonDecode(response.body);

        if (decoded is Map) {
          detail =
              decoded['message']?.toString() ??
              decoded['error']?.toString() ??
              '';
        }
      } catch (_) {}

      throw Exception(
        'Biquote HTTP ${response.statusCode}'
        '${detail.isNotEmpty ? ': $detail' : ''}',
      );
    }

    dynamic decoded;

    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw Exception('Biquote devolvió una respuesta JSON inválida');
    }

    // --------------------------------------------------------
    // Biquote:
    //
    // {
    //   "symbol": "EURUSD",
    //   "interval": "1m",
    //   "bars": [...]
    // }
    //
    // --------------------------------------------------------

    List<dynamic> bars = [];

    if (decoded is Map) {
      final rawBars = decoded['bars'];

      if (rawBars is List) {
        bars = rawBars;
      }

      // Compatibilidad con otras respuestas.
      if (bars.isEmpty) {
        final alternatives = [
          decoded['data'],
          decoded['candles'],
          decoded['ohlc'],
          decoded['result'],
        ];

        for (final item in alternatives) {
          if (item is List) {
            bars = item;
            break;
          }
        }
      }
    } else if (decoded is List) {
      bars = decoded;
    }

    if (bars.isEmpty) {
      throw Exception(
        'Biquote respondió correctamente pero no devolvió barras para $symbol $timeframe',
      );
    }

    final result = <Candle>[];

    for (final item in bars) {
      if (item is! Map) {
        continue;
      }

      try {
        final map = Map<String, dynamic>.from(item);

        final candle = Candle.fromJson(map);

        if (candle.open <= 0 ||
            candle.high <= 0 ||
            candle.low <= 0 ||
            candle.close <= 0) {
          continue;
        }

        result.add(candle);
      } catch (_) {}
    }

    result.sort((a, b) => a.time.compareTo(b.time));

    if (result.isEmpty) {
      throw Exception('Biquote devolvió barras pero ninguna vela fue válida');
    }

    return result;
  }

  // ----------------------------------------------------------
  // AGREGAR
  // ----------------------------------------------------------

  static List<Candle> aggregateCandles(List<Candle> source, Duration duration) {
    if (source.isEmpty) {
      return [];
    }

    final Map<int, List<Candle>> groups = {};

    for (final candle in source) {
      final bucket = _floorTime(candle.time, duration);

      groups.putIfAbsent(bucket.millisecondsSinceEpoch, () => []).add(candle);
    }

    final keys = groups.keys.toList()..sort();

    final result = <Candle>[];

    for (final key in keys) {
      final group = groups[key]!;

      if (group.isEmpty) {
        continue;
      }

      group.sort((a, b) => a.time.compareTo(b.time));

      result.add(
        Candle(
          time: DateTime.fromMillisecondsSinceEpoch(key),
          open: group.first.open,
          high: group.map((e) => e.high).reduce(max),
          low: group.map((e) => e.low).reduce(min),
          close: group.last.close,
          isOpen: group.any((e) => e.isOpen),
        ),
      );
    }

    return result;
  }

  static DateTime _floorTime(DateTime time, Duration duration) {
    final ms = time.millisecondsSinceEpoch;

    final size = duration.inMilliseconds;

    return DateTime.fromMillisecondsSinceEpoch((ms ~/ size) * size);
  }
}

// ============================================================
// TECHNICAL
// ============================================================

class Technical {
  static double ema(List<double> values, int period) {
    if (values.isEmpty) {
      return 0;
    }

    if (values.length < period) {
      return values.last;
    }

    final alpha = 2.0 / (period + 1);

    double result = values.take(period).reduce((a, b) => a + b) / period;

    for (int i = period; i < values.length; i++) {
      result = alpha * values[i] + (1 - alpha) * result;
    }

    return result;
  }

  static double rsi(List<double> closes, {int period = 14}) {
    if (closes.length <= period) {
      return 50;
    }

    double gains = 0;
    double losses = 0;

    for (int i = 1; i <= period; i++) {
      final change = closes[i] - closes[i - 1];

      if (change >= 0) {
        gains += change;
      } else {
        losses += change.abs();
      }
    }

    double avgGain = gains / period;

    double avgLoss = losses / period;

    for (int i = period + 1; i < closes.length; i++) {
      final change = closes[i] - closes[i - 1];

      final gain = change > 0 ? change : 0.0;

      final loss = change < 0 ? change.abs() : 0.0;

      avgGain = ((avgGain * (period - 1)) + gain) / period;

      avgLoss = ((avgLoss * (period - 1)) + loss) / period;
    }

    if (avgLoss == 0) {
      return 100;
    }

    final rs = avgGain / avgLoss;

    return 100 - (100 / (1 + rs));
  }

  static double trueRange(Candle current, Candle previous) {
    final a = current.high - current.low;

    final b = (current.high - previous.close).abs();

    final c = (current.low - previous.close).abs();

    return max(a, max(b, c));
  }

  static double atr(List<Candle> candles, {int period = 14}) {
    if (candles.length < period + 1) {
      return 0;
    }

    final values = <double>[];

    for (int i = 1; i < candles.length; i++) {
      values.add(trueRange(candles[i], candles[i - 1]));
    }

    if (values.length < period) {
      return 0;
    }

    return values.sublist(values.length - period).reduce((a, b) => a + b) /
        period;
  }

  static double macd(List<double> closes) {
    if (closes.length < 26) {
      return 0;
    }

    final fast = ema(closes, 12);

    final slow = ema(closes, 26);

    return fast - slow;
  }

  static double macdSignal(List<double> closes) {
    if (closes.length < 35) {
      return 0;
    }

    final values = <double>[];

    for (int i = 25; i < closes.length; i++) {
      final slice = closes.sublist(0, i + 1);

      values.add(ema(slice, 12) - ema(slice, 26));
    }

    return ema(values, 9);
  }

  static double adx(List<Candle> candles, {int period = 14}) {
    if (candles.length < period * 2 + 2) {
      return 0;
    }

    final trs = <double>[];
    final plusDm = <double>[];
    final minusDm = <double>[];

    for (int i = 1; i < candles.length; i++) {
      final current = candles[i];

      final previous = candles[i - 1];

      trs.add(trueRange(current, previous));

      final upMove = current.high - previous.high;

      final downMove = previous.low - current.low;

      plusDm.add(upMove > downMove && upMove > 0 ? upMove : 0);

      minusDm.add(downMove > upMove && downMove > 0 ? downMove : 0);
    }

    if (trs.length < period) {
      return 0;
    }

    final dxValues = <double>[];

    for (int i = period; i < trs.length; i++) {
      final start = i - period + 1;

      final trSum = trs.sublist(start, i + 1).reduce((a, b) => a + b);

      final plusSum = plusDm.sublist(start, i + 1).reduce((a, b) => a + b);

      final minusSum = minusDm.sublist(start, i + 1).reduce((a, b) => a + b);

      if (trSum == 0) {
        dxValues.add(0);
        continue;
      }

      final plusDi = 100 * plusSum / trSum;

      final minusDi = 100 * minusSum / trSum;

      final denominator = plusDi + minusDi;

      if (denominator == 0) {
        dxValues.add(0);
      } else {
        dxValues.add(100 * (plusDi - minusDi).abs() / denominator);
      }
    }

    if (dxValues.isEmpty) {
      return 0;
    }

    final usable = dxValues.length >= period
        ? dxValues.sublist(dxValues.length - period)
        : dxValues;

    return usable.reduce((a, b) => a + b) / usable.length;
  }
}

// ============================================================
// PRICE ACTION ENGINE
// ============================================================

class TradingStrategy {
  static const int minimumScore = 60;
  static const double minimumMargin = 8;
  static const int minimumConfirmations = 2;

  static SignalResult analyze(List<Candle> source, String timeframe) {
    final closed = source.where((c) => !c.isOpen).toList();

    if (closed.length < 40) {
      return SignalResult.wait(
        price: source.isNotEmpty ? source.last.close : 0,
        reason: 'Esperando al menos 40 velas cerradas',
      );
    }

    final recent = closed.length > 120
        ? closed.sublist(closed.length - 120)
        : closed;

    final last = recent.last;

    final closes = recent.map((e) => e.close).toList();

    // ----------------------------------------------------------
    // INDICADORES INFORMATIVOS
    // ----------------------------------------------------------

    final ema20 = Technical.ema(closes, 20);

    final ema50 = Technical.ema(closes, 50);

    final rsi = Technical.rsi(closes);

    final macd = Technical.macd(closes);

    final macdSignal = Technical.macdSignal(closes);

    final adx = Technical.adx(recent);

    final atr = Technical.atr(recent);

    // ----------------------------------------------------------
    // PIVOTS
    // ----------------------------------------------------------

    final pivotHighs = <int>[];

    final pivotLows = <int>[];

    for (int i = 2; i < recent.length - 2; i++) {
      final high = recent[i].high;

      final low = recent[i].low;

      final isHigh =
          high > recent[i - 1].high &&
          high > recent[i - 2].high &&
          high >= recent[i + 1].high &&
          high >= recent[i + 2].high;

      final isLow =
          low < recent[i - 1].low &&
          low < recent[i - 2].low &&
          low <= recent[i + 1].low &&
          low <= recent[i + 2].low;

      if (isHigh) {
        pivotHighs.add(i);
      }

      if (isLow) {
        pivotLows.add(i);
      }
    }

    // ----------------------------------------------------------
    // ESTRUCTURA
    // ----------------------------------------------------------

    bool bullishStructure = false;

    bool bearishStructure = false;

    if (pivotHighs.length >= 2 && pivotLows.length >= 2) {
      final h1 = recent[pivotHighs[pivotHighs.length - 2]].high;

      final h2 = recent[pivotHighs.last].high;

      final l1 = recent[pivotLows[pivotLows.length - 2]].low;

      final l2 = recent[pivotLows.last].low;

      bullishStructure = h2 > h1 && l2 > l1;

      bearishStructure = h2 < h1 && l2 < l1;
    }

    // ----------------------------------------------------------
    // SOPORTE / RESISTENCIA
    // ----------------------------------------------------------

    final resistance = pivotHighs.isNotEmpty
        ? recent[pivotHighs.last].high
        : recent
              .sublist(max(0, recent.length - 20))
              .map((e) => e.high)
              .reduce(max);

    final support = pivotLows.isNotEmpty
        ? recent[pivotLows.last].low
        : recent
              .sublist(max(0, recent.length - 20))
              .map((e) => e.low)
              .reduce(min);

    // ----------------------------------------------------------
    // BOS
    // ----------------------------------------------------------

    bool bullishBos = false;

    bool bearishBos = false;

    if (pivotHighs.isNotEmpty) {
      final high = recent[pivotHighs.last].high;

      bullishBos = last.close > high;
    }

    if (pivotLows.isNotEmpty) {
      final low = recent[pivotLows.last].low;

      bearishBos = last.close < low;
    }

    // ----------------------------------------------------------
    // CHOCH
    // ----------------------------------------------------------

    final bullishChoch = bullishBos && bearishStructure;

    final bearishChoch = bearishBos && bullishStructure;

    // ----------------------------------------------------------
    // VELA
    // ----------------------------------------------------------

    final range = max(last.high - last.low, 0.00000001);

    final body = (last.close - last.open).abs();

    final upperWick = last.high - max(last.open, last.close);

    final lowerWick = min(last.open, last.close) - last.low;

    final bodyRatio = body / range;

    final strongBull =
        last.close > last.open &&
        bodyRatio >= 0.55 &&
        last.close >= last.low + range * 0.70;

    final strongBear =
        last.close < last.open &&
        bodyRatio >= 0.55 &&
        last.close <= last.high - range * 0.70;

    // ----------------------------------------------------------
    // ENGULFING
    // ----------------------------------------------------------

    bool bullishEngulfing = false;

    bool bearishEngulfing = false;

    if (recent.length >= 2) {
      final previous = recent[recent.length - 2];

      bullishEngulfing =
          previous.close < previous.open &&
          last.close > last.open &&
          last.open <= previous.close &&
          last.close >= previous.open;

      bearishEngulfing =
          previous.close > previous.open &&
          last.close < last.open &&
          last.open >= previous.close &&
          last.close <= previous.open;
    }

    // ----------------------------------------------------------
    // REJECTION
    // ----------------------------------------------------------

    final bullishRejection =
        lowerWick >= body * 1.25 &&
        lowerWick > upperWick &&
        last.close > last.low + range * 0.55;

    final bearishRejection =
        upperWick >= body * 1.25 &&
        upperWick > lowerWick &&
        last.close < last.high - range * 0.55;

    // ----------------------------------------------------------
    // RANGO PROMEDIO
    // ----------------------------------------------------------

    final rangeWindow = recent.sublist(max(0, recent.length - 12));

    final ranges = rangeWindow.map((e) => e.high - e.low).toList();

    final avgRange = ranges.isEmpty
        ? range
        : ranges.reduce((a, b) => a + b) / ranges.length;

    // ----------------------------------------------------------
    // DISPLACEMENT
    // ----------------------------------------------------------

    final displacement = range >= avgRange * 1.20 && bodyRatio >= 0.55;

    final bullishDisplacement = displacement && last.close > last.open;

    final bearishDisplacement = displacement && last.close < last.open;

    // ----------------------------------------------------------
    // SWEEP
    // ----------------------------------------------------------

    bool bullishSweep = false;

    bool bearishSweep = false;

    if (recent.length >= 5) {
      final reference = recent[recent.length - 4];

      bullishSweep = last.low < reference.low && last.close > reference.low;

      bearishSweep = last.high > reference.high && last.close < reference.high;
    }

    // ----------------------------------------------------------
    // RETEST
    // ----------------------------------------------------------

    final bullishRetest =
        bullishBos &&
        last.low <= resistance * 1.0005 &&
        last.close > resistance;

    final bearishRetest =
        bearishBos && last.high >= support * 0.9995 && last.close < support;

    // ----------------------------------------------------------
    // FVG
    // ----------------------------------------------------------

    bool bullishFvg = false;

    bool bearishFvg = false;

    if (recent.length >= 3) {
      final a = recent[recent.length - 3];

      final b = recent[recent.length - 2];

      final c = recent.last;

      bullishFvg = c.low > a.high && b.close > b.open;

      bearishFvg = c.high < a.low && b.close < b.open;
    }

    // ----------------------------------------------------------
    // ORDER BLOCK
    // ----------------------------------------------------------

    bool bullishOb = false;

    bool bearishOb = false;

    if (recent.length >= 4) {
      final previous = recent[recent.length - 2];

      bullishOb = previous.close < previous.open && last.close > previous.high;

      bearishOb = previous.close > previous.open && last.close < previous.low;
    }

    // ----------------------------------------------------------
    // NIVELES
    // ----------------------------------------------------------

    final levelDistance = max(atr, avgRange * 0.50);

    final nearSupport = (last.close - support).abs() <= levelDistance;

    final nearResistance = (last.close - resistance).abs() <= levelDistance;

    // ----------------------------------------------------------
    // CONTEXTO
    // ----------------------------------------------------------

    final bullishContext = bullishStructure || bullishBos || bullishChoch;

    final bearishContext = bearishStructure || bearishBos || bearishChoch;

    // ----------------------------------------------------------
    // TRIGGER
    // ----------------------------------------------------------

    final bullishTrigger =
        strongBull ||
        bullishEngulfing ||
        bullishRejection ||
        bullishDisplacement;

    final bearishTrigger =
        strongBear ||
        bearishEngulfing ||
        bearishRejection ||
        bearishDisplacement;

    // ----------------------------------------------------------
    // SCORE DE ESTRUCTURA
    // Máximo 35.
    // ----------------------------------------------------------

    double callContext = 0;
    double putContext = 0;

    if (bullishStructure) {
      callContext += 18;
    }

    if (bullishBos) {
      callContext += 22;
    }

    if (bullishChoch) {
      callContext += 20;
    }

    if (bearishStructure) {
      putContext += 18;
    }

    if (bearishBos) {
      putContext += 22;
    }

    if (bearishChoch) {
      putContext += 20;
    }

    callContext = min(callContext, 35);

    putContext = min(putContext, 35);

    // ----------------------------------------------------------
    // SCORE LIQUIDEZ
    // Máximo 20.
    // ----------------------------------------------------------

    double callLiquidity = 0;
    double putLiquidity = 0;

    if (bullishSweep) {
      callLiquidity += 18;
    }

    if (bullishRetest) {
      callLiquidity += 15;
    }

    if (nearSupport) {
      callLiquidity += 5;
    }

    if (bearishSweep) {
      putLiquidity += 18;
    }

    if (bearishRetest) {
      putLiquidity += 15;
    }

    if (nearResistance) {
      putLiquidity += 5;
    }

    callLiquidity = min(callLiquidity, 20);

    putLiquidity = min(putLiquidity, 20);

    // ----------------------------------------------------------
    // SCORE TRIGGER
    // Máximo 30.
    // ----------------------------------------------------------

    double callTrigger = 0;
    double putTrigger = 0;

    if (bullishEngulfing) {
      callTrigger += 14;
    }

    if (bullishRejection) {
      callTrigger += 11;
    }

    if (bullishDisplacement) {
      callTrigger += 10;
    }

    if (strongBull) {
      callTrigger += 7;
    }

    if (bearishEngulfing) {
      putTrigger += 14;
    }

    if (bearishRejection) {
      putTrigger += 11;
    }

    if (bearishDisplacement) {
      putTrigger += 10;
    }

    if (strongBear) {
      putTrigger += 7;
    }

    callTrigger = min(callTrigger, 30);

    putTrigger = min(putTrigger, 30);

    // ----------------------------------------------------------
    // IMBALANCE
    // Máximo 10.
    // ----------------------------------------------------------

    double callImbalance = 0;
    double putImbalance = 0;

    if (bullishFvg) {
      callImbalance += 6;
    }

    if (bullishOb) {
      callImbalance += 6;
    }

    if (bearishFvg) {
      putImbalance += 6;
    }

    if (bearishOb) {
      putImbalance += 6;
    }

    callImbalance = min(callImbalance, 10);

    putImbalance = min(putImbalance, 10);

    // ----------------------------------------------------------
    // SCORE FINAL
    // ----------------------------------------------------------

    double callScore =
        callContext + callLiquidity + callTrigger + callImbalance;

    double putScore = putContext + putLiquidity + putTrigger + putImbalance;

    // ----------------------------------------------------------
    // CONFLICTOS
    // ----------------------------------------------------------

    final strongConflict =
        (bullishBos && bearishBos) ||
        (bullishChoch && bearishChoch) ||
        (bullishSweep && bearishSweep) ||
        (bullishTrigger && bearishTrigger);

    if (strongConflict) {
      callScore -= 15;
      putScore -= 15;
    }

    // ----------------------------------------------------------
    // EXTENSIÓN
    // ----------------------------------------------------------

    final overextended = range > avgRange * 2.50;

    // ----------------------------------------------------------
    // INDECISIÓN
    // ----------------------------------------------------------

    final indecision = bodyRatio < 0.15;

    // ----------------------------------------------------------
    // BLOQUEOS
    // ----------------------------------------------------------

    final callBlocked = nearResistance && !bullishBos && !bullishSweep;

    final putBlocked = nearSupport && !bearishBos && !bearishSweep;

    // ----------------------------------------------------------
    // CONFIRMACIONES INDEPENDIENTES
    // ----------------------------------------------------------

    int callConfirmations = 0;
    int putConfirmations = 0;

    if (bullishContext) {
      callConfirmations++;
    }

    if (bearishContext) {
      putConfirmations++;
    }

    if (bullishSweep || bullishRetest || nearSupport) {
      callConfirmations++;
    }

    if (bearishSweep || bearishRetest || nearResistance) {
      putConfirmations++;
    }

    if (bullishTrigger) {
      callConfirmations++;
    }

    if (bearishTrigger) {
      putConfirmations++;
    }

    if (bullishFvg || bullishOb) {
      callConfirmations++;
    }

    if (bearishFvg || bearishOb) {
      putConfirmations++;
    }

    // ----------------------------------------------------------
    // SETUPS
    // ----------------------------------------------------------

    final continuationCall = bullishContext && bullishTrigger;

    final continuationPut = bearishContext && bearishTrigger;

    final reversalCall =
        bullishSweep &&
        bullishTrigger &&
        (nearSupport || bullishChoch || bullishBos);

    final reversalPut =
        bearishSweep &&
        bearishTrigger &&
        (nearResistance || bearishChoch || bearishBos);

    final breakoutCall = bullishBos && bullishTrigger;

    final breakoutPut = bearishBos && bearishTrigger;

    final validCall = continuationCall || reversalCall || breakoutCall;

    final validPut = continuationPut || reversalPut || breakoutPut;

    // ----------------------------------------------------------
    // VALIDACIÓN
    // ----------------------------------------------------------

    final commonBlocked = overextended || indecision || strongConflict;

    final callReady =
        !commonBlocked &&
        !callBlocked &&
        validCall &&
        callScore >= minimumScore &&
        callScore - putScore >= minimumMargin &&
        callConfirmations >= minimumConfirmations;

    final putReady =
        !commonBlocked &&
        !putBlocked &&
        validPut &&
        putScore >= minimumScore &&
        putScore - callScore >= minimumMargin &&
        putConfirmations >= minimumConfirmations;

    // ----------------------------------------------------------
    // SETUP
    // ----------------------------------------------------------

    String setup = 'MONITOREANDO';

    if (callReady) {
      if (breakoutCall) {
        setup = 'RUPTURA ALCISTA';
      } else if (reversalCall) {
        setup = 'REVERSIÓN ALCISTA';
      } else {
        setup = 'CONTINUACIÓN ALCISTA';
      }
    } else if (putReady) {
      if (breakoutPut) {
        setup = 'RUPTURA BAJISTA';
      } else if (reversalPut) {
        setup = 'REVERSIÓN BAJISTA';
      } else {
        setup = 'CONTINUACIÓN BAJISTA';
      }
    } else if (bullishContext && bullishTrigger) {
      setup = 'SETUP ALCISTA';
    } else if (bearishContext && bearishTrigger) {
      setup = 'SETUP BAJISTA';
    }

    // ----------------------------------------------------------
    // WAIT
    // ----------------------------------------------------------

    if (!callReady && !putReady) {
      String reason;

      if (indecision) {
        reason = 'Vela de indecisión';
      } else if (overextended) {
        reason = 'Movimiento demasiado extendido';
      } else if (strongConflict) {
        reason = 'Conflicto entre compradores y vendedores';
      } else if (callBlocked && callScore >= putScore) {
        reason = 'CALL bloqueado por resistencia';
      } else if (putBlocked && putScore > callScore) {
        reason = 'PUT bloqueado por soporte';
      } else if (max(callScore, putScore) < minimumScore) {
        reason = 'Falta confluencia suficiente';
      } else {
        reason = 'Esperando ventaja clara';
      }

      final trend = callScore > putScore
          ? 'ALCISTA'
          : putScore > callScore
          ? 'BAJISTA'
          : 'NEUTRAL';

      final structure = bullishStructure
          ? 'HH + HL'
          : bearishStructure
          ? 'LH + LL'
          : bullishBos
          ? 'BOS ↑'
          : bearishBos
          ? 'BOS ↓'
          : 'LATERAL';

      return SignalResult(
        action: 'WAIT',
        direction: 'NEUTRAL',
        strength: 'WAIT',
        score: max(callScore, putScore).round().clamp(0, 100),
        ema20: ema20,
        ema50: ema50,
        rsi: rsi,
        macd: macd,
        macdSignal: macdSignal,
        adx: adx,
        atr: atr,
        entryPrice: last.close,
        trend: trend,
        higherTrend: trend,
        structure: structure,
        priceAction: bullishTrigger
            ? 'COMPRA'
            : bearishTrigger
            ? 'VENTA'
            : 'NEUTRAL',
        levelStatus: nearSupport
            ? 'SOPORTE'
            : nearResistance
            ? 'RESISTENCIA'
            : 'NEUTRAL',
        setup: setup,
        setupStatus: 'CONFIRMANDO',
        reasons: [
          reason,
          if (callConfirmations > 0) 'CALL: $callConfirmations confirmaciones',
          if (putConfirmations > 0) 'PUT: $putConfirmations confirmaciones',
        ],
        entryTiming: 'ESPERAR',
        plannedEntryTime: null,
        confirmations: max(callConfirmations, putConfirmations),
        callScore: callScore,
        putScore: putScore,
        support: support,
        resistance: resistance,
      );
    }

    // ----------------------------------------------------------
    // SEÑAL
    // ----------------------------------------------------------

    final isCall = callReady;

    final finalScore = (isCall ? callScore : putScore).round().clamp(0, 100);

    final finalConfirmations = isCall ? callConfirmations : putConfirmations;

    final strength = finalScore >= 85
        ? 'VERY STRONG'
        : finalScore >= 75
        ? 'STRONG'
        : finalScore >= 68
        ? 'GOOD'
        : 'MODERATE';

    final reasons = <String>[];

    if (isCall) {
      if (bullishStructure) {
        reasons.add('Estructura alcista HH + HL');
      }

      if (bullishBos) {
        reasons.add('BOS alcista');
      }

      if (bullishChoch) {
        reasons.add('CHoCH alcista');
      }

      if (bullishSweep) {
        reasons.add('Sweep de liquidez inferior');
      }

      if (bullishRetest) {
        reasons.add('Retesteo alcista');
      }

      if (bullishEngulfing) {
        reasons.add('Envolvente alcista');
      }

      if (bullishRejection) {
        reasons.add('Rechazo alcista');
      }

      if (bullishDisplacement) {
        reasons.add('Desplazamiento alcista');
      }

      if (nearSupport) {
        reasons.add('Precio cerca de soporte');
      }

      if (bullishFvg) {
        reasons.add('FVG alcista');
      }

      if (bullishOb) {
        reasons.add('Order Block alcista');
      }
    } else {
      if (bearishStructure) {
        reasons.add('Estructura bajista LH + LL');
      }

      if (bearishBos) {
        reasons.add('BOS bajista');
      }

      if (bearishChoch) {
        reasons.add('CHoCH bajista');
      }

      if (bearishSweep) {
        reasons.add('Sweep de liquidez superior');
      }

      if (bearishRetest) {
        reasons.add('Retesteo bajista');
      }

      if (bearishEngulfing) {
        reasons.add('Envolvente bajista');
      }

      if (bearishRejection) {
        reasons.add('Rechazo bajista');
      }

      if (bearishDisplacement) {
        reasons.add('Desplazamiento bajista');
      }

      if (nearResistance) {
        reasons.add('Precio cerca de resistencia');
      }

      if (bearishFvg) {
        reasons.add('FVG bajista');
      }

      if (bearishOb) {
        reasons.add('Order Block bajista');
      }
    }

    if (reasons.isEmpty) {
      reasons.add('Confluencia Price Action confirmada');
    }

    return SignalResult(
      action: isCall ? 'CALL' : 'PUT',
      direction: isCall ? 'UP' : 'DOWN',
      strength: strength,
      score: finalScore,
      ema20: ema20,
      ema50: ema50,
      rsi: rsi,
      macd: macd,
      macdSignal: macdSignal,
      adx: adx,
      atr: atr,
      entryPrice: last.close,
      trend: isCall ? 'ALCISTA' : 'BAJISTA',
      higherTrend: bullishStructure
          ? 'ALCISTA'
          : bearishStructure
          ? 'BAJISTA'
          : 'NEUTRAL',
      structure: isCall
          ? bullishStructure
                ? 'HH + HL'
                : bullishBos
                ? 'BOS ↑'
                : 'REVERSIÓN'
          : bearishStructure
          ? 'LH + LL'
          : bearishBos
          ? 'BOS ↓'
          : 'REVERSIÓN',
      priceAction: isCall ? 'CONFIRMACIÓN ALCISTA' : 'CONFIRMACIÓN BAJISTA',
      levelStatus: isCall
          ? nearSupport
                ? 'SOPORTE'
                : 'BREAKOUT'
          : nearResistance
          ? 'RESISTENCIA'
          : 'BREAKOUT',
      setup: setup,
      setupStatus: 'SIGNAL',
      reasons: reasons,
      entryTiming: 'PREPARANDO ENTRADA',
      plannedEntryTime: DateTime.now().add(const Duration(seconds: 15)),
      confirmations: finalConfirmations,
      callScore: callScore,
      putScore: putScore,
      support: support,
      resistance: resistance,
    );
  }
}

// ============================================================
// HOME
// ============================================================

class TradingHomePage extends StatefulWidget {
  const TradingHomePage({super.key});

  @override
  State<TradingHomePage> createState() => _TradingHomePageState();
}

class _TradingHomePageState extends State<TradingHomePage> {
  // ==========================================================
  // ASSETS
  // ==========================================================

  static const List<String> assets = [
    'EUR/USD',
    'GBP/USD',
    'USD/JPY',
    'AUD/USD',
    'USD/CAD',
    'USD/CHF',
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
    'CAD/JPY',
    'CAD/CHF',
    'CHF/JPY',
    'NZD/JPY',
    'NZD/CAD',
    'NZD/CHF',
    'USD/SGD',
    'USD/HKD',
    'USD/SEK',
    'USD/NOK',
    'USD/DKK',
    'USD/PLN',
    'USD/CZK',
    'USD/HUF',
    'USD/TRY',
    'USD/ZAR',
    'USD/MXN',
    'USD/BRL',
    'USD/THB',
    'USD/ILS',
    'USD/CNH',
    'EUR/PLN',
    'EUR/TRY',
    'EUR/SEK',
    'EUR/NOK',
    'EUR/DKK',
    'EUR/HUF',
    'EUR/CZK',
    'EUR/ZAR',
    'GBP/SEK',
    'GBP/NOK',
    'GBP/SGD',
    'GBP/ZAR',
    'AUD/SGD',
    'AUD/ZAR',
    'NZD/SGD',
    'SGD/JPY',
  ];

  static const List<String> timeframes = [
    '1m',
    '2m',
    '5m',
    '15m',
    '30m',
    '1h',
    '4h',
    '1d',
  ];

  // ==========================================================
  // STATE
  // ==========================================================

  String selectedAsset = 'EUR/USD';

  String selectedTimeframe = '1m';

  List<Candle> candles = [];

  SignalResult? signal;

  double currentPrice = 0;

  String? errorMessage;

  bool isAnalyzing = false;

  bool isLive = false;

  HubConnection? hubConnection;

  Timer? priceTimer;

  Timer? analysisTimer;

  Timer? countdownTimer;

  DateTime? signalCandleTime;

  DateTime? signalGeneratedAt;

  int entryCountdown = 0;

  bool entryReady = false;

  bool continuousAnalysisRunning = false;

  // ==========================================================
  // INIT
  // ==========================================================

  @override
  void initState() {
    super.initState();

    _startLiveSystem();
  }

  @override
  void dispose() {
    priceTimer?.cancel();
    analysisTimer?.cancel();
    countdownTimer?.cancel();

    try {
      hubConnection?.stop();
    } catch (_) {}

    super.dispose();
  }

  // ==========================================================
  // START
  // ==========================================================

  Future<void> _startLiveSystem() async {
    await _connectSignalR();

    _startPriceTimer();

    await _loadInitialAnalysis();

    _startContinuousAnalysis();
  }

  // ==========================================================
  // SIGNALR
  // ==========================================================

  Future<void> _connectSignalR() async {
    try {
      final connection = HubConnectionBuilder()
          .withUrl(BiquoteService.signalRUrl)
          .build();

      connection.on('ReceiveTick', (arguments) {
        if (arguments == null || arguments.isEmpty) {
          return;
        }

        _handleTick(arguments.first);
      });

      await connection.start();

      hubConnection = connection;

      if (!mounted) return;

      setState(() {
        isLive = true;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        isLive = false;
      });
    }
  }

  // ==========================================================
  // PRICE TIMER
  // ==========================================================

  void _startPriceTimer() {
    priceTimer?.cancel();

    priceTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      await _refreshLivePrice();
    });
  }

  // ==========================================================
  // CONTINUOUS ANALYSIS
  // ==========================================================

  void _startContinuousAnalysis() {
    if (continuousAnalysisRunning) {
      return;
    }

    continuousAnalysisRunning = true;

    analysisTimer?.cancel();

    analysisTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!isAnalyzing) {
        await _analyzeRealtime();
      }
    });
  }

  // ==========================================================
  // TICK
  // ==========================================================

  void _handleTick(dynamic raw) {
    try {
      double? price;

      if (raw is Map) {
        final map = Map<String, dynamic>.from(raw);

        final mid = _readNumber(map['mid']);

        final bid = _readNumber(map['bid']);

        final ask = _readNumber(map['ask']);

        price =
            mid ??
            ((bid != null && ask != null) ? (bid + ask) / 2 : bid ?? ask);
      } else if (raw is num) {
        price = raw.toDouble();
      }

      if (price == null || price <= 0) {
        return;
      }

      _setLivePrice(price);
    } catch (_) {}
  }

  double? _readNumber(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '');
  }

  void _setLivePrice(double price) {
    if (!mounted) return;

    setState(() {
      currentPrice = price;
      isLive = true;
    });

    _updateCurrentCandle(price);
  }

  // ==========================================================
  // TIMEFRAME
  // ==========================================================

  Duration _timeframeDuration(String timeframe) {
    switch (timeframe) {
      case '1m':
        return const Duration(minutes: 1);

      case '2m':
        return const Duration(minutes: 2);

      case '5m':
        return const Duration(minutes: 5);

      case '15m':
        return const Duration(minutes: 15);

      case '30m':
        return const Duration(minutes: 30);

      case '1h':
        return const Duration(hours: 1);

      case '4h':
        return const Duration(hours: 4);

      case '1d':
        return const Duration(days: 1);

      default:
        return const Duration(minutes: 1);
    }
  }

  DateTime _floorTime(DateTime time, Duration duration) {
    final milliseconds = time.millisecondsSinceEpoch;

    final size = duration.inMilliseconds;

    return DateTime.fromMillisecondsSinceEpoch((milliseconds ~/ size) * size);
  }

  // ==========================================================
  // LIVE CANDLE
  // ==========================================================

  void _updateCurrentCandle(double price) {
    if (candles.isEmpty) {
      return;
    }

    final duration = _timeframeDuration(selectedTimeframe);

    final candleStart = _floorTime(DateTime.now(), duration);

    final last = candles.last;

    if (last.time == candleStart) {
      setState(() {
        last.close = price;

        if (price > last.high) {
          last.high = price;
        }

        if (price < last.low) {
          last.low = price;
        }

        last.isOpen = true;
      });

      return;
    }

    if (last.time.isBefore(candleStart)) {
      final newCandle = Candle(
        time: candleStart,
        open: last.close,
        high: max(last.close, price),
        low: min(last.close, price),
        close: price,
        isOpen: true,
      );

      setState(() {
        candles = [...candles, newCandle];
      });
    }
  }

  // ==========================================================
  // LOAD
  // ==========================================================

  Future<void> _loadInitialAnalysis() async {
    if (!mounted) {
      return;
    }

    setState(() {
      isAnalyzing = true;
      errorMessage = null;
    });

    try {
      final downloaded = await BiquoteService.getCandles(
        selectedAsset,
        selectedTimeframe,
        limit: 200,
      );

      if (downloaded.isEmpty) {
        throw Exception(
          'Biquote no devolvió velas para '
          '$selectedAsset en '
          '$selectedTimeframe',
        );
      }

      downloaded.sort((a, b) => a.time.compareTo(b.time));

      final closedCount = downloaded.where((c) => !c.isOpen).length;

      if (closedCount < 40) {
        throw Exception(
          'Biquote devolvió '
          '$closedCount velas cerradas. '
          'Se necesitan al menos 40.',
        );
      }

      final latestPrice = currentPrice > 0
          ? currentPrice
          : downloaded.last.close;

      if (!mounted) return;

      setState(() {
        candles = downloaded;

        currentPrice = latestPrice;

        isLive = true;

        isAnalyzing = false;
      });

      await _analyzeRealtime();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isAnalyzing = false;

        errorMessage = e.toString().replaceFirst('Exception: ', '');

        isLive = false;
      });
    }
  }

  // ==========================================================
  // ANALYZE
  // ==========================================================

  Future<void> _analyzeRealtime() async {
    if (candles.isEmpty) {
      return;
    }

    final closed = candles.where((c) => !c.isOpen).toList();

    if (closed.length < 40) {
      return;
    }

    try {
      final result = TradingStrategy.analyze(closed, selectedTimeframe);

      // --------------------------------------------------------
      // Si ya estamos en countdown no reemplazar la entrada.
      // --------------------------------------------------------

      if (entryCountdown > 0 && signal != null && signal!.action != 'WAIT') {
        return;
      }

      // --------------------------------------------------------
      // WAIT
      // --------------------------------------------------------

      if (result.action == 'WAIT') {
        if (!mounted) {
          return;
        }

        setState(() {
          signal = result;
        });

        return;
      }

      // --------------------------------------------------------
      // NO REPETIR MISMA SEÑAL
      // --------------------------------------------------------

      final triggerTime = candles.isNotEmpty && candles.last.isOpen
          ? candles.last.time
          : closed.last.time;

      if (signalCandleTime == triggerTime && signal?.action == result.action) {
        return;
      }

      signalCandleTime = triggerTime;

      signalGeneratedAt = DateTime.now();

      _startEntryCountdown(result);

      if (!mounted) return;

      setState(() {
        signal = result;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        errorMessage = 'Error analizando mercado: $e';
      });
    }
  }

  // ==========================================================
  // MANUAL ANALYZE BUTTON
  // ==========================================================

  Future<void> _manualAnalyze() async {
    if (isAnalyzing) {
      return;
    }

    countdownTimer?.cancel();

    if (!mounted) return;

    setState(() {
      isAnalyzing = true;
      errorMessage = null;
      entryCountdown = 0;
      entryReady = false;
      signalCandleTime = null;
      signal = null;
    });

    await _loadInitialAnalysis();

    if (mounted) {
      setState(() {
        isAnalyzing = false;
      });
    }
  }

  // ==========================================================
  // COUNTDOWN
  // ==========================================================

  void _startEntryCountdown(SignalResult result) {
    countdownTimer?.cancel();

    entryCountdown = 15;
    entryReady = false;

    countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (entryCountdown <= 1) {
        timer.cancel();

        setState(() {
          entryCountdown = 0;
          entryReady = true;
        });

        return;
      }

      setState(() {
        entryCountdown--;
      });
    });
  }

  // ==========================================================
  // PRICE REFRESH
  // ==========================================================

  Future<void> _refreshLivePrice() async {
    try {
      final downloaded = await BiquoteService.getCandles(
        selectedAsset,
        '1m',
        limit: 5,
      );

      if (downloaded.isEmpty) {
        return;
      }

      _setLivePrice(downloaded.last.close);
    } catch (_) {}
  }

  // ==========================================================
  // CHANGE ASSET
  // ==========================================================

  Future<void> _changeAsset(String? value) async {
    if (value == null || value == selectedAsset) {
      return;
    }

    countdownTimer?.cancel();

    if (!mounted) return;

    setState(() {
      selectedAsset = value;

      candles = [];

      signal = null;

      errorMessage = null;

      currentPrice = 0;

      entryCountdown = 0;

      entryReady = false;

      signalCandleTime = null;

      signalGeneratedAt = null;

      isAnalyzing = true;
    });

    await _loadInitialAnalysis();
  }

  // ==========================================================
  // CHANGE TIMEFRAME
  // ==========================================================

  Future<void> _changeTimeframe(String? value) async {
    if (value == null || value == selectedTimeframe) {
      return;
    }

    countdownTimer?.cancel();

    if (!mounted) return;

    setState(() {
      selectedTimeframe = value;

      candles = [];

      signal = null;

      errorMessage = null;

      entryCountdown = 0;

      entryReady = false;

      signalCandleTime = null;

      signalGeneratedAt = null;

      isAnalyzing = true;
    });

    await _loadInitialAnalysis();
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF070B14),
        elevation: 0,
        titleSpacing: 18,
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: const LinearGradient(
                  colors: [Color(0xFF6C63FF), Color(0xFF9B8CFF)],
                ),
              ),
              child: const Icon(
                Icons.candlestick_chart,
                color: Colors.white,
                size: 21,
              ),
            ),
            const SizedBox(width: 11),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TRADING SIGNAL',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  'PRICE ACTION ENGINE',
                  style: TextStyle(
                    fontSize: 9,
                    color: Color(0xFF7F8AA3),
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [_liveBadge(), const SizedBox(width: 14)],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadInitialAnalysis,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 30),
            children: [
              _buildSelectors(),
              const SizedBox(height: 10),
              _buildAnalyzeButton(),
              const SizedBox(height: 14),
              _buildMarketHeader(),
              const SizedBox(height: 14),
              _buildSignalHero(),
              const SizedBox(height: 14),
              _buildMetricsGrid(),
              const SizedBox(height: 14),
              _buildConfluenceCard(),
              const SizedBox(height: 14),
              _buildChartCard(),
              const SizedBox(height: 14),
              _buildEngineCard(),
              if (errorMessage != null) ...[
                const SizedBox(height: 14),
                _buildErrorCard(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // LIVE BADGE
  // ==========================================================

  Widget _liveBadge() {
    final color = isLive ? const Color(0xFF31D391) : const Color(0xFFFF5964);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.30)),
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 6),
          Text(
            isLive ? 'LIVE' : 'OFFLINE',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // SELECTORS
  // ==========================================================

  Widget _buildSelectors() {
    return Row(
      children: [
        Expanded(
          child: _dropdownCard(
            label: 'ACTIVO',
            value: selectedAsset,
            items: assets,
            onChanged: _changeAsset,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _dropdownCard(
            label: 'TIMEFRAME',
            value: selectedTimeframe,
            items: timeframes,
            onChanged: _changeTimeframe,
          ),
        ),
      ],
    );
  }

  Widget _dropdownCard({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1321),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFF1C2639)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              color: Color(0xFF69758D),
              letterSpacing: 1,
            ),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              dropdownColor: const Color(0xFF111827),
              icon: const Icon(Icons.keyboard_arrow_down, size: 18),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
              items: items.map((item) {
                return DropdownMenuItem<String>(
                  value: item,
                  child: Text(item, overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // ANALYZE BUTTON
  // ==========================================================

  Widget _buildAnalyzeButton() {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: isAnalyzing ? null : _manualAnalyze,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF6C63FF),
          disabledBackgroundColor: const Color(0xFF252B3A),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
        child: isAnalyzing
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 10),
                  Text(
                    'ANALIZANDO...',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.radar_rounded, size: 20),
                  SizedBox(width: 9),
                  Text(
                    'ANALIZAR MERCADO',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ==========================================================
  // MARKET
  // ==========================================================

  Widget _buildMarketHeader() {
    final price = _formatPrice(currentPrice);

    final trend = signal?.trend ?? 'NEUTRAL';

    final trendColor = trend == 'ALCISTA'
        ? const Color(0xFF31D391)
        : trend == 'BAJISTA'
        ? const Color(0xFFFF5964)
        : const Color(0xFF8D99AE);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0B111E),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF182337)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selectedAsset,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF7F8AA3),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  price,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: trendColor.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: trendColor.withOpacity(0.30)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  'TENDENCIA',
                  style: TextStyle(
                    fontSize: 8,
                    color: Color(0xFF69758D),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  trend,
                  style: TextStyle(
                    color: trendColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // SIGNAL HERO
  // ==========================================================

  Widget _buildSignalHero() {
    final s = signal;

    final isCall = s?.action == 'CALL';

    final isPut = s?.action == 'PUT';

    final isWait = !isCall && !isPut;

    final color = isCall
        ? const Color(0xFF31D391)
        : isPut
        ? const Color(0xFFFF5964)
        : const Color(0xFF8D99AE);

    final icon = isCall
        ? Icons.arrow_upward_rounded
        : isPut
        ? Icons.arrow_downward_rounded
        : Icons.remove_rounded;

    final title = isCall
        ? 'CALL'
        : isPut
        ? 'PUT'
        : 'ESPERAR';

    final score = s?.score ?? 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withOpacity(0.13),
            const Color(0xFF0C1220),
            const Color(0xFF0A0F1B),
          ],
        ),
        border: Border.all(color: color.withOpacity(0.38)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withOpacity(0.12),
                  border: Border.all(color: color.withOpacity(0.35), width: 2),
                ),
                child: Icon(icon, color: color, size: 34),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: color,
                        letterSpacing: 1,
                      ),
                    ),
                    Text(
                      s?.setup ?? 'MONITOREANDO MERCADO',
                      style: const TextStyle(
                        color: Color(0xFFA7B0C2),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isWait) _strengthBadge(s!.strength, color),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              const Text(
                'CONFLUENCIA',
                style: TextStyle(
                  fontSize: 9,
                  color: Color(0xFF69758D),
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              Text(
                '$score/100',
                style: TextStyle(
                  color: color,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: (score / 100).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: const Color(0xFF1A2333),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 18),
          if (isWait) _buildWaitingState(s) else _buildEntryState(s!),
        ],
      ),
    );
  }

  Widget _strengthBadge(String strength, Color color) {
    String text;

    switch (strength) {
      case 'VERY STRONG':
        text = 'MUY FUERTE';
        break;

      case 'STRONG':
        text = 'FUERTE';
        break;

      case 'GOOD':
        text = 'BUENA';
        break;

      default:
        text = 'MODERADA';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildWaitingState(SignalResult? s) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.radar_rounded, color: Color(0xFF8D99AE), size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              s?.reasons.first ?? 'Buscando configuración...',
              style: const TextStyle(
                color: Color(0xFFA7B0C2),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryState(SignalResult s) {
    final color = s.action == 'CALL'
        ? const Color(0xFF31D391)
        : const Color(0xFFFF5964);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                entryReady ? 'GO' : '$entryCountdown',
                style: TextStyle(
                  color: color,
                  fontSize: entryReady ? 13 : 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entryReady ? 'ENTRADA ACTIVA' : 'PREPARANDO ENTRADA',
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  entryReady
                      ? 'Ventana de entrada lista'
                      : 'Confirmando condiciones',
                  style: const TextStyle(
                    color: Color(0xFFA7B0C2),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          Text(
            _formatPrice(s.entryPrice),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // METRICS
  // ==========================================================

  Widget _buildMetricsGrid() {
    final s = signal;

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.75,
      children: [
        _metricCard(
          'ESTRUCTURA',
          s?.structure ?? '--',
          Icons.account_tree_rounded,
          const Color(0xFF6C63FF),
        ),
        _metricCard(
          'PRICE ACTION',
          s?.priceAction ?? '--',
          Icons.bolt_rounded,
          const Color(0xFFFFB84D),
        ),
        _metricCard(
          'NIVEL',
          s?.levelStatus ?? '--',
          Icons.layers_rounded,
          const Color(0xFF42A5F5),
        ),
        _metricCard(
          'CONFIRMACIONES',
          '${s?.confirmations ?? 0}/4',
          Icons.verified_rounded,
          const Color(0xFF31D391),
        ),
      ],
    );
  }

  Widget _metricCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1321),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1A2538)),
      ),
      child: Row(
        children: [
          Container(
            width: 37,
            height: 37,
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF69758D),
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .7,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // CONFLUENCE
  // ==========================================================

  Widget _buildConfluenceCard() {
    final s = signal;

    return _sectionCard(
      title: 'CONFLUENCIA DEL MERCADO',
      icon: Icons.hub_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (s == null)
            const Text(
              'Esperando análisis...',
              style: TextStyle(color: Color(0xFF7F8AA3)),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: _scoreColumn(
                    'CALL',
                    s.callScore,
                    const Color(0xFF31D391),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: _scoreColumn(
                    'PUT',
                    s.putScore,
                    const Color(0xFFFF5964),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Text(
              'CONFIRMACIONES DETECTADAS',
              style: TextStyle(
                fontSize: 9,
                color: Color(0xFF69758D),
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: s.reasons
                  .take(8)
                  .map((reason) => _reasonChip(reason))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _scoreColumn(String label, double score, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
            const Spacer(),
            Text(
              '${score.round()}',
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: (score / 100).clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: const Color(0xFF1A2333),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  Widget _reasonChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF202C40)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFFB6C0D1),
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ==========================================================
  // CHART
  // ==========================================================

  Widget _buildChartCard() {
    final chartCandles = candles.length > 70
        ? candles.sublist(candles.length - 70)
        : candles;

    return _sectionCard(
      title: 'GRÁFICO',
      icon: Icons.show_chart_rounded,
      trailing: Text(
        selectedTimeframe.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFF7F8AA3),
          fontSize: 9,
          fontWeight: FontWeight.w900,
        ),
      ),
      child: chartCandles.length < 2
          ? SizedBox(
              height: 300,
              child: Center(
                child: isAnalyzing
                    ? const CircularProgressIndicator()
                    : const Text(
                        'Esperando velas...',
                        style: TextStyle(color: Color(0xFF69758D)),
                      ),
              ),
            )
          : SizedBox(
              height: 330,
              child: SfCartesianChart(
                backgroundColor: Colors.transparent,
                plotAreaBorderWidth: 0,
                margin: const EdgeInsets.all(4),
                primaryXAxis: DateTimeAxis(
                  majorGridLines: const MajorGridLines(width: 0),
                  axisLine: const AxisLine(
                    width: 0.5,
                    color: Color(0xFF263247),
                  ),
                  labelStyle: const TextStyle(
                    color: Color(0xFF59657A),
                    fontSize: 8,
                  ),
                ),
                primaryYAxis: NumericAxis(
                  majorGridLines: const MajorGridLines(
                    color: Color(0xFF151F30),
                    width: 0.6,
                  ),
                  axisLine: const AxisLine(
                    width: 0.5,
                    color: Color(0xFF263247),
                  ),
                  labelStyle: const TextStyle(
                    color: Color(0xFF59657A),
                    fontSize: 8,
                  ),
                ),
                zoomPanBehavior: ZoomPanBehavior(
                  enablePinching: true,
                  enablePanning: true,
                  zoomMode: ZoomMode.x,
                ),
                series: <CartesianSeries>[
                  CandleSeries<Candle, DateTime>(
                    dataSource: chartCandles,
                    xValueMapper: (Candle candle, _) => candle.time,
                    lowValueMapper: (Candle candle, _) => candle.low,
                    highValueMapper: (Candle candle, _) => candle.high,
                    openValueMapper: (Candle candle, _) => candle.open,
                    closeValueMapper: (Candle candle, _) => candle.close,
                    bullColor: const Color(0xFF31D391),
                    bearColor: const Color(0xFFFF5964),
                    enableSolidCandles: true,
                  ),
                ],
              ),
            ),
    );
  }

  // ==========================================================
  // ENGINE
  // ==========================================================

  Widget _buildEngineCard() {
    return _sectionCard(
      title: 'MOTOR DE SEÑALES',
      icon: Icons.settings_suggest_rounded,
      child: Column(
        children: [
          _engineRow(
            'Motor principal',
            'Price Action',
            Icons.candlestick_chart,
          ),
          _engineRow(
            'Estructura',
            'HH/HL · LH/LL · BOS · CHoCH',
            Icons.account_tree,
          ),
          _engineRow('Liquidez', 'Sweep · Retest', Icons.water_drop_outlined),
          _engineRow(
            'Triggers',
            'Engulfing · Rejection · Displacement',
            Icons.bolt_outlined,
          ),
          _engineRow(
            'Filtros',
            'Conflicto · Extensión · Soporte/Resistencia',
            Icons.filter_alt_outlined,
          ),
          _engineRow('Entrada', 'Ventana de 15 segundos', Icons.timer_outlined),
        ],
      ),
    );
  }

  Widget _engineRow(String title, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, size: 17, color: const Color(0xFF737EFF)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Color(0xFF7F8AA3),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xFFD6DBE6),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // ERROR
  // ==========================================================

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF2A1518),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFF6E2931)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFFF5964)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              errorMessage!,
              style: const TextStyle(
                color: Color(0xFFFF9DA5),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            onPressed: _manualAnalyze,
            icon: const Icon(Icons.refresh, size: 20),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // SECTION CARD
  // ==========================================================

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1321),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1A2538)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: const Color(0xFF737EFF)),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFFE7EAF0),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  // ==========================================================
  // PRICE FORMAT
  // ==========================================================

  String _formatPrice(double price) {
    if (price <= 0) {
      return '--';
    }

    if (selectedAsset.contains('JPY')) {
      return price.toStringAsFixed(3);
    }

    if (price >= 100) {
      return price.toStringAsFixed(2);
    }

    return price.toStringAsFixed(5);
  }
}
