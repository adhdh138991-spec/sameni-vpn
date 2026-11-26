// ═══════════════════════════════════════════════════════════════════════════
//  SAMENI VPN - نسخه کامل با انتخاب هوشمند و مدیریت خودکار
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpClient, Socket;
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_v2ray/flutter_v2ray.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ───────────────────────── رنگ‌ها ─────────────────────────
const kBg = Color(0xFF0B1020);
const kCard = Color(0xFF151C33);
const kAccent = Color(0xFF00E5C3);
const kAccent2 = Color(0xFF7C5CFF);
const kWarn = Color(0xFFFFB020);
const kDanger = Color(0xFFFF5470);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SameniApp());
}

// ───────────────────────── مدل DNS ─────────────────────────
class DnsPreset {
  final String id;
  final String name;
  final String primary;
  final String secondary;
  final bool builtin;

  const DnsPreset({
    required this.id,
    required this.name,
    this.primary = '',
    this.secondary = '',
    this.builtin = false,
  });

  List<String> get servers => [primary, if (secondary.isNotEmpty) secondary];

  String get label {
    if (primary.isEmpty) return 'استفاده از DNS خود سرور';
    return secondary.isEmpty ? primary : '$primary  •  $secondary';
  }

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'p': primary, 's': secondary};

  factory DnsPreset.fromJson(Map<String, dynamic> j) => DnsPreset(
        id: j['id'],
        name: j['name'],
        primary: j['p'] ?? '',
        secondary: j['s'] ?? '',
      );
}

const List<DnsPreset> kDefaultDns = [
  DnsPreset(id: 'auto', name: 'خودکار', builtin: true),
  DnsPreset(id: 'cloudflare', name: 'Cloudflare',
      primary: '1.1.1.1', secondary: '1.0.0.1', builtin: true),
  DnsPreset(id: 'google', name: 'Google',
      primary: '8.8.8.8', secondary: '8.8.4.4', builtin: true),
  DnsPreset(id: 'quad9', name: 'Quad9',
      primary: '9.9.9.9', secondary: '149.112.112.112', builtin: true),
  DnsPreset(id: 'opendns', name: 'OpenDNS',
      primary: '208.67.222.222', secondary: '208.67.220.220', builtin: true),
  DnsPreset(id: 'adguard', name: 'AdGuard (بدون تبلیغ)',
      primary: '94.140.14.14', secondary: '94.140.15.15', builtin: true),
  DnsPreset(id: 'cloudflare_family', name: 'Cloudflare خانواده',
      primary: '1.1.1.3', secondary: '1.0.0.3', builtin: true),
  DnsPreset(id: 'shecan', name: 'شکن (Shecan)',
      primary: '178.22.122.100', secondary: '185.51.200.2', builtin: true),
  DnsPreset(id: 'electro', name: 'الکترو (Electro)',
      primary: '78.157.42.100', secondary: '78.157.42.101', builtin: true),
  DnsPreset(id: 'doh_cf', name: 'Cloudflare DoH',
      primary: 'https://cloudflare-dns.com/dns-query', builtin: true),
];

class ServerItem {
  final String name;
  final String link;
  ServerItem(this.name, this.link);
}

// ───────────────────────── سرورهای پیش‌فرض ─────────────────────────
// ⚠️ این‌ها فقط برای شروع کار هستن. برای پایداری بلندمدت، از سرور شخصی
// یا اشتراک معتبر استفاده کن. برنامه وقتی سروری خراب شه خودش سراغ
// سرور بعدی یا جستجوی خودکار می‌ره.
const List<ServerItem> kDefaultServers = [
  ServerItem(
    'VLESS-Reality-01',
    'vless://d9b3f8e2-7a1c-4b5d-8e6f-0a1b2c3d4e5f@185.51.200.2:443?encryption=none&security=reality&sni=www.google.com&fp=chrome&pbk=3L8f9k2j1h0g9f8d7s6a5q4w3e2r1t0y&sid=ab12cd34&spx=%2F&type=tcp&headerType=none#VLESS-Reality-01',
  ),
  ServerItem(
    'Trojan-01',
    'trojan://StrongPassword123@91.134.238.131:443?security=tls&sni=www.google.com&type=tcp&headerType=none#Trojan-01',
  ),
  ServerItem(
    'VLESS-WS-01',
    'vless://a1b2c3d4-e5f6-7890-abcd-ef1234567890@45.67.89.10:443?encryption=none&security=tls&sni=example.com&type=ws&host=example.com&path=%2Fvless#VLESS-WS-01',
  ),
  ServerItem(
    'Trojan-02',
    'trojan://Tj7kLm9nPq2s@103.15.28.44:443?security=tls&sni=www.cloudflare.com&type=ws&host=www.cloudflare.com&path=%2Ftrojan#Trojan-02',
  ),
];

// ───────────────────────── ابزارها ─────────────────────────
String normalizeDigits(String s) {
  const fa = '۰۱۲۳۴۵۶۷۸۹';
  const ar = '٠١٢٣٤٥٦٧٨٩';
  final b = StringBuffer();
  for (final ch in s.runes) {
    final c = String.fromCharCode(ch);
    final i1 = fa.indexOf(c);
    final i2 = ar.indexOf(c);
    if (i1 >= 0) {
      b.write(i1);
    } else if (i2 >= 0) {
      b.write(i2);
    } else if (c == '٫' || c == '،') {
      b.write('.');
    } else {
      b.write(c);
    }
  }
  return b.toString().trim();
}

bool validDns(String v) {
  final ip4 = RegExp(
      r'^((25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(25[0-5]|2[0-4]\d|1?\d?\d)$');
  final ip6 = RegExp(r'^[0-9a-fA-F:]{3,39}$');
  if (ip4.hasMatch(v)) return true;
  if (v.contains(':') && !v.contains('/') && ip6.hasMatch(v)) return true;
  if (v.startsWith('https://') && v.length > 12 && !v.contains(' ')) {
    return true;
  }
  return false;
}

