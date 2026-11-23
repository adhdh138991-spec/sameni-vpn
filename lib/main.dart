import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpClient, HttpHeaders, HttpStatus, Socket, InternetAddress;
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_v2ray/flutter_v2ray.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ───────────────────────── رنگ‌ها ─────────────────────────
const kBg = Color(0xFF0B1020);
const kCard = Color(0xFF151C33);
const kAccent = Color(0xFF00E5C3);
const kAccent2 = Color(0xFFFFC65A);
const kWarn = Color(0xFFFFB020);
const kDanger = Color(0xFFFF5470);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SameniApp());
}

// ───────────────────────── مدل‌ها ─────────────────────────
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

  List<String> get servers =>
      [primary, if (secondary.isNotEmpty) secondary];

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
  DnsPreset(
      id: 'cloudflare',
      name: 'Cloudflare',
      primary: '1.1.1.1',
      secondary: '1.0.0.1',
      builtin: true),
  DnsPreset(
      id: 'google',
      name: 'Google',
      primary: '8.8.8.8',
      secondary: '8.8.4.4',
      builtin: true),
  DnsPreset(
      id: 'quad9',
      name: 'Quad9',
      primary: '9.9.9.9',
      secondary: '149.112.112.112',
      builtin: true),
  DnsPreset(
      id: 'opendns',
      name: 'OpenDNS',
      primary: '208.67.222.222',
      secondary: '208.67.220.220',
      builtin: true),
  DnsPreset(
      id: 'adguard',
      name: 'AdGuard DNS',
      primary: '94.140.14.14',
      secondary: '94.140.15.15',
      builtin: true),
  DnsPreset(
      id: 'cloudflare_family',
      name: 'Cloudflare خانواده',
      primary: '1.1.1.3',
      secondary: '1.0.0.3',
      builtin: true),
  DnsPreset(
      id: 'shecan',
      name: 'شکن (Shecan)',
      primary: '178.22.122.100',
      secondary: '185.51.200.2',
      builtin: true),
  DnsPreset(
      id: 'electro',
      name: 'الکترو (Electro)',
      primary: '78.157.42.100',
      secondary: '78.157.42.101',
      builtin: true),
  DnsPreset(
      id: 'doh_cf',
      name: 'Cloudflare DoH',
      primary: 'https://1.1.1.1/dns-query',
      builtin: true),
];

class ServerItem {
  final String name;
  final String link;
  ServerItem(this.name, this.link);
}

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

bool validDns(String value) {
  final v = normalizeDigits(value).trim();
  if (v.isEmpty || v.contains(' ')) return false;
  // InternetAddress validates both IPv4 and IPv6; a loose regex accepted
  // invalid values such as '::::' in the previous implementation.
  if (InternetAddress.tryParse(v) != null) return true;
  final uri = Uri.tryParse(v);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      uri.hasFragment == false;
}

