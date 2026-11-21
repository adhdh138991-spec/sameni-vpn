import 'dart:async';
import 'dart:convert';
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
      name: 'AdGuard (بدون تبلیغ)',
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
      primary: 'https://cloudflare-dns.com/dns-query',
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

// ───────────────────────── کنترلر ─────────────────────────
class AppController extends ChangeNotifier {
  late final FlutterV2ray v2ray;
  late SharedPreferences prefs;

  V2RayStatus status = V2RayStatus();
  List<ServerItem> servers = [];
  List<DnsPreset> customDns = [];
  int selectedServer = -1;
  String selectedDnsId = 'auto';
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

  Future<void> init() async {
    v2ray = FlutterV2ray(onStatusChanged: (s) {
      status = s;
      if (s.state == 'CONNECTED' || s.state == 'DISCONNECTED') busy = false;
      notifyListeners();
    });
    await v2ray.initializeV2Ray();
    prefs = await SharedPreferences.getInstance();
    _load();
    ready = true;
    notifyListeners();
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
      selectedServer = prefs.getInt('selected_server') ?? -1;
      selectedDnsId = prefs.getString('selected_dns') ?? 'auto';
      if (selectedServer >= servers.length) selectedServer = -1;
      if (selectedServer < 0 && servers.isNotEmpty) selectedServer = 0;
    } catch (_) {}
  }

  Future<void> _save() async {
    await prefs.setString(
        'servers',
        jsonEncode(servers
            .map((e) => {'name': e.name, 'link': e.link})
            .toList()));
    await prefs.setString(
        'custom_dns', jsonEncode(customDns.map((e) => e.toJson()).toList()));
    await prefs.setInt('selected_server', selectedServer);
    await prefs.setString('selected_dns', selectedDnsId);
  }

  // ───── اتصال ─────
  String _buildConfig(String link) {
    final parsed = FlutterV2ray.parseFromURL(link);
    final cfg = jsonDecode(parsed.getFullConfiguration())
        as Map<String, dynamic>;
    final dns = currentDns;
    if (dns.primary.isNotEmpty) {
      cfg['dns'] = {'servers': dns.servers};
    }
    return jsonEncode(cfg);
  }

  Future<String?> toggle() async {
    if (connected || status.state == 'CONNECTING') {
      v2ray.stopV2Ray();
      busy = false;
      notifyListeners();
      return null;
    }
    final s = currentServer;
    if (s == null) return 'ابتدا از تب «سرورها» یک سرور اضافه کنید';
    try {
      final cfg = _buildConfig(s.link);
      if (!await v2ray.requestPermission()) return 'دسترسی VPN داده نشد';
      busy = true;
      notifyListeners();
      v2ray.startV2Ray(
        remark: s.name,
        config: cfg,
        proxyOnly: false,
        bypassSubnets: null,
        blockedApps: null,
      );
      Future.delayed(const Duration(seconds: 25), () {
        if (busy && !connected) {
          busy = false;
          notifyListeners();
        }
      });
    } catch (e) {
      busy = false;
      notifyListeners();
      return 'کانفیگ این سرور نامعتبر است';
    }
    return null;
  }

  // ───── سرورها ─────
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
    servers.removeAt(i);
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
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kAccent,
          brightness: Brightness.dark,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: kCard,
          indicatorColor: kAccent.withOpacity(0.18),
        ),
      ),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const Shell(),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  final ctrl = AppController();
  int tab = 0;

  @override
  void initState() {
    super.initState();
    ctrl.init();
  }

  @override
  void dispose() {
    ctrl.dispose();
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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (context, _) {
        if (!ctrl.ready) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator(color: kAccent)));
        }
        return Scaffold(
          body: SafeArea(
            child: IndexedStack(
              index: tab,
              children: [
                HomePage(
                    c: ctrl,
                    toast: toast,
                    goTab: (i) => setState(() => tab = i)),
                ServersPage(c: ctrl, toast: toast),
                DnsPage(c: ctrl, toast: toast),
              ],
            ),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: (i) => setState(() => tab = i),
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.shield_outlined),
                  selectedIcon: Icon(Icons.shield, color: kAccent),
                  label: 'خانه'),
              NavigationDestination(
                  icon: Icon(Icons.dns_outlined),
                  selectedIcon: Icon(Icons.dns, color: kAccent),
                  label: 'سرورها'),
              NavigationDestination(
                  icon: Icon(Icons.travel_explore_outlined),
                  selectedIcon: Icon(Icons.travel_explore, color: kAccent),
                  label: 'DNS'),
            ],
          ),
        );
      },
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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border ?? Colors.white10),
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

