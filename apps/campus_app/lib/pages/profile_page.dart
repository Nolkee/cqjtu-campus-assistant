import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/providers.dart';
import 'package:campus_platform/services/credential_service.dart';
import 'package:campus_platform/services/notification_service.dart';
import 'package:core/models/dorm_room.dart';
import '../services/app_update_coordinator.dart';
import 'electricity_page.dart';
import 'leave_apply_page.dart';
import 'tools_page.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  void _logout(BuildContext context, WidgetRef ref) async {
    ref.invalidate(sessionManagerProvider);
    ref.invalidate(campusBackendProvider);
    await ref.read(credentialServiceProvider).clear();
    ref.invalidate(credentialsProvider);
    ref.invalidate(scheduleProvider);
    ref.invalidate(payCodeProvider);
    await ref.read(dormRoomProvider.notifier).clear();

    await NotificationService.cancelAllClassReminders();
    debugPrint('[Profile] 账号已退出，所有本地通知调度已清空');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final creds = ref.watch(credentialsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('我的', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        children: [
          _buildUserInfoCard(creds?.username ?? '未登录'),
          const SizedBox(height: 20),
          const _ElectricityCardWidget(),
          const SizedBox(height: 20),
          _sectionLabel('宿舍设置'),
          const _DormSettingsCard(),
          const SizedBox(height: 20),
          _sectionLabel('教务服务'),
          _buildServiceMenu(context),
          const SizedBox(height: 20),
          _sectionLabel('通知设置'),
          const _NotificationSettingsCard(),
          const SizedBox(height: 20),
          _sectionLabel('版本更新'),
          const _AppUpdateCard(),
          const SizedBox(height: 20),
          _sectionLabel('安全与隐私'),
          const _SecurityNoticeCard(),
          const SizedBox(height: 30),
          _buildLogoutButton(context, ref),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
    ),
  );

  Widget _buildUserInfoCard(String username) {
    return Row(
      children: [
        const CircleAvatar(
          radius: 36,
          backgroundColor: Colors.blueAccent,
          child: Icon(Icons.person, size: 40, color: Colors.white),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              username,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                '重庆交通大学',
                style: TextStyle(fontSize: 12, color: Colors.blueAccent),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildServiceMenu(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildMenuTile(
            icon: Icons.assignment_outlined,
            color: Colors.orange,
            title: '成绩查询',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const GradesPage()),
            ),
          ),
          const Divider(height: 1, indent: 56, color: Color(0xFFF0F0F0)),
          _buildMenuTile(
            icon: Icons.event_note_outlined,
            color: Colors.purpleAccent,
            title: '考试安排',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ExamsPage()),
            ),
          ),
          const Divider(height: 1, indent: 56, color: Color(0xFFF0F0F0)),
          _buildMenuTile(
            icon: Icons.exit_to_app_outlined,
            color: Colors.teal,
            title: '请假申请',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LeaveApplyPage()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuTile({
    required IconData icon,
    required Color color,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(
        title,
        style: const TextStyle(fontSize: 16, color: Colors.black87),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.black26),
      onTap: onTap,
    );
  }

  Widget _buildLogoutButton(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: TextButton(
        style: TextButton.styleFrom(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: () {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text('退出登录'),
              content: const Text('确定要退出当前账号吗？'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消', style: TextStyle(color: Colors.grey)),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _logout(context, ref);
                  },
                  child: const Text(
                    '退出',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                ),
              ],
            ),
          );
        },
        child: const Text(
          '退出登录',
          style: TextStyle(
            color: Colors.redAccent,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 宿舍设置卡片
// ══════════════════════════════════════════════════════════════
class _DormSettingsCard extends ConsumerWidget {
  const _DormSettingsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dormAsync = ref.watch(dormRoomProvider);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.home_outlined, color: Colors.amber),
        ),
        title: const Text(
          '我的宿舍',
          style: TextStyle(fontSize: 15, color: Colors.black87),
        ),
        subtitle: dormAsync.when(
          loading: () => const Text(
            '加载中...',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          error: (_, _) => const Text(
            '加载失败',
            style: TextStyle(fontSize: 12, color: Colors.red),
          ),
          data: (dorm) => Text(
            dorm == null ? '未设置，电费查询使用账号默认宿舍' : dorm.displayName,
            style: TextStyle(
              fontSize: 12,
              color: dorm == null ? Colors.orange : Colors.grey,
            ),
          ),
        ),
        trailing: FilledButton.tonal(
          onPressed: () => _showDormPicker(context, ref),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('选择', style: TextStyle(fontSize: 13)),
        ),
        onTap: () => _showDormPicker(context, ref),
      ),
    );
  }

  void _showDormPicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DormPickerSheet(
        currentDorm: ref.read(dormRoomProvider).valueOrNull,
        onSaved: (room) async {
          await ref.read(dormRoomProvider.notifier).set(room);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('已保存：${room.displayName}，电费数据正在刷新')),
            );
          }
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 宿舍选择底部弹窗（双滚轮 + 房间号输入）
// ══════════════════════════════════════════════════════════════
class _DormPickerSheet extends StatefulWidget {
  final DormRoom? currentDorm;
  final Future<void> Function(DormRoom) onSaved;

  const _DormPickerSheet({required this.currentDorm, required this.onSaved});

  @override
  State<_DormPickerSheet> createState() => _DormPickerSheetState();
}

class _DormPickerSheetState extends State<_DormPickerSheet> {
  late FixedExtentScrollController _gardenCtrl;
  late FixedExtentScrollController _numberCtrl;
  final _roomCtrl = TextEditingController();

  // 当前滚轮选中值（随滚动实时更新，用于预览）
  late DormGarden _selectedGarden;
  late int _selectedNumber;

  bool _saving = false;
  String? _roomError;

  static const _gardens = DormGarden.values;

  @override
  void initState() {
    super.initState();
    final dorm = widget.currentDorm;
    _selectedGarden = dorm?.garden ?? DormGarden.deYuan;
    _selectedNumber = dorm?.buildingNumber ?? 1;

    _gardenCtrl = FixedExtentScrollController(
      initialItem: _gardens.indexOf(_selectedGarden),
    );
    _numberCtrl = FixedExtentScrollController(
      initialItem: _selectedNumber - kDormNumberMin,
    );

    if (dorm != null) {
      // 还原房间号，去掉前导零
      _roomCtrl.text = dorm.roomNumber.replaceFirst(RegExp(r'^0+'), '');
    }
  }

  @override
  void dispose() {
    _gardenCtrl.dispose();
    _numberCtrl.dispose();
    _roomCtrl.dispose();
    super.dispose();
  }

  /// 将输入的房间号格式化为 4 位补零字符串
  String? _formatRoom(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    // 支持用户直接输入 "0305" 或 "305"
    if (!RegExp(r'^\d{1,4}$').hasMatch(t)) return null;
    final n = int.tryParse(t);
    if (n == null || n < 1) return null;
    return t.padLeft(4, '0');
  }

  Future<void> _save() async {
    final roomId = _formatRoom(_roomCtrl.text);
    if (roomId == null) {
      setState(() => _roomError = '请输入正确的房间号（如 305）');
      return;
    }
    setState(() {
      _roomError = null;
      _saving = true;
    });

    final room = DormRoom(
      campusName: '科学城校区',
      garden: _selectedGarden,
      buildingNumber: _selectedNumber,
      roomNumber: roomId,
    );
    await widget.onSaved(room);
    if (mounted) {
      setState(() => _saving = false);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 拖拽指示条 ──────────────────────────────────
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // ── 标题 ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.home_outlined,
                      color: Colors.amber,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '选择我的宿舍',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '目前仅支持科学城校区，南岸校区适配中',
                          style: TextStyle(fontSize: 12, color: Colors.orange),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),

            // ── 当前选中预览（仅显示楼栋名，不暴露内部 ID）──────
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.home_outlined,
                    size: 16,
                    color: Colors.amber.shade700,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '已选：${_selectedGarden.label}$_selectedNumber舍',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.amber.shade800,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),

            // ── 双滚轮：园区 + 舍号 ─────────────────────────
            SizedBox(
              height: 200,
              child: Row(
                children: [
                  // 园区滚轮（德园 / 礼园）
                  Expanded(
                    child: Stack(
                      children: [
                        // 选中项高亮背景
                        Center(
                          child: Container(
                            height: 44,
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        ListWheelScrollView.useDelegate(
                          controller: _gardenCtrl,
                          itemExtent: 44,
                          physics: const FixedExtentScrollPhysics(),
                          diameterRatio: 1.8,
                          perspective: 0.004,
                          onSelectedItemChanged: (i) {
                            setState(() => _selectedGarden = _gardens[i]);
                          },
                          childDelegate: ListWheelChildBuilderDelegate(
                            childCount: _gardens.length,
                            builder: (context, i) {
                              final selected = _gardens[i] == _selectedGarden;
                              return Center(
                                child: Text(
                                  _gardens[i].label,
                                  style: TextStyle(
                                    fontSize: selected ? 20 : 16,
                                    fontWeight: selected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: selected
                                        ? Colors.amber.shade800
                                        : Colors.grey,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 中间分隔符
                  Text(
                    '·',
                    style: TextStyle(fontSize: 24, color: Colors.grey.shade400),
                  ),

                  // 舍号滚轮（1-15）
                  Expanded(
                    child: Stack(
                      children: [
                        Center(
                          child: Container(
                            height: 44,
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        ListWheelScrollView.useDelegate(
                          controller: _numberCtrl,
                          itemExtent: 44,
                          physics: const FixedExtentScrollPhysics(),
                          diameterRatio: 1.8,
                          perspective: 0.004,
                          onSelectedItemChanged: (i) {
                            setState(
                              () => _selectedNumber = kDormNumberMin + i,
                            );
                          },
                          childDelegate: ListWheelChildBuilderDelegate(
                            childCount: kDormNumberMax - kDormNumberMin + 1,
                            builder: (context, i) {
                              final num = kDormNumberMin + i;
                              final selected = num == _selectedNumber;
                              return Center(
                                child: Text(
                                  '$num舍',
                                  style: TextStyle(
                                    fontSize: selected ? 20 : 16,
                                    fontWeight: selected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: selected
                                        ? Colors.amber.shade800
                                        : Colors.grey,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── 房间号输入 ───────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '房间号',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _roomCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    onChanged: (_) {
                      if (_roomError != null) setState(() => _roomError = null);
                    },
                    decoration: InputDecoration(
                      hintText: '如住 305 房，输入 305',
                      errorText: _roomError,
                      prefixIcon: const Icon(Icons.door_back_door_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      counterText: '',
                    ),
                  ),
                ],
              ),
            ),

            // ── 保存按钮 ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_rounded, size: 20),
                  label: Text(_saving ? '保存中...' : '保存宿舍设置'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.amber.shade700,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _saving ? null : _save,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 安全与隐私声明卡片
// ══════════════════════════════════════════════════════════════
class _AppUpdateCard extends StatefulWidget {
  const _AppUpdateCard();

  @override
  State<_AppUpdateCard> createState() => _AppUpdateCardState();
}

class _AppUpdateCardState extends State<_AppUpdateCard> {
  String _versionLabel = '读取中...';
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _loadVersionLabel();
  }

  Future<void> _loadVersionLabel() async {
    try {
      final label = await AppUpdateCoordinator.currentVersionLabel();
      if (!mounted) return;
      setState(() => _versionLabel = label);
    } catch (_) {
      if (!mounted) return;
      setState(() => _versionLabel = '读取失败');
    }
  }

  Future<void> _checkUpdate() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      await AppUpdateCoordinator.checkAndPrompt(context, manual: true);
    } finally {
      if (mounted) {
        setState(() => _checking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.system_update_alt, color: Colors.blue),
        ),
        title: const Text(
          '检查更新',
          style: TextStyle(fontSize: 15, color: Colors.black87),
        ),
        subtitle: Text(
          '当前版本：$_versionLabel\n发现新版本后可直接打开下载链接',
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
            height: 1.45,
          ),
        ),
        trailing: _checking
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : FilledButton.tonal(
                onPressed: _checkUpdate,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('检查', style: TextStyle(fontSize: 13)),
              ),
        onTap: _checkUpdate,
      ),
    );
  }
}

class _SecurityNoticeCard extends StatelessWidget {
  const _SecurityNoticeCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.verified_user_outlined, color: Colors.green),
        ),
        title: const Text(
          '数据安全声明',
          style: TextStyle(fontSize: 15, color: Colors.black87),
        ),
        subtitle: const Text(
          '点击查看隐私保护说明',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.black26),
        onTap: () => _showSecurityDialog(context),
      ),
    );
  }

  void _showSecurityDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.verified_user_outlined, color: Colors.green),
            SizedBox(width: 8),
            Text('数据安全声明'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _NoticeSection(
                icon: Icons.storage_outlined,
                iconColor: Colors.blue,
                title: '服务端零持久化',
                body:
                    '后端服务器不存储任何用户数据。账号密码仅在每次请求时实时传输，用于完成一次性登录并抓取数据，完成后立即丢弃，不写入任何数据库或日志。',
              ),
              const SizedBox(height: 16),
              _NoticeSection(
                icon: Icons.phone_android_outlined,
                iconColor: Colors.orange,
                title: '本机加密存储',
                body:
                    '账号密码保存在本机的系统级加密存储区（Android Keystore），其他应用无法读取。宿舍信息仅保存在本机，重装 App 后需重新设置。',
              ),
              const SizedBox(height: 16),
              _NoticeSection(
                icon: Icons.wifi_outlined,
                iconColor: Colors.purple,
                title: '仅与指定后端通信',
                body: 'App 只向本项目的私有后端发起网络请求，不接入任何第三方数据收集或统计服务，不植入广告 SDK。',
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 16,
                      color: Colors.green,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '本应用为个人开发的校园工具，账号信息不会以任何形式被记录或转移，无泄露风险。',
                        style: TextStyle(fontSize: 12, color: Colors.green),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}

class _NoticeSection extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;
  const _NoticeSection({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: iconColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.black54,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 通知设置卡片
// ══════════════════════════════════════════════════════════════
class _NotificationSettingsCard extends ConsumerStatefulWidget {
  const _NotificationSettingsCard();

  @override
  ConsumerState<_NotificationSettingsCard> createState() =>
      _NotificationSettingsCardState();
}

class _NotificationSettingsCardState
    extends ConsumerState<_NotificationSettingsCard>
    with WidgetsBindingObserver {
  bool? _courseReminderEnabled;
  int? _courseReminderMinutes;

  static const List<int> _reminderMinuteOptions = [
    15,
    20,
    25,
    30,
    35,
    40,
    45,
    50,
    55,
    60,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshStatus();
    }
  }

  Future<void> _refreshStatus() async {
    final courseReminder = await NotificationService.getCourseReminderEnabled();
    final courseReminderMinutes =
        await NotificationService.getCourseReminderMinutes();
    if (mounted) {
      setState(() {
        _courseReminderEnabled = courseReminder;
        _courseReminderMinutes = courseReminderMinutes;
      });
    }
  }

  Future<bool> _rescheduleCourseReminders({String? successMessage}) async {
    final semesterStart = ref.read(activeSemesterStartProvider).valueOrNull;
    final selectedSemester = ref
        .read(selectedScheduleSemesterProvider)
        .valueOrNull;

    if (semesterStart == null) {
      debugPrint('[Profile] 开启失败：尚未设置开学日期');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请先在课程表页面设置开学日期')));
      }
      return false;
    }

    try {
      final scheduleResult = await ref.read(
        scheduleProvider(selectedSemester).future,
      );
      await NotificationService.scheduleClassReminders(
        scheduleResult.courses,
        semesterStart,
      );

      if (successMessage != null && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(successMessage)));
      }
      return true;
    } catch (e) {
      debugPrint('[Profile] 调度失败（拉取课表出错）：$e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('课表获取失败，请稍后重试')));
      }
      return false;
    }
  }

  Future<void> _onReminderMinutesSelected(int minutes) async {
    if (_courseReminderMinutes == minutes) return;

    await NotificationService.setCourseReminderMinutes(minutes);
    if (mounted) {
      setState(() => _courseReminderMinutes = minutes);
    }

    if (_courseReminderEnabled == true) {
      final ok = await _rescheduleCourseReminders();
      if (ok && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('课前提醒已改为提前 $minutes 分钟')));
      }
    } else if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已保存为提前 $minutes 分钟，开启课前提醒后生效')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentReminderMinutes =
        _courseReminderMinutes ??
        NotificationService.defaultCourseReminderMinutes;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          _SettingTile(
            icon: Icons.notifications_active_outlined,
            iconColor: _courseReminderEnabled == true
                ? Colors.deepOrange
                : Colors.grey,
            title: '课程表课前通知',
            subtitleWidget:
                _courseReminderEnabled == null || _courseReminderMinutes == null
                ? const Text(
                    '加载中...',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  )
                : Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        _courseReminderEnabled == true
                            ? '✅ 已开启，课前 $currentReminderMinutes 分钟提醒'
                            : '预警已关闭（默认提前 $currentReminderMinutes 分钟）',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      PopupMenuButton<int>(
                        initialValue: currentReminderMinutes,
                        tooltip: '设置提醒提前时间',
                        onSelected: _onReminderMinutesSelected,
                        itemBuilder: (context) => _reminderMinuteOptions
                            .map(
                              (m) => PopupMenuItem<int>(
                                value: m,
                                child: Text('提前 $m 分钟'),
                              ),
                            )
                            .toList(),
                        child: const Text(
                          '修改',
                          style: TextStyle(
                            color: Colors.blue,
                            fontSize: 12,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
            trailing: _courseReminderEnabled == null
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Switch(
                    value: _courseReminderEnabled!,
                    activeThumbColor: Colors.deepOrange,
                    onChanged: (val) async {
                      await NotificationService.setCourseReminderEnabled(val);
                      setState(() => _courseReminderEnabled = val);

                      if (!val) {
                        await NotificationService.cancelAllClassReminders();
                        debugPrint('[Profile] 课前通知已关闭，所有调度已清空');
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('课前提醒已关闭')),
                        );
                      } else {
                        final minutes =
                            _courseReminderMinutes ??
                            NotificationService.defaultCourseReminderMinutes;
                        await _rescheduleCourseReminders(
                          successMessage: '课前提醒已开启（提前 $minutes 分钟）',
                        );
                      }
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;
  final Widget trailing;

  const _SettingTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    required this.trailing,
  }) : assert(subtitle != null || subtitleWidget != null);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor),
      ),
      title: Text(
        title,
        style: const TextStyle(fontSize: 15, color: Colors.black87),
      ),
      subtitle:
          subtitleWidget ??
          Text(
            subtitle!,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
      trailing: trailing,
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 电费卡片
// ══════════════════════════════════════════════════════════════
class _ElectricityCardWidget extends ConsumerWidget {
  const _ElectricityCardWidget();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(electricityProvider);

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ElectricityPage()),
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [Color(0xFF141E30), Color(0xFF243B55)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF243B55).withValues(alpha: 0.4),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
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
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.bolt,
                        color: Colors.amberAccent,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Consumer(
                      builder: (context, ref, _) {
                        final dorm = ref.watch(dormRoomProvider).valueOrNull;
                        return Text(
                          dorm == null ? '宿舍电费' : dorm.displayName,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const Text(
                  '点击去充值',
                  style: TextStyle(color: Colors.white38, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 24),
            balanceAsync.when(
              loading: () => const SizedBox(
                height: 80,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: CircularProgressIndicator(color: Colors.white54),
                ),
              ),
              error: (e, _) => SizedBox(
                height: 80,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: e is NoDormSetException
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '未设置宿舍',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              '请在下方「宿舍设置」中选择你的宿舍',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        )
                      : const Text(
                          '获取失败',
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              data: (balanceStr) {
                final isNegative = balanceStr.contains('-');
                final absNumStr = balanceStr.replaceAll(RegExp(r'[^0-9.]'), '');
                final balValue =
                    (double.tryParse(absNumStr) ?? 0.0) * (isNegative ? -1 : 1);

                return FutureBuilder<double>(
                  future: NotificationService.getElecThreshold(),
                  initialData: NotificationService.defaultElecThreshold,
                  builder: (context, snapshot) {
                    final threshold =
                        snapshot.data ??
                        NotificationService.defaultElecThreshold;
                    final isLowBalance = threshold > 0 && balValue < threshold;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6.0),
                              child: Text(
                                isNegative ? '-¥' : '¥',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              absNumStr.isEmpty ? '0.00' : absNumStr,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 48,
                                fontWeight: FontWeight.w900,
                                height: 1.0,
                                fontFamily: 'Roboto',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: isLowBalance
                                        ? Colors.redAccent
                                        : Colors.greenAccent,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color:
                                            (isLowBalance
                                                    ? Colors.redAccent
                                                    : Colors.greenAccent)
                                                .withValues(alpha: 0.6),
                                        blurRadius: 6,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  threshold == 0
                                      ? '余额预警已关闭'
                                      : (isLowBalance
                                            ? '余额偏低，建议充值'
                                            : '余额充足，安心用电'),
                                  style: TextStyle(
                                    color: isLowBalance
                                        ? Colors.red[200]
                                        : Colors.white70,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Row(
                                children: [
                                  Text(
                                    '详情',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(width: 2),
                                  Icon(
                                    Icons.chevron_right,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
