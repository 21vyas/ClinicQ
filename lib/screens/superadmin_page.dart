// lib/screens/superadmin_page.dart
//
// Superadmin-only dashboard — top-level tenant management.
// Route: /superadmin  (protected; superadmin knows this URL)
// Queries Supabase directly for cross-tenant data.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────
// Simple models for superadmin view
// ─────────────────────────────────────────────────────────

class _Hospital {
  final String  id;
  final String  name;
  final String  slug;
  final String? phone;
  final String? address;
  final DateTime createdAt;

  const _Hospital({
    required this.id,
    required this.name,
    required this.slug,
    this.phone,
    this.address,
    required this.createdAt,
  });

  factory _Hospital.fromJson(Map<String, dynamic> j) => _Hospital(
    id:        j['id']        as String,
    name:      j['name']      as String,
    slug:      j['slug']      as String? ?? '',
    phone:     j['phone']     as String?,
    address:   j['address']   as String?,
    createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ??
        DateTime.now(),
  );
}

class _AppUser {
  final String  id;
  final String  email;
  final String? fullName;
  final String? role;
  final DateTime createdAt;

  const _AppUser({
    required this.id,
    required this.email,
    this.fullName,
    this.role,
    required this.createdAt,
  });

  factory _AppUser.fromJson(Map<String, dynamic> j) => _AppUser(
    id:        j['id']        as String,
    email:     j['email']     as String? ?? '',
    fullName:  j['full_name'] as String?,
    role:      j['role']      as String?,
    createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ??
        DateTime.now(),
  );

  String get displayName => fullName ?? email.split('@').first;
}

// ─────────────────────────────────────────────────────────
// Providers (file-local, Riverpod-free — use FutureBuilder)
// ─────────────────────────────────────────────────────────

Future<List<_Hospital>> _fetchHospitals() async {
  final data = await Supabase.instance.client
      .from('hospitals')
      .select('id, name, slug, phone, address, created_at')
      .order('created_at', ascending: false);
  return (data as List)
      .map((e) => _Hospital.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList();
}

Future<List<_AppUser>> _fetchUsers() async {
  final data = await Supabase.instance.client
      .from('app_users')
      .select('id, email, full_name, role, created_at')
      .order('created_at', ascending: false);
  return (data as List)
      .map((e) => _AppUser.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList();
}

Future<void> _updateUserRole(String email, String role) async {
  await Supabase.instance.client
      .from('app_users')
      .update({'role': role.isEmpty ? null : role})
      .eq('email', email);
}

// ─────────────────────────────────────────────────────────
// Page
// ─────────────────────────────────────────────────────────

class SuperadminPage extends ConsumerStatefulWidget {
  const SuperadminPage({super.key});

  @override
  ConsumerState<SuperadminPage> createState() => _SuperadminPageState();
}

class _SuperadminPageState extends ConsumerState<SuperadminPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  late Future<List<_Hospital>> _hospitalsFuture;
  late Future<List<_AppUser>>  _usersFuture;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _reload();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _hospitalsFuture = _fetchHospitals();
      _usersFuture     = _fetchUsers();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          // ── Tab bar ─────────────────────────────────
          Container(
            color: AppColors.surface,
            child: TabBar(
              controller: _tab,
              labelColor:          AppColors.primary,
              unselectedLabelColor: AppColors.textHint,
              indicatorColor:      AppColors.primary,
              indicatorWeight:     2.5,
              labelStyle: GoogleFonts.dmSans(
                  fontSize: 13, fontWeight: FontWeight.w600),
              tabs: const [
                Tab(text: 'Hospitals'),
                Tab(text: 'Users'),
                Tab(text: 'Role Assign'),
              ],
            ),
          ),
          Container(height: 1, color: AppColors.border),

          // ── Tab views ───────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _HospitalsTab(future: _hospitalsFuture, onRefresh: _reload),
                _UsersTab(future: _usersFuture, onRefresh: _reload),
                _RoleAssignTab(onAssigned: _reload),
              ],
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        onPressed: () => context.go('/dashboard'),
        icon: const Icon(Icons.arrow_back_rounded),
        color: AppColors.textSecondary,
      ),
      title: Row(
        children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.admin_panel_settings_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Text(
            'Superadmin',
            style: GoogleFonts.dmSans(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          onPressed: _reload,
          icon: const Icon(Icons.refresh_rounded),
          color: AppColors.textSecondary,
          tooltip: 'Refresh',
        ),
        const SizedBox(width: 8),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppColors.border),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════
// TAB 1 — Hospitals
// ═════════════════════════════════════════════════════════

class _HospitalsTab extends StatelessWidget {
  final Future<List<_Hospital>> future;
  final VoidCallback onRefresh;
  const _HospitalsTab({required this.future, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_Hospital>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.primary));
        }
        if (snap.hasError) {
          return _ErrorRetry(
            message: snap.error.toString(),
            onRetry: onRefresh,
          );
        }
        final hospitals = snap.data ?? [];
        if (hospitals.isEmpty) {
          return const _EmptyState(
            icon:    Icons.local_hospital_outlined,
            message: 'No hospitals registered yet',
          );
        }
        return Column(
          children: [
            // Summary header
            _SummaryBanner(
              icon:  Icons.local_hospital_rounded,
              color: AppColors.primary,
              label: '${hospitals.length} hospital${hospitals.length == 1 ? '' : 's'} registered',
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount:     hospitals.length,
                separatorBuilder: (_, i) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _HospitalTile(h: hospitals[i]),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _HospitalTile extends StatelessWidget {
  final _Hospital h;
  const _HospitalTile({required this.h});

  @override
  Widget build(BuildContext context) {
    final age = DateTime.now().difference(h.createdAt).inDays;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // Icon badge
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: AppColors.primarySurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.local_hospital_rounded,
                color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 14),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  h.name,
                  style: GoogleFonts.dmSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      'slug: ${h.slug}',
                      style: GoogleFonts.dmSans(
                          fontSize: 11, color: AppColors.textHint),
                    ),
                    if (h.phone != null) ...[
                      const SizedBox(width: 10),
                      const Text('·',
                          style: TextStyle(color: AppColors.textHint)),
                      const SizedBox(width: 6),
                      Text(
                        h.phone!,
                        style: GoogleFonts.dmSans(
                            fontSize: 11, color: AppColors.textHint),
                      ),
                    ],
                  ],
                ),
                if (h.address != null)
                  Text(
                    h.address!,
                    style: GoogleFonts.dmSans(
                        fontSize: 11, color: AppColors.textHint),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),

          // Age badge
          _AgeBadge(days: age),
        ],
      ),
    );
  }
}

