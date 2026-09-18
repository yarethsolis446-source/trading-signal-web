import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

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
      debugShowCheckedModeBanner: false,
      title: 'Trading Signal Bot',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF090D14),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00C896),
          brightness: Brightness.dark,
        ),
      ),
      home: const HomePage(),
    );
  }
}

// ============================================================
// CONSTANTES
// ============================================================

const String biquoteBaseUrl = 'https://biquote.io/api';

const int entryWindowSeconds = 15;

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

// ============================================================
// UTILIDADES
// ============================================================

double _avg(List<double> values) {
  if (values.isEmpty) return 0;

  double total = 0;

  for (final value in values) {
    total += value;
  }

  return total / values.length;
}

double _highest(List<double> values) {
  if (values.isEmpty) return 0;

  double result = values.first;

  for (final value in values.skip(1)) {
    result = math.max(result, value).toDouble();
  }

  return result;
}

double _lowest(List<double> values) {
  if (values.isEmpty) return 0;

  double result = values.first;

  for (final value in values.skip(1)) {
    result = math.min(result, value).toDouble();
  }

  return result;
}

double _toDouble(dynamic value) {
  if (value is num) {
    return value.toDouble();
  }

  return double.tryParse(value?.toString() ?? '') ?? 0;
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

String formatPrice(double price) {
  if (price >= 100) {
    return price.toStringAsFixed(3);
  }

  if (price >= 10) {
    return price.toStringAsFixed(4);
  }

  return price.toStringAsFixed(5);
}

String formatTime(DateTime dateTime) {
  return DateFormat('HH:mm:ss').format(dateTime.toLocal());
}

// ============================================================
// CONFIGURACIÓN POR TEMPORALIDAD
// ============================================================

class TimeframeConfig {
  final String timeframe;

  final int candlesToRequest;
  final int analysisCandles;
  final int supportResistanceLookback;
  final int structureLookback;
  final int bosLookback;

  final int emaFast;
  final int emaSlow;

  final int atrPeriod;
  final int momentumPeriod;

  final double normalThreshold;
  final double highVolThreshold;
  final double lowVolThreshold;

  final double minimumDifference;

  final double dojiBodyRatio;
  final double overextensionAtr;
  final double breakoutAtrTolerance;
  final double retestAtrTolerance;

  final int cooldownSeconds;

  const TimeframeConfig({
    required this.timeframe,
    required this.candlesToRequest,
    required this.analysisCandles,
    required this.supportResistanceLookback,
    required this.structureLookback,
    required this.bosLookback,
    required this.emaFast,
    required this.emaSlow,
    required this.atrPeriod,
    required this.momentumPeriod,
    required this.normalThreshold,
    required this.highVolThreshold,
    required this.lowVolThreshold,
    required this.minimumDifference,
    required this.dojiBodyRatio,
    required this.overextensionAtr,
    required this.breakoutAtrTolerance,
    required this.retestAtrTolerance,
    required this.cooldownSeconds,
  });

  static TimeframeConfig forTimeframe(String timeframe) {
    switch (timeframe) {
      // --------------------------------------------------------
      // 1 MINUTO
      // --------------------------------------------------------
      case '1m':
        return const TimeframeConfig(
          timeframe: '1m',
          candlesToRequest: 220,
          analysisCandles: 140,
          supportResistanceLookback: 35,
          structureLookback: 18,
          bosLookback: 9,
          emaFast: 7,
          emaSlow: 18,
          atrPeriod: 14,
          momentumPeriod: 4,
          normalThreshold: 25,
          highVolThreshold: 29,
          lowVolThreshold: 23,
          minimumDifference: 4,
          dojiBodyRatio: 0.16,
          overextensionAtr: 2.20,
          breakoutAtrTolerance: 0.18,
          retestAtrTolerance: 0.28,
          cooldownSeconds: 20,
        );

      // --------------------------------------------------------
      // 5 MINUTOS
      // --------------------------------------------------------
      case '5m':
        return const TimeframeConfig(
          timeframe: '5m',
          candlesToRequest: 220,
          analysisCandles: 140,
          supportResistanceLookback: 40,
          structureLookback: 25,
          bosLookback: 12,
          emaFast: 9,
          emaSlow: 21,
          atrPeriod: 14,
          momentumPeriod: 5,
          normalThreshold: 28,
          highVolThreshold: 32,
          lowVolThreshold: 26,
          minimumDifference: 5,
          dojiBodyRatio: 0.18,
          overextensionAtr: 2.25,
          breakoutAtrTolerance: 0.15,
          retestAtrTolerance: 0.25,
          cooldownSeconds: 30,
        );

      // --------------------------------------------------------
      // 15 MINUTOS
      // --------------------------------------------------------
      case '15m':
        return const TimeframeConfig(
          timeframe: '15m',
          candlesToRequest: 240,
          analysisCandles: 160,
          supportResistanceLookback: 50,
          structureLookback: 32,
          bosLookback: 15,
          emaFast: 10,
          emaSlow: 24,
          atrPeriod: 14,
          momentumPeriod: 6,
          normalThreshold: 31,
          highVolThreshold: 35,
          lowVolThreshold: 29,
          minimumDifference: 6,
          dojiBodyRatio: 0.20,
          overextensionAtr: 2.40,
          breakoutAtrTolerance: 0.13,
          retestAtrTolerance: 0.23,
          cooldownSeconds: 45,
        );

      // --------------------------------------------------------
      // 30 MINUTOS
      // --------------------------------------------------------
      case '30m':
        return const TimeframeConfig(
          timeframe: '30m',
          candlesToRequest: 260,
          analysisCandles: 180,
          supportResistanceLookback: 60,
          structureLookback: 40,
          bosLookback: 18,
          emaFast: 12,
          emaSlow: 26,
          atrPeriod: 14,
          momentumPeriod: 7,
          normalThreshold: 34,
          highVolThreshold: 38,
          lowVolThreshold: 32,
          minimumDifference: 7,
          dojiBodyRatio: 0.22,
          overextensionAtr: 2.55,
          breakoutAtrTolerance: 0.12,
          retestAtrTolerance: 0.22,
          cooldownSeconds: 60,
        );

      // --------------------------------------------------------
      // 1 HORA
      // --------------------------------------------------------
      case '1h':
        return const TimeframeConfig(
          timeframe: '1h',
          candlesToRequest: 300,
          analysisCandles: 200,
          supportResistanceLookback: 70,
          structureLookback: 50,
          bosLookback: 22,
          emaFast: 14,
          emaSlow: 30,
          atrPeriod: 14,
          momentumPeriod: 8,
          normalThreshold: 37,
          highVolThreshold: 41,
          lowVolThreshold: 35,
          minimumDifference: 8,
          dojiBodyRatio: 0.24,
          overextensionAtr: 2.70,
          breakoutAtrTolerance: 0.11,
          retestAtrTolerance: 0.20,
          cooldownSeconds: 90,
        );

      default:
        return TimeframeConfig.forTimeframe('5m');
    }
  }
}

// ============================================================
// MODELOS
// ============================================================

class Candle {
  final DateTime time;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;

  const Candle({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    this.volume = 0,
  });

  bool get bullish => close > open;

  bool get bearish => close < open;

  double get range => high - low;

  double get body => (close - open).abs();

  double get upperWick {
    return high - math.max(open, close).toDouble();
  }

  double get lowerWick {
    return math.min(open, close).toDouble() - low;
  }
}

class LiveTick {
  final double price;
  final double bid;
  final double ask;
  final DateTime time;

  const LiveTick({
    required this.price,
    this.bid = 0,
    this.ask = 0,
    required this.time,
  });

  double get spread {
    if (bid <= 0 || ask <= 0) return 0;
    return (ask - bid).abs();
  }
}

class SignalResult {
  final String direction;
  final String arrow;
  final String strength;
  final int score;
  final int maxScore;

  final String setup;
  final String trend;
  final String rsi;
  final String macd;
  final String candle;

  final List<String> reasons;
  final List<String> confirmations;
  final List<String> filters;

  final double support;
  final double resistance;

  final double emaFast;
  final double emaSlow;
  final double atr;
  final double momentum;

  final bool nearSupport;
  final bool nearResistance;

  final double livePrice;

  final String timeframe;

  const SignalResult({
    required this.direction,
    required this.arrow,
    required this.strength,
    required this.score,
    required this.maxScore,
    required this.setup,
    required this.trend,
    required this.rsi,
    required this.macd,
    required this.candle,
    required this.reasons,
    required this.confirmations,
    required this.filters,
    required this.support,
    required this.resistance,
    required this.emaFast,
    required this.emaSlow,
    required this.atr,
    required this.momentum,
    required this.nearSupport,
    required this.nearResistance,
    required this.livePrice,
    required this.timeframe,
  });
}

// ============================================================
// INDICADORES
// ============================================================

List<double> _ema(List<double> values, int period) {
  if (values.isEmpty) return [];

  final result = List<double>.filled(values.length, 0);

  if (values.length < period) {
    double sum = 0;

    for (int i = 0; i < values.length; i++) {
      sum += values[i];
      result[i] = sum / (i + 1);
    }

    return result;
  }

  double sum = 0;

  for (int i = 0; i < period; i++) {
    sum += values[i];
  }

  result[period - 1] = sum / period;

  final multiplier = 2 / (period + 1);

  for (int i = period; i < values.length; i++) {
    result[i] = ((values[i] - result[i - 1]) * multiplier) + result[i - 1];
  }

  for (int i = 0; i < period - 1; i++) {
    result[i] = values[i];
  }

  return result;
}

List<double> _atr(List<Candle> candles, int period) {
  if (candles.isEmpty) return [];

  final tr = List<double>.filled(candles.length, 0);

  for (int i = 0; i < candles.length; i++) {
    if (i == 0) {
      tr[i] = candles[i].high - candles[i].low;
      continue;
    }

    final current = candles[i];

    final a = current.high - current.low;

    final b = (current.high - candles[i - 1].close).abs();

    final c = (current.low - candles[i - 1].close).abs();

    tr[i] = math.max(a, math.max(b, c)).toDouble();
  }

  final result = List<double>.filled(candles.length, 0);

  double rolling = 0;

  for (int i = 0; i < candles.length; i++) {
    rolling += tr[i];

    if (i >= period) {
      rolling -= tr[i - period];
    }

    final count = math.min(i + 1, period).toInt();

    result[i] = rolling / count;
  }

  return result;
}

List<double> _momentum(List<double> closes, int period) {
  final result = List<double>.filled(closes.length, 0);

  for (int i = 0; i < closes.length; i++) {
    if (i < period) {
      result[i] = 0;
    } else {
      result[i] = closes[i] - closes[i - period];
    }
  }

  return result;
}

// ============================================================
// BIQUOTE REST
// ============================================================

class BiquoteService {
  Future<List<Candle>> getCandles({
    required String symbol,
    required String timeframe,
    required int limit,
  }) async {
    final normalized = normalizeSymbol(symbol);

    final uri = Uri.parse(
      '$biquoteBaseUrl/$normalized/ohlc'
      '?interval=$timeframe'
      '&limit=$limit',
    );

    final response = await http
        .get(uri, headers: const {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 12));

    if (response.statusCode != 200) {
      throw Exception('Biquote HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);

    dynamic rawBars;

    if (decoded is Map<String, dynamic>) {
      rawBars = decoded['bars'];

      if (rawBars == null) {
        rawBars = decoded['data'];
      }

      if (rawBars == null) {
        rawBars = decoded['candles'];
      }
    } else if (decoded is List) {
      rawBars = decoded;
    }

    if (rawBars is! List) {
      throw Exception('Biquote no devolvió velas.');
    }

    final candles = <Candle>[];

    for (final item in rawBars) {
      if (item is! Map) continue;

      final isOpen = item['isOpen'];

      if (isOpen == true) {
        continue;
      }

      final open = _toDouble(item['open']);
      final high = _toDouble(item['high']);
      final low = _toDouble(item['low']);
      final close = _toDouble(item['close']);

      if (open <= 0 || high <= 0 || low <= 0 || close <= 0) {
        continue;
      }

      dynamic rawTime =
          item['openTime'] ?? item['time'] ?? item['timestamp'] ?? item['date'];

      DateTime? time;

      if (rawTime is num) {
        final value = rawTime.toInt();

        if (value > 100000000000) {
          time = DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
        } else {
          time = DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
        }
      } else if (rawTime != null) {
        time = DateTime.tryParse(rawTime.toString());
      }

      time ??= DateTime.now().toUtc();

      candles.add(
        Candle(
          time: time,
          open: open,
          high: high,
          low: low,
          close: close,
          volume: _toDouble(item['volume'] ?? item['tickVolume']),
        ),
      );
    }

    candles.sort((a, b) => a.time.compareTo(b.time));

    if (candles.length > limit) {
      return candles.sublist(candles.length - limit);
    }

    return candles;
  }

  Future<LiveTick?> getLatestTick({required String symbol}) async {
    final normalized = normalizeSymbol(symbol);

    final uri = Uri.parse('$biquoteBaseUrl/$normalized');

    try {
      final response = await http
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 7));

      if (response.statusCode != 200) {
        return null;
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map) {
        return null;
      }

      double price = _toDouble(
        decoded['mid'] ??
            decoded['price'] ??
            decoded['last'] ??
            decoded['close'],
      );

      final bid = _toDouble(decoded['bid']);

      final ask = _toDouble(decoded['ask']);

      if (price <= 0 && bid > 0 && ask > 0) {
        price = (bid + ask) / 2;
      }

      if (price <= 0) {
        return null;
      }

      dynamic rawTime =
          decoded['time'] ?? decoded['timestamp'] ?? decoded['timestampMs'];

      DateTime time = DateTime.now().toUtc();

      if (rawTime is num) {
        final value = rawTime.toInt();

        if (value > 100000000000) {
          time = DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
        } else {
          time = DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
        }
      }

      return LiveTick(price: price, bid: bid, ask: ask, time: time);
    } catch (_) {
      return null;
    }
  }
}

// ============================================================
// REALTIME
// ============================================================

class BiquoteRealtime {
  WebSocketChannel? _channel;

  StreamSubscription? _subscription;

  final StreamController<LiveTick> _controller =
      StreamController<LiveTick>.broadcast();

  Stream<LiveTick> get stream => _controller.stream;

  bool get isConnected => _channel != null;

  Future<void> connect({required String symbol}) async {
    await disconnect();

    try {
      final channel = WebSocketChannel.connect(
        Uri.parse('wss://biquote.io/hubs/tick'),
      );

      _channel = channel;

      _subscription = channel.stream.listen(
        (message) {
          _parseMessage(message);
        },
        onError: (_) {
          _channel = null;
        },
        onDone: () {
          _channel = null;
        },
        cancelOnError: false,
      );

      final handshake = jsonEncode({'protocol': 'json', 'version': 1});

      channel.sink.add('$handshake\u001e');

      final invocation = jsonEncode({
        'type': 1,
        'target': 'Subscribe',
        'arguments': [normalizeSymbol(symbol)],
      });

      channel.sink.add('$invocation\u001e');
    } catch (_) {
      _channel = null;
    }
  }

  void _parseMessage(dynamic message) {
    try {
      String raw = message.toString();

      raw = raw.replaceAll('\u001e', '');

      if (raw.isEmpty) return;

      final decoded = jsonDecode(raw);

      if (decoded is! Map) return;

      final arguments = decoded['arguments'];

      dynamic data = arguments;

      if (arguments is List && arguments.isNotEmpty) {
        data = arguments.first;
      }

      if (data is List && data.isNotEmpty) {
        data = data.first;
      }

      if (data is! Map) return;

      final price = _toDouble(
        data['mid'] ?? data['price'] ?? data['last'] ?? data['close'],
      );

      final bid = _toDouble(data['bid']);

      final ask = _toDouble(data['ask']);

      if (price <= 0 && bid <= 0 && ask <= 0) {
        return;
      }

      final finalPrice = price > 0
          ? price
          : (bid > 0 && ask > 0)
          ? (bid + ask) / 2
          : bid > 0
          ? bid
          : ask;

      if (finalPrice <= 0) return;

      _controller.add(
        LiveTick(
          price: finalPrice,
          bid: bid,
          ask: ask,
          time: DateTime.now().toUtc(),
        ),
      );
    } catch (_) {}
  }

  Future<void> disconnect() async {
    try {
      await _subscription?.cancel();
    } catch (_) {}

    try {
      await _channel?.sink.close();
    } catch (_) {}

    _subscription = null;
    _channel = null;
  }

  Future<void> dispose() async {
    await disconnect();
    await _controller.close();
  }
}

// ============================================================
// PRICE ACTION ENGINE MULTI-TIMEFRAME
// ============================================================

class PriceActionEngine {
  SignalResult analyze({
    required List<Candle> candles,
    required String timeframe,
    LiveTick? liveTick,
  }) {
    final config = TimeframeConfig.forTimeframe(timeframe);

    if (candles.length < 30) {
      return SignalResult(
        direction: 'WAIT',
        arrow: '⏸',
        strength: 'WEAK',
        score: 0,
        maxScore: 130,
        setup: 'INSUFFICIENT DATA',
        trend: 'NEUTRAL',
        rsi: 'N/A',
        macd: 'N/A',
        candle: 'N/A',
        reasons: const ['Se necesitan al menos 30 velas cerradas.'],
        confirmations: const [],
        filters: const [],
        support: 0,
        resistance: 0,
        emaFast: 0,
        emaSlow: 0,
        atr: 0,
        momentum: 0,
        nearSupport: false,
        nearResistance: false,
        livePrice: liveTick?.price ?? 0,
        timeframe: timeframe,
      );
    }

    final selected = candles.length > config.analysisCandles
        ? candles.sublist(candles.length - config.analysisCandles)
        : candles;

    final closes = selected.map((c) => c.close).toList();

    final emaFastList = _ema(closes, config.emaFast);

    final emaSlowList = _ema(closes, config.emaSlow);

    final atrList = _atr(selected, config.atrPeriod);

    final momentumList = _momentum(closes, config.momentumPeriod);

    final lastIndex = selected.length - 1;

    final current = selected[lastIndex];

    final emaFast = emaFastList[lastIndex];

    final emaSlow = emaSlowList[lastIndex];

    final atr = atrList[lastIndex];

    final momentum = momentumList[lastIndex];

    final srStart = math
        .max(0, selected.length - config.supportResistanceLookback)
        .toInt();

    final srCandles = selected.sublist(srStart);

    final support = _lowest(srCandles.map((c) => c.low).toList());

    final resistance = _highest(srCandles.map((c) => c.high).toList());

    final structureStart = math
        .max(0, selected.length - config.structureLookback)
        .toInt();

    final structureCandles = selected.sublist(structureStart);

    final previousStructureStart = math
        .max(0, structureCandles.length - 12)
        .toInt();

    final previousStructure = structureCandles.sublist(previousStructureStart);

    final recentHigh = _highest(previousStructure.map((c) => c.high).toList());

    final recentLow = _lowest(previousStructure.map((c) => c.low).toList());

    // ========================================================
    // ESTRUCTURA
    // ========================================================

    final highs = structureCandles.map((c) => c.high).toList();

    final lows = structureCandles.map((c) => c.low).toList();

    bool bullishStructure = false;

    bool bearishStructure = false;

    if (highs.length >= 8) {
      final mid = highs.length ~/ 2;

      final firstHigh = _highest(highs.sublist(0, mid));

      final secondHigh = _highest(highs.sublist(mid));

      final firstLow = _lowest(lows.sublist(0, mid));

      final secondLow = _lowest(lows.sublist(mid));

      bullishStructure = secondHigh > firstHigh && secondLow > firstLow;

      bearishStructure = secondHigh < firstHigh && secondLow < firstLow;
    }

    // ========================================================
    // BOS
    // ========================================================

    final bosStart = math.max(0, selected.length - config.bosLookback).toInt();

    final bosCandles = selected.sublist(bosStart);

    final bosPreviousCount = math.max(1, bosCandles.length - 3).toInt();

    final bosPrevious = bosCandles.sublist(0, bosPreviousCount);

    final bosHigh = _highest(bosPrevious.map((c) => c.high).toList());

    final bosLow = _lowest(bosPrevious.map((c) => c.low).toList());

    final bullishBos = current.close > bosHigh;

    final bearishBos = current.close < bosLow;

    // ========================================================
    // CHoCH
    // ========================================================

    final chochBullish = bullishStructure && current.close > recentHigh;

    final chochBearish = bearishStructure && current.close < recentLow;

    // ========================================================
    // BREAKOUT
    // ========================================================

    final breakoutTolerance = atr * config.breakoutAtrTolerance;

    final bullishBreakout =
        current.close >= resistance - breakoutTolerance &&
        current.close > current.open;

    final bearishBreakout =
        current.close <= support + breakoutTolerance &&
        current.close < current.open;

    // ========================================================
    // RETEST
    // ========================================================

    bool bullishRetest = false;

    bool bearishRetest = false;

    if (selected.length >= 4) {
      final previous = selected[lastIndex - 1];

      bullishRetest =
          previous.low <= resistance + (atr * config.retestAtrTolerance) &&
          current.close > resistance &&
          current.close > current.open;

      bearishRetest =
          previous.high >= support - (atr * config.retestAtrTolerance) &&
          current.close < support &&
          current.close < current.open;
    }

    // ========================================================
    // REJECTION
    // ========================================================

    final bullishRejection =
        current.lowerWick > current.body * 1.25 && current.close > current.open;

    final bearishRejection =
        current.upperWick > current.body * 1.25 && current.close < current.open;

    // ========================================================
    // ENGULFING
    // ========================================================

    bool bullishEngulfing = false;

    bool bearishEngulfing = false;

    if (selected.length >= 2) {
      final previous = selected[lastIndex - 1];

      bullishEngulfing =
          previous.bearish &&
          current.bullish &&
          current.open <= previous.close &&
          current.close >= previous.open;

      bearishEngulfing =
          previous.bullish &&
          current.bearish &&
          current.open >= previous.close &&
          current.close <= previous.open;
    }

    // ========================================================
    // MOMENTUM
    // ========================================================

    final bullishMomentum = momentum > atr * 0.12;

    final bearishMomentum = momentum < -atr * 0.12;

    // ========================================================
    // EMA TREND
    // ========================================================

    final bullishTrend = emaFast > emaSlow && current.close >= emaFast;

    final bearishTrend = emaFast < emaSlow && current.close <= emaFast;

    // ========================================================
    // LIVE PRICE
    // ========================================================

    bool liveBullish = false;

    bool liveBearish = false;

    if (liveTick != null && liveTick.price > 0) {
      liveBullish = liveTick.price > current.close + (atr * 0.02);

      liveBearish = liveTick.price < current.close - (atr * 0.02);
    }

    // ========================================================
    // CANDLE QUALITY
    // ========================================================

    final candleRange = math.max(current.range, 0.00000001).toDouble();

    final bodyRatio = current.body / candleRange;

    final isDoji = bodyRatio < config.dojiBodyRatio;

    final candleBullish = current.bullish && bodyRatio >= config.dojiBodyRatio;

    final candleBearish = current.bearish && bodyRatio >= config.dojiBodyRatio;

    // ========================================================
    // OVEREXTENSION
    // ========================================================

    final distanceFromFast = (current.close - emaFast).abs();

    final overextended =
        atr > 0 && distanceFromFast > atr * config.overextensionAtr;

    // ========================================================
    // SUPPORT / RESISTANCE
    // ========================================================

    final srTolerance = math.max(atr * 0.25, current.close * 0.0005).toDouble();

    final nearSupport = (current.close - support).abs() <= srTolerance;

    final nearResistance = (resistance - current.close).abs() <= srTolerance;

    // ========================================================
    // VOLATILIDAD
    // ========================================================

    final recentAtrStart = math.max(0, atrList.length - 20).toInt();

    final recentAtr = atrList.sublist(recentAtrStart);

    final averageAtr = _avg(recentAtr);

    double threshold;

    if (atr > averageAtr * 1.35) {
      threshold = config.highVolThreshold;
    } else if (atr < averageAtr * 0.70) {
      threshold = config.lowVolThreshold;
    } else {
      threshold = config.normalThreshold;
    }

    // ========================================================
    // SCORE
    // ========================================================

    int bullishScore = 0;

    int bearishScore = 0;

    final confirmations = <String>[];

    final filters = <String>[];

    final reasons = <String>[];

    // Structure
    if (bullishStructure) {
      bullishScore += 16;
      confirmations.add('Estructura HH/HL');
    }

    if (bearishStructure) {
      bearishScore += 16;
      confirmations.add('Estructura LH/LL');
    }

    // EMA
    if (bullishTrend) {
      bullishScore += 6;
      confirmations.add('EMA ${config.emaFast} > EMA ${config.emaSlow}');
    }

    if (bearishTrend) {
      bearishScore += 6;
      confirmations.add('EMA ${config.emaFast} < EMA ${config.emaSlow}');
    }

    // BOS
    if (bullishBos) {
      bullishScore += 18;
      confirmations.add('BOS alcista');
    }

    if (bearishBos) {
      bearishScore += 18;
      confirmations.add('BOS bajista');
    }

    // CHoCH
    if (chochBullish) {
      bullishScore += 14;
      confirmations.add('CHoCH alcista');
    }

    if (chochBearish) {
      bearishScore += 14;
      confirmations.add('CHoCH bajista');
    }

    // Breakout
    if (bullishBreakout) {
      bullishScore += 14;
      confirmations.add('Breakout alcista');
    }

    if (bearishBreakout) {
      bearishScore += 14;
      confirmations.add('Breakout bajista');
    }

    // Retest
    if (bullishRetest) {
      bullishScore += 16;
      confirmations.add('Retest alcista');
    }

    if (bearishRetest) {
      bearishScore += 16;
      confirmations.add('Retest bajista');
    }

    // Rejection
    if (bullishRejection) {
      bullishScore += 10;
      confirmations.add('Rechazo de mínimos');
    }

    if (bearishRejection) {
      bearishScore += 10;
      confirmations.add('Rechazo de máximos');
    }

    // Engulfing
    if (bullishEngulfing) {
      bullishScore += 10;
      confirmations.add('Engulfing alcista');
    }

    if (bearishEngulfing) {
      bearishScore += 10;
      confirmations.add('Engulfing bajista');
    }

    // Momentum
    if (bullishMomentum) {
      bullishScore += 8;
      confirmations.add('Momentum alcista');
    }

    if (bearishMomentum) {
      bearishScore += 8;
      confirmations.add('Momentum bajista');
    }

    // Live price
    if (liveBullish) {
      bullishScore += 5;
      confirmations.add('Precio en vivo confirma ALZA');
    }

    if (liveBearish) {
      bearishScore += 5;
      confirmations.add('Precio en vivo confirma BAJA');
    }

    // Candle
    if (candleBullish) {
      bullishScore += 4;
      confirmations.add('Vela alcista válida');
    }

    if (candleBearish) {
      bearishScore += 4;
      confirmations.add('Vela bajista válida');
    }

    // ========================================================
    // FILTROS
    // ========================================================

    if (isDoji) {
      filters.add('Vela demasiado indecisa');
    }

    if (overextended) {
      filters.add('Precio sobreextendido');
    }

    if (nearSupport) {
      filters.add('Cerca de soporte');
    }

    if (nearResistance) {
      filters.add('Cerca de resistencia');
    }

    if (atr <= 0) {
      filters.add('Volatilidad insuficiente');
    }

    // ========================================================
    // CONFLICTO DIRECCIONAL
    // ========================================================

    final difference = (bullishScore - bearishScore).abs();

    final contradictory =
        bullishScore > 0 &&
        bearishScore > 0 &&
        difference < config.minimumDifference + 4;

    // ========================================================
    // DIRECCIÓN
    // ========================================================

    String direction = 'WAIT';

    int score = math.max(bullishScore, bearishScore).toInt();

    if (bullishScore >= threshold &&
        bullishScore > bearishScore &&
        difference >= config.minimumDifference &&
        !contradictory &&
        !isDoji &&
        !overextended &&
        candleBullish) {
      direction = 'UP';
    } else if (bearishScore >= threshold &&
        bearishScore > bullishScore &&
        difference >= config.minimumDifference &&
        !contradictory &&
        !isDoji &&
        !overextended &&
        candleBearish) {
      direction = 'DOWN';
    }

    // ========================================================
    // RAZONES
    // ========================================================

    if (direction == 'UP') {
      reasons.add('La presión compradora supera a la vendedora.');

      if (bullishStructure) {
        reasons.add('La estructura favorece máximos y mínimos crecientes.');
      }

      if (bullishBos) {
        reasons.add('Se detectó ruptura estructural alcista.');
      }

      if (bullishRetest) {
        reasons.add('El precio confirmó un retest alcista.');
      }

      if (bullishMomentum) {
        reasons.add('El momentum acompaña el movimiento.');
      }
    } else if (direction == 'DOWN') {
      reasons.add('La presión vendedora supera a la compradora.');

      if (bearishStructure) {
        reasons.add('La estructura favorece máximos y mínimos decrecientes.');
      }

      if (bearishBos) {
        reasons.add('Se detectó ruptura estructural bajista.');
      }

      if (bearishRetest) {
        reasons.add('El precio confirmó un retest bajista.');
      }

      if (bearishMomentum) {
        reasons.add('El momentum acompaña el movimiento.');
      }
    } else {
      if (isDoji) {
        reasons.add('La vela actual tiene poca convicción.');
      }

      if (overextended) {
        reasons.add('El precio está demasiado alejado de la EMA.');
      }

      if (contradictory) {
        reasons.add(
          'Las evidencias alcistas y bajistas están demasiado equilibradas.',
        );
      }

      if (score < threshold) {
        reasons.add(
          'La puntuación no alcanza el umbral de ${threshold.toStringAsFixed(0)} para $timeframe.',
        );
      }

      if (reasons.isEmpty) {
        reasons.add('No existe suficiente confirmación direccional.');
      }
    }

    // ========================================================
    // SETUP
    // ========================================================

    final setupParts = <String>[];

    if (bullishBos || bearishBos) {
      setupParts.add('BOS');
    }

    if (bullishRetest || bearishRetest) {
      setupParts.add('RETEST');
    }

    if (bullishBreakout || bearishBreakout) {
      setupParts.add('BREAKOUT');
    }

    if (chochBullish || chochBearish) {
      setupParts.add('CHoCH');
    }

    if (bullishEngulfing || bearishEngulfing) {
      setupParts.add('ENGULFING');
    }

    if (bullishRejection || bearishRejection) {
      setupParts.add('REJECTION');
    }

    if (setupParts.isEmpty && (bullishStructure || bearishStructure)) {
      setupParts.add('STRUCTURE');
    }

    if (setupParts.isEmpty) {
      setupParts.add('EARLY PRICE ACTION');
    }

    final setup = setupParts.join(' + ');

    // ========================================================
    // STRENGTH
    // ========================================================

    String strength;

    if (direction == 'WAIT') {
      strength = 'FILTERED';
    } else if (score >= 75) {
      strength = 'STRONG';
    } else if (score >= 55) {
      strength = 'GOOD';
    } else if (score >= 40) {
      strength = 'MODERATE';
    } else {
      strength = 'EARLY';
    }

    // ========================================================
    // TEXTOS
    // ========================================================

    String trend;

    if (bullishTrend) {
      trend = 'ALCISTA';
    } else if (bearishTrend) {
      trend = 'BAJISTA';
    } else {
      trend = 'NEUTRAL';
    }

    String candleText;

    if (candleBullish) {
      candleText = 'ALCISTA';
    } else if (candleBearish) {
      candleText = 'BAJISTA';
    } else {
      candleText = 'INDECISA';
    }

    String momentumText;

    if (bullishMomentum) {
      momentumText = 'ALCISTA';
    } else if (bearishMomentum) {
      momentumText = 'BAJISTA';
    } else {
      momentumText = 'NEUTRO';
    }

    return SignalResult(
      direction: direction,
      arrow: direction == 'UP'
          ? '↑'
          : direction == 'DOWN'
          ? '↓'
          : '⏸',
      strength: strength,
      score: score,
      maxScore: 130,
      setup: setup,
      trend: trend,
      rsi: 'N/A',
      macd: momentumText,
      candle: candleText,
      reasons: reasons,
      confirmations: confirmations,
      filters: filters,
      support: support,
      resistance: resistance,
      emaFast: emaFast,
      emaSlow: emaSlow,
      atr: atr,
      momentum: momentum,
      nearSupport: nearSupport,
      nearResistance: nearResistance,
      livePrice: liveTick?.price ?? current.close,
      timeframe: timeframe,
    );
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

  final BiquoteRealtime _realtime = BiquoteRealtime();

  final PriceActionEngine _engine = PriceActionEngine();

  Timer? _refreshTimer;

  Timer? _countdownTimer;

  StreamSubscription? _tickSubscription;

  String selectedPair = supportedPairs.first;

  String selectedTimeframe = '5m';

  List<Candle> candles = [];

  LiveTick? liveTick;

  SignalResult? signal;

  bool loading = false;

  bool connected = false;

  String? error;

  DateTime? _entryExpiresAt;

  int entrySecondsRemaining = 0;

  int secondsToNextCandle = 0;

  String? _lastSignalKey;

  DateTime? _lastAnalysisTime;

  @override
  void initState() {
    super.initState();

    _loadData();

    _refreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      _refreshCandles();
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateTimers();
    });

    _setupRealtime();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();

    _countdownTimer?.cancel();

    _tickSubscription?.cancel();

    _realtime.dispose();

    super.dispose();
  }

  // ==========================================================
  // CARGA
  // ==========================================================

  Future<void> _loadData() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final config = TimeframeConfig.forTimeframe(selectedTimeframe);

      final result = await _service.getCandles(
        symbol: selectedPair,
        timeframe: selectedTimeframe,
        limit: config.candlesToRequest,
      );

      if (!mounted) return;

      if (result.length < 30) {
        throw Exception(
          'Biquote devolvió ${result.length} velas cerradas. Se necesitan al menos 30.',
        );
      }

      setState(() {
        candles = result;
        loading = false;
      });

      await _setupRealtime();

      await _analyzeNow();

      await _loadLatestTick();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loading = false;
        error = e.toString();
      });
    }
  }

  Future<void> _refreshCandles() async {
    if (loading) return;

    try {
      final config = TimeframeConfig.forTimeframe(selectedTimeframe);

      final result = await _service.getCandles(
        symbol: selectedPair,
        timeframe: selectedTimeframe,
        limit: config.candlesToRequest,
      );

      if (!mounted) return;

      if (result.length < 30) {
        return;
      }

      setState(() {
        candles = result;
      });

      await _analyzeNow();

      await _loadLatestTick();
    } catch (_) {}
  }

  Future<void> _loadLatestTick() async {
    final tick = await _service.getLatestTick(symbol: selectedPair);

    if (!mounted) return;

    if (tick != null) {
      setState(() {
        liveTick = tick;
        connected = true;
      });

      _analyzeFromLiveTick();
    }
  }

  // ==========================================================
  // REALTIME
  // ==========================================================

  Future<void> _setupRealtime() async {
    await _tickSubscription?.cancel();

    _tickSubscription = _realtime.stream.listen((tick) {
      if (!mounted) return;

      setState(() {
        liveTick = tick;
        connected = true;
      });

      _analyzeFromLiveTick();
    });

    await _realtime.connect(symbol: selectedPair);

    final fallback = await _service.getLatestTick(symbol: selectedPair);

    if (!mounted) return;

    if (fallback != null) {
      setState(() {
        liveTick = fallback;
        connected = true;
      });

      _analyzeFromLiveTick();
    }
  }

  // ==========================================================
  // ANALISIS
  // ==========================================================

  Future<void> _analyzeNow() async {
    if (candles.length < 30) return;

    final result = _engine.analyze(
      candles: candles,
      timeframe: selectedTimeframe,
      liveTick: liveTick,
    );

    if (!mounted) return;

    setState(() {
      signal = result;
      _lastAnalysisTime = DateTime.now();
    });

    _handleSignal(result);
  }

  void _analyzeFromLiveTick() {
    if (candles.length < 30) return;

    final result = _engine.analyze(
      candles: candles,
      timeframe: selectedTimeframe,
      liveTick: liveTick,
    );

    if (!mounted) return;

    setState(() {
      signal = result;
    });

    _handleSignal(result);
  }

  // ==========================================================
  // SEÑALES
  // ==========================================================

  void _handleSignal(SignalResult result) {
    if (result.direction == 'WAIT') {
      return;
    }

    final latestCandle = candles.isNotEmpty
        ? candles.last.time.millisecondsSinceEpoch
        : 0;

    final key =
        '${selectedPair}_${selectedTimeframe}_${latestCandle}_${result.direction}';

    if (_lastSignalKey == key) {
      return;
    }

    _lastSignalKey = key;

    _entryExpiresAt = DateTime.now().add(
      const Duration(seconds: entryWindowSeconds),
    );

    entrySecondsRemaining = entryWindowSeconds;
  }

  // ==========================================================
  // TEMPORIZADORES
  // ==========================================================

  void _updateTimers() {
    if (!mounted) return;

    int entry = 0;

    if (_entryExpiresAt != null) {
      final difference = _entryExpiresAt!.difference(DateTime.now()).inSeconds;

      entry = math.max(0, difference).toInt();

      if (entry == 0) {
        _entryExpiresAt = null;
      }
    }

    int nextCandle = 0;

    if (candles.isNotEmpty) {
      final timeframe = timeframeSeconds(selectedTimeframe);

      final last = candles.last.time.toLocal();

      final next = last.add(Duration(seconds: timeframe));

      nextCandle = math
          .max(0, next.difference(DateTime.now()).inSeconds)
          .toInt();

      if (nextCandle > timeframe) {
        nextCandle = timeframe;
      }
    }

    setState(() {
      entrySecondsRemaining = entry;
      secondsToNextCandle = nextCandle;
    });
  }

  // ==========================================================
  // CAMBIAR PAR
  // ==========================================================

  Future<void> _changePair(String value) async {
    if (value == selectedPair) return;

    setState(() {
      selectedPair = value;
      candles = [];
      signal = null;
      liveTick = null;
      connected = false;
      error = null;
      _lastSignalKey = null;
      _entryExpiresAt = null;
      entrySecondsRemaining = 0;
    });

    await _loadData();
  }

  // ==========================================================
  // CAMBIAR TIMEFRAME
  // ==========================================================

  Future<void> _changeTimeframe(String value) async {
    if (value == selectedTimeframe) return;

    setState(() {
      selectedTimeframe = value;
      candles = [];
      signal = null;
      liveTick = null;
      connected = false;
      error = null;
      _lastSignalKey = null;
      _entryExpiresAt = null;
      entrySecondsRemaining = 0;
    });

    await _loadData();
  }

  // ==========================================================
  // UI
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: const Row(
          children: [
            Icon(Icons.candlestick_chart, size: 27),
            SizedBox(width: 10),
            Text(
              'Trading Signal Bot',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: connected
                      ? const Color(0xFF00C896).withOpacity(.14)
                      : Colors.red.withOpacity(.14),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: connected ? const Color(0xFF00C896) : Colors.red,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      connected ? 'ONLINE' : 'OFFLINE',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildConnectionCard(),

                const SizedBox(height: 14),

                _buildSelectors(),

                const SizedBox(height: 14),

                _buildAnalyzeButton(),

                if (loading) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                ],

                if (error != null) ...[
                  const SizedBox(height: 16),
                  _buildErrorCard(),
                ],

                if (signal != null) ...[
                  const SizedBox(height: 16),
                  _buildSignalCard(),

                  const SizedBox(height: 12),

                  _buildEntryTimer(),

                  const SizedBox(height: 12),

                  _buildMarketInfo(),

                  const SizedBox(height: 12),

                  _buildChart(),

                  const SizedBox(height: 12),

                  _buildAnalysisCard(),

                  const SizedBox(height: 12),

                  _buildSupportResistance(),

                  const SizedBox(height: 12),

                  _buildConfirmations(),
                ],

                const SizedBox(height: 20),

                _buildFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // CONNECTION CARD
  // ==========================================================

  Widget _buildConnectionCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [const Color(0xFF101A25), const Color(0xFF0D131C)],
        ),
        border: Border.all(
          color: connected
              ? const Color(0xFF00C896).withOpacity(.25)
              : Colors.white.withOpacity(.07),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: connected
                  ? const Color(0xFF00C896).withOpacity(.12)
                  : Colors.red.withOpacity(.12),
            ),
            child: Icon(
              connected ? Icons.wifi : Icons.wifi_off,
              color: connected ? const Color(0xFF00C896) : Colors.red,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  connected ? 'Conectado a Biquote' : 'Esperando conexión',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  connected
                      ? 'Datos de mercado en tiempo real'
                      : 'Intentando obtener datos...',
                  style: TextStyle(
                    color: Colors.white.withOpacity(.55),
                    fontSize: 12,
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
  // SELECTORES
  // ==========================================================

  Widget _buildSelectors() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101720),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'MERCADO',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: Colors.white54,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: selectedPair,
            decoration: const InputDecoration(
              labelText: 'Par',
              prefixIcon: Icon(Icons.currency_exchange),
              border: OutlineInputBorder(),
            ),
            items: supportedPairs.map((pair) {
              return DropdownMenuItem(value: pair, child: Text(pair));
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                _changePair(value);
              }
            },
          ),
          const SizedBox(height: 12),
          const Text(
            'TEMPORALIDAD',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: Colors.white54,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: supportedTimeframes.map((timeframe) {
              final selected = timeframe == selectedTimeframe;

              return ChoiceChip(
                label: Text(timeframe.toUpperCase()),
                selected: selected,
                onSelected: (_) {
                  _changeTimeframe(timeframe);
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // BUTTON
  // ==========================================================

  Widget _buildAnalyzeButton() {
    return SizedBox(
      height: 52,
      child: FilledButton.icon(
        onPressed: loading ? null : _loadData,
        icon: const Icon(Icons.analytics_outlined),
        label: const Text(
          'ANALIZAR AHORA',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: .4),
        ),
      ),
    );
  }

  // ==========================================================
  // ERROR
  // ==========================================================

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withOpacity(.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 10),
          Expanded(
            child: Text(error!, style: const TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // SIGNAL CARD
  // ==========================================================

  Widget _buildSignalCard() {
    final currentSignal = signal!;

    final isUp = currentSignal.direction == 'UP';

    final isDown = currentSignal.direction == 'DOWN';

    final signalColor = isUp
        ? const Color(0xFF00C896)
        : isDown
        ? const Color(0xFFFF5268)
        : Colors.orange;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [signalColor.withOpacity(.17), const Color(0xFF101720)],
        ),
        border: Border.all(color: signalColor.withOpacity(.35)),
        boxShadow: [
          BoxShadow(
            color: signalColor.withOpacity(.08),
            blurRadius: 30,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'SEÑAL ${currentSignal.timeframe.toUpperCase()}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.4,
                  color: Colors.white54,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: signalColor.withOpacity(.13),
                ),
                child: Text(
                  currentSignal.strength,
                  style: TextStyle(
                    color: signalColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            currentSignal.arrow,
            style: TextStyle(
              fontSize: 64,
              height: 1,
              color: signalColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            currentSignal.direction == 'UP'
                ? 'ALZA'
                : currentSignal.direction == 'DOWN'
                ? 'BAJA'
                : 'ESPERAR',
            style: TextStyle(
              color: signalColor,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            currentSignal.setup,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _metricBox(
                  'SCORE',
                  '${currentSignal.score}/${currentSignal.maxScore}',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _metricBox('TENDENCIA', currentSignal.trend)),
              const SizedBox(width: 8),
              Expanded(child: _metricBox('VELA', currentSignal.candle)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricBox(String title, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.035),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // ENTRY TIMER
  // ==========================================================

  Widget _buildEntryTimer() {
    final active = entrySecondsRemaining > 0 && signal?.direction != 'WAIT';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: active
            ? const Color(0xFF00C896).withOpacity(.07)
            : const Color(0xFF101720),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: active
              ? const Color(0xFF00C896).withOpacity(.25)
              : Colors.white.withOpacity(.06),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active
                  ? const Color(0xFF00C896).withOpacity(.13)
                  : Colors.white.withOpacity(.04),
            ),
            child: Icon(
              Icons.timer_outlined,
              color: active ? const Color(0xFF00C896) : Colors.white38,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'VENTANA DE ENTRADA',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                    color: Colors.white54,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  active
                      ? '$entrySecondsRemaining segundos'
                      : 'Esperando nueva señal',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          Text(
            active ? '$entrySecondsRemaining' : '--',
            style: TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.w900,
              color: active ? const Color(0xFF00C896) : Colors.white38,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // MARKET INFO
  // ==========================================================

  Widget _buildMarketInfo() {
    final price =
        liveTick?.price ?? (candles.isNotEmpty ? candles.last.close : 0);

    return Row(
      children: [
        Expanded(
          child: _infoCard(
            icon: Icons.price_change,
            title: 'PRECIO',
            value: price > 0 ? formatPrice(price) : '--',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _infoCard(
            icon: Icons.schedule,
            title: 'PRÓXIMA VELA',
            value: secondsToNextCandle > 0
                ? _formatDuration(secondsToNextCandle)
                : '--',
          ),
        ),
      ],
    );
  }

  Widget _infoCard({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101720),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(.06)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 21, color: Colors.white54),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 9,
                    color: Colors.white38,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;

    final remaining = seconds % 60;

    if (minutes > 0) {
      return '${minutes}m ${remaining}s';
    }

    return '${remaining}s';
  }

  // ==========================================================
  // CHART
  // ==========================================================

  Widget _buildChart() {
    if (candles.isEmpty) {
      return const SizedBox.shrink();
    }

    final visible = candles.length > 80
        ? candles.sublist(candles.length - 80)
        : candles;

    return Container(
      height: 370,
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF101720),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'GRÁFICO DE PRECIO',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1,
                fontWeight: FontWeight.bold,
                color: Colors.white54,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: SfCartesianChart(
              backgroundColor: Colors.transparent,
              plotAreaBorderWidth: 0,
              primaryXAxis: DateTimeAxis(
                isVisible: true,
                dateFormat: DateFormat('HH:mm'),
                majorGridLines: const MajorGridLines(width: 0.2),
                labelStyle: const TextStyle(fontSize: 9, color: Colors.white38),
              ),
              primaryYAxis: NumericAxis(
                opposedPosition: true,
                numberFormat: NumberFormat('0.#####'),
                majorGridLines: const MajorGridLines(width: 0.2),
                labelStyle: const TextStyle(fontSize: 9, color: Colors.white38),
              ),
              tooltipBehavior: TooltipBehavior(enable: true),
              series: <CartesianSeries>[
                CandleSeries<Candle, DateTime>(
                  dataSource: visible,
                  xValueMapper: (Candle candle, _) => candle.time.toLocal(),
                  lowValueMapper: (Candle candle, _) => candle.low,
                  highValueMapper: (Candle candle, _) => candle.high,
                  openValueMapper: (Candle candle, _) => candle.open,
                  closeValueMapper: (Candle candle, _) => candle.close,
                  enableSolidCandles: true,
                  bearColor: const Color(0xFFFF5268),
                  bullColor: const Color(0xFF00C896),
                  borderWidth: 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // ANALYSIS
  // ==========================================================

  Widget _buildAnalysisCard() {
    final currentSignal = signal!;

    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: const Color(0xFF101720),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ANÁLISIS',
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1.2,
              fontWeight: FontWeight.bold,
              color: Colors.white54,
            ),
          ),
          const SizedBox(height: 12),
          _analysisRow('EMA rápida', formatPrice(currentSignal.emaFast)),
          _analysisRow('EMA lenta', formatPrice(currentSignal.emaSlow)),
          _analysisRow('ATR', formatPrice(currentSignal.atr)),
          _analysisRow('Momentum', formatPrice(currentSignal.momentum)),
          _analysisRow('Tendencia', currentSignal.trend),
          _analysisRow('Momentum dirección', currentSignal.macd),
          _analysisRow('Vela', currentSignal.candle),
          _analysisRow('Temporalidad', currentSignal.timeframe.toUpperCase()),
          if (_lastAnalysisTime != null)
            _analysisRow('Último análisis', formatTime(_lastAnalysisTime!)),
        ],
      ),
    );
  }

  Widget _analysisRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // SUPPORT / RESISTANCE
  // ==========================================================

  Widget _buildSupportResistance() {
    final currentSignal = signal!;

    return Row(
      children: [
        Expanded(
          child: _levelCard(
            title: 'SOPORTE',
            value: currentSignal.support > 0
                ? formatPrice(currentSignal.support)
                : '--',
            color: const Color(0xFF00C896),
            near: currentSignal.nearSupport,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _levelCard(
            title: 'RESISTENCIA',
            value: currentSignal.resistance > 0
                ? formatPrice(currentSignal.resistance)
                : '--',
            color: const Color(0xFFFF5268),
            near: currentSignal.nearResistance,
          ),
        ),
      ],
    );
  }

  Widget _levelCard({
    required String title,
    required String value,
    required Color color,
    required bool near,
  }) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF101720),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: color.withOpacity(.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 9,
                  color: Colors.white54,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          if (near) ...[
            const SizedBox(height: 5),
            Text(
              'PRECIO CERCANO',
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ==========================================================
  // CONFIRMATIONS
  // ==========================================================

  Widget _buildConfirmations() {
    final currentSignal = signal!;

    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: const Color(0xFF101720),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CONFIRMACIONES',
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1.2,
              fontWeight: FontWeight.bold,
              color: Colors.white54,
            ),
          ),
          const SizedBox(height: 12),
          if (currentSignal.confirmations.isEmpty)
            const Text(
              'No hay confirmaciones suficientes.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            )
          else
            ...currentSignal.confirmations.map((item) {
              return _bulletRow(item, true);
            }),
          if (currentSignal.filters.isNotEmpty) ...[
            const SizedBox(height: 15),
            const Text(
              'FILTROS / ALERTAS',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1,
                fontWeight: FontWeight.bold,
                color: Colors.white54,
              ),
            ),
            const SizedBox(height: 8),
            ...currentSignal.filters.map((item) {
              return _bulletRow(item, false);
            }),
          ],
          const SizedBox(height: 15),
          const Text(
            'RAZONES',
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1,
              fontWeight: FontWeight.bold,
              color: Colors.white54,
            ),
          ),
          const SizedBox(height: 8),
          ...currentSignal.reasons.map((item) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Text(
                '• $item',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _bulletRow(String text, bool positive) {
    final color = positive ? const Color(0xFF00C896) : Colors.orange;

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            positive ? Icons.check_circle : Icons.warning_amber,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // FOOTER
  // ==========================================================

  Widget _buildFooter() {
    return Column(
      children: [
        Text(
          'Trading Signal Bot',
          style: TextStyle(
            color: Colors.white.withOpacity(.35),
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Price Action Adaptive • Multi-Timeframe',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withOpacity(.22), fontSize: 10),
        ),
        const SizedBox(height: 8),
        Text(
          'Las señales son análisis técnico y no garantizan resultados.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withOpacity(.18), fontSize: 9),
        ),
      ],
    );
  }
}