// ───────────────────────── صفحهٔ خانه ─────────────────────────
class HomePage extends StatelessWidget {
  final AppController c;
  final void Function(String) toast;
  final void Function(int) goTab;
  const HomePage(
      {super.key, required this.c, required this.toast, required this.goTab});

  @override
  Widget build(BuildContext context) {
    final st = c.status;
    final connected = c.connected;
    final connecting = c.connecting && !connected;
    final color = connected ? kAccent : (connecting ? kWarn : Colors.white38);
    final label =
        connected ? 'متصل شد' : (connecting ? 'در حال اتصال...' : 'قطع است');

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF131E42), kBg],
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [kAccent, kAccent2]),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.shield, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              const Text('SAMENI VPN',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.4)),
            ],
          ),
          const SizedBox(height: 36),
          Center(
            child: GestureDetector(
              onTap: () async {
                final err = await c.toggle();
                if (err != null) toast(err);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 350),
                width: 190,
                height: 190,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    color.withOpacity(0.28),
                    color.withOpacity(0.06),
                  ]),
                  border: Border.all(color: color, width: 3),
                  boxShadow: [
                    BoxShadow(
                        color: color.withOpacity(connected ? 0.55 : 0.2),
                        blurRadius: connected ? 50 : 20,
                        spreadRadius: connected ? 6 : 0),
                  ],
                ),
                child: Center(
                  child: connecting
                      ? SizedBox(
                          width: 54,
                          height: 54,
                          child: CircularProgressIndicator(
                              color: color, strokeWidth: 4))
                      : Icon(Icons.power_settings_new_rounded,
                          size: 78, color: color),
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          Center(
            child: Text(label,
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800, color: color)),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              connected ? st.duration : 'برای اتصال ضربه بزنید',
              style: const TextStyle(
                  fontSize: 16, color: Colors.white60, letterSpacing: 1.5),
            ),
          ),
          const SizedBox(height: 26),
          AppCard(
            child: Row(
              children: [
                _stat(Icons.arrow_downward_rounded, 'دانلود',
                    '${fmtBytes(st.downloadSpeed)}/s', fmtBytes(st.download),
                    kAccent),
                Container(width: 1, height: 46, color: Colors.white12),
                _stat(Icons.arrow_upward_rounded, 'آپلود',
                    '${fmtBytes(st.uploadSpeed)}/s', fmtBytes(st.upload),
                    kAccent2),
              ],
            ),
          ),
          AppCard(
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
                const Icon(Icons.chevron_left, color: Colors.white38),
              ],
            ),
          ),
          AppCard(
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11.5, color: Colors.white54)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_left, color: Colors.white38),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(IconData icon, String title, String speed, String total,
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
          Text(speed,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800)),
          Text('مجموع: $total',
              style: const TextStyle(fontSize: 11, color: Colors.white38)),
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
              if (c.servers.isNotEmpty)
                TextButton.icon(
                  onPressed: c.pingAll,
                  icon: const Icon(Icons.speed, size: 18),
                  label: const Text('تست همه'),
                ),
            ],
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
                        onTap: () => c.selectServer(i),
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
                                if (v == 'del') c.removeServer(i);
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
        if (c.connected) widget.toast('برای اعمال DNS، یک بار قطع و دوباره وصل شوید');
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
            subtitle: 'DNS انتخابی در اتصال بعدی روی کانفیگ اعمال می‌شود'),
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