class _AgeBadge extends StatelessWidget {
  final int days;
  const _AgeBadge({required this.days});

  @override
  Widget build(BuildContext context) {
    final label = days == 0
        ? 'Today'
        : days < 30
            ? '${days}d'
            : '${(days / 30).floor()}mo';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
            fontSize: 11,
            color: AppColors.textHint,
            fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════
// TAB 2 — Users
// ═════════════════════════════════════════════════════════

class _UsersTab extends StatelessWidget {
  final Future<List<_AppUser>> future;
  final VoidCallback onRefresh;
  const _UsersTab({required this.future, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_AppUser>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.primary));
        }
        if (snap.hasError) {
          return _ErrorRetry(
            message: snap.error.toString(),
            onRetry: onRefresh,
          );
        }
        final users = snap.data ?? [];
        if (users.isEmpty) {
          return const _EmptyState(
            icon:    Icons.people_outline_rounded,
            message: 'No users found',
          );
        }

        // Group by role
        final admins  = users.where((u) => u.role == 'admin').toList();
        final regular = users.where((u) => u.role != 'admin').toList();

        return Column(
          children: [
            _SummaryBanner(
              icon:  Icons.people_rounded,
              color: Colors.indigo,
              label: '${users.length} users  ·  ${admins.length} admin',
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (admins.isNotEmpty) ...[
                    _SectionLabel(label: 'Admins (${admins.length})'),
                    const SizedBox(height: 8),
                    ...admins.map((u) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _UserTile(user: u),
                    )),
                    const SizedBox(height: 12),
                  ],
                  if (regular.isNotEmpty) ...[
                    _SectionLabel(
                        label: 'Users (${regular.length})'),
                    const SizedBox(height: 8),
                    ...regular.map((u) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _UserTile(user: u),
                    )),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _UserTile extends StatelessWidget {
  final _AppUser user;
  const _UserTile({required this.user});

  @override
  Widget build(BuildContext context) {
    final isAdmin = user.role == 'admin';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isAdmin
              ? const Color(0xFF7C3AED).withValues(alpha: 0.3)
              : AppColors.border,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          // Avatar initial
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: isAdmin
                  ? const Color(0xFF7C3AED).withValues(alpha: 0.1)
                  : AppColors.primarySurface,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                user.displayName[0].toUpperCase(),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isAdmin
                      ? const Color(0xFF7C3AED)
                      : AppColors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayName,
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  user.email,
                  style: GoogleFonts.dmSans(
                      fontSize: 11, color: AppColors.textHint),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Role pill
          _RolePill(role: user.role),
        ],
      ),
    );
  }
}

class _RolePill extends StatelessWidget {
  final String? role;
  const _RolePill({this.role});

  @override
  Widget build(BuildContext context) {
    final label = role?.isEmpty != false ? 'user' : role!;
    final isAdmin = label == 'admin';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isAdmin
            ? const Color(0xFF7C3AED).withValues(alpha: 0.1)
            : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isAdmin
              ? const Color(0xFF7C3AED).withValues(alpha: 0.3)
              : AppColors.border,
        ),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: isAdmin
              ? const Color(0xFF7C3AED)
              : AppColors.textSecondary,
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════
// TAB 3 — Role Assignment
// ═════════════════════════════════════════════════════════

class _RoleAssignTab extends StatefulWidget {
  final VoidCallback onAssigned;
  const _RoleAssignTab({required this.onAssigned});