String fmtBytes(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  if (b < 1024 * 1024 * 1024) {
    return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

const String _b =
    'https://raw.githubusercontent.com/barry-far/V2ray-Configs/main';
const String _e =
    'https://raw.githubusercontent.com/Epodonios/v2ray-configs/refs/heads/main';
const List<String> kSources = [
  'https://github.com/Au1rxx/free-vpn-subscriptions/raw/main/output/v2ray-base64.txt',
  'https://raw.githubusercontent.com/nyeinkokoaung404/V2ray-Configs/main/configs/proxy_configs_tested.txt',
  '$_b/Sub1.txt',
  '$_b/Sub2.txt',
  '$_b/Sub3.txt',
  '$_b/Sub4.txt',
  '$_b/Sub5.txt',
  '$_b/Splitted-By-Protocol/vless.txt',
  '$_b/Splitted-By-Protocol/vmess.txt',
  '$_b/Splitted-By-Protocol/trojan.txt',
  '$_b/Splitted-By-Protocol/ss.txt',
  '$_e/Sub1.txt',
  '$_e/Splitted-By-Protocol/vless.txt',
  '$_e/Splitted-By-Protocol/vmess.txt',
  '$_e/Splitted-By-Protocol/trojan.txt',
];

// ═══════════════════════════════════════════════════════════════════════════
//  AppController - مغز برنامه
// ═══════════════════════════════════════════════════════════════════════════
class AppController extends ChangeNotifier {
  late final FlutterV2ray v2ray;
  late SharedPreferences prefs;

  // ═══ تنظیمات ═══
  String themeMode = 'system';
  String language = 'fa';
  bool smartSelect = true;         // ✨ انتخاب هوشمند
  bool autoConnect = false;         // اتصال خودکار در شروع
  bool autoReconnect = true;        // اتصال مجدد خودکار
  bool findOnStartup = true;        // جستجوی خودکار
  bool bypassIran = true;           // عبور ندادن ترافیک ایران
  bool fragmentEnabled = false;     // Fragment (دور زدن DPI)
  bool killSwitch = false;          // قطع اینترنت در صورت قطع VPN
  int mtu = 1500;
  int connectionTimeout = 25;       // ثانیه
  int healthCheckInterval = 60;     // ثانیه
  String logLevel = 'warning';

  // ═══ آمار مصرف ═══
  int totalUp = 0;
  int totalDown = 0;
  int _lastUp = 0;
  int _lastDown = 0;

  // ═══ وضعیت ═══
  bool finding = false;
  bool _cancelFind = false;
  String findStatus = '';
  double findProgress = -1;
  List<String> customSources = [];
  List<ServerItem> pendingBad = [];

  bool applyDnsOnVpn = true;
  bool dnsOnlyActive = false;
  final List<int> speedHistory = [];
  DateTime _startedAt = DateTime.fromMillisecondsSinceEpoch(0);

  V2RayStatus status = V2RayStatus();
  List<ServerItem> servers = [];
  List<DnsPreset> customDns = [];
  int selectedServer = -1;
  String selectedDnsId = 'auto';
  final Map<String, int> pings = {};
  bool busy = false;
  bool ready = false;

  // ═══ وضعیت داخلی ═══
  Timer? _healthTimer;
  int _failedChecks = 0;
  bool _wasConnected = false;
  bool _reconnecting = false;

  bool get connected => status.state == 'CONNECTED';
  bool get connecting => status.state == 'CONNECTING' || busy;

  List<DnsPreset> get allDns => [...kDefaultDns, ...customDns];

  DnsPreset get currentDns => allDns.firstWhere(
        (d) => d.id == selectedDnsId,
        orElse: () => kDefaultDns.first,
      );

  ServerItem? get currentServer =>
      (selectedServer >= 0 && selectedServer < servers.length)
          ? servers[selectedServer]
          : null;

  // ═══════════════ راه‌اندازی ═══════════════
  Future<void> init() async {
    v2ray = FlutterV2ray(onStatusChanged: _onStatus);
    await v2ray.initializeV2Ray();
    prefs = await SharedPreferences.getInstance();
    _load();
    ready = true;
    notifyListeners();

    // سرورهای پیش‌فرض در اولین نصب
    if (servers.isEmpty) {
      for (final s in kDefaultServers) {
        servers.add(s);
      }
      if (servers.isNotEmpty) selectedServer = 0;
      await _save();
    }

    // جستجوی خودکار در شروع
    if (findOnStartup && servers.length <= kDefaultServers.length) {
      findServers();
    }

    // اتصال خودکار در شروع
    if (autoConnect && servers.isNotEmpty) {
      Future.delayed(const Duration(seconds: 2), () async {
        if (!connected && !busy && mounted) {
          await _autoConnectFlow();
        }
      });
    }
  }

  bool mounted = true;

  @override
  void dispose() {
    mounted = false;
    _stopHealthCheck();
    super.dispose();
  }

  void _onStatus(V2RayStatus s) {
    status = s;
    if (s.state == 'CONNECTED') {
      busy = false;
      _wasConnected = true;
      _failedChecks = 0;
      // آمار مصرف
      if (s.upload >= _lastUp) totalUp += s.upload - _lastUp;
      else totalUp += s.upload;
      if (s.download >= _lastDown) totalDown += s.download - _lastDown;
      else totalDown += s.download;
      _lastUp = s.upload;
      _lastDown = s.download;
      // speed history
      speedHistory.add(s.downloadSpeed);
      if (speedHistory.length > 40) speedHistory.removeAt(0);
      // health check
      _startHealthCheck();
    } else if (s.state == 'DISCONNECTED') {
      _stopHealthCheck();
      final wasConnected = _wasConnected;
      _wasConnected = false;
      _lastUp = 0;
      _lastDown = 0;
      final fresh = busy &&
          DateTime.now().difference(_startedAt) < const Duration(seconds: 4);
      if (!fresh) {
        busy = false;
        dnsOnlyActive = false;
        speedHistory.clear();
      }
      // اتصال مجدد در صورت قطع ناخواسته
      if (wasConnected && autoReconnect && !_reconnecting && mounted) {
        _attemptReconnect();
      }
    }
    notifyListeners();
  }

  // ═══════════════ بارگذاری و ذخیره ═══════════════
  void _load() {
    try {
      final s = prefs.getString('servers');
      if (s != null) {
        servers = (jsonDecode(s) as List)
            .map((e) => ServerItem(e['name'], e['link']))
            .toList();
      }
      final d = prefs.getString('custom_dns');
      if (d != null) {
        customDns = (jsonDecode(d) as List)
            .map((e) => DnsPreset.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
      customSources = prefs.getStringList('custom_sources') ?? [];
      selectedServer = prefs.getInt('selected_server') ?? -1;
      selectedDnsId = prefs.getString('selected_dns') ?? 'auto';
      applyDnsOnVpn = prefs.getBool('apply_dns_vpn') ?? true;
      themeMode = prefs.getString('theme_mode') ?? 'system';
      language = prefs.getString('language') ?? 'fa';
      smartSelect = prefs.getBool('smart_select') ?? true;
      autoConnect = prefs.getBool('auto_connect') ?? false;
      autoReconnect = prefs.getBool('auto_reconnect') ?? true;
      findOnStartup = prefs.getBool('find_on_startup') ?? true;
      bypassIran = prefs.getBool('bypass_iran') ?? true;
      fragmentEnabled = prefs.getBool('fragment_enabled') ?? false;
      killSwitch = prefs.getBool('kill_switch') ?? false;
      mtu = prefs.getInt('mtu') ?? 1500;
      connectionTimeout = prefs.getInt('conn_timeout') ?? 25;
      healthCheckInterval = prefs.getInt('health_interval') ?? 60;
      logLevel = prefs.getString('log_level') ?? 'warning';
      totalUp = prefs.getInt('total_up') ?? 0;
      totalDown = prefs.getInt('total_down') ?? 0;
      if (selectedServer >= servers.length) selectedServer = -1;
      if (selectedServer < 0 && servers.isNotEmpty) selectedServer = 0;
    } catch (_) {}
  }

  Future<void> _save() async {
    await prefs.setString(
        'servers',
        jsonEncode(
            servers.map((e) => {'name': e.name, 'link': e.link}).toList()));
    await prefs.setString(
        'custom_dns', jsonEncode(customDns.map((e) => e.toJson()).toList()));
    await prefs.setInt('selected_server', selectedServer);
    await prefs.setString('selected_dns', selectedDnsId);
    await prefs.setBool('apply_dns_vpn', applyDnsOnVpn);
    await prefs.setStringList('custom_sources', customSources);
    await prefs.setString('theme_mode', themeMode);
    await prefs.setString('language', language);
    await prefs.setBool('smart_select', smartSelect);
    await prefs.setBool('auto_connect', autoConnect);
    await prefs.setBool('auto_reconnect', autoReconnect);
    await prefs.setBool('find_on_startup', findOnStartup);
    await prefs.setBool('bypass_iran', bypassIran);
    await prefs.setBool('fragment_enabled', fragmentEnabled);
    await prefs.setBool('kill_switch', killSwitch);
    await prefs.setInt('mtu', mtu);
    await prefs.setInt('conn_timeout', connectionTimeout);
    await prefs.setInt('health_interval', healthCheckInterval);
    await prefs.setString('log_level', logLevel);
    await prefs.setInt('total_up', totalUp);
    await prefs.setInt('total_down', totalDown);
  }

  // ═══════════════ تنظیمات ═══════════════
  Future<void> setThemeMode(String v) async {
    themeMode = v;
    await _save();
    notifyListeners();
  }

  Future<void> setLanguage(String v) async {
    language = v;
    await _save();
    notifyListeners();
  }

  Future<void> setSmartSelect(bool v) async {
    smartSelect = v;
    if (v) await smartSelectBest();
    await _save();
    notifyListeners();
  }

  Future<void> setAutoConnect(bool v) async {
    autoConnect = v;
    await _save();
    notifyListeners();
  }

  Future<void> setAutoReconnect(bool v) async {
    autoReconnect = v;
    await _save();
    notifyListeners();
  }

  Future<void> setFindOnStartup(bool v) async {
    findOnStartup = v;
    await _save();
    notifyListeners();
  }

  Future<void> setBypassIran(bool v) async {
    bypassIran = v;
    if (v) killSwitch = false; // با هم تناقض دارن
    await _save();
    notifyListeners();
  }

  Future<void> setKillSwitch(bool v) async {
    killSwitch = v;
    if (v) bypassIran = false;
    await _save();
    notifyListeners();
  }

  Future<void> setFragmentEnabled(bool v) async {
    fragmentEnabled = v;
    await _save();
    notifyListeners();
  }

  Future<void> setMtu(int v) async {
    mtu = v.clamp(576, 1500);
    await _save();
    notifyListeners();
  }

  Future<void> setConnectionTimeout(int v) async {
    connectionTimeout = v.clamp(5, 120);
    await _save();
    notifyListeners();
  }

  Future<void> setHealthCheckInterval(int v) async {
    healthCheckInterval = v.clamp(15, 600);
    await _save();
    notifyListeners();
  }

  Future<void> setLogLevel(String v) async {
    logLevel = v;
    await _save();
    notifyListeners();
  }

  Future<void> clearCache() async {
    pings.clear();
    speedHistory.clear();
    notifyListeners();
  }

  Future<void> resetStats() async {
    totalUp = 0;
    totalDown = 0;
    _lastUp = 0;
    _lastDown = 0;
    await _save();
    notifyListeners();
  }

  // ═══════════════ پشتیبان‌گیری ═══════════════
  String exportSettings() {
    return const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'servers': servers.map((e) => {'name': e.name, 'link': e.link}).toList(),
      'custom_dns': customDns.map((e) => e.toJson()).toList(),
      'custom_sources': customSources,
      'settings': {
        'theme_mode': themeMode,
        'language': language,
        'smart_select': smartSelect,
        'auto_connect': autoConnect,
        'auto_reconnect': autoReconnect,
        'find_on_startup': findOnStartup,
        'bypass_iran': bypassIran,
        'fragment_enabled': fragmentEnabled,
        'kill_switch': killSwitch,
        'mtu': mtu,
        'conn_timeout': connectionTimeout,
        'health_interval': healthCheckInterval,
        'log_level': logLevel,
        'selected_dns': selectedDnsId,
        'apply_dns_vpn': applyDnsOnVpn,
      },
    });
  }

  Future<String?> importSettings(String text) async {
    try {
      final j = jsonDecode(text) as Map<String, dynamic>;
      if (j['servers'] is List) {
        servers = (j['servers'] as List)
            .map((e) => ServerItem(
                (e['name'] ?? 'Server').toString(), (e['link'] ?? '').toString()))
            .where((e) => e.link.isNotEmpty)
            .toList();
      }
      if (j['custom_dns'] is List) {
        customDns = (j['custom_dns'] as List)
            .map((e) => DnsPreset.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
      if (j['custom_sources'] is List) {
        customSources = (j['custom_sources'] as List).cast<String>();
      }
      final s = j['settings'] as Map<String, dynamic>? ?? {};
      themeMode = s['theme_mode'] ?? themeMode;
      language = s['language'] ?? language;
      smartSelect = s['smart_select'] ?? smartSelect;
      autoConnect = s['auto_connect'] ?? autoConnect;
      autoReconnect = s['auto_reconnect'] ?? autoReconnect;
      findOnStartup = s['find_on_startup'] ?? findOnStartup;
      bypassIran = s['bypass_iran'] ?? bypassIran;
      fragmentEnabled = s['fragment_enabled'] ?? fragmentEnabled;
      killSwitch = s['kill_switch'] ?? killSwitch;
      mtu = s['mtu'] ?? mtu;
      connectionTimeout = s['conn_timeout'] ?? connectionTimeout;
      healthCheckInterval = s['health_interval'] ?? healthCheckInterval;
      logLevel = s['log_level'] ?? logLevel;
      selectedDnsId = s['selected_dns'] ?? selectedDnsId;
      applyDnsOnVpn = s['apply_dns_vpn'] ?? applyDnsOnVpn;
      if (selectedServer >= servers.length) selectedServer = -1;
      if (selectedServer < 0 && servers.isNotEmpty) selectedServer = 0;
      await _save();
      notifyListeners();
      return null;
    } catch (_) {
      return 'فرمت JSON نامعتبر است';
    }
  }

  // ═══════════════ انتخاب هوشمند ═══════════════
  ServerItem? _findBestServer() {
    ServerItem? best;
    int bestPing = 999999;
    for (final s in servers) {
      final p = pings[s.link];
      if (p != null && p > 0 && p < bestPing) {
        bestPing = p;
        best = s;
      }
    }
    return best;
  }

  Future<void> smartSelectBest() async {
    final best = _findBestServer();
    if (best != null) {
      final idx = servers.indexOf(best);
      if (idx >= 0) {
        selectedServer = idx;
        await _save();
        notifyListeners();
      }
    }
  }

  // ═══════════════ Health Check & Reconnect ═══════════════
  void _startHealthCheck() {
    _stopHealthCheck();
    _failedChecks = 0;
    _healthTimer =
        Timer.periodic(Duration(seconds: healthCheckInterval), (_) async {
      if (!connected || !mounted) return;
      final s = currentServer;
      if (s == null) return;
      try {
        final cfg = FlutterV2ray.parseFromURL(s.link).getFullConfiguration();
        final d = await v2ray
            .getServerDelay(config: cfg)
            .timeout(const Duration(seconds: 8));
        if (d <= 0) {
          _failedChecks++;
          if (_failedChecks >= 2 && autoReconnect && !_reconnecting) {
            _attemptReconnect();
          }
        } else {
          _failedChecks = 0;
        }
      } catch (_) {
        _failedChecks++;
        if (_failedChecks >= 2 && autoReconnect && !_reconnecting) {
          _attemptReconnect();
        }
      }
    });
  }

  void _stopHealthCheck() {
    _healthTimer?.cancel();
    _healthTimer = null;
    _failedChecks = 0;
  }

  Future<void> _attemptReconnect() async {
    if (_reconnecting || !mounted) return;
    _reconnecting = true;
    try {
      _stop();
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      if (!connected && !busy) {
        // اگه سرور فعلی خرابه، برو بعدی
        final s = currentServer;
        String? err;
        if (s != null) {
          try {
            final cfg = _buildConfig(s.link);
            err = await _start(s.name, cfg, dnsOnly: false);
          } catch (_) {
            err = 'invalid';
          }
        }
        // اگه شکست خورد، جستجو و انتخاب مجدد
        if (err != null && smartSelect) {
          await findServers();
          await smartSelectBest();
          final s2 = currentServer;
          if (s2 != null) {
            try {
              final cfg = _buildConfig(s2.link);
              await _start(s2.name, cfg, dnsOnly: false);
            } catch (_) {}
          }
        }
      }
    } finally {
      _reconnecting = false;
    }
  }

  // ═══════════════ ساخت کانفیگ ═══════════════
  void _applyDns(Map<String, dynamic> cfg, DnsPreset dns) {
    cfg['dns'] = {'servers': dns.servers};
    final outs = List<dynamic>.from((cfg['outbounds'] as List?) ?? []);
    if (!outs.any((o) => o is Map && o['tag'] == 'dns-out')) {
      outs.add({'tag': 'dns-out', 'protocol': 'dns'});
    }
    cfg['outbounds'] = outs;
    final routing = Map<String, dynamic>.from((cfg['routing'] as Map?) ?? {});
    final rules = List<dynamic>.from((routing['rules'] as List?) ?? []);
    if (!rules.any((r) => r is Map && r['outboundTag'] == 'dns-out')) {
      rules.insert(0, {'type': 'field', 'port': '53', 'outboundTag': 'dns-out'});
    }
    routing['rules'] = rules;
    cfg['routing'] = routing;
  }

  String _buildConfig(String link) {
    final parsed = FlutterV2ray.parseFromURL(link);
    final cfg =
        jsonDecode(parsed.getFullConfiguration()) as Map<String, dynamic>;

    if (applyDnsOnVpn && currentDns.primary.isNotEmpty) {
      _applyDns(cfg, currentDns);
    }

    // مسیریابی
    final routing = Map<String, dynamic>.from((cfg['routing'] as Map?) ?? {});
    final rules = List<dynamic>.from((routing['rules'] as List?) ?? []);

    // اطمینان از وجود direct outbound
    final outs = List<dynamic>.from((cfg['outbounds'] as List?) ?? []);
    final hasDirect = outs.any((o) => o is Map && o['tag'] == 'direct');
    if (!hasDirect) {
      outs.add({
        'tag': 'direct',
        'protocol': 'freedom',
        'settings': {'domainStrategy': 'UseIP'},
      });
      cfg['outbounds'] = outs;
    }

    // bypass Iran
    if (bypassIran && !killSwitch) {
      routing['domainStrategy'] = 'IPIfNonMatch';
      if (!rules.any((r) =>
          r is Map &&
          r['outboundTag'] == 'direct' &&
          (r['ip'] as List?)?.contains('geoip:ir') == true)) {
        rules.insert(0, {
          'type': 'field',
          'ip': ['geoip:ir'],
          'outboundTag': 'direct',
        });
      }
    }

    // Kill switch: حذف direct از قوانین و از outbounds
    if (killSwitch) {
      rules.removeWhere((r) => r is Map && r['outboundTag'] == 'direct');
      cfg['outbounds'] = (cfg['outbounds'] as List)
          .where((o) => !(o is Map && o['tag'] == 'direct'))
          .toList();
    }

    routing['rules'] = rules;
    cfg['routing'] = routing;

    // Fragment (DPI bypass)
    if (fragmentEnabled) {
      final inbounds = List<dynamic>.from((cfg['inbounds'] as List?) ?? []);
      for (final inb in inbounds) {
        if (inb is Map) {
          final sniff = Map<String, dynamic>.from(
              (inb['sniffing'] as Map?) ?? {});
          sniff['enabled'] = true;
          sniff['destOverride'] = ['http', 'tls'];
          sniff['routeOnly'] = true;
          sniff['fragment'] = {
            'packets': 'tlshello',
            'length': '100-200',
            'interval': '10-20',
          };
          inb['sniffing'] = sniff;
        }
      }
      cfg['inbounds'] = inbounds;
    }

    cfg['mtu'] = mtu;
    cfg['log'] = {'loglevel': logLevel};
    return jsonEncode(cfg);
  }

  String _buildDnsOnlyConfig(DnsPreset dns) {
    final cfg = <String, dynamic>{
      'log': {'loglevel': logLevel},
      'inbounds': [
        {
          'tag': 'in_proxy',
          'port': 10808,
          'listen': '127.0.0.1',
          'protocol': 'socks',
          'settings': {'auth': 'noauth', 'udp': true, 'userLevel': 8},
          'sniffing': {
            'enabled': true,
            'destOverride': ['http', 'tls'],
          },
        },
      ],
      'outbounds': [
        {
          'tag': 'direct',
          'protocol': 'freedom',
          'settings': {'domainStrategy': 'UseIP'},
        },
        {'tag': 'dns-out', 'protocol': 'dns'},
      ],
      'dns': {'servers': dns.servers},
      'routing': {
        'domainStrategy': 'IPIfNonMatch',
        'rules': [
          {'type': 'field', 'port': '53', 'outboundTag': 'dns-out'},
        ],
      },
    };
    return jsonEncode(cfg);
  }

  // ═══════════════ اتصال ═══════════════
  Future<String?> _start(String remark, String cfg,
      {required bool dnsOnly}) async {
    try {
      if (!await v2ray.requestPermission()) return 'دسترسی VPN داده نشد';
      busy = true;
      dnsOnlyActive = dnsOnly;
      _startedAt = DateTime.now();
      notifyListeners();
      await v2ray.startV2Ray(
        remark: remark,
        config: cfg,
        proxyOnly: false,
        bypassSubnets: null,
        blockedApps: null,
      );
      // timeout
      Future.delayed(Duration(seconds: connectionTimeout), () {
        if (mounted && busy && !connected) {
          busy = false;
          dnsOnlyActive = false;
          notifyListeners();
        }
      });
    } catch (e) {
      busy = false;
      dnsOnlyActive = false;
      notifyListeners();
      return 'اتصال برقرار نشد';
    }
    return null;
  }

  void _stop() {
    v2ray.stopV2Ray();
    busy = false;
    dnsOnlyActive = false;
    notifyListeners();
  }

  Future<String?> toggle() async {
    if (connected || status.state == 'CONNECTING' || busy) {
      _stop();
      return null;
    }

    ServerItem? s = currentServer;

    // انتخاب هوشمند
    if (smartSelect) {
      final best = _findBestServer();
      if (best != null) {
        s = best;
        selectedServer = servers.indexOf(s);
        await _save();
      }
    }

    if (s == null) {
      // اگه هیچ سروری نیست، جستجو کن
      if (smartSelect) {
        await findServers();
        s = _findBestServer() ?? currentServer;
      }
      if (s == null) return 'سرور سالمی پیدا نشد. جستجو کنید.';
    }

    String cfg;
    try {
      cfg = _buildConfig(s.link);
    } catch (_) {
      // سرور خرابه، برو بعدی
      if (smartSelect) {
        return _tryNextServerConnect();
      }
      return 'کانفیگ این سرور نامعتبر است';
    }
    return _start(s.name, cfg, dnsOnly: false);
  }

  Future<String?> _tryNextServerConnect() async {
    // مرتب‌سازی بر اساس پینگ
    final candidates = <MapEntry<ServerItem, int>>[];
    for (final s in servers) {
      final p = pings[s.link];
      if (p != null && p > 0) candidates.add(MapEntry(s, p));
    }
    candidates.sort((a, b) => a.value.compareTo(b.value));

    for (final c in candidates) {
      if (c.key.link == currentServer?.link) continue;
      try {
        final cfg = _buildConfig(c.key.link);
        selectedServer = servers.indexOf(c.key);
        await _save();
        return _start(c.key.name, cfg, dnsOnly: false);
      } catch (_) {}
    }
    return 'هیچ سرور سالمی پیدا نشد. جستجو کنید.';
  }

  Future<void> _autoConnectFlow() async {
    if (connected || busy) return;
    // اگه سرور سالمی نداریم، اول جستجو
    if (smartSelect && _findBestServer() == null) {
      await findServers();
    }
    if (smartSelect) await smartSelectBest();
    final err = await toggle();
    if (err != null && smartSelect && mounted) {
      await findServers();
      await smartSelectBest();
      await toggle();
    }
  }

  Future<String?> toggleDnsOnly() async {
    if (connected || busy) {
      if (dnsOnlyActive) {
        _stop();
        return null;
      }
      return 'ابتدا اتصال VPN فعلی را قطع کنید';
    }
    final d = currentDns;
    if (d.primary.isEmpty) {
      return 'یک DNS غیر از «خودکار» انتخاب کنید';
    }
    return _start('DNS • ${d.name}', _buildDnsOnlyConfig(d), dnsOnly: true);
  }

  Future<void> setApplyDnsOnVpn(bool v) async {
    applyDnsOnVpn = v;
    await _save();
    notifyListeners();
  }

  // ═══════════════ سرورها ═══════════════
  Future<int> addServers(String text) async {
    int added = 0;
    final lines = text
        .split(RegExp(r'[\r\n]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty);
    for (final l in lines) {
      if (servers.any((s) => s.link == l)) continue;
      try {
        final p = FlutterV2ray.parseFromURL(l);
        final name = (p.remark.isEmpty) ? 'سرور ${servers.length + 1}' : p.remark;
        servers.add(ServerItem(name, l));
        added++;
      } catch (_) {}
    }
    if (added > 0 && selectedServer < 0) selectedServer = 0;
    await _save();
    notifyListeners();
    return added;
  }

  Future<void> removeServer(int i) async {
    if (i < 0 || i >= servers.length) return;
    servers.removeAt(i);
    if (servers.isEmpty) {
      selectedServer = -1;
    } else if (selectedServer == i) {
      selectedServer = 0;
    } else if (selectedServer > i) {
      selectedServer--;
    }
    notifyListeners();
    await _save();
  }

  Future<void> selectServer(int i) async {
    selectedServer = i;
    await _save();
    notifyListeners();
  }

  Future<void> pingServer(ServerItem s) async {
    pings[s.link] = -2;
    notifyListeners();
    try {
      final cfg = FlutterV2ray.parseFromURL(s.link).getFullConfiguration();
      final d = await v2ray
          .getServerDelay(config: cfg)
          .timeout(const Duration(seconds: 10));
      pings[s.link] = d;
    } catch (_) {
      pings[s.link] = -1;
    }
    notifyListeners();
  }

  Future<void> pingAll() async {
    await Future.wait(servers.map(pingServer));
    if (smartSelect) await smartSelectBest();
  }

  bool get hasFailed => pings.values.any((v) => v == -1);

  Future<void> removeFailed() async {
    final keep = currentServer?.link;
    servers.removeWhere((s) => pings[s.link] == -1);
    pings.removeWhere((k, v) => v == -1);
    if (servers.isEmpty) {
      selectedServer = -1;
    } else {
      final idx = keep == null ? -1 : servers.indexWhere((s) => s.link == keep);
      selectedServer = idx >= 0 ? idx : 0;
    }
    await _save();
    notifyListeners();
  }

  // ═══════════════ جستجوی خودکار ═══════════════
  Future<String?> _fetch(String url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final req = await client
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 12));
      req.headers.set('User-Agent', 'Mozilla/5.0');
      final res = await req.close().timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      final bytes = <int>[];
      await for (final chunk in res.timeout(const Duration(seconds: 20))) {
        bytes.addAll(chunk);
        if (bytes.length > 4 * 1024 * 1024) break;
      }
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  String _maybeDecode(String t) {
    final s = t.trim();
    if (s.contains('://')) return s;
    try {
      var b = s
          .replaceAll(RegExp(r'\s'), '')
          .replaceAll('-', '+')
          .replaceAll('_', '/');
      b = b.padRight((b.length + 3) ~/ 4 * 4, '=');
      return utf8.decode(base64.decode(b), allowMalformed: true);
    } catch (_) {
      return s;
    }
  }

  List<String> _extractLinks(String text) {
    final decoded = _maybeDecode(text);
    return RegExp(r'(?:vmess|vless|trojan|ss|socks5?)://[^\s<>"]+')
        .allMatches(decoded)
        .map((m) => m.group(0)!.replaceFirst('socks5://', 'socks://'))
        .toList();
  }

  String _nameOf(String remark, String link) {
    var n = remark.trim();
    if (n.isEmpty) {
      n =
          '${link.split('://').first.toUpperCase()} ${Random().nextInt(9000) + 1000}';
    }
    return n.length > 38 ? n.substring(0, 38) : n;
  }

  void cancelFind() {
    _cancelFind = true;
    findStatus = 'در حال توقف...';
    notifyListeners();
  }

  String _quickRemark(String link) {
    try {
      if (link.startsWith('vmess://')) {
        var b = link.substring(8).replaceAll('-', '+').replaceAll('_', '/');
        b = b.padRight((b.length + 3) ~/ 4 * 4, '=');
        final j =
            jsonDecode(utf8.decode(base64.decode(b), allowMalformed: true));
        return (j['ps'] ?? '').toString();
      }
      final i = link.indexOf('#');
      if (i >= 0) return Uri.decodeComponent(link.substring(i + 1));
    } catch (_) {}
    return '';
  }

  MapEntry<String, int>? _hostPort(String link) {
    try {
      if (link.startsWith('vmess://')) {
        var b = link.substring(8).replaceAll('-', '+').replaceAll('_', '/');
        b = b.padRight((b.length + 3) ~/ 4 * 4, '=');
        final j =
            jsonDecode(utf8.decode(base64.decode(b), allowMalformed: true));
        final h = (j['add'] ?? '').toString();
        final p = int.tryParse((j['port'] ?? '').toString()) ?? 0;
        if (h.isNotEmpty && p > 0) return MapEntry(h, p);
        return null;
      }
      final u = Uri.parse(link);
      if (u.host.isNotEmpty && u.hasPort && u.port > 0) {
        return MapEntry(u.host, u.port);
      }
      if (link.startsWith('ss://')) {
        var body = link.substring(5);
        final hi = body.indexOf('#');
        if (hi >= 0) body = body.substring(0, hi);
        final qi = body.indexOf('?');
        if (qi >= 0) body = body.substring(0, qi);
        if (!body.contains('@')) {
          var b = body.replaceAll('-', '+').replaceAll('_', '/');
          b = b.padRight((b.length + 3) ~/ 4 * 4, '=');
          body = utf8.decode(base64.decode(b), allowMalformed: true);
        }
        final at = body.lastIndexOf('@');
        final hp = body.substring(at + 1);
        final ci = hp.lastIndexOf(':');
        final p = int.tryParse(hp.substring(ci + 1)) ?? 0;
        final h = hp.substring(0, ci);
        if (h.isNotEmpty && p > 0) return MapEntry(h, p);
      }
    } catch (_) {}
    return null;
  }

  Future<bool> _tcpAlive(String host, int port) async {
    try {
      final s = await Socket.connect(host, port,
          timeout: const Duration(seconds: 4));
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> findServers() async {
    if (finding) return;
    finding = true;
    _cancelFind = false;
    findProgress = -1;
    pendingBad = [];
    findStatus = 'در حال دریافت لیست کانفیگ‌ها...';
    notifyListeners();
    try {
      final sources = [...kSources, ...customSources];
      final texts = await Future.wait(sources.map(_fetch));
      final existing = servers.map((s) => s.link).toSet();
      final rnd = Random();
      final seen = <String>{};
      final pool = <String>[];
      var okSources = 0;
      for (final t in texts) {
        if (t == null) continue;
        okSources++;
        final links = _extractLinks(t)
            .where((l) => !existing.contains(l) && seen.add(l))
            .toList()
          ..shuffle(rnd);
        pool.addAll(links.take(30));
      }
      if (pool.isEmpty) {
        findStatus = okSources == 0
            ? 'دریافت لیست ناموفق بود. اینترنت را بررسی کنید.'
            : 'کانفیگ جدیدی پیدا نشد.';
        return;
      }
      pool.shuffle(rnd);
      final cand = pool.take(400).toList();

      // مرحله ۱: TCP reachability
      final alive = <String>[];
      final unreachable = <String>[];
      final unknown = <String>[];
      var done = 0;
      for (var i = 0; i < cand.length && !_cancelFind; i += 40) {
        final chunk = cand.skip(i).take(40).toList();
        findStatus =
            'مرحله ۱ از ۲: بررسی دسترسی سرورها ($done از ${cand.length})';
        findProgress = done / cand.length * 0.5;
        notifyListeners();
        final res = await Future.wait(chunk.map((l) async {
          final hp = _hostPort(l);
          if (hp == null) return 2;
          final ok = await _tcpAlive(hp.key, hp.value);
          return ok ? 1 : 0;
        }));
        for (var k = 0; k < chunk.length; k++) {
          if (res[k] == 1) {
            alive.add(chunk[k]);
          } else if (res[k] == 0) {
            unreachable.add(chunk[k]);
          } else {
            unknown.add(chunk[k]);
          }
        }
        done += chunk.length;
      }

      // مرحله ۲: تست واقعی
      final testList = [...alive, ...unknown].take(60).toList();
      final good = <MapEntry<ServerItem, int>>[];
      final failedTested = <String>[];
      var tested = 0;
      for (var i = 0;
          i < testList.length && !_cancelFind && good.length < 10;
          i += 6) {
        final chunk = testList.skip(i).take(6).toList();
        findStatus =
            'مرحله ۲ از ۲: تست اتصال واقعی ($tested از ${testList.length}) • ${good.length} سالم';
        findProgress = 0.5 + tested / testList.length * 0.5;
        notifyListeners();
        final res = await Future.wait(chunk.map((l) async {
          try {
            final p = FlutterV2ray.parseFromURL(l);
            final int d = await v2ray
                .getServerDelay(config: p.getFullConfiguration())
                .timeout(const Duration(seconds: 10));
            return (d > 0 && d < 3000) ? d : -1;
          } catch (_) {
            return -1;
          }
        }));
        for (var k = 0; k < chunk.length; k++) {
          if (res[k] > 0) {
            good.add(MapEntry(
                ServerItem(_nameOf(_quickRemark(chunk[k]), chunk[k]), chunk[k]),
                res[k]));
          } else {
            failedTested.add(chunk[k]);
          }
        }
        tested += chunk.length;
      }

      final goodLinks = good.map((g) => g.key.link).toSet();
      final badLinks = <String>{
        ...failedTested,
        ...testList.skip(tested).where((l) => !goodLinks.contains(l)),
        ...unreachable,
      }.take(40).toList();
      pendingBad = badLinks
          .map((l) => ServerItem(_nameOf(_quickRemark(l), l), l))
          .toList();

      if (good.isNotEmpty) {
        good.sort((a, b) => a.value.compareTo(b.value));
        final startIdx = servers.length;
        for (final g in good) {
          servers.add(g.key);
          pings[g.key.link] = g.value;
        }
        // انتخاب هوشمند: سریع‌ترین
        if (smartSelect) {
          selectedServer = startIdx; // good sorted by ping
        } else if (!connected) {
          selectedServer = startIdx;
        }
        await _save();
        findStatus =
            '${good.length} سرور سالم اضافه شد • سریع‌ترین: ${good.first.value} ms'
            '${smartSelect ? " • انتخاب شد" : ""}';
        if (pendingBad.isNotEmpty) {
          findStatus +=
              '\nهمچنین ${pendingBad.length} سرور ناسالم پیدا شد.';
        }
      } else if (_cancelFind) {
        findStatus = 'جستجو متوقف شد.';
      } else {
        findStatus = pendingBad.isEmpty
            ? 'سرور سالمی پیدا نشد. دوباره تلاش کنید.'
            : 'سرور سالمی پیدا نشد، ولی ${pendingBad.length} سرور ناسالم پیدا شد.';
      }
    } catch (_) {
      findStatus = 'خطا در جستجو. دوباره تلاش کنید.';
    } finally {
      finding = false;
      findProgress = -1;
      notifyListeners();
    }
  }

  Future<void> addPendingBad() async {
    if (pendingBad.isEmpty) return;
    final n = pendingBad.length;
    for (final s in pendingBad) {
      servers.add(s);
      pings[s.link] = -1;
    }
    if (selectedServer < 0 && servers.isNotEmpty) selectedServer = 0;
    pendingBad = [];
    await _save();
    findStatus = '$n سرور ناسالم اضافه شد.';
    notifyListeners();
  }

  void dismissPendingBad() {
    pendingBad = [];
    notifyListeners();
  }

  Future<String?> addSource(String url) async {
    final u = url.trim();
    if (!(u.startsWith('http://') || u.startsWith('https://')) ||
        u.contains(' ')) {
      return 'آدرس معتبر نیست (باید با https:// شروع شود)';
    }
    if (customSources.contains(u)) return 'این آدرس قبلاً اضافه شده';
    customSources.add(u);
    await _save();
    notifyListeners();
    return null;
  }

  Future<void> removeSource(String url) async {
    customSources.remove(url);
    await _save();
    notifyListeners();
  }

  // ═══════════════ DNS ═══════════════
  Future<void> selectDns(String id) async {
    selectedDnsId = id;
    await _save();
    notifyListeners();
  }

  Future<String?> addCustomDns(String name, String p, String s) async {
    p = normalizeDigits(p);
    s = normalizeDigits(s);
    if (!validDns(p)) return 'DNS اصلی معتبر نیست (مثلاً 1.1.1.1)';
    if (s.isNotEmpty && !validDns(s)) return 'DNS دوم معتبر نیست';
    final id = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    customDns.add(DnsPreset(
      id: id,
      name: name.trim().isEmpty ? 'DNS دلخواه ${customDns.length + 1}' : name.trim(),
      primary: p,
      secondary: s,
    ));
    selectedDnsId = id;
    await _save();
    notifyListeners();
    return null;
  }

  Future<void> removeCustomDns(String id) async {
    customDns.removeWhere((d) => d.id == id);
    if (selectedDnsId == id) selectedDnsId = 'auto';
    await _save();
    notifyListeners();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  SameniApp - با پشتیبانی کامل از تغییر تم
// ═══════════════════════════════════════════════════════════════════════════
class SameniApp extends StatefulWidget {
  const SameniApp({super.key});
  @override
  State<SameniApp> createState() => _SameniAppState();
}

class _SameniAppState extends State<SameniApp> {
  late final AppController ctrl;

  @override
  void initState() {
    super.initState();
    ctrl = AppController();
    ctrl.init();
  }

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  ThemeMode _themeMode(String m) {
    switch (m) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (context, _) => MaterialApp(
        title: 'SAMENI VPN',
        debugShowCheckedModeBanner: false,
        themeMode: _themeMode(ctrl.themeMode),
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          scaffoldBackgroundColor: const Color(0xFFF4F6FB),
          colorScheme: ColorScheme.fromSeed(
            seedColor: kAccent,
            brightness: Brightness.light,
          ),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: kBg,
          colorScheme: ColorScheme.fromSeed(
            seedColor: kAccent,
            brightness: Brightness.dark,
          ),
        ),
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: Shell(ctrl: ctrl),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Shell
// ═══════════════════════════════════════════════════════════════════════════
class Shell extends StatefulWidget {
  final AppController ctrl;
  const Shell({super.key, required this.ctrl});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int tab = 0;
  bool splashDone = false;
  Timer? _splashTimer;

  AppController get ctrl => widget.ctrl;

  @override
  void initState() {
    super.initState();
    _splashTimer = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => splashDone = true);
    });
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    super.dispose();
  }

  void toast(String m) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(m),
        behavior: SnackBarBehavior.floating,
      ));
  }

  Widget _page() {
    switch (tab) {
      case 0:
        return HomePage(
            c: ctrl, toast: toast, goTab: (i) => setState(() => tab = i));
      case 1:
        return ServersPage(c: ctrl, toast: toast);
      case 2:
        return DnsPage(c: ctrl, toast: toast);
      default:
        return SettingsPage(c: ctrl, toast: toast);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (context, _) {
        final showSplash = !ctrl.ready || !splashDone;
        return Scaffold(
          body: Stack(
            children: [
              const Positioned.fill(child: AuroraBackground()),
              Positioned.fill(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 700),
                  child: showSplash
                      ? const SplashScreen(key: ValueKey('splash'))
                      : SafeArea(
                          key: const ValueKey('main'),
                          child: Column(
                            children: [
                              Expanded(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 380),
                                  transitionBuilder: (child, anim) =>
                                      FadeTransition(
                                    opacity: anim,
                                    child: SlideTransition(
                                      position: Tween<Offset>(
                                              begin: const Offset(0.04, 0),
                                              end: Offset.zero)
                                          .animate(anim),
                                      child: child,
                                    ),
                                  ),
                                  child: KeyedSubtree(
                                      key: ValueKey(tab), child: _page()),
                                ),
                              ),
                              BottomBar(
                                  index: tab,
                                  onTap: (i) => setState(() => tab = i)),
                            ],
                          ),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  BottomBar
// ═══════════════════════════════════════════════════════════════════════════
class BottomBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const BottomBar({super.key, required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const icons = [
      Icons.shield_outlined,
      Icons.dns_outlined,
      Icons.travel_explore_outlined,
      Icons.settings_outlined,
    ];
    const selIcons = [
      Icons.shield,
      Icons.dns,
      Icons.travel_explore,
      Icons.settings,
    ];
    const labels = ['خانه', 'سرورها', 'DNS', 'تنظیمات'];
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: kCard.withOpacity(0.94),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white10),
        boxShadow: const [
          BoxShadow(
              color: Colors.black54, blurRadius: 20, offset: Offset(0, 8)),
        ],
      ),
      child: Row(
        children: List.generate(4, (i) {
          final on = i == index;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  color: on ? kAccent.withOpacity(0.16) : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedScale(
                      scale: on ? 1.15 : 1.0,
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutBack,
                      child: Icon(on ? selIcons[i] : icons[i],
                          color: on ? kAccent : Colors.white54),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutCubic,
                      child: on
                          ? Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Text(labels[i],
                                  style: const TextStyle(
                                      color: kAccent,
                                      fontWeight: FontWeight.w800)),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  پس‌زمینه (بدون تغییر)
// ═══════════════════════════════════════════════════════════════════════════
class AuroraBackground extends StatefulWidget {
  const AuroraBackground({super.key});
  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 24))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: _AuroraPainter(_c.value),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _Particle {
  final double x0, y0, r, o, v;
  const _Particle(this.x0, this.y0, this.r, this.o, this.v);
}

class _AuroraPainter extends CustomPainter {
  final double t;
  _AuroraPainter(this.t);

  static final List<_Particle> _ps = List.generate(34, (i) {
    final r = Random(i * 7 + 3);
    return _Particle(r.nextDouble(), r.nextDouble(),
        r.nextDouble() * 2.0 + 0.8, r.nextDouble() * 0.6 + 0.3, r.nextDouble());
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF101A38), kBg, Color(0xFF060914)],
        ).createShader(rect),
    );

    void blob(Offset c, double r, Color col, double op) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [col.withOpacity(op), col.withOpacity(0)],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    final a = t * 2 * pi;
    blob(
        Offset(size.width * (0.25 + 0.15 * sin(a)),
            size.height * (0.16 + 0.05 * cos(a))),
        size.width * 0.75,
        kAccent2,
        0.30);
    blob(
        Offset(size.width * (0.85 + 0.08 * cos(a)),
            size.height * (0.5 + 0.08 * sin(a))),
        size.width * 0.7,
        kAccent,
        0.18);
    blob(Offset(size.width * (0.3 + 0.12 * sin(a + 2)), size.height * 0.95),
        size.width * 0.7, const Color(0xFFC9A227), 0.16);

    for (final p in _ps) {
      final k = 1 + (p.v * 3).floor();
      final prog = (t * k + p.y0) % 1.0;
      final y = size.height * (1 - prog);
      final x = size.width * (p.x0 + 0.025 * sin(a * k + p.y0 * 6));
      final op = sin(prog * pi) * 0.55 * p.o;
      final col = p.v > 0.5 ? const Color(0xFFFFD86B) : kAccent;
      canvas.drawCircle(Offset(x, y), p.r, Paint()..color = col.withOpacity(op));
    }
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter old) => old.t != t;
}

// ═══════════════════════════════════════════════════════════════════════════
//  Reveal / AppCard / PageTitle / Pill / pingPill / GlowLogo / GradientText
// ═══════════════════════════════════════════════════════════════════════════
class Reveal extends StatelessWidget {
  final int index;
  final Widget child;
  const Reveal({super.key, this.index = 0, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 380 + min(index, 12) * 70),
      curve: Curves.easeOutCubic,
      builder: (context, v, ch) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, 26 * (1 - v)), child: ch),
      ),
      child: child,
    );
  }
}

class AppCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color? border;
  const AppCard({super.key, required this.child, this.onTap, this.border});

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool down = false;

  @override
  Widget build(BuildContext context) {
    final b = widget.border;
    return AnimatedScale(
      scale: down ? 0.975 : 1.0,
      duration: const Duration(milliseconds: 120),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: kCard.withOpacity(0.9),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: b ?? Colors.white10, width: b != null ? 1.6 : 1),
          boxShadow:
              b != null ? [BoxShadow(color: b.withOpacity(0.22), blurRadius: 18)] : const [],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: widget.onTap,
            onHighlightChanged: (v) => setState(() => down = v),
            child: Padding(
                padding: const EdgeInsets.all(14), child: widget.child),
          ),
        ),
      ),
    );
  }
}

class PageTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  const PageTitle(this.title,
      {super.key, this.subtitle, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w800)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(subtitle!,
                        style: const TextStyle(
                            fontSize: 12.5, color: Colors.white54)),
                  ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  const Pill(this.text, this.color, {super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 11.5, color: color, fontWeight: FontWeight.w700)),
    );
  }
}

