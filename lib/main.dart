import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

// ==================== 1. النماذج (MODELS) ====================
class MaterialModel {
  String id, code, name, category;
  double priceMultiplier;

  MaterialModel({required this.id, required this.code, required this.name, required this.category, this.priceMultiplier = 1.0});

  Map<String, dynamic> toMap() => {'id': id, 'code': code, 'name': name, 'category': category, 'priceMultiplier': priceMultiplier};
  factory MaterialModel.fromMap(Map<String, dynamic> map) => MaterialModel(
    id: map['id'], code: map['code'], name: map['name'], category: map['category'], priceMultiplier: (map['priceMultiplier'] as num).toDouble(),
  );
}

class UnitModel {
  String id, code, description, category;
  double width, height, depth, basePrice;

  UnitModel({required this.id, required this.code, required this.description, required this.category, required this.width, required this.height, required this.depth, required this.basePrice});

  Map<String, dynamic> toMap() => {'id': id, 'code': code, 'description': description, 'category': category, 'width': width, 'height': height, 'depth': depth, 'basePrice': basePrice};
  factory UnitModel.fromMap(Map<String, dynamic> map) => UnitModel(
    id: map['id'], code: map['code'], description: map['description'], category: map['category'],
    width: (map['width'] as num).toDouble(), height: (map['height'] as num).toDouble(), depth: (map['depth'] as num).toDouble(), basePrice: (map['basePrice'] as num).toDouble(),
  );
}

class CatalogModel {
  String id, code, name, targetVersion;
  List<UnitModel> units;
  List<MaterialModel> materials;

  CatalogModel({required this.id, required this.code, required this.name, this.targetVersion = "V6.5", List<UnitModel>? units, List<MaterialModel>? materials})
      : units = units ?? [], materials = materials ?? [];

  Map<String, dynamic> toMap() => {'id': id, 'code': code, 'name': name, 'targetVersion': targetVersion, 'units': units.map((u) => u.toMap()).toList(), 'materials': materials.map((m) => m.toMap()).toList()};
  factory CatalogModel.fromMap(Map<String, dynamic> map) => CatalogModel(
    id: map['id'], code: map['code'], name: map['name'], targetVersion: map['targetVersion'] ?? "V6.5",
    units: (map['units'] as List?)?.map((u) => UnitModel.fromMap(u)).toList() ?? [],
    materials: (map['materials'] as List?)?.map((m) => MaterialModel.fromMap(m)).toList() ?? [],
  );
  String toJson() => json.encode(toMap());
  factory CatalogModel.fromJson(String source) => CatalogModel.fromMap(json.decode(source));
}

// ==================== 2. محرك تصدير KITCHENDRAW ====================
class KDExportService {
  static Future<File> exportCatalog(CatalogModel catalog) async {
    final buf = StringBuffer();
    buf.writeln("; KITCHENDRAW CATALOG - Generated Mobile");
    buf.writeln("CATALOG \"${catalog.code}\" \"${catalog.name}\"");
    buf.writeln("VERSION \"${catalog.targetVersion}\"\n");

    buf.writeln("TABLE FINISHES");
    for (var m in catalog.materials) {
      buf.writeln("  FINISH \"${m.code}\" \"${m.name}\" RATIO ${m.priceMultiplier} FAM \"${m.category}\"");
    }
    buf.writeln("END_TABLE\n");

    Map<String, List<UnitModel>> grouped = {};
    for (var u in catalog.units) { grouped.putIfAbsent(u.category, () => []).add(u); }

    grouped.forEach((cat, list) {
      buf.writeln("CHAPTER \"${cat.toUpperCase()}\" \"$cat Units\"");
      for (var u in list) {
        buf.writeln("  BLOCK \"${u.code}\" \"${u.description}\"");
        buf.writeln("    DIM ${u.width.toInt()} ${u.height.toInt()} ${u.depth.toInt()}");
        buf.writeln("    PRICE ${u.basePrice}");
        buf.writeln("    SCRIPT\n      BOX 0, 0, 0, DX, DY, DZ\n    END_SCRIPT");
        buf.writeln("  END_BLOCK\n");
      }
      buf.writeln("END_CHAPTER\n");
    });
    buf.writeln("END_CATALOG");

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${catalog.code}.cat');
    return await file.writeAsString(buf.toString(), encoding: utf8);
  }
}

// ==================== 3. التطبيق والواجهات (UI) ====================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getStringList('catalogs_data') ?? [];
  final catalogs = saved.map((s) => CatalogModel.fromJson(s)).toList();

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(catalogs),
      child: const KDApp(),
    ),
  );
}

class AppState extends ChangeNotifier {
  List<CatalogModel> catalogs;
  AppState(this.catalogs);

