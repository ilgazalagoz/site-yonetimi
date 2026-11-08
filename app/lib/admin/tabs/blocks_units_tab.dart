import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase.dart';
import '../dialogs/add_block_dialog.dart';
import '../dialogs/add_unit_dialog.dart';
import '../dialogs/add_unit_type_dialog.dart';
import '../dialogs/bulk_add_units_dialog.dart';

class BlocksUnitsTab extends StatefulWidget {
  final String siteId;
  final VoidCallback? onDataChanged;

  const BlocksUnitsTab({
    super.key,
    required this.siteId,
    this.onDataChanged,
  });

  @override
  State<BlocksUnitsTab> createState() => _BlocksUnitsTabState();
}

class _BlocksUnitsTabState extends State<BlocksUnitsTab> {
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _blocks = [];
  List<Map<String, dynamic>> _unitTypes = [];
  List<Map<String, dynamic>> _units = [];

  String? _selectedBlockFilter; // null means 'Tümü'
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final blocksRes = await supabase
          .from('blocks')
          .select('id, name')
          .eq('site_id', widget.siteId)
          .order('name');

      final unitTypesRes = await supabase
          .from('unit_types')
          .select('id, name, monthly_amount')
          .eq('site_id', widget.siteId)
          .order('name');

      final unitsRes = await supabase
          .from('units')
          .select('id, unit_no, block_id, unit_type_id, blocks(id, name), unit_types(id, name, monthly_amount)')
          .eq('site_id', widget.siteId);

      final unitsList = List<Map<String, dynamic>>.from(unitsRes);

      // İki seviyeli akıllı sıralama: Önce Blok adına göre, sonra daire numarasına (sayısal) göre
      unitsList.sort((a, b) {
        final bNameA = (a['blocks']?['name'] ?? '').toString();
        final bNameB = (b['blocks']?['name'] ?? '').toString();
        final blockCompare = bNameA.compareTo(bNameB);
        if (blockCompare != 0) return blockCompare;

        final noA = (a['unit_no'] ?? '').toString();
        final noB = (b['unit_no'] ?? '').toString();
        final intA = int.tryParse(noA);
        final intB = int.tryParse(noB);
        if (intA != null && intB != null) {
          return intA.compareTo(intB);
        }
        return noA.compareTo(noB);
      });