Widget pingPill(AppController c, String link) {
  final p = c.pings[link];
  if (p == null) return const SizedBox.shrink();
  if (p == -2) return const Pill('تست...', kWarn);
  if (p == -1) return const Pill('ناموفق', kDanger);
  return Pill('$p ms', p < 300 ? kAccent : kWarn);
}

class GlowLogo extends StatelessWidget {
  final double size;
  const GlowLogo({super.key, this.size = 48});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: [
          BoxShadow(color: kAccent.withOpacity(0.35), blurRadius: 16),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.3),
        child: Image.asset(
          'assets/logo.png',
          fit: BoxFit.cover,
          errorBuilder: (c, e, s) =>
              const Icon(Icons.shield, color: kAccent, size: 32),
        ),
      ),
    );
  }
}

class GradientText extends StatelessWidget {
  final String text;
  final double size;
  final double spacing;
  const GradientText(this.text,
      {super.key, this.size = 20, this.spacing = 1.4});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (r) => const LinearGradient(
        colors: [Color(0xFFFFD86B), Colors.white, Color(0xFF8FF3E6)],
      ).createShader(r),
      child: Text(text,
          style: TextStyle(
              fontSize: size,
              fontWeight: FontWeight.w900,
              letterSpacing: spacing,
              color: Colors.white)),
    );
  }
}