  @override
  State<_RoleAssignTab> createState() => _RoleAssignTabState();
}

class _RoleAssignTabState extends State<_RoleAssignTab> {
  final _emailCtrl = TextEditingController();
  String  _selectedRole = 'admin';
  bool    _isLoading    = false;
  String? _result;
  bool    _isError      = false;

  static const _roles = ['admin', 'user', 'viewer'];

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _assign() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _result  = 'Enter a valid email address';
        _isError = true;
      });
      return;
    }

    setState(() { _isLoading = true; _result = null; });

    try {
      await _updateUserRole(email, _selectedRole);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _result    = 'Role "$_selectedRole" assigned to $email';
        _isError   = false;
      });
      _emailCtrl.clear();
      widget.onAssigned();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _result    = 'Failed: ${e.toString()}';
        _isError   = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF7C3AED).withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: const Color(0xFF7C3AED).withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.manage_accounts_rounded,
                        color: Color(0xFF7C3AED), size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Manual Role Assignment',
                            style: GoogleFonts.dmSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            'Assign or change a role for any registered user by email',
                            style: GoogleFonts.dmSans(
                                fontSize: 12,
                                color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Email input
              Text(
                'User Email',
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller:   _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText:        'user@example.com',
                  prefixIcon:      const Icon(Icons.email_outlined, size: 18),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:  const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:  const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:  const BorderSide(
                        color: AppColors.primary, width: 1.5),
                  ),
                  filled:      true,
                  fillColor:   AppColors.surface,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 14),
                ),
              ),
              const SizedBox(height: 16),

              // Role selector
              Text(
                'Assign Role',
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                children: _roles.map((r) {
                  final selected = r == _selectedRole;
                  return ChoiceChip(
                    label: Text(r),
                    selected: selected,
                    onSelected: (_) => setState(() => _selectedRole = r),
                    selectedColor: AppColors.primary.withValues(alpha: 0.15),
                    labelStyle: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                    side: BorderSide(
                      color: selected
                          ? AppColors.primary
                          : AppColors.border,
                    ),
                    backgroundColor: AppColors.surface,
                    showCheckmark: false,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // Assign button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _assign,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.check_rounded, size: 18),
                  label: Text(
                    _isLoading ? 'Assigning…' : 'Assign Role',
                    style: GoogleFonts.dmSans(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    disabledBackgroundColor:
                        const Color(0xFF7C3AED).withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),

              // Result banner
              if (_result != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: _isError
                        ? AppColors.error.withValues(alpha: 0.08)
                        : AppColors.success.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isError
                          ? AppColors.error.withValues(alpha: 0.3)
                          : AppColors.success.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isError
                            ? Icons.error_outline_rounded
                            : Icons.check_circle_outline_rounded,
                        color: _isError
                            ? AppColors.error
                            : AppColors.success,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _result!,
                          style: GoogleFonts.dmSans(
                            fontSize: 13,
                            color: _isError
                                ? AppColors.error
                                : AppColors.success,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 32),

              // Module usage info section
              _ModuleUsageSection(),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Module Usage Section (inside Role tab, informational)
// ─────────────────────────────────────────────────────────

class _ModuleUsageSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Module Status',
          style: GoogleFonts.dmSans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _ModuleBadge(
                icon:    Icons.queue_rounded,
                label:   'Queue',
                status:  'Active',
                color:   AppColors.success,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ModuleBadge(
                icon:    Icons.chat_bubble_outline_rounded,
                label:   'WhatsApp',
                status:  'Coming Soon',
                color:   AppColors.textHint,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ModuleBadge(
                icon:    Icons.calendar_today_rounded,
                label:   'Appointment',
                status:  'Coming Soon',
                color:   AppColors.textHint,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              const Icon(Icons.payments_outlined,
                  color: AppColors.textSecondary, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Payment tracking per hospital is available via Supabase '
                  'dashboard — query the payments table filtered by hospital_id.',
                  style: GoogleFonts.dmSans(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ModuleBadge extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   status;
  final Color    color;

  const _ModuleBadge({
    required this.icon,
    required this.label,
    required this.status,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = status == 'Active';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isActive ? 0.07 : 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: color.withValues(alpha: isActive ? 0.25 : 0.1)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            status,
            style: GoogleFonts.dmSans(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Shared widgets
// ─────────────────────────────────────────────────────────

class _SummaryBanner extends StatelessWidget {
  final IconData icon;
  final Color    color;
  final String   label;
  const _SummaryBanner({
    required this.icon,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: GoogleFonts.dmSans(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: AppColors.textHint,
      letterSpacing: 0.5,
    ),
  );
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String   message;
  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 44,
            color: AppColors.textHint.withValues(alpha: 0.4)),
        const SizedBox(height: 12),
        Text(message,
            style: GoogleFonts.dmSans(
                fontSize: 14, color: AppColors.textHint)),
      ],
    ),
  );
}

class _ErrorRetry extends StatelessWidget {
  final String       message;
  final VoidCallback onRetry;
  const _ErrorRetry({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.error, size: 40),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
                fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon:  const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Retry'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    ),
  );
}