      if (mounted) {
        setState(() {
          _blocks = List<Map<String, dynamic>>.from(blocksRes);
          _unitTypes = List<Map<String, dynamic>>.from(unitTypesRes);
          _units = unitsList;
          _loading = false;
        });
        widget.onDataChanged?.call();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Bilgiler yüklenirken hata oluştu: $e';
        });
      }
    }
  }

  // --- Blok İşlemleri ---
  Future<void> _openAddBlockDialog({Map<String, dynamic>? block}) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AddBlockDialog(siteId: widget.siteId, block: block),
    );
    if (res == true) {
      _loadData();
    }
  }

  Future<void> _deleteBlock(Map<String, dynamic> block) async {
    final count = _units.where((u) => u['block_id'] == block['id']).length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bloku Sil'),
        content: Text(
          count > 0
              ? '"${block['name']}" bloğunu silmek üzeresiniz. Bu blokta bulunan $count adet daire de silinecektir!\n\nEmin misiniz?'
              : '"${block['name']}" bloğu silinsin mi?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await supabase.from('blocks').delete().eq('id', block['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${block['name']} başarıyla silindi.')),
        );
      }
      _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Blok silinemedi: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // --- Daire Tipi İşlemleri ---
  Future<void> _openAddUnitTypeDialog({Map<String, dynamic>? unitType}) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AddUnitTypeDialog(siteId: widget.siteId, unitType: unitType),
    );
    if (res == true) {
      _loadData();
    }
  }

  Future<void> _deleteUnitType(Map<String, dynamic> unitType) async {
    final count = _units.where((u) => u['unit_type_id'] == unitType['id']).length;
    if (count > 0) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Silme Engellendi'),
          content: Text(
            '"${unitType['name']}" tipine bağlı $count adet daire bulunuyor. '
            'Önce bu dairelerin tipini değiştirmeniz veya daireleri silmeniz gerekmektedir.',
          ),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tamam')),
          ],
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Daire Tipini Sil'),
        content: Text('"${unitType['name']}" tipi silinsin mi?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await supabase.from('unit_types').delete().eq('id', unitType['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${unitType['name']} başarıyla silindi.')),
        );
      }
      _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Daire tipi silinemedi: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // --- Daire İşlemleri ---
  Future<void> _openAddUnitDialog({Map<String, dynamic>? unit}) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AddUnitDialog(
        siteId: widget.siteId,
        blocks: _blocks,
        unitTypes: _unitTypes,
        initialBlockId: _selectedBlockFilter,
        unit: unit,
      ),
    );
    if (res == true) {
      _loadData();
    }
  }

  Future<void> _openBulkAddUnitsDialog() async {
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => BulkAddUnitsDialog(
        siteId: widget.siteId,
        blocks: _blocks,
        unitTypes: _unitTypes,
        initialBlockId: _selectedBlockFilter,
      ),
    );
    if (res == true) {
      _loadData();
    }
  }

  Future<void> _deleteUnit(Map<String, dynamic> unit) async {
    final bName = unit['blocks']?['name'] ?? '';
    final uNo = unit['unit_no'] ?? '';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Daireyi Sil'),
        content: Text('$bName No: $uNo dairesini silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await supabase.from('units').delete().eq('id', unit['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$bName No: $uNo silindi.')),
        );
      }
      _loadData();
    } on PostgrestException catch (e) {
      if (mounted) {
        String msg = 'Daire silinemedi: ${e.message}';
        if (e.code == '23503') {
          msg = 'Bu daireye ait aidat/borç geçmişi olduğu için silinemez.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredUnits {
    return _units.where((u) {
      if (_selectedBlockFilter != null && u['block_id'] != _selectedBlockFilter) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final unitNo = (u['unit_no'] ?? '').toString().toLowerCase();
        final blockName = (u['blocks']?['name'] ?? '').toString().toLowerCase();
        final typeName = (u['unit_types']?['name'] ?? '').toString().toLowerCase();
        return unitNo.contains(query) || blockName.contains(query) || typeName.contains(query);
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Yeniden Dene'),
            ),
          ],
        ),
      );
    }

    final filtered = _filteredUnits;

    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Üst Bölüm: Bloklar ve Daire Tipleri Kartları
            _buildBlocksAndTypesSection(),
            const SizedBox(height: 28),

            // Orta Bölüm: Daireler Başlığı, Hızlı Aksiyon Butonları & Arama
            _buildUnitsHeaderSection(filtered.length),
            const SizedBox(height: 16),

            // Daireler Listesi
            if (_units.isEmpty)
              _buildEmptyUnitsCard()
            else if (filtered.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.search_off, size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 8),
                        const Text(
                          'Arama veya filtre kriterinize uygun daire bulunamadı.',
                          style: TextStyle(color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              _buildUnitsGridOrList(filtered),
          ],
        ),
      ),
    );
  }

  Widget _buildBlocksAndTypesSection() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 720;
        final blocksCard = _buildBlocksCard();
        final typesCard = _buildTypesCard();

        if (isNarrow) {
          return Column(
            children: [
              blocksCard,
              const SizedBox(height: 16),
              typesCard,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: blocksCard),
            const SizedBox(width: 16),
            Expanded(child: typesCard),
          ],
        );
      },
    );
  }

  Widget _buildBlocksCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.domain, color: Colors.blue.shade700, size: 20),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Bloklar (${_blocks.length})',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: () => _openAddBlockDialog(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Blok Ekle'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_blocks.isEmpty)
              const Text(
                'Henüz tanımlanmış blok bulunmuyor. Daire ekleyebilmek için blok oluşturun.',
                style: TextStyle(color: Colors.black54, fontSize: 13),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _blocks.map((b) {
                  final count = _units.where((u) => u['block_id'] == b['id']).length;
                  return Chip(
                    avatar: CircleAvatar(
                      backgroundColor: Colors.blue.shade100,
                      child: Text(
                        (b['name'] as String).characters.first.toUpperCase(),
                        style: TextStyle(fontSize: 11, color: Colors.blue.shade900),
                      ),
                    ),
                    label: Text('${b['name']} ($count daire)'),
                    deleteIcon: const Icon(Icons.more_vert, size: 16),
                    onDeleted: () {
                      _showBlockActionSheet(b);
                    },
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  void _showBlockActionSheet(Map<String, dynamic> block) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Blok Adını Düzenle'),
              onTap: () {
                Navigator.pop(ctx);
                _openAddBlockDialog(block: block);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Bloku Sil', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _deleteBlock(block);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypesCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.category, color: Colors.purple.shade700, size: 20),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Daire Tipleri & Aidat (${_unitTypes.length})',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: () => _openAddUnitTypeDialog(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Tip Ekle'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_unitTypes.isEmpty)
              const Text(
                'Henüz daire tipi ve aidat tutarı tanımlanmadı. Örn: "2+1 Standart / 1.500 ₺"',
                style: TextStyle(color: Colors.black54, fontSize: 13),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _unitTypes.map((t) {
                  final amount = t['monthly_amount'];
                  return Chip(
                    backgroundColor: Colors.purple.shade50,
                    label: Text(
                      '${t['name']}: ${amount != null ? '$amount ₺' : 'Belirtilmedi'}',
                      style: TextStyle(color: Colors.purple.shade900, fontWeight: FontWeight.w500),
                    ),
                    deleteIcon: const Icon(Icons.more_vert, size: 16),
                    onDeleted: () {
                      _showUnitTypeActionSheet(t);
                    },
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  void _showUnitTypeActionSheet(Map<String, dynamic> unitType) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Daire Tipini Düzenle'),
              onTap: () {
                Navigator.pop(ctx);
                _openAddUnitTypeDialog(unitType: unitType);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Daire Tipini Sil', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _deleteUnitType(unitType);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnitsHeaderSection(int filteredCount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Daireler',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$filteredCount / ${_units.length}',
                        style: TextStyle(
                          color: Colors.indigo.shade800,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Sitedeki bağımsız bölümleri listeleyin, ekleyin veya düzenleyin.',
                  style: TextStyle(color: Colors.black54, fontSize: 13),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _blocks.isEmpty || _unitTypes.isEmpty
                      ? null
                      : () => _openBulkAddUnitsDialog(),
                  icon: const Icon(Icons.dynamic_feed, size: 18),
                  label: const Text('Toplu Daire Ekle'),
                ),
                FilledButton.icon(
                  onPressed: _blocks.isEmpty || _unitTypes.isEmpty
                      ? null
                      : () => _openAddUnitDialog(),
                  icon: const Icon(Icons.add_home_outlined, size: 18),
                  label: const Text('Tek Daire Ekle'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Filtre Barı (Blok chipleri & Arama)
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    FilterChip(
                      selected: _selectedBlockFilter == null,
                      label: const Text('Tüm Bloklar'),
                      onSelected: (_) {
                        setState(() => _selectedBlockFilter = null);
                      },
                    ),
                    const SizedBox(width: 8),
                    ..._blocks.map((b) {
                      final isSelected = _selectedBlockFilter == b['id'];
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          selected: isSelected,
                          label: Text(b['name']),
                          onSelected: (_) {
                            setState(() {
                              _selectedBlockFilter = isSelected ? null : b['id'];
                            });
                          },
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 220,
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Daire no veya tip ara...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  isDense: true,
                ),
                onChanged: (val) {
                  setState(() => _searchQuery = val.trim());
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEmptyUnitsCard() {
    return Card(
      elevation: 0,
      color: Colors.grey.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.meeting_room_outlined, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              const Text(
                'Henüz daire kaydı bulunmuyor.',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Önce en az bir blok ve daire tipi oluşturduğunuzdan emin olun, ardından tek tek veya toplu olarak dairelerinizi ekleyin.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54, fontSize: 13),
              ),
              const SizedBox(height: 16),
              if (_blocks.isEmpty || _unitTypes.isEmpty)
                const Text(
                  '⚠️ Lütfen önce yukarıdan Blok ve Daire Tipi tanımlayınız.',
                  style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w600, fontSize: 13),
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _openBulkAddUnitsDialog(),
                      icon: const Icon(Icons.dynamic_feed),
                      label: const Text('Toplu Daire Ekle (1..20)'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: () => _openAddUnitDialog(),
                      icon: const Icon(Icons.add),
                      label: const Text('Tek Daire Ekle'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUnitsGridOrList(List<Map<String, dynamic>> units) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Geniş ekranda kart gridi, dar ekranda liste
        int crossAxisCount = 1;
        if (constraints.maxWidth > 1100) {
          crossAxisCount = 3;
        } else if (constraints.maxWidth > 700) {
          crossAxisCount = 2;
        }

        if (crossAxisCount == 1) {
          return ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: units.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (ctx, i) => _buildUnitCard(units[i]),
          );
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 2.8,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: units.length,
          itemBuilder: (ctx, i) => _buildUnitCard(units[i]),
        );
      },
    );
  }

  Widget _buildUnitCard(Map<String, dynamic> unit) {
    final block = unit['blocks'] as Map<String, dynamic>?;
    final blockName = block?['name'] ?? '-';
    final unitType = unit['unit_types'] as Map<String, dynamic>?;
    final typeName = unitType?['name'] ?? 'Tip belirtilmemiş';
    final amount = unitType?['monthly_amount'];
    final unitNo = unit['unit_no'] ?? '-';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: Colors.indigo.shade50,
              child: Text(
                unitNo.toString(),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.indigo.shade800,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$blockName Blok, No: $unitNo',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    typeName,
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    amount != null ? 'Aidat: $amount ₺' : 'Aidat tanımlanmamış',
                    style: TextStyle(
                      color: Colors.green.shade800,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 20, color: Colors.black54),
              onSelected: (val) {
                if (val == 'edit') {
                  _openAddUnitDialog(unit: unit);
                } else if (val == 'delete') {
                  _deleteUnit(unit);
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 18),
                      SizedBox(width: 8),
                      Text('Düzenle'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, size: 18, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Sil', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