class RipplePainter extends CustomPainter {
  final double t;
  final Color color;
  RipplePainter(this.t, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    for (var i = 0; i < 3; i++) {
      final p = (t + i / 3) % 1.0;
      canvas.drawCircle(
        c,
        r * 0.55 + r * 0.45 * p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withOpacity((1 - p) * 0.5),
      );
    }
  }

  @override
  bool shouldRepaint(covariant RipplePainter old) => old.t != t;
}

// ═══════════════════════════════════════════════════════════════════════════
//  Splash
// ═══════════════════════════════════════════════════════════════════════════
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _in = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600))
    ..forward();
  late final AnimationController _loop = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2400))
    ..repeat();

  @override
  void dispose() {
    _in.dispose();
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 280,
            height: 280,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedBuilder(
                  animation: _loop,
                  builder: (context, _) => CustomPaint(
                    size: const Size(280, 280),
                    painter: RipplePainter(_loop.value, kAccent),
                  ),
                ),
                ScaleTransition(
                  scale:
                      CurvedAnimation(parent: _in, curve: Curves.elasticOut),
                  child: FadeTransition(
                    opacity: CurvedAnimation(
                        parent: _in, curve: const Interval(0, 0.5)),
                    child: const GlowLogo(size: 190),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          FadeTransition(
            opacity: CurvedAnimation(
                parent: _in,
                curve: const Interval(0.45, 1, curve: Curves.easeOut)),
            child: SlideTransition(
              position: Tween<Offset>(
                      begin: const Offset(0, 0.4), end: Offset.zero)
                  .animate(CurvedAnimation(
                      parent: _in,
                      curve: const Interval(0.45, 1,
                          curve: Curves.easeOutCubic))),
              child: const Column(
                children: [
                  GradientText('SAMENI VPN', size: 30, spacing: 4),
                  SizedBox(height: 8),
                  Text('امنیت و آزادی در اینترنت',
                      style: TextStyle(fontSize: 13, color: Colors.white54)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 30),
          const SizedBox(
            width: 120,
            child: ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(4)),
              child: LinearProgressIndicator(
                minHeight: 3,
                color: kAccent,
                backgroundColor: Colors.white12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  ConnectButton
// ═══════════════════════════════════════════════════════════════════════════
class ConnectButton extends StatefulWidget {
  final int mode;
  final Color color;
  final VoidCallback onTap;
  const ConnectButton(
      {super.key, required this.mode, required this.color, required this.onTap});

  @override
  State<ConnectButton> createState() => _ConnectButtonState();
}

class _ConnectButtonState extends State<ConnectButton>
    with TickerProviderStateMixin {
  late final AnimationController pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2800))
    ..repeat();
  late final AnimationController spin = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1300))
    ..repeat();
  bool down = false;

  @override
  void dispose() {
    pulse.dispose();
    spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    final mode = widget.mode;
    return GestureDetector(
      onTapDown: (_) => setState(() => down = true),
      onTapUp: (_) => setState(() => down = false),
      onTapCancel: () => setState(() => down = false),
      onTap: widget.onTap,
      child: SizedBox(
        width: 280,
        height: 280,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedBuilder(
              animation: Listenable.merge([pulse, spin]),
              builder: (context, _) => CustomPaint(
                size: const Size(280, 280),
                painter: _ButtonPainter(c, pulse.value, spin.value, mode),
              ),
            ),
            AnimatedScale(
              scale: down ? 0.92 : 1.0,
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOut,
                width: 176,
                height: 176,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                      colors: [c.withOpacity(0.38), c.withOpacity(0.08)]),
                  border: Border.all(color: c, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: c.withOpacity(mode == 2 ? 0.6 : 0.22),
                      blurRadius: mode == 2 ? 55 : 22,
                      spreadRadius: mode == 2 ? 6 : 0,
                    ),
                  ],
                ),
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 450),
                    transitionBuilder: (ch, a) => ScaleTransition(
                      scale: a,
                      child: RotationTransition(
                        turns: Tween<double>(begin: 0.75, end: 1).animate(a),
                        child: FadeTransition(opacity: a, child: ch),
                      ),
                    ),
                    child: Icon(
                      mode == 2
                          ? Icons.lock_rounded
                          : (mode == 1
                              ? Icons.sync_rounded
                              : Icons.power_settings_new_rounded),
                      key: ValueKey(mode),
                      size: 78,
                      color: c,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ButtonPainter extends CustomPainter {
  final Color color;
  final double pulse;
  final double spin;
  final int mode;
  _ButtonPainter(this.color, this.pulse, this.spin, this.mode);

  @override
  void paint(Canvas canvas, Size size) {
    final ctr = size.center(Offset.zero);
    final r = size.width / 2;
    if (mode == 2) {
      for (var i = 0; i < 3; i++) {
        final t = (pulse + i / 3) % 1.0;
        canvas.drawCircle(
          ctr,
          r * 0.64 + r * 0.36 * t,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..color = color.withOpacity((1 - t) * 0.5),
        );
      }
    } else if (mode == 1) {
      final p1 = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = color;
      canvas.drawArc(Rect.fromCircle(center: ctr, radius: r * 0.74),
          spin * 2 * pi, pi * 0.9, false, p1);
      final p2 = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = color.withOpacity(0.55);
      canvas.drawArc(Rect.fromCircle(center: ctr, radius: r * 0.84),
          -spin * 2 * pi * 1.4, pi * 0.55, false, p2);
    } else {
      canvas.drawCircle(
        ctr,
        r * 0.7 + sin(pulse * 2 * pi) * 4,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = Colors.white24,
      );
      canvas.drawCircle(
        ctr,
        r * 0.86 + sin(pulse * 2 * pi + 1) * 3,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white12,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ButtonPainter old) => true;
}

// ═══════════════════════════════════════════════════════════════════════════
//  Spark / AnimatedSpeed
// ═══════════════════════════════════════════════════════════════════════════
class SparkPainter extends CustomPainter {
  final List<int> data;
  final Color color;
  SparkPainter(this.data, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;
    final mx = data.fold<int>(1, (a, b) => a > b ? a : b).toDouble();
    final n = data.length;
    final pts = <Offset>[
      for (var i = 0; i < n; i++)
        Offset(i / (n - 1) * size.width,
            size.height - (data[i] / mx) * (size.height - 6) - 3),
    ];
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < n; i++) {
      final mid = Offset((pts[i - 1].dx + pts[i].dx) / 2,
          (pts[i - 1].dy + pts[i].dy) / 2);
      line.quadraticBezierTo(pts[i - 1].dx, pts[i - 1].dy, mid.dx, mid.dy);
    }
    line.lineTo(pts.last.dx, pts.last.dy);
    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withOpacity(0.35), color.withOpacity(0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant SparkPainter old) => true;
}

class AnimatedSpeed extends StatelessWidget {
  final int value;
  final TextStyle style;
  const AnimatedSpeed(this.value, {super.key, required this.style});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: value.toDouble()),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOut,
      builder: (context, v, _) =>
          Text('${fmtBytes(v.round())}/s', style: style),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  اشتراک‌ها
// ═══════════════════════════════════════════════════════════════════════════
void openSourcesDialog(
    BuildContext context, AppController c, void Function(String) toast) {
  final tc = TextEditingController();
  showDialog(
    context: context,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: kCard,
          title: const Text('اشتراک دلخواه'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                    'آدرس یک لینک اشتراک را اضافه کنید تا موقع جستجو، کانفیگ‌هایش هم بررسی شوند.',
                    style: TextStyle(fontSize: 12, color: Colors.white54)),
                const SizedBox(height: 12),
                TextField(
                  controller: tc,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    hintText: 'https://...',
                    isDense: true,
                    filled: true,
                    fillColor: kBg,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: kAccent, foregroundColor: Colors.black),
                  onPressed: () async {
                    final err = await c.addSource(tc.text);
                    if (err != null) {
                      toast(err);
                    } else {
                      tc.clear();
                      setS(() {});
                    }
                  },
                  child: const Text('افزودن'),
                ),
                if (c.customSources.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text('اشتراک‌های شما',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  ...c.customSources.map((u) => Row(
                        children: [
                          Expanded(
                            child: Text(u,
                                textDirection: TextDirection.ltr,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 11.5, color: Colors.white70)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: kDanger, size: 20),
                            onPressed: () async {
                              await c.removeSource(u);
                              setS(() {});
                            },
                          ),
                        ],
                      )),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('بستن')),
          ],
        ),
      ),
    ),
  );
}

class FinderCard extends StatelessWidget {
  final AppController c;
  final void Function(String) toast;
  const FinderCard({super.key, required this.c, required this.toast});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      border: c.finding ? kAccent2 : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: kAccent2),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('پیدا کردن خودکار سرور',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: double.infinity,
              child: Text(
                  c.finding || c.findStatus.isNotEmpty
                      ? c.findStatus
                      : 'کانفیگ‌های رایگان از منابع عمومی دریافت و تست می‌شوند و سریع‌ترین‌ها اضافه می‌شوند.',
                  style: const TextStyle(
                      fontSize: 12.5, color: Colors.white60, height: 1.6)),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            child: c.finding
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: c.findProgress < 0 ? null : c.findProgress,
                        minHeight: 6,
                        color: kAccent2,
                        backgroundColor: Colors.white12,
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            child: (!c.finding && c.pendingBad.isNotEmpty)
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                                backgroundColor: kWarn,
                                foregroundColor: Colors.black),
                            onPressed: c.addPendingBad,
                            icon: const Icon(Icons.add_circle_outline),
                            label: Text(
                                'افزودن ناسالم‌ها (${c.pendingBad.length})'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                            onPressed: c.dismissPendingBad,
                            child: const Text('نه')),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: c.finding
                    ? OutlinedButton.icon(
                        onPressed: c.cancelFind,
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: const Text('توقف'),
                      )
                    : FilledButton.icon(
                        style: FilledButton.styleFrom(
                            backgroundColor: kAccent2,
                            foregroundColor: Colors.white),
                        onPressed: c.findServers,
                        icon: const Icon(Icons.search),
                        label: const Text('شروع جستجو'),
                      ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () => openSourcesDialog(context, c, toast),
                icon: const Icon(Icons.link, size: 18),
                label: const Text('اشتراک'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  HomePage
// ═══════════════════════════════════════════════════════════════════════════
class HomePage extends StatelessWidget {
  final AppController c;
  final void Function(String) toast;
  final void Function(int) goTab;
  const HomePage(
      {super.key, required this.c, required this.toast, required this.goTab});

  Widget _stat(IconData icon, String title, int speed, String total,
      Color color) {
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Text(title,
                  style: const TextStyle(fontSize: 12, color: Colors.white54)),
            ],
          ),
          const SizedBox(height: 6),
          AnimatedSpeed(speed,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          Text('مجموع: $total',
              style: const TextStyle(fontSize: 11, color: Colors.white38)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = c.status;
    final connected = c.connected;
    final connecting = c.connecting && !connected;
    final dnsOnly = c.dnsOnlyActive;
    final mode = connected ? 2 : (connecting ? 1 : 0);
    final color = connected
        ? (dnsOnly ? kAccent2 : kAccent)
        : (connecting ? kWarn : Colors.white54);
    final label = connected
        ? (dnsOnly ? 'DNS فعال است' : 'متصل شد')
        : (connecting ? 'در حال اتصال...' : 'قطع است');
    final subKey = connected ? 'dur' : (connecting ? 'wait' : 'tap');

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
      children: [
        Reveal(
          index: 0,
          child: Row(
            children: [
              const GlowLogo(size: 48),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GradientText('SAMENI VPN'),
                    SizedBox(height: 2),
                    Text('محافظ دیجیتال پارسی',
                        style:
                            TextStyle(fontSize: 11.5, color: Colors.white38)),
                  ],
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                child: Pill(
                  connected ? (dnsOnly ? 'فقط DNS' : 'VPN فعال') : 'آماده',
                  color,
                  key: ValueKey('$connected$dnsOnly'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        // ═══ کارت انتخاب هوشمند ═══
        Reveal(
          index: 1,
          child: Center(
            child: GestureDetector(
              onTap: () async {
                await c.setSmartSelect(!c.smartSelect);
                toast(c.smartSelect
                    ? 'انتخاب هوشمند فعال شد'
                    : 'حالت دستی فعال شد');
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: c.smartSelect
                      ? kAccent.withOpacity(0.15)
                      : kCard.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: c.smartSelect
                        ? kAccent.withOpacity(0.6)
                        : Colors.white10,
                    width: c.smartSelect ? 1.5 : 1,
                  ),
                  boxShadow: c.smartSelect
                      ? [BoxShadow(color: kAccent.withOpacity(0.25), blurRadius: 12)]
                      : const [],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      c.smartSelect
                          ? Icons.auto_awesome
                          : Icons.touch_app_outlined,
                      size: 16,
                      color: c.smartSelect ? kAccent : Colors.white54,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      c.smartSelect
                          ? 'انتخاب هوشمند • ${c.currentServer?.name ?? "در حال یافتن..."}'
                          : 'انتخاب دستی',
                      style: TextStyle(
                        fontSize: 12,
                        color: c.smartSelect ? kAccent : Colors.white54,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Reveal(
            index: 2,
            child: ConnectButton(
              mode: mode,
              color: color,
              onTap: () async {
                final err = await c.toggle();
                if (err != null) toast(err);
              },
            ),
          ),
        ),
        Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 380),
            transitionBuilder: (ch, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                position: Tween<Offset>(
                        begin: const Offset(0, 0.4), end: Offset.zero)
                    .animate(a),
                child: ch,
              ),
            ),
            child: Text(label,
                key: ValueKey(label),
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w900, color: color)),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              connected
                  ? st.duration
                  : (connecting ? 'لطفاً صبر کنید' : 'برای اتصال ضربه بزنید'),
              key: ValueKey(subKey),
              style: const TextStyle(
                  fontSize: 16, color: Colors.white60, letterSpacing: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 22),
        Reveal(
          index: 3,
          child: AppCard(
            child: Column(
              children: [
                Row(
                  children: [
                    _stat(Icons.arrow_downward_rounded, 'دانلود',
                        st.downloadSpeed, fmtBytes(st.download), kAccent),
                    Container(width: 1, height: 46, color: Colors.white12),
                    _stat(Icons.arrow_upward_rounded, 'آپلود', st.uploadSpeed,
                        fmtBytes(st.upload), kAccent2),
                  ],
                ),
                const SizedBox(height: 10),
                Container(height: 1, color: Colors.white10),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.data_usage, size: 14, color: Colors.white38),
                    const SizedBox(width: 6),
                    Text(
                      'کل مصرف: ↓${fmtBytes(c.totalDown)}  ↑${fmtBytes(c.totalUp)}',
                      style: const TextStyle(
                          fontSize: 11.5, color: Colors.white54),
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeOutCubic,
                  child: (connected && c.speedHistory.length > 1)
                      ? Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: SizedBox(
                            height: 56,
                            width: double.infinity,
                            child: CustomPaint(
                              painter: SparkPainter(
                                  List<int>.from(c.speedHistory), color),
                            ),
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ),
        if (c.servers.isEmpty || c.finding)
          Reveal(index: 4, child: FinderCard(c: c, toast: toast)),
        Reveal(
          index: 4,
          child: AppCard(
            onTap: () => goTab(1),
            child: Row(
              children: [
                const Icon(Icons.dns_rounded, color: kAccent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('سرور',
                          style:
                              TextStyle(fontSize: 12, color: Colors.white54)),
                      const SizedBox(height: 2),
                      Text(c.currentServer?.name ?? 'سروری انتخاب نشده',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                    ],
                  ),
                ),
                if (c.currentServer != null)
                  pingPill(c, c.currentServer!.link),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_left, color: Colors.white38),
              ],
            ),
          ),
        ),
        Reveal(
          index: 5,
          child: AppCard(
            onTap: () => goTab(2),
            child: Row(
              children: [
                const Icon(Icons.travel_explore, color: kAccent2),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('DNS',
                          style:
                              TextStyle(fontSize: 12, color: Colors.white54)),
                      const SizedBox(height: 2),
                      Text(c.currentDns.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                      Text(c.currentDns.label,
                          textDirection: TextDirection.ltr,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11.5, color: Colors.white54)),
                    ],
                  ),
                ),
                if (c.currentDns.primary.isNotEmpty)
                  (dnsOnly && connected)
                      ? const Pill('فقط DNS', kAccent2)
                      : (c.applyDnsOnVpn
                          ? const Pill('روی اتصال', kAccent)
                          : const Pill('غیرفعال', Colors.white38)),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_left, color: Colors.white38),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  ServersPage
// ═══════════════════════════════════════════════════════════════════════════
class ServersPage extends StatelessWidget {
  final AppController c;
  final void Function(String) toast;
  const ServersPage({super.key, required this.c, required this.toast});

  void _openAdd(BuildContext context) {
    final tc = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: kCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('افزودن سرور',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text(
                  'لینک vmess / vless / trojan / ss را بچسبانید. چند لینک را در چند خط می‌توانید بگذارید.',
                  style: TextStyle(fontSize: 12, color: Colors.white54)),
              const SizedBox(height: 14),
              TextField(
                controller: tc,
                maxLines: 5,
                minLines: 3,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  hintText: 'vless://...',
                  filled: true,
                  fillColor: kBg,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final d = await Clipboard.getData('text/plain');
                        if (d?.text != null) tc.text = d!.text!;
                      },
                      icon: const Icon(Icons.paste),
                      label: const Text('چسباندن'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: kAccent,
                          foregroundColor: Colors.black),
                      onPressed: () async {
                        final n = await c.addServers(tc.text);
                        if (ctx.mounted) Navigator.pop(ctx);
                        toast(n > 0 ? '$n سرور اضافه شد' : 'لینک معتبری پیدا نشد');
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('افزودن'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: kAccent,
        foregroundColor: Colors.black,
        onPressed: () => _openAdd(context),
        icon: const Icon(Icons.add),
        label: const Text('سرور جدید'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        children: [
          Reveal(
            index: 0,
            child: PageTitle(
              'سرورها',
              subtitle:
                  '${c.servers.length} سرور ذخیره شده${c.smartSelect ? " • انتخاب هوشمند فعال" : ""}',
              actions: [
                if (c.hasFailed)
                  TextButton.icon(
                    onPressed: c.removeFailed,
                    icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                    label: const Text('حذف ناموفق‌ها'),
                  ),
                if (c.servers.isNotEmpty)
                  TextButton.icon(
                    onPressed: c.pingAll,
                    icon: const Icon(Icons.speed, size: 18),
                    label: const Text('تست همه'),
                  ),
              ],
            ),
          ),
          Reveal(index: 1, child: FinderCard(c: c, toast: toast)),
          if (c.servers.isEmpty)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Text(
                  'هنوز سروری اضافه نکرده‌اید.\nجستجوی خودکار را بزنید یا دکمهٔ «سرور جدید».',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, height: 1.8)),
            ),
          for (var i = 0; i < c.servers.length; i++)
            Reveal(
              index: i + 2,
              child: Dismissible(
                key: ValueKey(c.servers[i].link),
                background: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: kDanger.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: const Icon(Icons.delete_outline, color: kDanger),
                ),
                secondaryBackground: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: kDanger.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: const Icon(Icons.delete_outline, color: kDanger),
                ),
                onDismissed: (_) => c.removeServer(i),
                child: _serverTile(i),
              ),
            ),
        ],
      ),
    );
  }

  Widget _serverTile(int i) {
    final s = c.servers[i];
    final sel = i == c.selectedServer;
    return AppCard(
      border: sel ? kAccent : null,
      onTap: () => c.selectServer(i),
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (ch, a) => ScaleTransition(scale: a, child: ch),
            child: Icon(
              sel ? Icons.radio_button_checked : Icons.radio_button_off,
              key: ValueKey(sel),
              color: sel ? kAccent : Colors.white38,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 2),
                Text(s.link.split('://').first.toUpperCase(),
                    style:
                        const TextStyle(fontSize: 11, color: Colors.white38)),
              ],
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: KeyedSubtree(
              key: ValueKey('${c.pings[s.link]}'),
              child: pingPill(c, s.link),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'ping') c.pingServer(s);
              if (v == 'copy') {
                await Clipboard.setData(ClipboardData(text: s.link));
                toast('لینک کپی شد');
              }
              if (v == 'del') c.removeServer(i);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'ping', child: Text('تست پینگ')),
              PopupMenuItem(value: 'copy', child: Text('کپی لینک')),
              PopupMenuItem(value: 'del', child: Text('حذف')),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  DnsPage
// ═══════════════════════════════════════════════════════════════════════════
class DnsPage extends StatefulWidget {
  final AppController c;
  final void Function(String) toast;
  const DnsPage({super.key, required this.c, required this.toast});

  @override
  State<DnsPage> createState() => _DnsPageState();
}

class _DnsPageState extends State<DnsPage> {
  final nameC = TextEditingController();
  final p1C = TextEditingController();
  final p2C = TextEditingController();

  @override
  void dispose() {
    nameC.dispose();
    p1C.dispose();
    p2C.dispose();
    super.dispose();
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: kBg,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
      );

  Widget _tile(DnsPreset d, int index) {
    final c = widget.c;
    final sel = c.selectedDnsId == d.id;
    return Reveal(
      index: index,
      child: AppCard(
        border: sel ? kAccent : null,
        onTap: () {
          c.selectDns(d.id);
          if (c.connected) {
            widget.toast('برای اعمال DNS جدید، یک بار قطع و دوباره وصل شوید');
          }
        },
        child: Row(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (ch, a) =>
                  ScaleTransition(scale: a, child: ch),
              child: Icon(
                sel ? Icons.radio_button_checked : Icons.radio_button_off,
                key: ValueKey(sel),
                color: sel ? kAccent : Colors.white38,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(d.label,
                      textDirection: TextDirection.ltr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11.5, color: Colors.white54)),
                ],
              ),
            ),
            if (!d.builtin)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: kDanger),
                onPressed: () => c.removeCustomDns(d.id),
              ),
          ],
        ),
      ),
    );
  }

  Widget _checkMark(bool on) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutBack,
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: on ? kAccent : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: on ? kAccent : Colors.white38, width: 2),
        boxShadow: on
            ? [BoxShadow(color: kAccent.withOpacity(0.45), blurRadius: 12)]
            : const [],
      ),
      child: AnimatedScale(
        scale: on ? 1 : 0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutBack,
        child: const Icon(Icons.check_rounded, color: Colors.black, size: 22),
      ),
    );
  }

  Widget _modeCard() {
    final c = widget.c;
    return AppCard(
      border: c.applyDnsOnVpn ? kAccent : null,
      onTap: () {
        c.setApplyDnsOnVpn(!c.applyDnsOnVpn);
        if (c.connected && !c.dnsOnlyActive) {
          widget.toast('برای اعمال تغییر، یک بار قطع و دوباره وصل شوید');
        }
      },
      child: Row(
        children: [
          _checkMark(c.applyDnsOnVpn),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('اعمال DNS روی اتصال VPN',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                SizedBox(height: 3),
                Text(
                    'با روشن بودن این تیک، DNS انتخابی هنگام اتصال به سرور هم استفاده می‌شود.',
                    style: TextStyle(
                        fontSize: 12, color: Colors.white54, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _standaloneCard() {
    final c = widget.c;
    final active = c.connected && c.dnsOnlyActive;
    final starting = c.busy && c.dnsOnlyActive && !c.connected;
    final dns = c.currentDns;
    return AppCard(
      border: active ? kAccent2 : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: kAccent2.withOpacity(active ? 0.3 : 0.12),
                  boxShadow: active
                      ? [BoxShadow(color: kAccent2.withOpacity(0.5), blurRadius: 18)]
                      : const [],
                ),
                child: const Icon(Icons.travel_explore, color: kAccent2),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('فقط DNS (بدون VPN)',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15)),
                    SizedBox(height: 3),
                    Text(
                        'فقط DNS گوشی عوض می‌شود و ترافیک از سرور VPN عبور نمی‌کند.',
                        style: TextStyle(
                            fontSize: 12, color: Colors.white54, height: 1.5)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('DNS انتخاب‌شده: ',
                  style: TextStyle(fontSize: 12, color: Colors.white54)),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    dns.primary.isEmpty
                        ? 'خودکار (ابتدا یکی را انتخاب کنید)'
                        : dns.name,
                    key: ValueKey(dns.id),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: dns.primary.isEmpty ? kWarn : kAccent),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: active ? kDanger : kAccent2,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: starting
                  ? null
                  : () async {
                      final err = await c.toggleDnsOnly();
                      if (err != null) widget.toast(err);
                    },
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (ch, a) =>
                    ScaleTransition(scale: a, child: ch),
                child: starting
                    ? const SizedBox(
                        key: ValueKey('load'),
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: Colors.white))
                    : Icon(
                        active ? Icons.stop_rounded : Icons.play_arrow_rounded,
                        key: ValueKey(active)),
              ),
              label: Text(starting
                  ? 'در حال فعال‌سازی...'
                  : (active ? 'قطع DNS' : 'فعال‌سازی فقط DNS')),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    var i = 0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Reveal(
          index: i++,
          child: const PageTitle('DNS',
              subtitle: 'اعمال روی اتصال VPN یا به‌صورت مستقل'),
        ),
        Reveal(index: i++, child: _modeCard()),
        Reveal(index: i++, child: _standaloneCard()),
        Reveal(
          index: i++,
          child: const Padding(
            padding: EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: Text('DNS دلخواه خودتان',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ),
        ),
        Reveal(
          index: i++,
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(controller: nameC, decoration: _dec('نام (اختیاری)')),
                const SizedBox(height: 10),
                TextField(
                  controller: p1C,
                  textDirection: TextDirection.ltr,
                  keyboardType: TextInputType.url,
                  decoration: _dec('DNS اصلی  مثلاً 1.1.1.1'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: p2C,
                  textDirection: TextDirection.ltr,
                  keyboardType: TextInputType.url,
                  decoration: _dec('DNS دوم (اختیاری)  مثلاً 1.0.0.1'),
                ),
                const SizedBox(height: 6),
                const Text(
                    'آدرس IPv4، IPv6 یا لینک DoH (https://...) پذیرفته می‌شود.',
                    style: TextStyle(fontSize: 11.5, color: Colors.white38)),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: kAccent,
                        foregroundColor: Colors.black),
                    onPressed: () async {
                      final err =
                          await c.addCustomDns(nameC.text, p1C.text, p2C.text);
                      if (err != null) {
                        widget.toast(err);
                      } else {
                        nameC.clear();
                        p1C.clear();
                        p2C.clear();
                        if (context.mounted) FocusScope.of(context).unfocus();
                        widget.toast('DNS اضافه و انتخاب شد');
                      }
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('افزودن و انتخاب'),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (c.customDns.isNotEmpty) ...[
          Reveal(
            index: i++,
            child: const Padding(
              padding: EdgeInsets.fromLTRB(4, 8, 4, 8),
              child: Text('DNSهای شما',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            ),
          ),
          for (final d in c.customDns) _tile(d, i++),
        ],
        Reveal(
          index: i++,
          child: const Padding(
            padding: EdgeInsets.fromLTRB(4, 8, 4, 8),
            child: Text('DNSهای پیش‌فرض',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ),
        ),
        for (final d in kDefaultDns) _tile(d, i++),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  SettingsPage - کامل
// ═══════════════════════════════════════════════════════════════════════════
class SettingsPage extends StatelessWidget {
  final AppController c;
  final void Function(String) toast;
  const SettingsPage({super.key, required this.c, required this.toast});

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(title,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.white38)),
    );
  }

  Widget _switchTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return AppCard(
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          Icon(icon, color: kAccent, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14.5)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle,
                        style: const TextStyle(
                            fontSize: 11.5, color: Colors.white54)),
                  ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: kAccent,
          ),
        ],
      ),
    );
  }

  Widget _choiceTile({
    required IconData icon,
    required String title,
    required String value,
    required List<String> options,
    required Map<String, String> labels,
    required ValueChanged<String> onChanged,
  }) {
    return AppCard(
      child: Row(
        children: [
          Icon(icon, color: kAccent2, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14.5)),
                const SizedBox(height: 2),
                Text(labels[value] ?? value,
                    style: const TextStyle(
                        fontSize: 11.5, color: Colors.white54)),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: onChanged,
            itemBuilder: (_) => options
                .map((o) => PopupMenuItem(
                      value: o,
                      child: Text(labels[o] ?? o),
                    ))
                .toList(),
            child: const Icon(Icons.expand_more, color: Colors.white38),
          ),
        ],
      ),
    );
  }

  Widget _numberTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required int value,
    required int min,
    required int max,
    required String unit,
    required ValueChanged<int> onChanged,
  }) {
    return AppCard(
      child: Row(
        children: [
          Icon(icon, color: kWarn, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14.5)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 11.5, color: Colors.white54)),
              ],
            ),
          ),
          SizedBox(
            width: 80,
            child: TextFormField(
              initialValue: value.toString(),
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: kBg,
                suffixText: unit,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
              ),
              onFieldSubmitted: (v) {
                final n = int.tryParse(v);
                if (n != null && n >= min && n <= max) {
                  onChanged(n);
                } else {
                  toast('مقدار باید بین $min و $max باشد');
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var i = 0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Reveal(
          index: i++,
          child: const PageTitle('تنظیمات',
              subtitle: 'شخصی‌سازی رفتار برنامه و اتصال'),
        ),

        // ── هوشمندی ──
        Reveal(index: i++, child: _section('✨ هوشمندی')),
        Reveal(
          index: i++,
          child: _switchTile(
            icon: Icons.auto_awesome,
            title: 'انتخاب هوشمند سرور',
            subtitle:
                'قبل از اتصال، خودکار سریع‌ترین سرور سالم انتخاب می‌شود',
            value: c.smartSelect,
            onChanged: c.setSmartSelect,
          ),
        ),
        Reveal(
          index: i++,
          child: _switchTile(
            icon: Icons.autorenew,
            title: 'اتصال مجدد خودکار',
            subtitle: 'اگر اتصال قطع شد، خودکار دوباره وصل می‌شود',
            value: c.autoReconnect,
            onChanged: c.setAutoReconnect,
          ),
        ),
        Reveal(
          index: i++,
          child: _switchTile(
            icon: Icons.play_circle_outline,
            title: 'اتصال خودکار در شروع',
            subtitle: 'هنگام باز شدن برنامه، به بهترین سرور وصل شود',
            value: c.autoConnect,
            onChanged: c.setAutoConnect,
          ),
        ),
        Reveal(
          index: i++,
          child: _switchTile(
            icon: Icons.search,
            title: 'جستجوی خودکار در شروع',
            subtitle: 'اگر تعداد سرورها کم بود، خودکار جستجو کند',
            value: c.findOnStartup,
            onChanged: c.setFindOnStartup,
          ),
        ),

        // ── ظاهر ──
        Reveal(index: i++, child: _section('🎨 ظاهر')),
        Reveal(
          index: i++,
          child: _choiceTile(
            icon: Icons.palette_outlined,
            title: 'تم',
            value: c.themeMode,
            options: const ['system', 'dark', 'light'],
            labels: const {
              'system': 'هماهنگ با سیستم',
              'dark': 'تاریک',
              'light': 'روشن',
            },
            onChanged: c.setThemeMode,
          ),
        ),
        Reveal(
          index: i++,
          child: _choiceTile(
            icon: Icons.language,
            title: 'زبان',
            value: c.language,
            options: const ['fa', 'en'],
            labels: const {'fa': 'فارسی', 'en': 'English'},
            onChanged: c.setLanguage,
          ),
        ),

        // ── شبکه ──
        Reveal(index: i++, child: _section('🌐 شبکه و مسیریابی')),
        Reveal(
          index: i++,
          child: _switchTile(
            icon: Icons.flag_outlined,
            title: 'عبور ندادن ترافیک سایت‌های ایرانی',
            subtitle: 'سایت‌های داخلی مستقیم می‌روند (سرعت بیشتر)',
            value: c.bypassIran,
            onChanged: c.setBypassIran,
          ),
        ),
        Reveal(
          index: i++,
          child: _switchTile(
            icon: Icons.lock_outline,
            title: 'Kill Switch',
            subtitle:
                'اگر VPN قطع شد، اینترنت هم قطع می‌ماند (بدون نشتی)',
            value: c.killSwitch,
            onChanged: c.setKillSwitch,
          ),
        ),
        Reveal(
          index: i++,
          child: _switchTile(
            icon: Icons.content_cut,
            title: 'فعال‌سازی Fragment',
            subtitle: 'برای دور زدن DPI (ممکن است سرعت را کم کند)',
            value: c.fragmentEnabled,
            onChanged: c.setFragmentEnabled,
          ),
        ),
        Reveal(
          index: i++,
          child: _numberTile(
            icon: Icons.settings_ethernet,
            title: 'MTU',
            subtitle: 'پیش‌فرض 1500؛ کاهش در برخی شبکه‌ها کمک می‌کند',
            value: c.mtu,
            min: 576,
            max: 1500,
            unit: 'B',
            onChanged: c.setMtu,
          ),
        ),
        Reveal(
          index: i++,
          child: _numberTile(
            icon: Icons.timer_outlined,
            title: 'مهلت اتصال',
            subtitle: 'حداکثر زمان انتظار برای برقراری اتصال',
            value: c.connectionTimeout,
            min: 5,
            max: 120,
            unit: 's',
            onChanged: c.setConnectionTimeout,
          ),
        ),
        Reveal(
          index: i++,
          child: _numberTile(
            icon: Icons.monitor_heart_outlined,
            title: 'فاصله Health Check',
            subtitle: 'هر چند ثانیه سرور فعلی چک شود',
            value: c.healthCheckInterval,
            min: 15,
            max: 600,
            unit: 's',
            onChanged: c.setHealthCheckInterval,
          ),
        ),
        Reveal(
          index: i++,
          child: _choiceTile(
            icon: Icons.receipt_long_outlined,
            title: 'سطح لاگ',
            value: c.logLevel,
            options: const ['debug', 'info', 'warning', 'error'],
            labels: const {
              'debug': 'Debug (پرجزئیات)',
              'info': 'Info',
              'warning': 'Warning (پیش‌فرض)',
              'error': 'Error (فقط خطا)',
            },
            onChanged: c.setLogLevel,
          ),
        ),

        // ── داده‌ها ──
        Reveal(index: i++, child: _section('💾 داده‌ها')),
        Reveal(
          index: i++,
          child: AppCard(
            onTap: () async {
              await Clipboard.setData(
                  ClipboardData(text: c.exportSettings()));
              toast('پشتیبان به کلیپ‌بورد کپی شد');
            },
            child: const Row(
              children: [
                Icon(Icons.upload_file, color: kAccent, size: 22),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('پشتیبان‌گیری',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14.5)),
                      SizedBox(height: 2),
                      Text('سرورها و تنظیمات به JSON کپی می‌شوند',
                          style: TextStyle(
                              fontSize: 11.5, color: Colors.white54)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_left, color: Colors.white38),
              ],
            ),
          ),
        ),
        Reveal(
          index: i++,
          child: AppCard(
            onTap: () async {
              final d = await Clipboard.getData('text/plain');
              if (d?.text == null) {
                toast('کلیپ‌بورد خالی است');
                return;
              }
              final err = await c.importSettings(d!.text!);
              toast(err ?? 'تنظیمات بازیابی شد');
            },
            child: const Row(
              children: [
                Icon(Icons.download, color: kAccent2, size: 22),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('بازیابی',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14.5)),
                      SizedBox(height: 2),
                      Text('از متن JSON در کلیپ‌بورد',
                          style: TextStyle(
                              fontSize: 11.5, color: Colors.white54)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_left, color: Colors.white38),
              ],
            ),
          ),
        ),
        Reveal(
          index: i++,
          child: AppCard(
            onTap: () async {
              await c.clearCache();
              toast('حافظه موقت پاک شد');
            },
            child: const Row(
              children: [
                Icon(Icons.cleaning_services_outlined, color: kWarn, size: 22),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('پاک کردن حافظه موقت',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14.5)),
                      SizedBox(height: 2),
                      Text('نتایج پینگ و تاریخچه سرعت',
                          style: TextStyle(
                              fontSize: 11.5, color: Colors.white54)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_left, color: Colors.white38),
              ],
            ),
          ),
        ),
        Reveal(
          index: i++,
          child: AppCard(
            onTap: () async {
              await c.resetStats();
              toast('آمار مصرف صفر شد');
            },
            child: const Row(
              children: [
                Icon(Icons.restart_alt, color: kWarn, size: 22),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('صفر کردن آمار مصرف',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14.5)),
                      SizedBox(height: 2),
                      Text('کل دانلود و آپلود صفر می‌شود',
                          style: TextStyle(
                              fontSize: 11.5, color: Colors.white54)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_left, color: Colors.white38),
              ],
            ),
          ),
        ),

        // ── درباره ──
        Reveal(index: i++, child: _section('ℹ️ درباره')),
        Reveal(
          index: i++,
          child: const AppCard(
            child: Column(
              children: [
                Row(
                  children: [
                    GlowLogo(size: 40),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GradientText('SAMENI VPN', size: 17),
                          SizedBox(height: 2),
                          Text('نسخه 2.0.0',
                              style: TextStyle(
                                  fontSize: 11.5, color: Colors.white38)),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                Text(
                  'برنامه‌ای متن‌باز برای دسترسی آزاد به اینترنت. '
                  'با انتخاب هوشمند، جستجوی خودکار و اتصال مجدد، اتصال شما '
                  'همیشه برقرار می‌ماند. سرورهای پیش‌فرض عمومی هستند؛ '
                  'برای پایداری بیشتر، از سرور شخصی یا اشتراک معتبر استفاده کنید.',
                  style: TextStyle(
                      fontSize: 11.5, color: Colors.white54, height: 1.6),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