String fmtBytes(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  if (b < 1024 * 1024 * 1024) {
    return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

// منابع عمومی کانفیگ. پاسخ هر منبع همچنان باید داخل برنامه تست شود؛
// وجود یک لینک در این فهرست به معنی فعال‌بودن سرور نیست.
const List<String> kSources = [
  'https://raw.githubusercontent.com/Au1rxx/free-vpn-subscriptions/main/output/v2ray-base64.txt',
  'https://raw.githubusercontent.com/nyeinkokoaung404/V2ray-Configs/main/configs/proxy_configs_tested.txt',
  'https://raw.githubusercontent.com/barry-far/V2ray-Config/main/Sub1.txt',
  'https://raw.githubusercontent.com/mahdibland/V2RayAggregator/master/sub/sub_merge.txt',
];

// ───────────────────────── کنترلر ─────────────────────────
class AppController extends ChangeNotifier {
  late FlutterV2ray v2ray;
  late SharedPreferences prefs;
  bool _preferencesReady = false;
  bool engineReady = false;
  String? engineError;
  int? connectedPing;
  String coreVersion = 'نامشخص';
  String? storageWarning;
  int _connectionAttempt = 0;
  bool engineStarting = false;
  final Set<String> _pingInFlight = {};
  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelFind = true;
    super.dispose();
  }

  // جستجوی خودکار
  bool finding = false;
  bool _cancelFind = false;
  String findStatus = '';
  double findProgress = -1; // -1 = نامشخص
  List<String> customSources = [];
  List<ServerItem> pendingBad = []; // سرورهای ناسالم پیداشده (اختیاری)

  V2RayStatus status = V2RayStatus();
  List<ServerItem> servers = [];
  List<DnsPreset> customDns = [];
  int selectedServer = -1;
  String selectedDnsId = 'auto';
  bool dnsEnabled = true;
  bool applyDnsOnConnect = true;
  bool animationsEnabled = true;
  bool hapticsEnabled = true;
  bool showTrafficStats = true;
  bool optimizing = false;
  double optimizationProgress = -1;
  String optimizationStatus = '';
  int? optimizationPing;
  final Map<String, int> pings = {}; // -2 = در حال تست ، -1 = ناموفق
  bool busy = false;
  bool ready = false;

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

  void _onStatusChanged(V2RayStatus s) {
    status = s;
    if (s.state == 'CONNECTED' || s.state == 'DISCONNECTED') busy = false;
    if (s.state != 'CONNECTED') connectedPing = null;
    notifyListeners();
  }

  Future<void> init() async {
    try {
      prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 12));
      _load();
      _preferencesReady = true;
    } catch (_) {
      // Keep the UI usable even if local persistence is unavailable.
      storageWarning = 'ذخیره‌سازی تنظیمات در این دستگاه در دسترس نیست؛ تغییرات ممکن است پس از بستن برنامه باقی نمانند.';
    }
    await retryEngine(silent: true);
    ready = true;
    notifyListeners();
    if (engineReady && servers.isEmpty) unawaited(findServers());
  }

  Future<void> retryEngine({bool silent = false}) async {
    if (engineStarting) return;
    engineStarting = true;
    engineReady = false;
    engineError = null;
    if (!silent) notifyListeners();
    try {
      v2ray = FlutterV2ray(onStatusChanged: _onStatusChanged);
      await v2ray.initializeV2Ray(
        notificationIconResourceType: 'mipmap',
        notificationIconResourceName: 'ic_launcher',
      ).timeout(const Duration(seconds: 25));
      engineReady = true;
      engineError = null;
      try {
        coreVersion = await v2ray.getCoreVersion()
            .timeout(const Duration(seconds: 8));
      } catch (_) {
        coreVersion = 'نامشخص';
      }
    } catch (_) {
      engineReady = false;
      engineError = 'موتور Xray راه‌اندازی نشد. گوشی را بررسی کنید و دوباره تلاش کنید.';
    } finally {
      engineStarting = false;
    }
    notifyListeners();
    if (engineReady && servers.isEmpty && ready && !finding) {
      unawaited(findServers());
    }
  }

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
      dnsEnabled = prefs.getBool('dns_enabled') ?? true;
      applyDnsOnConnect = prefs.getBool('apply_dns_on_connect') ?? true;
      animationsEnabled = prefs.getBool('animations_enabled') ?? true;
      hapticsEnabled = prefs.getBool('haptics_enabled') ?? true;
      showTrafficStats = prefs.getBool('show_traffic_stats') ?? true;
      if (selectedServer >= servers.length) selectedServer = -1;
      if (selectedServer < 0 && servers.isNotEmpty) selectedServer = 0;
    } catch (_) {}
  }

  Future<void> _save() async {
    if (!_preferencesReady) return;
    try {
      await prefs.setString(
          'servers',
          jsonEncode(servers
              .map((e) => {'name': e.name, 'link': e.link})
              .toList()));
      await prefs.setString(
          'custom_dns', jsonEncode(customDns.map((e) => e.toJson()).toList()));
      await prefs.setInt('selected_server', selectedServer);
      await prefs.setString('selected_dns', selectedDnsId);
      await prefs.setBool('dns_enabled', dnsEnabled);
      await prefs.setBool('apply_dns_on_connect', applyDnsOnConnect);
      await prefs.setBool('animations_enabled', animationsEnabled);
      await prefs.setBool('haptics_enabled', hapticsEnabled);
      await prefs.setBool('show_traffic_stats', showTrafficStats);
      await prefs.setStringList('custom_sources', customSources);
      storageWarning = null;
    } catch (_) {
      storageWarning = 'ذخیره تنظیمات ناموفق بود؛ فضای خالی و مجوزهای دستگاه را بررسی کنید.';
    }
  }

  // ───── اتصال و DNS تونل ─────
  String _buildConfig(String link, {bool forceDns = false}) {
    final parsed = FlutterV2ray.parseFromURL(link);
    final cfg = jsonDecode(parsed.getFullConfiguration())
        as Map<String, dynamic>;
    final shouldApplyDns = dnsEnabled && (applyDnsOnConnect || forceDns);
    if (shouldApplyDns && currentDns.primary.isNotEmpty) {
      final existingDns = cfg['dns'];
      final dns = existingDns is Map
          ? Map<String, dynamic>.from(existingDns)
          : <String, dynamic>{};
      dns['servers'] = currentDns.servers;
      cfg['dns'] = dns;
    }
    return jsonEncode(cfg);
  }

  Future<String?> _startConnection({bool forceDns = false}) async {
    if (!engineReady) {
      return engineError ?? 'موتور VPN آماده نیست؛ دوباره راه‌اندازی کنید.';
    }
    final server = currentServer;
    if (server == null) return 'ابتدا از تب «سرورها» یک سرور انتخاب کنید';

    final attempt = ++_connectionAttempt;
    busy = true;
    notifyListeners();
    try {
      final cfg = _buildConfig(server.link, forceDns: forceDns);
      final permitted = await v2ray
          .requestPermission()
          .timeout(const Duration(seconds: 30));
      if (!permitted) {
        if (_connectionAttempt == attempt) {
          busy = false;
          notifyListeners();
        }
        return 'اجازه ساخت اتصال VPN داده نشد.';
      }
      await v2ray.startV2Ray(
        remark: server.name,
        config: cfg,
        proxyOnly: false,
        bypassSubnets: null,
        blockedApps: null,
      ).timeout(const Duration(seconds: 25));
      Future.delayed(const Duration(seconds: 25), () {
        if (_connectionAttempt == attempt && busy && !connected) {
          busy = false;
          notifyListeners();
        }
      });
      return null;
    } catch (_) {
      if (_connectionAttempt == attempt) {
        busy = false;
        notifyListeners();
      }
      return 'شروع اتصال ناموفق بود؛ دسترسی اینترنت، مجوز VPN و اعتبار کانفیگ را بررسی کنید.';
    }
  }

  Future<String?> toggle() async {
    if (optimizing) return 'تا پایان بهینه‌سازی اتصال صبر کنید.';
    if (!engineReady && !connected) {
      return engineError ?? 'موتور VPN آماده نیست.';
    }
    if (connected || status.state == 'CONNECTING' || busy) {
      _connectionAttempt++; // invalidate any pending connection timeout
      try {
        await v2ray.stopV2Ray().timeout(const Duration(seconds: 20));
      } catch (_) {
        return 'قطع اتصال VPN ناموفق بود؛ دوباره تلاش کنید';
      }
      busy = false;
      notifyListeners();
      return null;
    }
    return _startConnection();
  }

  Future<void> setDnsEnabled(bool value) async {
    dnsEnabled = value;
    await _save();
    notifyListeners();
  }

  Future<void> setApplyDnsOnConnect(bool value) async {
    applyDnsOnConnect = value;
    await _save();
    notifyListeners();
  }

  /// اعمال فوری DNS در تونل جاری؛ برای جایگزینی DNS، تونل یک‌بار از نو بالا می‌آید.
  Future<String?> applyDnsNow() async {
    if (!engineReady) return engineError ?? 'موتور VPN آماده نیست.';
    if (connecting) return 'اتصال هنوز در حال برقراری است؛ پس از تکمیل اتصال دوباره اعمال کنید.';
    if (!connected) {
      await _save();
      return dnsEnabled && currentDns.primary.isEmpty
          ? 'DNS خودکار ذخیره شد؛ از DNS سرور استفاده می‌شود'
          : 'DNS برای اتصال بعدی ذخیره شد';
    }
    if (currentServer == null) return 'سرور فعالی برای اتصال انتخاب نشده است';

    try {
      await v2ray.stopV2Ray().timeout(const Duration(seconds: 20));
    } catch (_) {
      return 'قطع تونل برای تغییر DNS ناموفق بود';
    }
    for (var i = 0; i < 15 && status.state != 'DISCONNECTED'; i++) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
    if (status.state != 'DISCONNECTED') {
      busy = false;
      notifyListeners();
      return 'قطع تونل قبلی تأیید نشد؛ یک‌بار دستی قطع و دوباره وصل کنید';
    }
    return _startConnection(forceDns: true);
  }

  Future<void> setAnimationsEnabled(bool value) async {
    animationsEnabled = value;
    await _save();
    notifyListeners();
  }

  Future<void> setHapticsEnabled(bool value) async {
    hapticsEnabled = value;
    await _save();
    notifyListeners();
  }

  Future<void> setShowTrafficStats(bool value) async {
    showTrafficStats = value;
    await _save();
    notifyListeners();
  }

  /// Finds the lowest-latency currently testable server. It optimizes the VPN
  /// route; it cannot increase the carrier/ISP's underlying line capacity.
  Future<String> optimizeSpeed() async {
    if (optimizing) return 'بهینه‌سازی از قبل در حال اجراست.';
    if (!engineReady) return engineError ?? 'موتور Xray آماده نیست.';
    if (finding || connecting) return 'ابتدا عملیات فعلی را تمام کنید.';

    if (servers.isEmpty) {
      await findServers();
      if (servers.isEmpty) {
        return findStatus.isNotEmpty
            ? findStatus
            : 'سروری برای آزمایش وجود ندارد؛ ابتدا کانفیگ اضافه کنید.';
      }
    }

    optimizing = true;
    optimizationProgress = 0;
    optimizationPing = null;
    optimizationStatus = 'آماده‌سازی آزمون سرورها...';
    notifyListeners();

    final previousIndex = selectedServer;
    final previousServer = currentServer;
    final wasConnected = connected;

    try {
      final candidates = servers.take(30).toList();
      if (previousServer != null &&
          !candidates.any((item) => item.link == previousServer.link)) {
        candidates.add(previousServer);
      }

      var completed = 0;
      for (var i = 0; i < candidates.length; i += 4) {
        final chunk = candidates.skip(i).take(4).toList();
        optimizationStatus =
            'در حال سنجش پینگ و دسترسی سرورها ($completed از ${candidates.length})';
        optimizationProgress = completed / candidates.length;
        notifyListeners();

        final results = await Future.wait(chunk.map((server) async {
          try {
            final parsed = FlutterV2ray.parseFromURL(server.link);
            return await _measureServerDelay(parsed.getFullConfiguration());
          } catch (_) {
            return -1;
          }
        }));

        for (var j = 0; j < chunk.length; j++) {
          pings[chunk[j].link] = results[j];
        }
        completed += chunk.length;
        optimizationProgress = completed / candidates.length;
        notifyListeners();
      }

      final ranked = candidates
          .where((server) => (pings[server.link] ?? -1) > 0)
          .toList()
        ..sort((a, b) =>
            pings[a.link]!.compareTo(pings[b.link]!));

      if (ranked.isEmpty) {
        optimizationStatus = 'هیچ سروری از آزمون اتصال عبور نکرد.';
        return 'سرور قابل‌اتصالی پیدا نشد. اینترنت پایه و منابع کانفیگ را بررسی کنید.';
      }

      final best = ranked.first;
      final bestIndex = servers.indexWhere((item) => item.link == best.link);
      final bestDelay = pings[best.link]!;
      optimizationPing = bestDelay;

      if (bestIndex < 0) return 'سرور منتخب دیگر در فهرست وجود ندارد.';

      if (!wasConnected) {
        selectedServer = bestIndex;
        await _save();
        optimizationStatus = 'بهترین مسیر انتخاب شد: ${best.name}';
        return 'بهترین سرور انتخاب شد: ${best.name} • پینگ $bestDelay ms. برای استفاده، اتصال را بزنید.';
      }

      if (best.link == previousServer?.link) {
        optimizationStatus = 'سرور فعلی بهترین نتیجه را دارد.';
        return 'سرور فعلی بهترین نتیجه را دارد؛ پینگ $bestDelay ms. تغییری لازم نیست.';
      }

      optimizationStatus = 'در حال جابه‌جایی امن به سرور کم‌تأخیرتر...';
      notifyListeners();
      try {
        await v2ray.stopV2Ray().timeout(const Duration(seconds: 20));
      } catch (_) {
        return 'قطع تونل فعلی برای تغییر سرور ناموفق بود.';
      }

      for (var i = 0; i < 30; i++) {
        if (status.state == 'DISCONNECTED') break;
        await Future.delayed(const Duration(milliseconds: 180));
      }
      if (status.state != 'DISCONNECTED') {
        return 'قطع اتصال قبلی تأیید نشد؛ برای جلوگیری از قطع ناخواسته، سرور تغییر نکرد.';
      }

      selectedServer = bestIndex;
      await _save();
      final startError = await _startConnection();
      if (startError != null) {
        selectedServer = previousIndex;
        await _save();
        if (previousIndex >= 0) await _startConnection();
        return 'سرور سریع‌تر شروع نشد؛ سرور قبلی دوباره انتخاب شد و تلاش برای اتصال مجدد انجام شد. $startError';
      }

      var connectedSuccessfully = false;
      for (var i = 0; i < 55; i++) {
        if (connected) {
          connectedSuccessfully = true;
          break;
        }
        if (status.state == 'DISCONNECTED' && !busy && i > 2) break;
        await Future.delayed(const Duration(milliseconds: 350));
      }

      if (connectedSuccessfully) {
        connectedPing = bestDelay;
        optimizationStatus = 'اتصال روی مسیر جدید برقرار شد.';
        return 'اتصال به ${best.name} منتقل شد • پینگ آزمایش‌شده $bestDelay ms.';
      }

      // Roll back if the candidate fails to establish a real tunnel.
      try {
        await v2ray.stopV2Ray().timeout(const Duration(seconds: 12));
      } catch (_) {}
      for (var i = 0; i < 25 && status.state != 'DISCONNECTED'; i++) {
        await Future.delayed(const Duration(milliseconds: 180));
      }
      selectedServer = previousIndex;
      await _save();
      var restored = false;
      if (previousIndex >= 0) {
        final restoreError = await _startConnection();
        if (restoreError == null) {
          for (var i = 0; i < 35 && !connected; i++) {
            await Future.delayed(const Duration(milliseconds: 300));
          }
          restored = connected;
        }
      }
      optimizationStatus = restored
          ? 'سرور جدید متصل نشد؛ اتصال قبلی بازیابی شد.'
          : 'سرور جدید متصل نشد؛ سرور قبلی انتخاب شد ولی اتصال دوباره تأیید نشد.';
      return restored
          ? 'سرور جدید وصل نشد؛ اتصال به سرور قبلی برگشت.'
          : 'سرور جدید وصل نشد. سرور قبلی انتخاب شد، اما اتصال مجدد تأیید نشد؛ دستی دوباره وصل کنید.';
    } catch (_) {
      optimizationStatus = 'آزمون سرعت با خطا روبه‌رو شد.';
      return 'در بهینه‌سازی خطایی رخ داد؛ دوباره تلاش کنید.';
    } finally {
      optimizing = false;
      optimizationProgress = -1;
      notifyListeners();
    }
  }

  // ───── سرورها ─────
  Future<int> addServers(String text) async {
    if (optimizing) return 0;
    int added = 0;
    final lines = text
        .split(RegExp(r'[\r\n]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty);
    for (final l in lines) {
      if (servers.length >= 500) break;
      if (servers.any((s) => s.link == l)) continue;
      if (!RegExp(r'^(vmess|vless|trojan|ss)://', caseSensitive: false)
          .hasMatch(l)) continue;
      try {
        final parsed = FlutterV2ray.parseFromURL(l);
        final fullConfig = jsonDecode(parsed.getFullConfiguration());
        if (fullConfig is! Map || fullConfig['outbounds'] is! List ||
            (fullConfig['outbounds'] as List).isEmpty) continue;
        final name = (parsed.remark.isEmpty)
            ? 'سرور ${servers.length + 1}'
            : parsed.remark;
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
    if (optimizing) return;
    if ((connected || connecting) && i == selectedServer) return;
    if (i < 0 || i >= servers.length) return;
    final removed = servers.removeAt(i);
    pings.remove(removed.link);
    if (servers.isEmpty) {
      selectedServer = -1;
    } else if (selectedServer == i) {
      selectedServer = 0;
    } else if (selectedServer > i) {
      selectedServer--;
    }
    await _save();
    notifyListeners();
  }

  Future<void> selectServer(int i) async {
    if (optimizing || connected || connecting || i < 0 || i >= servers.length) return;
    selectedServer = i;
    await _save();
    notifyListeners();
  }

  Future<void> pingServer(ServerItem s) async {
    if (optimizing || _pingInFlight.contains(s.link)) return;
    if (!engineReady) {
      pings[s.link] = -1;
      notifyListeners();
      return;
    }
    _pingInFlight.add(s.link);
    pings[s.link] = -2;
    notifyListeners();
    try {
      final cfg = FlutterV2ray.parseFromURL(s.link).getFullConfiguration();
      pings[s.link] = await _measureServerDelay(cfg);
    } catch (_) {
      pings[s.link] = -1;
    } finally {
      _pingInFlight.remove(s.link);
    }
    notifyListeners();
  }

  Future<void> pingAll() async {
    if (optimizing || finding) return;
    // Keep native Xray test processes bounded; launching hundreds at once can
    // freeze lower-memory phones and distort the measurements.
    for (var i = 0; i < servers.length; i += 5) {
      await Future.wait(servers.skip(i).take(5).map(pingServer));
    }
  }

  static const List<String> _delayTestUrls = [
    'https://cp.cloudflare.com/generate_204',
    'https://www.google.com/generate_204',
    'https://connectivitycheck.gstatic.com/generate_204',
  ];

  Future<int> _measureServerDelay(String config) async {
    for (final url in _delayTestUrls) {
      try {
        final delay = await v2ray
            .getServerDelay(config: config, url: url)
            .timeout(const Duration(seconds: 9));
        if (delay > 0 && delay < 10000) return delay;
      } catch (_) {
        // Try the next independent reachability endpoint.
      }
    }
    return -1;
  }

  Future<void> pingConnected() async {
    if (!engineReady || !connected) return;
    connectedPing = -2;
    notifyListeners();
    for (final url in _delayTestUrls) {
      try {
        final delay = await v2ray
            .getConnectedServerDelay(url: url)
            .timeout(const Duration(seconds: 9));
        if (delay > 0 && delay < 10000) {
          connectedPing = delay;
          notifyListeners();
          return;
        }
      } catch (_) {
        // Try fallback endpoint.
      }
    }
    connectedPing = -1;
    notifyListeners();
  }

  bool get hasFailed => pings.values.any((v) => v == -1);

  Future<void> removeFailed() async {
    if (optimizing) return;
    final keep = currentServer?.link;
    servers.removeWhere((s) =>
        pings[s.link] == -1 && !((connected || connecting) && s.link == keep));
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

  // ───── پیدا کردن خودکار کانفیگ ─────
  Future<String?> _fetch(String url) async {
    final initial = Uri.tryParse(url);
    if (initial == null || initial.scheme != 'https' ||
        initial.host.isEmpty || initial.userInfo.isNotEmpty) return null;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12)
      ..maxRedirects = 3;
    try {
      Future<HttpClientResponse?> request(Uri uri, int redirectsLeft) async {
        final req = await client.getUrl(uri).timeout(const Duration(seconds: 12));
        req.followRedirects = false;
        req.headers.set('User-Agent', 'SAMENI-VPN/1.2');
        final response = await req.close().timeout(const Duration(seconds: 20));
        final isRedirect = response.statusCode == HttpStatus.movedPermanently ||
            response.statusCode == HttpStatus.found ||
            response.statusCode == HttpStatus.seeOther ||
            response.statusCode == HttpStatus.temporaryRedirect ||
            response.statusCode == HttpStatus.permanentRedirect;
        if (isRedirect) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          await response.drain<void>();
          if (redirectsLeft <= 0 || location == null) return null;
          final next = uri.resolve(location);
          // Never follow a subscription redirect to an unencrypted HTTP URL.
          if (next.scheme != 'https' || next.host.isEmpty ||
              next.userInfo.isNotEmpty) return null;
          return request(next, redirectsLeft - 1);
        }
        return response;
      }

      final res = await request(initial, 3);
      if (res == null || res.statusCode != HttpStatus.ok) return null;
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
      var b = s.replaceAll(RegExp(r'\s'), '').replaceAll('-', '+').replaceAll('_', '/');
      b = b.padRight((b.length + 3) ~/ 4 * 4, '=');
      return utf8.decode(base64.decode(b), allowMalformed: true);
    } catch (_) {
      return s;
    }
  }

  List<String> _extractLinks(String text) {
    final payloads = <String>{text.trim()};
    var current = text.trim();
    // A few subscription providers double-encode their response.
    for (var depth = 0; depth < 2; depth++) {
      final decoded = _maybeDecode(current);
      if (decoded == current || decoded.isEmpty) break;
      payloads.add(decoded);
      current = decoded;
    }
    // Some feeds put each base64 link on its own line with a header around it.
    for (final line in text.split(RegExp(r'[\r\n]+'))) {
      final candidate = line.trim();
      if (candidate.length < 24 || candidate.contains('://')) continue;
      final decodedLine = _maybeDecode(candidate);
      if (decodedLine != candidate) payloads.add(decodedLine);
    }

    final found = <String>{};
    final pattern = RegExp(
      r'(?:vmess|vless|trojan|ss)://[^\s<>"]+',
      caseSensitive: false,
    );
    for (final payload in payloads) {
      for (final match in pattern.allMatches(payload)) {
        final link = match.group(0)!.replaceAll(RegExp(r'[)\],;}]+$'), '');
        if (link.isNotEmpty) found.add(link);
      }
    }
    return found.toList();
  }

  String _nameOf(String remark, String link) {
    var n = remark.trim();
    if (n.isEmpty) {
      n = '${link.split('://').first.toUpperCase()} ${Random().nextInt(9000) + 1000}';
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
        final j = jsonDecode(utf8.decode(base64.decode(b), allowMalformed: true));
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
        final j = jsonDecode(utf8.decode(base64.decode(b), allowMalformed: true));
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
    if (finding || optimizing) return;
    if (!engineReady) {
      findStatus = engineError ?? 'موتور Xray آماده نیست.';
      notifyListeners();
      return;
    }
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
            ? 'دریافت لیست ناموفق بود. اینترنت را بررسی کنید (یا با یک VPN دیگر وصل شوید).'
            : 'کانفیگ جدیدی پیدا نشد.';
        return;
      }
      pool.shuffle(rnd);
      final cand = pool.take(400).toList();

      // مرحله ۱: بررسی سریع دسترسی TCP
      final alive = <String>[];
      final unreachable = <String>[];
      final unknown = <String>[];
      var done = 0;
      for (var i = 0; i < cand.length && !_cancelFind; i += 12) {
        final chunk = cand.skip(i).take(12).toList();
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

      // مرحله ۲: تست اتصال واقعی از داخل هستهٔ V2Ray
      final testList = [...alive, ...unknown].take(60).toList();
      final good = <MapEntry<ServerItem, int>>[];
      final failedTested = <String>[];
      var tested = 0;
      for (var i = 0;
          i < testList.length && !_cancelFind && good.length < 10;
          i += 4) {
        final chunk = testList.skip(i).take(4).toList();
        findStatus =
            'مرحله ۲ از ۲: تست اتصال واقعی ($tested از ${testList.length}) • ${good.length} سالم';
        findProgress = 0.5 + tested / testList.length * 0.5;
        notifyListeners();
        final res = await Future.wait(chunk.map((l) async {
          try {
            final p = FlutterV2ray.parseFromURL(l);
            return await _measureServerDelay(p.getFullConfiguration());
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

      // سرورهای ناسالم: اول آن‌هایی که باز بودند ولی تست اتصال رد شدند، بعد بقیه
      final badLinks = <String>{
        ...failedTested,
        ...unreachable,
      }.take(40).toList();
      pendingBad = badLinks
          .map((l) => ServerItem(_nameOf(_quickRemark(l), l), l))
          .toList();

      if (good.isNotEmpty) {
        good.sort((a, b) => a.value.compareTo(b.value));
        final availableSlots = 200 - servers.length;
        if (availableSlots <= 0) {
          findStatus = 'فهرست سرورها به سقف ۲۰۰ مورد رسیده است؛ ابتدا سرورهای قدیمی را حذف کنید.';
          return;
        }
        final accepted = good.take(availableSlots).toList();
        final startIdx = servers.length;
        for (final g in accepted) {
          servers.add(g.key);
          pings[g.key.link] = g.value;
        }
        if (!connected) selectedServer = startIdx; // سریع‌ترین
        await _save();
        findStatus =
            '${accepted.length} سرور با تست Xray اضافه شد • سریع‌ترین: ${accepted.first.value} ms';
        if (pendingBad.isNotEmpty) {
          findStatus +=
              '\nهمچنین ${pendingBad.length} سرور ناسالم پیدا شد. اگر خواستید، اضافه‌شان کنید.';
        }
      } else if (_cancelFind) {
        findStatus = 'جستجو متوقف شد.';
      } else {
        findStatus = pendingBad.isEmpty
            ? 'سرور سالمی پیدا نشد. دوباره تلاش کنید.'
            : 'سرور سالمی پیدا نشد، ولی ${pendingBad.length} سرور ناسالم پیدا شد. می‌خواهید اضافه شوند تا خودتان امتحان کنید؟';
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
      if (servers.length >= 500) break;
      if (servers.any((existing) => existing.link == s.link)) continue;
      servers.add(s);
      pings[s.link] = -1;
    }
    if (selectedServer < 0 && servers.isNotEmpty) selectedServer = 0;
    pendingBad = [];
    await _save();
    findStatus = '$n سرور ناسالم اضافه شد. می‌توانید دستی امتحانشان کنید.';
    notifyListeners();
  }

  void dismissPendingBad() {
    pendingBad = [];
    notifyListeners();
  }

  Future<String?> addSource(String url) async {
    final u = url.trim();
    final parsed = Uri.tryParse(u);
    if (parsed == null ||
        parsed.scheme != 'https' ||
        parsed.host.isEmpty ||
        parsed.userInfo.isNotEmpty ||
        u.contains(' ')) {
      return 'آدرس معتبر نیست؛ فقط لینک HTTPS قابل‌اعتماد اضافه کنید.';
    }
    if (customSources.contains(u)) return 'این آدرس قبلاً اضافه شده';
    if (customSources.length >= 20) return 'حداکثر ۲۰ منبع اشتراک می‌توانید اضافه کنید.';
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

  // ───── DNS ─────
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
    if (customDns.length >= 20) return 'حداکثر ۲۰ DNS دلخواه می‌توانید ذخیره کنید.';
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

// ───────────────────────── اپ ─────────────────────────
class SameniApp extends StatelessWidget {
  const SameniApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SAMENI VPN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Vazirmatn',
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kAccent,
          brightness: Brightness.dark,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: kCard,
          indicatorColor: kAccent.withOpacity(0.20),
        labelTextStyle: const WidgetStatePropertyAll<TextStyle>(TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5)),
        ),
      ),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const SplashGate(),
    );
  }
}

class SplashGate extends StatefulWidget {
  const SplashGate({super.key});
  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro;
  late final AnimationController _orbit;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _fade = CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic);
    _scale = Tween<double>(begin: 0.78, end: 1.0).animate(
      CurvedAnimation(parent: _intro, curve: Curves.easeOutBack),
    );
    _orbit = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    )..repeat();
    _intro.forward();
    Future.delayed(const Duration(milliseconds: 2300), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 550),
          pageBuilder: (_, __, ___) => const Shell(),
          transitionsBuilder: (_, animation, __, child) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(scale: Tween<double>(begin: 1.02, end: 1).animate(animation), child: child),
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _intro.dispose();
    _orbit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.18),
            radius: 0.95,
            colors: [Color(0xFF24345A), Color(0xFF0B1020), Color(0xFF050812)],
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _orbit,
                    builder: (context, _) {
                      final wave = 0.5 + 0.5 * sin(_orbit.value * 2 * pi);
                      return SizedBox(
                        width: 294,
                        height: 294,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Transform.rotate(
                              angle: _orbit.value * 2 * pi,
                              child: Container(
                                width: 288,
                                height: 288,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: kAccent.withOpacity(0.20 + wave * 0.28),
                                    width: 1.4,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: kAccent.withOpacity(0.08 + wave * 0.12),
                                      blurRadius: 20 + wave * 18,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(38),
                                boxShadow: [
                                  BoxShadow(color: kAccent.withOpacity(0.18 + wave * 0.18), blurRadius: 44, spreadRadius: 5),
                                  BoxShadow(color: kAccent2.withOpacity(0.09 + wave * 0.08), blurRadius: 30, spreadRadius: 2),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(31),
                                child: Image.asset(
                                  'assets/branding/sameni_achaemenid.png',
                                  width: 260,
                                  height: 260,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 26),
                  const Text('اتصال هوشمند، با هویت ایرانی',
                    style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: 132,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: const LinearProgressIndicator(
                        minHeight: 3,
                        backgroundColor: Colors.white12,
                        color: kAccent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with TickerProviderStateMixin {
  final ctrl = AppController();
  final PageController _pages = PageController();
  late final AnimationController _exit;
  int tab = 0;
  bool _isExiting = false;

  @override
  void initState() {
    super.initState();
    _exit = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    ctrl.init();
  }

  @override
  void dispose() {
    _pages.dispose();
    _exit.dispose();
    ctrl.dispose();
    super.dispose();
  }

  void _goTab(int index) {
    if (_isExiting || index < 0 || index > 3) return;
    if (index == tab) return;
    setState(() => tab = index);
    if (_pages.hasClients) {
      if (ctrl.animationsEnabled) {
        _pages.animateToPage(
          index,
          duration: const Duration(milliseconds: 520),
          curve: Curves.easeInOutCubic,
        );
      } else {
        _pages.jumpToPage(index);
      }
    }
  }

  void _onBack(bool didPop, Object? result) {
    if (didPop || _isExiting) return;
    if (tab != 0) {
      _goTab(0);
      return;
    }
    _playExit();
  }

  Future<void> _playExit() async {
    if (_isExiting) return;
    if (!ctrl.animationsEnabled) {
      // Keep the VPN tunnel alive while closing the UI.
      await SystemNavigator.pop();
      return;
    }
    setState(() => _isExiting = true);
    await _exit.forward();
    // Do not stop the VPN tunnel here: Android's VPN foreground service is
    // managed by the native plugin and the user may intentionally leave it on.
    await SystemNavigator.pop();
  }

  void toast(String m) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(m),
        behavior: SnackBarBehavior.floating,
      ));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: _onBack,
      child: AnimatedBuilder(
        animation: ctrl,
        builder: (context, _) {
          if (!ctrl.ready) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator(color: kAccent)),
            );
          }
          return Stack(
            children: [
              Scaffold(
                body: SafeArea(
                  child: PageView(
                    controller: _pages,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      HomePage(c: ctrl, toast: toast, goTab: _goTab),
                      ServersPage(c: ctrl, toast: toast),
                      DnsPage(c: ctrl, toast: toast),
                      SettingsPage(c: ctrl, toast: toast, goTab: _goTab),
                    ],
                  ),
                ),
                bottomNavigationBar: NavigationBar(
                  selectedIndex: tab,
                  onDestinationSelected: _goTab,
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.shield_outlined),
                      selectedIcon: Icon(Icons.shield, color: kAccent),
                      label: 'خانه',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.dns_outlined),
                      selectedIcon: Icon(Icons.dns, color: kAccent),
                      label: 'سرورها',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.travel_explore_outlined),
                      selectedIcon: Icon(Icons.travel_explore, color: kAccent),
                      label: 'DNS',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.tune_rounded),
                      selectedIcon: Icon(Icons.settings_rounded, color: kAccent),
                      label: 'تنظیمات',
                    ),
                  ],
                ),
              ),
              if (_isExiting)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _exit,
                      builder: (context, _) {
                        final t = Curves.easeInOutCubic.transform(_exit.value);
                        return Opacity(
                          opacity: t,
                          child: Container(
                            color: const Color(0xFF050812),
                            alignment: Alignment.center,
                            child: Transform.translate(
                              offset: Offset(0, 22 * t),
                              child: Transform.scale(
                                scale: 1.0 - (0.08 * t),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(34),
                                        boxShadow: [
                                          BoxShadow(
                                            color: kAccent.withOpacity(0.24 * t),
                                            blurRadius: 42,
                                            spreadRadius: 4,
                                          ),
                                          BoxShadow(
                                            color: kAccent2.withOpacity(0.16 * t),
                                            blurRadius: 30,
                                          ),
                                        ],
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(30),
                                        child: Image.asset(
                                          'assets/branding/sameni_achaemenid.png',
                                          width: 190,
                                          height: 190,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    const Text(
                                      'SAMENI VPN',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 2,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'تا اتصال دوباره...',
                                      style: TextStyle(
                                        color: Colors.white60,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 22),
                                    SizedBox(
                                      width: 90,
                                      child: LinearProgressIndicator(
                                        value: t,
                                        minHeight: 3,
                                        color: kAccent,
                                        backgroundColor: Colors.white12,
                                        borderRadius: BorderRadius.circular(9),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ───────────────────────── ابزار UI ─────────────────────────
class AppCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color? border;
  const AppCard({super.key, required this.child, this.onTap, this.border});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border ?? Colors.white10),
        boxShadow: [
          if (border != null) BoxShadow(color: border!.withOpacity(0.12), blurRadius: 18, spreadRadius: 1),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(14), child: child),
        ),
      ),
    );
  }
}

class PageTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  const PageTitle(this.title, {super.key, this.subtitle, this.actions = const []});

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

// ───────────────────────── کارت پیدا کردن خودکار ─────────────────────────
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
                    'آدرس یک لینک اشتراک (Subscription) را اضافه کنید تا موقع جستجوی خودکار، کانفیگ‌هایش هم بررسی شوند.',
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
          Text(
              c.finding || c.findStatus.isNotEmpty
                  ? c.findStatus
                  : 'کانفیگ‌های عمومی دریافت می‌شوند؛ فقط سرورهایی که اکنون از تست Xray عبور کنند اضافه می‌شوند. پایداری و حریم خصوصی سرورهای ناشناس تضمین نیست.',
              style: const TextStyle(
                  fontSize: 12.5, color: Colors.white60, height: 1.6)),
          if (c.finding) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: c.findProgress < 0 ? null : c.findProgress,
                minHeight: 6,
                color: kAccent2,
                backgroundColor: Colors.white12,
              ),
            ),
          ],
          if (!c.finding && c.pendingBad.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: kWarn, foregroundColor: Colors.black),
                    onPressed: c.addPendingBad,
                    icon: const Icon(Icons.add_circle_outline),
                    label: Text('افزودن ناسالم‌ها (${c.pendingBad.length})'),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                    onPressed: c.dismissPendingBad, child: const Text('نه')),
              ],
            ),
          ],
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

