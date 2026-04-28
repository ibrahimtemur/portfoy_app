import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:ui';

void main() {
  runApp(const PortfoyApp());
}

class Asset {
  String id;
  double lot;
  double maliyet;
  String apiTicker;
  double guncelFiyat;

  Asset({required this.id, required this.lot, required this.maliyet, required this.apiTicker, required this.guncelFiyat});

  Map<String, dynamic> toJson() => {'id': id, 'lot': lot, 'maliyet': maliyet, 'apiTicker': apiTicker, 'guncelFiyat': guncelFiyat};
  
  factory Asset.fromJson(Map<String, dynamic> json) => Asset(
      id: json['id'], lot: json['lot'], maliyet: json['maliyet'], apiTicker: json['apiTicker'], guncelFiyat: json['guncelFiyat']);

  double get toplamMaliyet => lot * maliyet;
  double get toplamDeger => lot * guncelFiyat;
  double get kzMiktari => toplamDeger - toplamMaliyet;
  double get kzOrani => (guncelFiyat - maliyet) / maliyet;
}

// main.dart içine şu PortfoyApp yapısını yapıştır:

class PortfoyApp extends StatefulWidget {
  const PortfoyApp({super.key});

  static PortfoyAppState of(BuildContext context) =>
      context.findAncestorStateOfType<PortfoyAppState>()!;

  @override
  State<PortfoyApp> createState() => PortfoyAppState();
}

class PortfoyAppState extends State<PortfoyApp> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('isDarkMode');
    if (isDark != null) {
      setState(() {
        _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
      });
    }
  }

  void toggleTheme(bool isDarkNow) async {
    setState(() {
      _themeMode = isDarkNow ? ThemeMode.light : ThemeMode.dark;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', !isDarkNow);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Canlı Portföyüm',
      
      // 1. ADIM: Tema Modunu Sisteme Bağla
      themeMode: _themeMode, 
      
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {PointerDeviceKind.mouse, PointerDeviceKind.touch, PointerDeviceKind.stylus, PointerDeviceKind.trackpad},
      ),
      
      // 2. ADIM: Aydınlık Tema (Gündüz Modu)
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.grey[100],
        cardColor: Colors.white, // Kartlar gündüz beyaz
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF263238), foregroundColor: Colors.white),
      ),
      
      // 3. ADIM: Koyu Tema (Karanlık Mod)
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black, // Simsiyah arka plan
        cardColor: const Color(0xFF1E1E1E),   // Koyu gri kartlar
        appBarTheme: const AppBarTheme(backgroundColor: Colors.black, foregroundColor: Colors.white),
        iconTheme: const IconThemeData(color: Colors.white70),
      ),
      
      home: const AnaEkran(),
    );
  }
}

class AnaEkran extends StatefulWidget {
  const AnaEkran({super.key});

  @override
  State<AnaEkran> createState() => _AnaEkranState();
}

class _AnaEkranState extends State<AnaEkran> {
  List<Asset> portfoy = [];
  String _sonGuncellemeText = "Son Güncelleme: Bekleniyor..."; 

  bool _bakiyeGizli = false;
  bool _detayliGorunum = true;

  String _sonSiralamaKriteri = '';
  bool _siralamaArtan = false;

  final PageController _pageController = PageController(initialPage: 1);
  int _currentPage = 1;

  final TextEditingController _kodController = TextEditingController();
  final TextEditingController _lotController = TextEditingController();
  final TextEditingController _maliyetController = TextEditingController();

  final NumberFormat _paraFormatter = NumberFormat('#,##0.00', 'tr_TR');
  final NumberFormat _lotFormatter = NumberFormat('#,##0', 'tr_TR');

  @override
  void initState() {
    super.initState();
    _loadPortfoy();
  }

  Future<void> _loadPortfoy() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('portfoy_verisi');
    final String? kayitliZaman = prefs.getString('son_guncelleme_zamani');
    final bool? bakiyeGizliKayit = prefs.getBool('bakiye_gizli');
    
    if (kayitliZaman != null) {
      _sonGuncellemeText = kayitliZaman;
    }

