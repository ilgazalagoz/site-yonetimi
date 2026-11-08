import 'package:flutter/material.dart';
import '../../core/supabase.dart';
import 'dialogs/add_block_dialog.dart';
import 'dialogs/add_unit_dialog.dart';
import 'dialogs/create_announcement_dialog.dart';
import 'tabs/announcements_tab.dart';
import 'tabs/blocks_units_tab.dart';
import 'tabs/members_tab.dart';

class AdminDashboard extends StatefulWidget {
  final Map<String, dynamic> site;

  const AdminDashboard({super.key, required this.site});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  bool _loadingSummary = true;
  int _blockCount = 0;
  int _unitCount = 0;
  int _memberCount = 0;
  int _announcementCount = 0;
  List<Map<String, dynamic>> _recentAnnouncements = [];
  List<Map<String, dynamic>> _recentMembers = [];
  String? _error;

  String get _siteId => widget.site['id'] as String;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadSummary();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadSummary() async {
    setState(() {
      _loadingSummary = true;
      _error = null;
    });

    try {
      final blocksRes = await supabase
          .from('blocks')
          .select('id')
          .eq('site_id', _siteId);

      final unitsRes = await supabase
          .from('units')
          .select('id')
          .eq('site_id', _siteId);

      final membersRes = await supabase
          .from('memberships')
          .select('id, role, profiles(full_name), units(unit_no, blocks(name))')
          .eq('site_id', _siteId)
          .eq('status', 'active');

      final annRes = await supabase
          .from('announcements')
          .select('id, title, body, pinned, created_at')
          .eq('site_id', _siteId)
          .order('pinned', ascending: false)
          .order('created_at', ascending: false);

      final annList = List<Map<String, dynamic>>.from(annRes);
      final membersList = List<Map<String, dynamic>>.from(membersRes);

      if (mounted) {
        setState(() {
          _blockCount = (blocksRes as List).length;
          _unitCount = (unitsRes as List).length;
          _memberCount = membersList.length;
          _announcementCount = annList.length;
          _recentAnnouncements = annList.take(3).toList();
          _recentMembers = membersList.take(4).toList();
          _loadingSummary = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Özet veriler yüklenemedi: $e';
          _loadingSummary = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        // Üst Bilgi Başlığı ve TabBar
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.site['name'] ?? 'Site Yönetimi',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.location_on_outlined, size: 16, color: Colors.grey.shade600),
                            const SizedBox(width: 4),
                            Text(
                              '${widget.site['city']} / ${widget.site['district']}',
                              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                            ),
                            if (widget.site['address'] != null &&
                                widget.site['address'].toString().isNotEmpty) ...[
                              Text(' • ', style: TextStyle(color: Colors.grey.shade400)),
                              Text(
                                widget.site['address'].toString(),
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                    IconButton(
                      tooltip: 'Verileri Yenile',
                      icon: const Icon(Icons.refresh),
                      onPressed: _loadSummary,
                    ),
                  ],
                ),
              ),
              TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: theme.colorScheme.primary,
                unselectedLabelColor: Colors.black54,
                indicatorColor: theme.colorScheme.primary,
                indicatorWeight: 3,
                tabs: const [
                  Tab(icon: Icon(Icons.dashboard_outlined), text: 'Genel Bakış'),
                  Tab(icon: Icon(Icons.domain), text: 'Blok & Daire Yönetimi'),
                  Tab(icon: Icon(Icons.campaign_outlined), text: 'Duyurular'),
                  Tab(icon: Icon(Icons.people_outline), text: 'Sakinler & Üyeler'),
                ],
              ),
            ],
          ),
        ),

        // Sekme İçerikleri
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // 1. Sekme: Genel Bakış
              _buildOverviewTab(),

              // 2. Sekme: Blok & Daire Yönetimi
              BlocksUnitsTab(
                siteId: _siteId,
                onDataChanged: _loadSummary,
              ),

              // 3. Sekme: Duyurular
              AnnouncementsTab(
                siteId: _siteId,
                onDataChanged: _loadSummary,
              ),

              // 4. Sekme: Sakinler & Üyeler
              MembersTab(
                site: widget.site,
                onDataChanged: _loadSummary,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOverviewTab() {
    if (_loadingSummary) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _loadSummary, child: const Text('Yenile')),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // İstatistik Kartları Satırı
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 640;
              final isMedium = constraints.maxWidth < 1000;

              if (isNarrow) {
                return Column(
                  children: [
                    _buildStatCard(
                      'Blok Sayısı',
                      _blockCount.toString(),
                      Icons.domain,
                      Colors.blue,
                      () => _tabController.animateTo(1),
                    ),
                    const SizedBox(height: 12),
                    _buildStatCard(
                      'Daire Sayısı',
                      _unitCount.toString(),
                      Icons.meeting_room,
                      Colors.purple,
                      () => _tabController.animateTo(1),
                    ),
                    const SizedBox(height: 12),
                    _buildStatCard(
                      'Aktif Üyeler',
                      _memberCount.toString(),
                      Icons.people,
                      Colors.teal,
                      () => _tabController.animateTo(3),
                    ),
                    const SizedBox(height: 12),
                    _buildStatCard(
                      'Duyurular',
                      _announcementCount.toString(),
                      Icons.campaign,
                      Colors.amber.shade800,
                      () => _tabController.animateTo(2),
                    ),
                  ],
                );
              }

              if (isMedium) {
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            'Blok Sayısı',
                            _blockCount.toString(),
                            Icons.domain,
                            Colors.blue,
                            () => _tabController.animateTo(1),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildStatCard(
                            'Daire Sayısı',
                            _unitCount.toString(),
                            Icons.meeting_room,
                            Colors.purple,
                            () => _tabController.animateTo(1),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            'Aktif Üyeler',
                            _memberCount.toString(),
                            Icons.people,
                            Colors.teal,
                            () => _tabController.animateTo(3),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildStatCard(
                            'Duyurular',
                            _announcementCount.toString(),
                            Icons.campaign,
                            Colors.amber.shade800,
                            () => _tabController.animateTo(2),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      'Blok Sayısı',
                      _blockCount.toString(),
                      Icons.domain,
                      Colors.blue,
                      () => _tabController.animateTo(1),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildStatCard(
                      'Daire Sayısı',
                      _unitCount.toString(),
                      Icons.meeting_room,
                      Colors.purple,
                      () => _tabController.animateTo(1),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildStatCard(
                      'Aktif Üyeler',
                      _memberCount.toString(),
                      Icons.people,
                      Colors.teal,
                      () => _tabController.animateTo(3),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildStatCard(
                      'Duyurular',
                      _announcementCount.toString(),
                      Icons.campaign,
                      Colors.amber.shade800,
                      () => _tabController.animateTo(2),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 28),

          // Hızlı Aksiyonlar Kartı
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hızlı Aksiyonlar',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        icon: const Icon(Icons.person_add, size: 18),
                        label: const Text('Daire / Sakin Davet Et'),
                        onPressed: () => _tabController.animateTo(3),
                      ),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.campaign, size: 18),
                        label: const Text('Yeni Duyuru Yayınla'),
                        onPressed: () async {
                          final res = await showDialog<bool>(
                            context: context,
                            builder: (_) => CreateAnnouncementDialog(siteId: _siteId),
                          );
                          if (res == true) {
                            _loadSummary();
                          }
                        },
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.add_home_outlined, size: 18),
                        label: const Text('Daire Ekle'),
                        onPressed: () async {
                          final res = await showDialog<bool>(
                            context: context,
                            builder: (_) => AddUnitDialog(siteId: _siteId),
                          );
                          if (res == true) {
                            _loadSummary();
                          }
                        },
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.domain_add, size: 18),
                        label: const Text('Blok Ekle'),
                        onPressed: () async {
                          final res = await showDialog<bool>(
                            context: context,
                            builder: (_) => AddBlockDialog(siteId: _siteId),
                          );
                          if (res == true) {
                            _loadSummary();
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),

          // Son Duyurular & Son Üyeler Çift Sütun
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 800;

              final announcementsWidget = _buildRecentAnnouncementsCard();
              final membersWidget = _buildRecentMembersCard();

              if (isNarrow) {
                return Column(
                  children: [
                    announcementsWidget,
                    const SizedBox(height: 20),
                    membersWidget,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: announcementsWidget),
                  const SizedBox(width: 20),
                  Expanded(child: membersWidget),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: color.withOpacity(0.12),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentAnnouncementsCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.campaign, color: Colors.amber.shade800, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Son Duyurular',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: () => _tabController.animateTo(2),
                  child: const Text('Tümünü Gör'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_recentAnnouncements.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    'Henüz duyuru bulunmuyor.',
                    style: TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _recentAnnouncements.length,
                separatorBuilder: (_, __) => const Divider(height: 16),
                itemBuilder: (ctx, i) {
                  final a = _recentAnnouncements[i];
                  final isPinned = a['pinned'] == true;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Row(
                      children: [
                        if (isPinned)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Icon(Icons.push_pin, size: 14, color: Colors.amber.shade800),
                          ),
                        Expanded(
                          child: Text(
                            a['title'] ?? 'Başlıksız',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    subtitle: Text(
                      a['body'] ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                    onTap: () => _tabController.animateTo(2),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentMembersCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.people, color: Colors.teal.shade700, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Son Katılan Sakinler',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: () => _tabController.animateTo(3),
                  child: const Text('Tümünü Gör'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_recentMembers.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    'Henüz katılmış bir sakin yok.',
                    style: TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _recentMembers.length,
                separatorBuilder: (_, __) => const Divider(height: 16),
                itemBuilder: (ctx, i) {
                  final m = _recentMembers[i];
                  final profile = m['profiles'] as Map<String, dynamic>?;
                  final unit = m['units'] as Map<String, dynamic>?;
                  final block = unit?['blocks']?['name'];
                  final unitNo = unit?['unit_no'];

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.indigo.shade50,
                      child: Text(
                        (profile?['full_name'] ?? 'U').toString().characters.first.toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo.shade800,
                        ),
                      ),
                    ),
                    title: Text(
                      profile?['full_name'] ?? 'İsimsiz Kullanıcı',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      m['role'] == 'resident' && unitNo != null
                          ? '$block Blok, No: $unitNo'
                          : (m['role'] == 'technician' ? 'Teknik Personel' : 'Site Yöneticisi'),
                      style: const TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                    onTap: () => _tabController.animateTo(3),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