// ───────────────────────── صفحهٔ خانه ─────────────────────────
class HomePage extends StatefulWidget {
  final AppController c;
  final void Function(String) toast;
  final void Function(int) goTab;
  const HomePage(
      {super.key, required this.c, required this.toast, required this.goTab});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2100),
    );
    _syncPulse();
  }

  void _syncPulse() {
    final shouldAnimate = widget.c.animationsEnabled && (widget.c.connected || widget.c.connecting);
    if (shouldAnimate && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!shouldAnimate && _pulse.isAnimating) {
      _pulse.animateTo(0, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
    }
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPulse();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final st = c.status;
    final connected = c.connected;
    final connecting = c.connecting && !connected;
    final color = connected ? kAccent : (connecting ? kWarn : Colors.white54);
    final label = connected
        ? 'اتصال برقرار است'
        : (connecting ? 'در حال برقراری اتصال...' : 'آماده اتصال');

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF182747), kBg, Color(0xFF070B15)],
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 26),
        children: [
          if (c.storageWarning != null)
            AppCard(
              border: kWarn,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: kWarn),
                  const SizedBox(width: 9),
                  Expanded(child: Text(c.storageWarning!, style: const TextStyle(fontSize: 11.5, color: Colors.white70, height: 1.5))),
                ],
              ),
            ),
          if (c.engineStarting)
            AppCard(
              border: kAccent,
              child: Row(
                children: [
                  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: kAccent)),
                  const SizedBox(width: 11),
                  const Expanded(child: Text('در حال راه‌اندازی موتور امن Xray...', style: TextStyle(fontSize: 12.5, color: Colors.white70))),
                ],
              ),
            ),
          if (c.engineError != null)
            AppCard(
              border: kDanger,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('موتور اتصال آماده نیست', style: TextStyle(fontWeight: FontWeight.w800, color: kDanger)),
                  const SizedBox(height: 5),
                  Text(c.engineError!, style: const TextStyle(fontSize: 12, color: Colors.white70)),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: c.engineStarting ? null : () => c.retryEngine(),
                      icon: c.engineStarting
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.refresh),
                      label: Text(c.engineStarting ? 'در حال راه‌اندازی' : 'تلاش دوباره'),
                    ),
                  ),
                ],
              ),
            ),
          AppCard(
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(17),
                  child: Image.asset(
                    'assets/branding/sameni_achaemenid.png',
                    width: 82,
                    height: 82,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('SAMENI VPN', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 1.1)),
                      SizedBox(height: 5),
                      Text('امنیت و آزادی اتصال', style: TextStyle(color: Colors.white70, fontSize: 12.5)),
                      SizedBox(height: 5),
                      Text('PERSIAN EDITION  •  SECURE TUNNEL', style: TextStyle(color: kAccent, fontSize: 9, letterSpacing: 1.0, fontWeight: FontWeight.w700)),
                      SizedBox(height: 4),
                      Text('Xray Core  ${c.coreVersion}', style: TextStyle(color: Colors.white38, fontSize: 10)),
                    ],
                  ),
                ),
                Icon(Icons.verified_user_rounded, color: connected ? kAccent : Colors.white24, size: 25),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) {
                final t = _pulse.value;
                return SizedBox(
                  width: 246,
                  height: 246,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Transform.rotate(
                        angle: t * 0.34,
                        child: Container(
                          width: 236,
                          height: 236,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: color.withOpacity(0.16 + t * 0.18), width: 1.5),
                          ),
                        ),
                      ),
                      Container(
                        width: 208 + t * 7,
                        height: 208 + t * 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: color.withOpacity(0.28), width: 2),
                          boxShadow: [
                            BoxShadow(color: color.withOpacity(0.14 + t * 0.2), blurRadius: 24 + t * 22, spreadRadius: 1 + t * 4),
                          ],
                        ),
                      ),
                      Transform.scale(
                        scale: 0.97 + t * 0.035,
                        child: Material(
                          color: Colors.transparent,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () async {
                              if (c.hapticsEnabled) HapticFeedback.selectionClick();
                              final err = await c.toggle();
                              if (err != null) widget.toast(err);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 450),
                              width: 174,
                              height: 174,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(colors: [color.withOpacity(0.25), const Color(0xFF0D1426), const Color(0xFF090E1B)]),
                                border: Border.all(color: color, width: 3),
                                boxShadow: [BoxShadow(color: color.withOpacity(0.3 + t * 0.2), blurRadius: 34, spreadRadius: 2)],
                              ),
                              child: Center(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 350),
                                  transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: FadeTransition(opacity: animation, child: child)),
                                  child: connecting
                                      ? SizedBox(key: const ValueKey('loading'), width: 58, height: 58, child: CircularProgressIndicator(color: color, strokeWidth: 4))
                                      : Icon(
                                          connected ? Icons.shield_rounded : Icons.power_settings_new_rounded,
                                          key: ValueKey(connected ? 'secure' : 'power'),
                                          size: 76,
                                          color: color,
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 15,
                        right: 39,
                        child: Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: color.withOpacity(0.8), blurRadius: 10)])),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              child: Text(label, key: ValueKey(label), style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: color)),
            ),
          ),
          const SizedBox(height: 7),
          Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                connected ? st.duration : (connecting ? 'در حال مذاکره با سرور...' : 'برای اتصال ضربه بزنید'),
                key: ValueKey('${connected}_${connecting}_${st.duration}'),
                style: const TextStyle(fontSize: 13, color: Colors.white60, letterSpacing: 0.8),
              ),
            ),
          ),
          if (connected)
            Padding(
              padding: const EdgeInsets.only(top: 9),
              child: Center(
                child: OutlinedButton.icon(
                  onPressed: c.connectedPing == -2 ? null : c.pingConnected,
                  icon: c.connectedPing == -2
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.speed_rounded, size: 17),
                  label: Text(c.connectedPing == null
                      ? 'بررسی تأخیر اتصال'
                      : (c.connectedPing! > 0 ? '${c.connectedPing} ms' : 'تست ناموفق • تلاش دوباره')),
                ),
              ),
            ),
          const SizedBox(height: 23),
          if (c.showTrafficStats)
            AppCard(
              child: Row(
                children: [
                  _stat(Icons.arrow_downward_rounded, 'دانلود', '${fmtBytes(st.downloadSpeed)}/s', fmtBytes(st.download), kAccent),
                  Container(width: 1, height: 48, color: Colors.white12),
                  _stat(Icons.arrow_upward_rounded, 'آپلود', '${fmtBytes(st.uploadSpeed)}/s', fmtBytes(st.upload), kAccent2),
                ],
              ),
            ),
          AppCard(
            border: c.optimizing ? kAccent : kAccent2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: kAccent2.withOpacity(0.13),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(Icons.rocket_launch_rounded, color: kAccent2),
                    ),
                    const SizedBox(width: 11),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('بهینه‌سازی سرعت اتصال', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                          SizedBox(height: 3),
                          Text('تست سرورها و انتخاب مسیر کم‌تأخیرتر', style: TextStyle(fontSize: 11, color: Colors.white54)),
                        ],
                      ),
                    ),
                    if (c.optimizing)
                      const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: kAccent2)),
                  ],
                ),
                if (c.optimizing || c.optimizationStatus.isNotEmpty) ...[
                  const SizedBox(height: 11),
                  Text(c.optimizationStatus, style: const TextStyle(fontSize: 11.5, color: Colors.white70, height: 1.5)),
                ],
                if (c.optimizing) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: c.optimizationProgress < 0 ? null : c.optimizationProgress,
                      minHeight: 5,
                      color: kAccent2,
                      backgroundColor: Colors.white12,
                    ),
                  ),
                ],
                const SizedBox(height: 11),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: c.optimizing || c.connecting
                        ? null
                        : () async {
                            if (c.hapticsEnabled) HapticFeedback.lightImpact();
                            final message = await c.optimizeSpeed();
                            if (mounted) widget.toast(message);
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: kAccent2,
                      foregroundColor: const Color(0xFF17120A),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.bolt_rounded),
                    label: Text(c.optimizing ? 'در حال بهینه‌سازی...' : 'بهینه‌سازی و انتخاب بهترین سرور'),
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'این ابزار پینگ و دسترسی سرورها را می‌سنجد و مسیر بهتر VPN را انتخاب می‌کند؛ سرعت پایه اینترنت اپراتور را تغییر نمی‌دهد.',
                  style: TextStyle(fontSize: 10, color: Colors.white38, height: 1.5),
                ),
              ],
            ),
          ),
          if (c.servers.isEmpty || c.finding) FinderCard(c: c, toast: widget.toast),
          AppCard(
            onTap: () => widget.goTab(1),
            child: Row(
              children: [
                const Icon(Icons.dns_rounded, color: kAccent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('سرور انتخابی', style: TextStyle(fontSize: 11.5, color: Colors.white54)),
                    const SizedBox(height: 3),
                    Text(c.currentServer?.name ?? 'سروری انتخاب نشده', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  ]),
                ),
                const Icon(Icons.chevron_left, color: Colors.white38),
              ],
            ),
          ),
          AppCard(
            child: Row(
              children: [
                const Icon(Icons.travel_explore_rounded, color: kAccent2),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () => widget.goTab(2),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('DNS تونل', style: TextStyle(fontSize: 11.5, color: Colors.white54)),
                      const SizedBox(height: 3),
                      Text(c.dnsEnabled ? c.currentDns.name : 'غیرفعال', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      Text(c.currentDns.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.white54)),
                    ]),
                  ),
                ),
                Switch.adaptive(
                  value: c.dnsEnabled,
                  activeColor: kAccent,
                  onChanged: (v) async {
                    final wasConnected = c.connected;
                    await c.setDnsEnabled(v);
                    widget.toast(wasConnected
                        ? 'تنظیم ذخیره شد؛ برای اعمال فوری به صفحه DNS بروید و دکمه اعمال را بزنید'
                        : (v ? 'DNS برای اتصال بعدی فعال شد' : 'DNS سفارشی برای اتصال بعدی خاموش شد'));
                  },
                ),
                IconButton(onPressed: () => widget.goTab(2), icon: const Icon(Icons.tune_rounded, color: Colors.white54)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(IconData icon, String title, String speed, String total, Color color) {
    return Expanded(
      child: Column(
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(title, style: const TextStyle(fontSize: 12, color: Colors.white54)),
          ]),
          const SizedBox(height: 6),
          Text(speed, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          Text('مجموع: $total', style: const TextStyle(fontSize: 11, color: Colors.white38)),
        ],
      ),
    );
  }
}