    if (bakiyeGizliKayit != null) {
      _bakiyeGizli = bakiyeGizliKayit;
    }

    if (data != null) {
      setState(() {
        Iterable l = json.decode(data);
        portfoy = List<Asset>.from(l.map((model) => Asset.fromJson(model)));
      });
    } else {
      setState(() {
        portfoy = [];
      });
      _savePortfoy();
    }
  }

  Future<void> _savePortfoy() async {
    final prefs = await SharedPreferences.getInstance();
    final String encodedData = json.encode(portfoy.map((e) => e.toJson()).toList());
    await prefs.setString('portfoy_verisi', encodedData);
    await prefs.setString('son_guncelleme_zamani', _sonGuncellemeText);
  }

  Future<void> _toggleBakiyeGizli() async {
    setState(() {
      _bakiyeGizli = !_bakiyeGizli;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('bakiye_gizli', _bakiyeGizli);
  }

  Future<void> _fiyatlariGuncelle() async {
    for (var hisse in portfoy) {
      if (hisse.id == 'GRAM ALTIN') {
        try {
          final url = Uri.parse('https://finans.truncgil.com/today.json');
          final response = await http.get(url);

          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            String altinStr = data['gram-altin']['Satış']; 
            
            altinStr = altinStr.replaceAll('.', '').replaceAll(',', '.');
            
            setState(() {
              hisse.guncelFiyat = double.parse(altinStr);
            });
          }
        } catch (e) {
          debugPrint('Altın verisi çekilemedi: $e');
        }
        continue; 
      }

      if (hisse.apiTicker.isEmpty) continue; 

      try {
        final url = Uri.parse('https://query1.finance.yahoo.com/v8/finance/chart/${hisse.apiTicker}');
        final response = await http.get(url);

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          double canliFiyat = data['chart']['result'][0]['meta']['regularMarketPrice'].toDouble();
          
          setState(() {
            hisse.guncelFiyat = canliFiyat;
          });
        }
      } catch (e) {
        debugPrint('${hisse.id} için hisse verisi çekilemedi: $e');
      }
    }

    final simdi = DateTime.now();
    final saat = simdi.hour.toString().padLeft(2, '0');
    final dakika = simdi.minute.toString().padLeft(2, '0');
    final saniye = simdi.second.toString().padLeft(2, '0');
    
    setState(() {
      _sonGuncellemeText = "Son Güncelleme: $saat:$dakika:$saniye";
    });

    _savePortfoy();
  }

  // YENİ: SIRALAMA FONKSİYONU
  void _listeyiSirala(String kriter) {
    setState(() {
      if (_sonSiralamaKriteri == kriter) {
        _siralamaArtan = !_siralamaArtan;
      } else {
        _sonSiralamaKriteri = kriter;
        _siralamaArtan = (kriter == 'isim') ? true : false; // İsim için A-Z başlasın, diğerleri azalan başlasın
      }

      if (kriter == 'deger') {
        if (_siralamaArtan) {
          portfoy.sort((a, b) => a.toplamDeger.compareTo(b.toplamDeger));
        } else {
          portfoy.sort((a, b) => b.toplamDeger.compareTo(a.toplamDeger));
        }
      } else if (kriter == 'kar') {
        if (_siralamaArtan) {
          portfoy.sort((a, b) => a.kzMiktari.compareTo(b.kzMiktari));
        } else {
          portfoy.sort((a, b) => b.kzMiktari.compareTo(a.kzMiktari));
        }
      } else if (kriter == 'isim') {
        if (_siralamaArtan) {
          portfoy.sort((a, b) => a.id.compareTo(b.id));
        } else {
          portfoy.sort((a, b) => b.id.compareTo(a.id));
        }
      }
    });
    _savePortfoy();
  }

  void _hisseEkleDialogGoster() {
    _kodController.clear();
    _lotController.clear();
    _maliyetController.clear();
    
    showDialog(
      context: context,
      builder: (context) {
        bool yukleniyor = false;
        String? hataMetni;

        return StatefulBuilder(builder: (ctx, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Yeni Hisse Ekle', style: TextStyle(fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _kodController,
                  decoration: InputDecoration(
                    labelText: 'Hisse Kodu (Örn: THYAO)',
                    border: const OutlineInputBorder(),
                    errorText: hataMetni,
                  ),
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (_) { if (hataMetni != null) setDialogState(() => hataMetni = null); },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _lotController,
                  decoration: const InputDecoration(labelText: 'Lot Miktarı', border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _maliyetController,
                  decoration: const InputDecoration(labelText: 'Maliyet (TL)', border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: yukleniyor ? null : () => Navigator.pop(ctx),
                child: const Text('İptal', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey[900]),
                onPressed: yukleniyor ? null : () async {
                  final String kod = _kodController.text.trim().toUpperCase();
                  final double lot = double.tryParse(_lotController.text.replaceAll(',', '.')) ?? 0;
                  final double maliyet = double.tryParse(_maliyetController.text.replaceAll(',', '.')) ?? 0;

                  if (kod.isEmpty || lot <= 0 || maliyet <= 0) {
                    setDialogState(() => hataMetni = 'Tüm alanları doğru doldurun.');
                    return;
                  }

                  // GRAM ALTIN özel durum – doğrulama atla
                  if (kod == 'GRAM ALTIN') {
                    setState(() {
                      portfoy.add(Asset(id: kod, lot: lot, maliyet: maliyet, apiTicker: '', guncelFiyat: maliyet));
                    });
                    _savePortfoy();
                    Navigator.pop(ctx);
                    _fiyatlariGuncelle();
                    return;
                  }

                  // Yahoo Finance ile ticker doğrulama (fiyat endpointi ile aynı)
                  setDialogState(() { yukleniyor = true; hataMetni = null; });
                  try {
                    final ticker = '$kod.IS';
                    final resp = await http.get(
                      Uri.parse('https://query1.finance.yahoo.com/v8/finance/chart/$ticker?interval=1d&range=1d'),
                    ).timeout(const Duration(seconds: 8));

                    bool gecerli = false;
                    if (resp.statusCode == 200) {
                      final data = json.decode(resp.body);
                      final result = data['chart']?['result'] as List?;
                      gecerli = result != null && result.isNotEmpty;
                    }

                    if (!ctx.mounted) return;

                    if (gecerli) {
                      setState(() {
                        portfoy.add(Asset(id: kod, lot: lot, maliyet: maliyet, apiTicker: '$kod.IS', guncelFiyat: maliyet));
                      });
                      _savePortfoy();
                      Navigator.pop(ctx);
                      _fiyatlariGuncelle();
                    } else {
                      setDialogState(() {
                        yukleniyor = false;
                        hataMetni = '"$kod" geçerli bir BIST hisse kodu değil.';
                      });
                    }
                  } catch (e) {
                    if (!ctx.mounted) return;
                    setDialogState(() {
                      yukleniyor = false;
                      hataMetni = 'Bağlantı hatası. İnternet bağlantınızı kontrol edin.';
                    });
                  }
                },
                child: yukleniyor
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Ekle', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        });
      },
    );
  }

  // YENİ: DÜZENLEME PENCERESİ
  void _hisseDuzenleDialogGoster(int index) {
    final hisse = portfoy[index];
    _kodController.text = hisse.id;
    _lotController.text = hisse.lot.toString();
    _maliyetController.text = hisse.maliyet.toString();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('${hisse.id} Düzenle', style: const TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _kodController,
                decoration: const InputDecoration(labelText: 'Hisse Kodu', border: OutlineInputBorder()),
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _lotController,
                decoration: const InputDecoration(labelText: 'Yeni Lot Miktarı', border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _maliyetController,
                decoration: const InputDecoration(labelText: 'Yeni Maliyet (TL)', border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey[900]),
              onPressed: () {
                if (_kodController.text.isNotEmpty && _lotController.text.isNotEmpty && _maliyetController.text.isNotEmpty) {
                  String yeniKod = _kodController.text.trim().toUpperCase();
                  double yeniLot = double.tryParse(_lotController.text.replaceAll(',', '.')) ?? 0;
                  double yeniMaliyet = double.tryParse(_maliyetController.text.replaceAll(',', '.')) ?? 0;
                  String yeniTicker = yeniKod == 'GRAM ALTIN' ? '' : '$yeniKod.IS';

                  setState(() {
                    portfoy[index] = Asset(
                      id: yeniKod,
                      lot: yeniLot,
                      maliyet: yeniMaliyet,
                      apiTicker: yeniTicker,
                      guncelFiyat: (yeniKod == hisse.id) ? hisse.guncelFiyat : yeniMaliyet, // Eğer kod değişmediyse eski fiyatı koru
                    );
                  });
                  
                  _savePortfoy();
                  Navigator.pop(context);
                  if (yeniKod != hisse.id) _fiyatlariGuncelle(); // İsim değiştiyse yeni fiyat çek
                }
              },
              child: const Text('Kaydet', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  double get genelToplamMaliyet => portfoy.isEmpty ? 0 : portfoy.fold(0, (sum, item) => sum + item.toplamMaliyet);
  double get genelToplamDeger => portfoy.isEmpty ? 0 : portfoy.fold(0, (sum, item) => sum + item.toplamDeger);
  double get genelKzMiktari => genelToplamDeger - genelToplamMaliyet;
  double get genelKzOrani => genelToplamMaliyet == 0 ? 0 : genelKzMiktari / genelToplamMaliyet;

    @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Canlı Portföyüm', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (Widget child, Animation<double> animation) {
                return ScaleTransition(
                  scale: animation,
                  child: RotationTransition(
                    turns: Tween<double>(begin: 0.5, end: 1.0).animate(animation),
                    child: child,
                  ),
                );
              },
              child: Theme.of(context).brightness == Brightness.dark
                  ? const Icon(Icons.light_mode, key: ValueKey('light'), color: Colors.amber, size: 28)
                  : const Icon(Icons.dark_mode, key: ValueKey('dark'), color: Colors.white, size: 28),
            ),
            onPressed: () {
              final isDark = Theme.of(context).brightness == Brightness.dark;
              PortfoyApp.of(context).toggleTheme(isDark);
            },
          ),
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white, size: 28),
            onPressed: _hisseEkleDialogGoster,
          ),
          const SizedBox(width: 8),
        ],
      ),
      // FloatingActionButton burada artık yok!
      body: Column(
        children: [
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() {
                  _currentPage = index;
                });
              },
              children: [
                // 0. SAYFA: Haber & Bilanço
                HaberEkrani(portfoy: portfoy),
                // 1. SAYFA: Özet ve Pasta Grafiği
                RefreshIndicator(
                  onRefresh: _fiyatlariGuncelle,
                  color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.blueGrey[900],
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(
                      children: [
                        _buildToplamKart(),
                        _buildPastaGrafigi(),
                      ],
                    ),
                  ),
                ),
                // 2. SAYFA: Varlık Detayları Listesi
                RefreshIndicator(
                  onRefresh: _fiyatlariGuncelle,
                  color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.blueGrey[900],
                  child: _buildHisseListesi(),
                ),
              ],
            ),
          ),
          // SAYFA GÖSTERGESİ (Page Indicator)
          Padding(
            padding: const EdgeInsets.only(bottom: 16.0, top: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildPageIndicator(0),
                _buildPageIndicator(1),
                _buildPageIndicator(2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageIndicator(int pageIndex) {
    bool isSelected = _currentPage == pageIndex;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 4.0),
      height: 8.0,
      width: isSelected ? 24.0 : 8.0,
      decoration: BoxDecoration(
        color: isSelected 
            ? (Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.blueGrey[900]) 
            : Colors.grey.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4.0),
      ),
    );
  }

  Widget _buildToplamKart() {
    bool kardayiz = genelKzMiktari >= 0;
    Color durumRengi = kardayiz ? Colors.green : Colors.red;
    String isaret = kardayiz ? '+' : (genelKzMiktari == 0 ? '' : '-');

    return Container(
      margin: const EdgeInsets.only(left: 16.0, right: 16.0, top: 16.0, bottom: 8.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 5)),
        ],
      ),
      child: Column(
        children: [
          const Text('TOPLAM PORTFÖY DEĞERİ', style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _bakiyeGizli ? '*****' : '${_paraFormatter.format(genelToplamDeger)} TL',
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _toggleBakiyeGizli,
                child: Icon(
                  _bakiyeGizli ? Icons.visibility_off : Icons.visibility,
                  color: Colors.grey[400],
                  size: 26,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Ana Para', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  Text(
                    _bakiyeGizli ? '*****' : '${_paraFormatter.format(genelToplamMaliyet)} TL', 
                    style: const TextStyle(fontWeight: FontWeight.w600)
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Kâr / Zarar', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  Text(
                    _bakiyeGizli ? '*****' : '$isaret${_paraFormatter.format(genelKzMiktari.abs())} TL ($isaret%${_paraFormatter.format((genelKzOrani * 100).abs())})',
                    style: TextStyle(color: _bakiyeGizli ? null : durumRengi, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, thickness: 1),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.access_time, size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Text(
                _sonGuncellemeText,
                style: const TextStyle(color: Colors.grey, fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildPastaGrafigi() {
    if (portfoy.isEmpty || genelToplamDeger == 0) return const SizedBox.shrink();

    List<Color> renkler = [
      const Color(0xFF264653), const Color(0xFF2A9D8F), const Color(0xFFE9C46A),
      const Color(0xFFF4A261), const Color(0xFFE76F51), const Color(0xFF8AB17D),
      const Color(0xFFE07A5F), const Color(0xFF3D5A80), const Color(0xFF98C1D9),
    ];

    List<Asset> siraliPortfoy = List.from(portfoy);
    siraliPortfoy.sort((a, b) => b.toplamDeger.compareTo(a.toplamDeger));

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 8.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 5)),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            height: 160,
            width: 160,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 40,
                sections: siraliPortfoy.asMap().entries.map((entry) {
                  final index = entry.key;
                  final hisse = entry.value;
                  final oran = (hisse.toplamDeger / genelToplamDeger) * 100;

                  return PieChartSectionData(
                    color: renkler[index % renkler.length],
                    value: oran,
                    title: oran > 5 ? '%${oran.toStringAsFixed(0)}' : '',
                    radius: 40,
                    titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Column(
            children: List.generate(
              ((siraliPortfoy.length.clamp(0, 9)) / 2).ceil(),
              (rowIndex) {
                final leftIdx = rowIndex * 2;
                final rightIdx = rowIndex * 2 + 1;

                Widget buildItem(int idx) {
                  final h = siraliPortfoy[idx];
                  final o = (h.toplamDeger / genelToplamDeger) * 100;
                  return Row(
                    children: [
                      Container(
                        width: 11, height: 11,
                        decoration: BoxDecoration(color: renkler[idx % renkler.length], shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(h.id, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                      ),
                      Text('%${o.toStringAsFixed(1)}', style: const TextStyle(fontSize: 13, color: Colors.blueGrey, fontWeight: FontWeight.bold)),
                    ],
                  );
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10.0),
                  child: Row(
                    children: [
                      Expanded(child: buildItem(leftIdx)),
                      if (rightIdx < siraliPortfoy.length && rightIdx <= 8) ...[
                        const SizedBox(width: 16),
                        Expanded(child: buildItem(rightIdx)),
                      ] else
                        const Expanded(child: SizedBox()),
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

  Widget _buildHisseListesi() {
    if (portfoy.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32.0),
        child: Center(child: Text("Henüz hisse eklenmedi.")),
      );
    }

    double anlikToplamDeger = genelToplamDeger;

    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: portfoy.length,
      padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 88.0),
      header: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 0.0, vertical: 8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Text('Varlık Detayları', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                const SizedBox(width: 2),
                SizedBox(
                  width: 36,
                  height: 36,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      _detayliGorunum ? Icons.unfold_less : Icons.unfold_more,
                      color: Colors.blueGrey,
                      size: 20,
                    ),
                    tooltip: _detayliGorunum ? 'Detayları gizle' : 'Detayları göster',
                    onPressed: () => setState(() => _detayliGorunum = !_detayliGorunum),
                  ),
                ),
              ],
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.sort, color: Colors.blueGrey),
              tooltip: 'Sırala',
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              onSelected: _listeyiSirala,
              itemBuilder: (BuildContext context) {
                String degerText = (_sonSiralamaKriteri == 'deger' && !_siralamaArtan) ? 'En Düşük Değerli' : 'En Değerli';
                String karText = (_sonSiralamaKriteri == 'kar' && !_siralamaArtan) ? 'En Zararlı' : 'En Kârlı';
                String isimText = (_sonSiralamaKriteri == 'isim' && _siralamaArtan) ? 'Z - A' : 'A - Z';
                return <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(value: 'deger', child: Text(degerText)),
                  const PopupMenuDivider(),
                  PopupMenuItem<String>(value: 'kar', child: Text(karText)),
                  const PopupMenuDivider(),
                  PopupMenuItem<String>(value: 'isim', child: Text(isimText)),
                ];
              },
            ),
          ],
        ),
      ),
      onReorder: (int oldIndex, int newIndex) {
        setState(() {
          if (newIndex > oldIndex) newIndex -= 1; // Sürüklerken indeks kaymasını önler
          final item = portfoy.removeAt(oldIndex);
          portfoy.insert(newIndex, item);
        });
        _savePortfoy(); // Yeni sıralamayı cihaza kaydet
      },
      itemBuilder: (context, index) {
        final hisse = portfoy[index];
        final kardayiz = hisse.kzMiktari >= 0;
        final durumRengi = kardayiz ? Colors.green : Colors.red;
        
        final dagilimOrani = anlikToplamDeger == 0 ? 0.0 : (hisse.toplamDeger / anlikToplamDeger);
        String isaret = kardayiz ? '+' : (hisse.kzMiktari == 0 ? '' : '-');

        return ReorderableDelayedDragStartListener(
          key: ObjectKey(hisse),
          index: index,
          child: Slidable(
            key: ValueKey('${hisse.id}_slidable'),
            startActionPane: ActionPane(
              motion: const DrawerMotion(),
              extentRatio: 0.25,
              children: [
                SlidableAction(
                  onPressed: (_) => _hisseDuzenleDialogGoster(index),
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  icon: Icons.edit,
                  label: 'Düzenle',
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                ),
              ],
            ),
            endActionPane: ActionPane(
              motion: const DrawerMotion(),
              extentRatio: 0.25,
              children: [
                SlidableAction(
                  onPressed: (_) {
                    final silinenHisse = hisse;
                    final silinenIndex = index;
                    setState(() {
                      portfoy.removeAt(index);
                    });
                    _savePortfoy();
                    ScaffoldMessenger.of(context).clearSnackBars();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        behavior: SnackBarBehavior.floating,
                        margin: EdgeInsets.only(
                          bottom: 20,
                          left: MediaQuery.of(context).size.width * 0.3,
                          right: MediaQuery.of(context).size.width * 0.3,
                        ),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        content: Center(
                          child: GeriAlSnackBarContent(
                            onGeriAl: () {
                              ScaffoldMessenger.of(context).hideCurrentSnackBar();
                              setState(() {
                                if (silinenIndex > portfoy.length) {
                                  portfoy.add(silinenHisse);
                                } else {
                                  portfoy.insert(silinenIndex, silinenHisse);
                                }
                              });
                              _savePortfoy();
                            },
                          ),
                        ),
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  },
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  icon: Icons.delete_outline,
                  label: 'Sil',
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(16)),
                ),
              ],
            ),
            child: Card(
              elevation: 3,
              margin: const EdgeInsets.only(bottom: 14.0),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.blueGrey[800] : Colors.blueGrey[100],
                              child: Text(
                                hisse.id.isNotEmpty ? hisse.id.substring(0, 1) : '?', 
                                style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.blueGrey)
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(hisse.id, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text('Toplam Değer', style: TextStyle(color: Colors.grey, fontSize: 11)),
                            Text('${_paraFormatter.format(hisse.toplamDeger)} TL', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          ],
                        ),
                      ],
                    ),
                    if (_detayliGorunum) ...[
                      const Divider(height: 24, thickness: 1),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildInfoColumn('Lot', _lotFormatter.format(hisse.lot)),
                          _buildInfoColumn('Maliyet', '${_paraFormatter.format(hisse.maliyet)} ₺'),
                          _buildInfoColumn('Güncel', '${_paraFormatter.format(hisse.guncelFiyat)} ₺'),
                          _buildInfoColumn('Dağılım', '%${_paraFormatter.format(dagilimOrani * 100)}', renk: Colors.blueGrey[700]),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildInfoColumn('K/Z Miktarı', '$isaret${_paraFormatter.format(hisse.kzMiktari.abs())} ₺', renk: durumRengi),
                          _buildInfoColumn('K/Z Oranı', '$isaret%${_paraFormatter.format((hisse.kzOrani * 100).abs())}', renk: durumRengi),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );

      },
    );
  }

  Widget _buildInfoColumn(String baslik, String deger, {Color? renk}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(baslik, style: const TextStyle(color: Colors.grey, fontSize: 11)),
        const SizedBox(height: 4),
        Text(deger, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: renk)),
      ],
    );
  }
}