  void save() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setStringList('catalogs_data', catalogs.map((c) => c.toJson()).toList());
    notifyListeners();
  }

  void add(CatalogModel c) { catalogs.add(c); save(); }
  void update(CatalogModel c) {
    int i = catalogs.indexWhere((item) => item.id == c.id);
    if (i != -1) { catalogs[i] = c; save(); }
  }
}

class KDApp extends StatelessWidget {
  const KDApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'MA'),
      supportedLocales: const [Locale('ar', 'MA')],
      localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      theme: ThemeData(primaryColor: const Color(0xFF1E3A8A), useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);
    return Scaffold(
      appBar: AppBar(title: const Text("كتالوجات KitchenDraw")),
      body: state.catalogs.isEmpty
          ? const Center(child: Text("اضغط + لإنشاء أول كتالوج"))
          : ListView.builder(
              itemCount: state.catalogs.length,
              itemBuilder: (ctx, i) {
                final cat = state.catalogs[i];
                return Card(
                  margin: const EdgeInsets.all(8),
                  child: ListTile(
                    title: Text("${cat.name} (${cat.code})", style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text("الوحدات: ${cat.units.length} | الإصدار: ${cat.targetVersion}"),
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => UnitsScreen(catalog: cat))),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () {
          final cCtrl = TextEditingController();
          final nCtrl = TextEditingController();
          showDialog(
            context: context,
            builder: (dCtx) => AlertDialog(
              title: const Text("كتالوج جديد"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: cCtrl, decoration: const InputDecoration(labelText: "كود الكتالوج (مثال: C01)")),
                  TextField(controller: nCtrl, decoration: const InputDecoration(labelText: "اسم الكتالوج")),
                ],
              ),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    if (cCtrl.text.isNotEmpty && nCtrl.text.isNotEmpty) {
                      state.add(CatalogModel(id: const Uuid().v4(), code: cCtrl.text.toUpperCase(), name: nCtrl.text));
                      Navigator.pop(dCtx);
                    }
                  },
                  child: const Text("حفظ"),
                )
              ],
            ),
          );
        },
      ),
    );
  }
}

class UnitsScreen extends StatefulWidget {
  final CatalogModel catalog;
  const UnitsScreen({super.key, required this.catalog});
  @override
  State<UnitsScreen> createState() => _UnitsScreenState();
}

class _UnitsScreenState extends State<UnitsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.catalog.name)),
      body: widget.catalog.units.isEmpty
          ? const Center(child: Text("لا توجد وحدات. اضغط + لإضافة كيسون"))
          : ListView.builder(
              itemCount: widget.catalog.units.length,
              itemBuilder: (ctx, i) {
                final u = widget.catalog.units[i];
                return ListTile(
                  title: Text("${u.code} - ${u.description}"),
                  subtitle: Text("${u.width}x${u.height}x${u.depth} mm"),
                  trailing: Text("${u.basePrice} \$"),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add_box),
        onPressed: () => _addUnitDialog(context),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(12),
        child: ElevatedButton.icon(
          icon: const Icon(Icons.share),
          label: const Text("تصدير ملف .CAT للواتساب"),
          onPressed: () async {
            final file = await KDExportService.exportCatalog(widget.catalog);
            await Share.shareXFiles([XFile(file.path)], text: "كتالوج KitchenDraw");
          },
        ),
      ),
    );
  }

  void _addUnitDialog(BuildContext context) {
    final c = TextEditingController(), d = TextEditingController(), w = TextEditingController(text: "600"), h = TextEditingController(text: "850"), dp = TextEditingController(text: "580"), p = TextEditingController(text: "150");
    String cat = "Base";
    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text("إضافة كيسون / وحدة"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: c, decoration: const InputDecoration(labelText: "الرمز (Code)")),
              TextField(controller: d, decoration: const InputDecoration(labelText: "الوصف")),
              TextField(controller: w, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "العرض W")),
              TextField(controller: h, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "الارتفاع H")),
              TextField(controller: dp, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "العمق D")),
              TextField(controller: p, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "السعر \$")),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              if (c.text.isNotEmpty) {
                setState(() {
                  widget.catalog.units.add(UnitModel(
                    id: const Uuid().v4(), code: c.text.toUpperCase(), description: d.text, category: cat,
                    width: double.parse(w.text), height: double.parse(h.text), depth: double.parse(dp.text), basePrice: double.parse(p.text),
                  ));
                });
                Provider.of<AppState>(context, listen: false).update(widget.catalog);
                Navigator.pop(dCtx);
              }
            },
            child: const Text("إضافة"),
          )
        ],
      ),
    );
  }
}