// ───────────────────────── صفحهٔ سرورها ─────────────────────────
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
                  'لینک‌های vmess / vless / trojan / shadowsocks را بچسبانید. هر لینک را در یک خط بگذارید.',
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
                        toast(n > 0
                            ? '$n سرور اضافه شد'
                            : 'لینک معتبری پیدا نشد');
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
      body: Column(
        children: [
          PageTitle(
            'سرورها',
            subtitle: '${c.servers.length} سرور ذخیره شده',
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FinderCard(c: c, toast: toast),
          ),
          Expanded(
            child: c.servers.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                          'هنوز سروری اضافه نکرده‌اید.\nدکمهٔ «سرور جدید» را بزنید.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white54, height: 1.8)),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                    itemCount: c.servers.length,
                    itemBuilder: (ctx, i) {
                      final s = c.servers[i];
                      final sel = i == c.selectedServer;
                      final p = c.pings[s.link];
                      String pt = '';
                      Color pc = Colors.white54;
                      if (p == -2) {
                        pt = '...';
                      } else if (p == -1) {
                        pt = 'ناموفق';
                        pc = kDanger;
                      } else if (p != null) {
                        pt = '$p ms';
                        pc = p < 300 ? kAccent : kWarn;
                      }
                      return AppCard(
                        border: sel ? kAccent : null,
                        onTap: () {
                          if (c.connected || c.connecting) {
                            toast('برای تغییر سرور، ابتدا اتصال VPN را قطع کنید.');
                          } else {
                            c.selectServer(i);
                          }
                        },
                        child: Row(
                          children: [
                            Icon(
                                sel
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                color: sel ? kAccent : Colors.white38),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(s.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15)),
                                  const SizedBox(height: 2),
                                  Text(s.link.split('://').first.toUpperCase(),
                                      style: const TextStyle(
                                          fontSize: 11, color: Colors.white38)),
                                ],
                              ),
                            ),
                            if (pt.isNotEmpty)
                              Text(pt,
                                  style: TextStyle(
                                      color: pc, fontWeight: FontWeight.w700)),
                            PopupMenuButton<String>(
                              onSelected: (v) async {
                                if (v == 'ping') c.pingServer(s);
                                if (v == 'copy') {
                                  await Clipboard.setData(
                                      ClipboardData(text: s.link));
                                  toast('لینک کپی شد');
                                }
                                if (v == 'del') {
                                  if ((c.connected || c.connecting) && sel) {
                                    toast('برای حذف سرور فعال، ابتدا VPN را قطع کنید.');
                                  } else {
                                    await c.removeServer(i);
                                  }
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                    value: 'ping', child: Text('تست پینگ')),
                                PopupMenuItem(
                                    value: 'copy', child: Text('کپی لینک')),
                                PopupMenuItem(
                                    value: 'del', child: Text('حذف')),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── صفحهٔ تنظیمات کامل ─────────────────────────
class SettingsPage extends StatelessWidget {
  final AppController c;
  final void Function(String) toast;
  final void Function(int) goTab;

  const SettingsPage({
    super.key,
    required this.c,
    required this.toast,
    required this.goTab,
  });

  Widget _reveal(int index, Widget child) {
    if (!c.animationsEnabled) return child;
    final delay = (index * 55).clamp(0, 330).toInt();
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 430 + delay),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, value, content) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 16),
          child: content,
        ),
      ),
    );
  }

  Widget _toggleCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    Color color = kAccent,
  }) {
    return AppCard(
      child: SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        secondary: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color),
        ),
        value: value,
        activeColor: color,
        onChanged: onChanged,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 10.5, color: Colors.white54, height: 1.5)),
      ),
    );
  }

  Widget _section(String title, String subtitle) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 10.5, color: Colors.white38)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      children: [
        const PageTitle('تنظیمات کامل', subtitle: 'شخصی‌سازی، شبکه، عیب‌یابی و اطلاعات برنامه'),
        _reveal(0, AppCard(
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: Image.asset('assets/branding/sameni_achaemenid.png', width: 64, height: 64, fit: BoxFit.cover),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SAMENI VPN', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: 1)),
                    SizedBox(height: 4),
                    Text('نسخه 1.3.0 • Achaemenid Edition', style: TextStyle(fontSize: 11, color: kAccent)),
                    SizedBox(height: 3),
                    Text('مدیریت تجربه اتصال در یکجا', style: TextStyle(fontSize: 10.5, color: Colors.white54)),
                  ],
                ),
              ),
              Icon(Icons.verified_user_rounded, color: c.engineReady ? kAccent : kWarn, size: 25),
            ],
          ),
        )),
        _reveal(1, _section('ظاهر و تجربه کاربری', 'انیمیشن‌ها و رفتار برنامه را مطابق سلیقه‌ات تنظیم کن')),
        _reveal(2, _toggleCard(
          icon: Icons.auto_awesome_rounded,
          title: 'انیمیشن‌های برنامه',
          subtitle: 'حرکت تب‌ها، افکت کارت‌ها و حلقه نورانی اتصال',
          value: c.animationsEnabled,
          onChanged: (v) => c.setAnimationsEnabled(v),
        )),
        _reveal(3, _toggleCard(
          icon: Icons.vibration_rounded,
          title: 'بازخورد لرزشی',
          subtitle: 'لرزش ظریف هنگام فشردن دکمه‌های مهم',
          value: c.hapticsEnabled,
          onChanged: (v) => c.setHapticsEnabled(v),
          color: kAccent2,
        )),
        _reveal(4, _toggleCard(
          icon: Icons.query_stats_rounded,
          title: 'نمایش آمار ترافیک',
          subtitle: 'نمایش لحظه‌ای دانلود، آپلود و حجم مصرف‌شده در صفحه خانه',
          value: c.showTrafficStats,
          onChanged: (v) => c.setShowTrafficStats(v),
          color: const Color(0xFF76A9FF),
        )),
        _reveal(5, _section('شبکه و بهینه‌سازی', 'آزمایش کیفیت سرورها و مدیریت مسیر VPN')),
        _reveal(6, AppCard(
          border: c.optimizing ? kAccent : kAccent2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.rocket_launch_rounded, color: kAccent2, size: 25),
                const SizedBox(width: 10),
                const Expanded(child: Text('بهینه‌سازی سرعت اتصال', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14))),
                if (c.optimizing) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: kAccent2)),
              ]),
              const SizedBox(height: 8),
              Text(
                c.optimizationStatus.isEmpty
                    ? 'تا ۳۱ سرور را با هسته Xray آزمایش می‌کند و کم‌تأخیرترین گزینه را انتخاب می‌کند.'
                    : c.optimizationStatus,
                style: const TextStyle(fontSize: 11, color: Colors.white60, height: 1.5),
              ),
              if (c.optimizing) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(value: c.optimizationProgress < 0 ? null : c.optimizationProgress, color: kAccent2, backgroundColor: Colors.white12),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: c.optimizing || c.connecting ? null : () async {
                    final result = await c.optimizeSpeed();
                    toast(result);
                  },
                  style: FilledButton.styleFrom(backgroundColor: kAccent2, foregroundColor: const Color(0xFF17120A)),
                  icon: const Icon(Icons.bolt_rounded),
                  label: Text(c.optimizing ? 'در حال آزمایش...' : 'شروع بهینه‌سازی'),
                ),
              ),
              const SizedBox(height: 6),
              const Text('نتیجه بر اساس پینگ و دسترسی لحظه‌ای است؛ سرعت اسمی اینترنت اپراتور یا پهنای باند سرور را تضمین نمی‌کند.', style: TextStyle(fontSize: 10, color: Colors.white38, height: 1.5)),
            ],
          ),
        )),
        _reveal(7, AppCard(
          child: Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.dns_rounded, color: kAccent),
                title: const Text('مدیریت سرورها', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                subtitle: Text('${c.servers.length} سرور • ${c.pings.values.where((v) => v > 0).length} سرور تست‌شده', style: const TextStyle(fontSize: 10.5, color: Colors.white54)),
                trailing: const Icon(Icons.chevron_left, color: Colors.white38),
                onTap: () => goTab(1),
              ),
              const Divider(color: Colors.white12, height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.travel_explore_rounded, color: kAccent2),
                title: const Text('تنظیمات DNS', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                subtitle: Text(c.dnsEnabled ? '${c.currentDns.name} • فعال' : 'DNS سفارشی غیرفعال', style: const TextStyle(fontSize: 10.5, color: Colors.white54)),
                trailing: const Icon(Icons.chevron_left, color: Colors.white38),
                onTap: () => goTab(2),
              ),
              const Divider(color: Colors.white12, height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.link_rounded, color: Color(0xFF76A9FF)),
                title: const Text('منابع اشتراک کانفیگ', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                subtitle: Text('${c.customSources.length} منبع سفارشی • فقط HTTPS', style: const TextStyle(fontSize: 10.5, color: Colors.white54)),
                trailing: const Icon(Icons.chevron_left, color: Colors.white38),
                onTap: () => openSourcesDialog(context, c, toast),
              ),
            ],
          ),
        )),
        _reveal(8, _section('عیب‌یابی و نگهداری', 'ابزارهای بررسی وضعیت برنامه')),
        _reveal(9, AppCard(
          child: Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.speed_rounded, color: kAccent),
                title: const Text('آزمایش پینگ همه سرورها', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                trailing: const Icon(Icons.chevron_left, color: Colors.white38),
                onTap: c.servers.isEmpty ? null : () { c.pingAll(); toast('آزمایش پینگ آغاز شد'); },
              ),
              const Divider(color: Colors.white12, height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.search_rounded, color: kAccent2),
                title: const Text('جستجوی سرورهای تازه', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                trailing: const Icon(Icons.chevron_left, color: Colors.white38),
                onTap: c.finding || c.optimizing ? null : () { goTab(1); c.findServers(); },
              ),
              const Divider(color: Colors.white12, height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.cleaning_services_rounded, color: kWarn),
                title: const Text('حذف سرورهای ناموفق', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                subtitle: Text('${c.pings.values.where((v) => v == -1).length} مورد ناموفق', style: const TextStyle(fontSize: 10, color: Colors.white38)),
                trailing: const Icon(Icons.chevron_left, color: Colors.white38),
                onTap: c.hasFailed ? () async { await c.removeFailed(); toast('سرورهای ناموفق حذف شدند'); } : null,
              ),
              const Divider(color: Colors.white12, height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.memory_rounded, color: c.engineReady ? kAccent : kDanger),
                title: const Text('راه‌اندازی دوباره موتور Xray', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                subtitle: Text(c.engineReady ? 'آماده • ${c.coreVersion}' : 'نیازمند بررسی', style: const TextStyle(fontSize: 10, color: Colors.white38)),
                trailing: const Icon(Icons.refresh_rounded, color: Colors.white38),
                onTap: c.engineStarting || c.connected || c.optimizing ? null : () async { await c.retryEngine(); toast(c.engineReady ? 'موتور Xray آماده است' : (c.engineError ?? 'راه‌اندازی ناموفق')); },
              ),
            ],
          ),
        )),
        _reveal(10, AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('وضعیت و اطلاعات', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
              const SizedBox(height: 10),
              _infoRow('وضعیت موتور', c.engineReady ? 'آماده' : 'آماده نیست'),
              _infoRow('نسخه هسته', c.coreVersion),
              _infoRow('تعداد سرورها', '${c.servers.length}'),
              _infoRow('DNS انتخابی', c.dnsEnabled ? c.currentDns.name : 'غیرفعال'),
              _infoRow('انیمیشن‌ها', c.animationsEnabled ? 'فعال' : 'خاموش'),
              _infoRow('بازخورد لرزشی', c.hapticsEnabled ? 'فعال' : 'خاموش'),
              const SizedBox(height: 7),
              const Text('کانفیگ‌های عمومی ممکن است ناپایدار یا متعلق به اشخاص ناشناس باشند؛ برای اطلاعات حساس فقط از سرور مورد اعتماد استفاده کنید.', style: TextStyle(fontSize: 10, color: Colors.white38, height: 1.5)),
            ],
          ),
        )),
      ],
    );
  }

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 11, color: Colors.white54))),
            Flexible(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
          ],
        ),
      );
}