class GeriAlSnackBarContent extends StatefulWidget {
  final VoidCallback onGeriAl;
  const GeriAlSnackBarContent({super.key, required this.onGeriAl});

  @override
  State<GeriAlSnackBarContent> createState() => _GeriAlSnackBarContentState();
}

class _GeriAlSnackBarContentState extends State<GeriAlSnackBarContent> {
  int _sayac = 3;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_sayac > 1) {
        if (mounted) setState(() => _sayac--);
      } else {
        _timer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onGeriAl,
      child: Container(
        color: Colors.transparent,
        child: Text(
          'Geri Al ($_sayac)',
          style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  HABER & BİLANÇO SAYFASI
// ─────────────────────────────────────────────

class HaberEkrani extends StatefulWidget {
  final List<Asset> portfoy;
  const HaberEkrani({super.key, required this.portfoy});

  @override
  State<HaberEkrani> createState() => _HaberEkraniState();
}

class _HaberEkraniState extends State<HaberEkrani> {
  List<Map<String, String>> _borsaHaberleri = [];
  List<Map<String, String>> _dunyaHaberleri = [];

  bool _haberleriYukleniyor = true;
  String? _haberHatasi;

  @override
  void initState() {
    super.initState();
    _verileriYukle();
  }

  Future<void> _verileriYukle() async {
    setState(() {
      _haberleriYukleniyor = true;
      _haberHatasi = null;
    });
    await _haberleriYukle();
  }

  String? _rssTag(String xml, String tag) {
    final m = RegExp('<$tag[^>]*>([\\s\\S]*?)</$tag>').firstMatch(xml);
    return m?.group(1)
        ?.replaceAll(RegExp(r'<!\[CDATA\[|\]\]>'), '')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&amp;', '&').replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>').replaceAll('&quot;', '"').replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  List<Map<String, String>> _parseRss(String body) {
    final items = <Map<String, String>>[];
    for (final m in RegExp(r'<item>([\s\S]*?)</item>').allMatches(body)) {
      final xml = m.group(1)!;
      final title = _rssTag(xml, 'title') ?? '';
      final link = RegExp(r'<link>([\s\S]*?)</link>').firstMatch(xml)?.group(1)?.trim() ??
          RegExp(r'<link[^>]+href="([^"]+)"').firstMatch(xml)?.group(1) ?? '';
      final pubDate = _rssTag(xml, 'pubDate') ?? _rssTag(xml, 'published') ?? '';
      if (title.isNotEmpty) items.add({'title': title, 'link': link, 'pubDate': pubDate});
      if (items.length >= 15) break;
    }
    return items;
  }

  Future<void> _haberleriYukle() async {
    try {
      final results = await Future.wait([
        http.get(
          Uri.parse('https://news.google.com/rss/search?q=borsa+istanbul+hisse&hl=tr&gl=TR&ceid=TR:tr'),
          headers: {'User-Agent': 'Mozilla/5.0'},
        ).timeout(const Duration(seconds: 12)),
        http.get(
          Uri.parse('https://news.google.com/rss/search?q=global+stock+market+finance&hl=en&gl=US&ceid=US:en'),
          headers: {'User-Agent': 'Mozilla/5.0'},
        ).timeout(const Duration(seconds: 12)),
      ]);
      if (!mounted) return;
      setState(() {
        if (results[0].statusCode == 200) _borsaHaberleri = _parseRss(utf8.decode(results[0].bodyBytes));
        if (results[1].statusCode == 200) _dunyaHaberleri = _parseRss(utf8.decode(results[1].bodyBytes));
        _haberleriYukleniyor = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _haberHatasi = 'Haberler yüklenemedi.';
        _haberleriYukleniyor = false;
      });
    }
  }

  Future<void> _linkAc(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }


  Widget _buildExpansionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isLoading,
    required Widget content,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ExpansionTile(
        leading: Icon(icon, color: Colors.blueGrey),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        initiallyExpanded: false,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          isLoading
              ? const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
              : content,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return RefreshIndicator(
      onRefresh: _verileriYukle,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 8, bottom: 40),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 20, top: 8, bottom: 8),
            child: Text('Piyasa Bilgileri',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.blueGrey[400])),
          ),

          // ── SON BİLANÇOLAR ──
          _buildExpansionCard(
            icon: Icons.receipt_long_outlined,
            title: 'Son Bilançolar',
            subtitle: 'KAP\'ta en son açıklanan finansal raporlar',
            isLoading: false,
            content: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _linkAc('https://fintables.com/son-bilancolar'),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark ? Colors.blueGrey[700]! : Colors.blueGrey[200]!,
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDark
                          ? [Colors.blueGrey[900]!, Colors.blueGrey[800]!]
                          : [Colors.blueGrey[50]!, Colors.white],
                    ),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE53935).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Center(
                          child: Text('F', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFFE53935))),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('fintables.com', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            const SizedBox(height: 2),
                            Text(
                              'Son Bilançolar sayfası – KAP\'ta açıklanan tüm finansal raporlar',
                              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(Icons.link, size: 13, color: Colors.blueGrey[400]),
                                const SizedBox(width: 4),
                                Text(
                                  'fintables.com/son-bilancolar',
                                  style: TextStyle(fontSize: 11, color: Colors.blueGrey[400]),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.open_in_new, size: 20, color: Colors.blueGrey[400]),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── BORSA HABERLERİ ──
          _buildExpansionCard(
            icon: Icons.bar_chart_rounded,
            title: 'Borsa Haberleri',
            subtitle: 'Türkiye borsası ve hisse senetleri',
            isLoading: _haberleriYukleniyor,
            content: _buildHaberListesi(_borsaHaberleri),
          ),

          // ── DÜNYA GÜNDEMİ ──
          _buildExpansionCard(
            icon: Icons.public,
            title: 'Dünya Gündemi',
            subtitle: 'Küresel piyasaları etkileyen gelişmeler',
            isLoading: _haberleriYukleniyor,
            content: _buildHaberListesi(_dunyaHaberleri),
          ),
        ],
      ),
    );
  }

  Widget _buildHaberListesi(List<Map<String, String>> haberler) {
    if (haberler.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(_haberHatasi ?? 'Haber bulunamadı.', style: const TextStyle(color: Colors.grey)),
      );
    }
    return Column(
      children: haberler.map((h) => ListTile(
        dense: true,
        title: Text(h['title'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(h['pubDate'] ?? '', style: const TextStyle(fontSize: 11, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.arrow_forward_ios, size: 13, color: Colors.grey),
        onTap: () => _linkAc(h['link'] ?? ''),
      )).toList(),
    );
  }
}