// ───────────────────────── صفحهٔ DNS ─────────────────────────
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

  Widget _tile(DnsPreset d) {
    final c = widget.c;
    final sel = c.selectedDnsId == d.id;
    return AppCard(
      border: sel ? kAccent : null,
      onTap: () {
        c.selectDns(d.id);
        if (c.connected) widget.toast('برای اعمال فوری، دکمه «اعمال روی اتصال فعلی» را بزنید');
      },
      child: Row(
        children: [
          Icon(sel ? Icons.radio_button_checked : Icons.radio_button_off,
              color: sel ? kAccent : Colors.white38),
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
                    style:
                        const TextStyle(fontSize: 11.5, color: Colors.white54)),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        const PageTitle('DNS',
            subtitle: 'مدیریت مستقل تنظیم DNS و نحوه اعمال آن در تونل'),
        AppCard(
          border: c.dnsEnabled ? kAccent : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(color: kAccent.withOpacity(0.12), borderRadius: BorderRadius.circular(13)),
                    child: const Icon(Icons.dns_rounded, color: kAccent),
                  ),
                  const SizedBox(width: 11),
                  const Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('فعال‌سازی DNS در تونل', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                      SizedBox(height: 3),
                      Text('DNS انتخابی داخل اتصال VPN استفاده شود', style: TextStyle(fontSize: 11.5, color: Colors.white54)),
                    ]),
                  ),
                  Switch.adaptive(
                    value: c.dnsEnabled,
                    activeColor: kAccent,
                    onChanged: (v) async {
                      await c.setDnsEnabled(v);
                      widget.toast(c.connected
                          ? 'تنظیم ذخیره شد؛ برای اعمال روی اتصال فعلی دکمه پایین را بزنید'
                          : 'وضعیت DNS برای اتصال بعدی ذخیره شد');
                    },
                  ),
                ],
              ),
              const Divider(color: Colors.white12, height: 22),
              CheckboxListTile(
                value: c.applyDnsOnConnect,
                onChanged: c.dnsEnabled ? (v) => c.setApplyDnsOnConnect(v ?? false) : null,
                activeColor: kAccent,
                checkColor: Colors.black,
                controlAffinity: ListTileControlAffinity.trailing,
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('اعمال خودکار هنگام اتصال', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                subtitle: const Text('هر بار VPN را وصل می‌کنید، این DNS روی تونل اعمال شود.', style: TextStyle(fontSize: 11, color: Colors.white54)),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: kAccent, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 13)),
                  onPressed: () async {
                    final result = await c.applyDnsNow();
                    widget.toast(result ?? 'درخواست اعمال تنظیم DNS ارسال شد');
                  },
                  icon: const Icon(Icons.bolt_rounded),
                  label: Text(c.connected ? 'اعمال تنظیم DNS روی اتصال فعلی' : 'ذخیره برای اتصال بعدی'),
                ),
              ),
              const SizedBox(height: 9),
              const Text('اعمال فوری، تونل VPN را یک‌بار راه‌اندازی مجدد می‌کند. این DNS فقط داخل تونل SAMENI اعمال می‌شود؛ تغییر DNS سراسری اندروید باید از تنظیمات Private DNS گوشی انجام شود.', style: TextStyle(fontSize: 10.5, color: Colors.white38, height: 1.5)),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 4, 4, 8),
          child: Text('DNS دلخواه خودتان',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        ),
        AppCard(
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
                      backgroundColor: kAccent, foregroundColor: Colors.black),
                  onPressed: () async {
                    final err = await c.addCustomDns(
                        nameC.text, p1C.text, p2C.text);
                    if (err != null) {
                      widget.toast(err);
                    } else {
                      nameC.clear();
                      p1C.clear();
                      p2C.clear();
                      FocusScope.of(context).unfocus();
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
        if (c.customDns.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 8, 4, 8),
            child: Text('DNSهای شما',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ),
          ...c.customDns.map(_tile),
        ],
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 8, 4, 8),
          child: Text('DNSهای پیش‌فرض',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        ),
        ...kDefaultDns.map(_tile),
      ],
    );
  }
}
