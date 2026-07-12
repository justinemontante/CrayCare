import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_colors.dart';
import 'login_screen.dart';
import '../services/settings_service.dart';
import '../widgets/settings/settings_menu.dart';
import '../widgets/settings/profile_edit_form.dart';
import '../widgets/settings/change_password_form.dart';
import '../widgets/settings/notif_settings.dart';
import '../widgets/settings/stage_settings.dart';
import '../widgets/settings/logout_sheet.dart';
import '../services/database_service.dart';
import '../services/storage_service.dart'; // Para sa pag-pick ng profile picture
import '../services/auth_service.dart';

class SettingsScreen extends StatefulWidget {
  final String? initialPhotoUrl;

  const SettingsScreen({super.key, this.initialPhotoUrl});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _currentPage = 0;
  String _profileName = 'Loading...';
  String _profileEmail = 'Loading...';
  String? _photoUrl; // URL ng profile picture galing RTDB

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _currentPwCtrl = TextEditingController();
  final _newPwCtrl = TextEditingController();
  final _confirmPwCtrl = TextEditingController();

  bool _notifSound = true;
  bool _notifVibration = true;
  bool _notifCritical = true;
  bool _notifFeeding = true;
  bool _notifSampling = true;
  bool _notifWarning = true;

  @override
  void initState() {
    super.initState();
    SettingsService.instance.addListener(_onSettingsChange);
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      setState(() {
        _profileName = user.displayName ?? 'CrayCare User';
        _profileEmail = user.email ?? 'No email linked';
      });
      if (widget.initialPhotoUrl != null) {
        setState(() => _photoUrl = widget.initialPhotoUrl);
      } else {
        _loadPhotoFromRTDB(user.uid);
      }
      final notifPrefs = await DatabaseService.instance.getNotificationPrefs(user.uid);
      if (notifPrefs != null && mounted) {
        setState(() {
          _notifSound = notifPrefs['sound'] as bool? ?? true;
          _notifVibration = notifPrefs['vibration'] as bool? ?? true;
          _notifCritical = notifPrefs['critical'] as bool? ?? true;
          _notifFeeding = notifPrefs['feeding'] as bool? ?? true;
          _notifSampling = notifPrefs['sampling'] as bool? ?? true;
          _notifWarning = notifPrefs['warning'] as bool? ?? true;
        });
      }
    }
  }

  Future<void> _loadPhotoFromRTDB(String uid) async {
    final data = await DatabaseService.instance.getUserProfile(uid);
    if (data != null && data['photoUrl'] != null && mounted) {
      setState(() => _photoUrl = data['photoUrl'] as String);
    }
  }

  @override
  void dispose() {
    SettingsService.instance.removeListener(_onSettingsChange);
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _currentPwCtrl.dispose();
    _newPwCtrl.dispose();
    _confirmPwCtrl.dispose();
    super.dispose();
  }

  void _onSettingsChange() => setState(() {});

  Future<void> _saveNotifPrefs() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await DatabaseService.instance.saveNotificationPrefs(
      uid: user.uid,
      sound: _notifSound,
      vibration: _notifVibration,
      critical: _notifCritical,
      feeding: _notifFeeding,
      sampling: _notifSampling,
      warning: _notifWarning,
    );
  }

  void _goTo(int page) {
    _nameCtrl.text = _profileName;
    _emailCtrl.text = _profileEmail;
    setState(() => _currentPage = page);
  }

  void _back() {
    if (_currentPage == 0) {
      Navigator.of(context).pop(_photoUrl); // Ibalik ang photoUrl para iwas reload
    } else {
      setState(() => _currentPage = 0);
    }
  }

  void _showSuccessModal({String message = 'Your profile name has been saved!'}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF22c55e).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF22c55e),
                size: 50,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Updated Successfully!',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppColors.dark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.dark.withValues(alpha: 0.6),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _back();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Done',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndUploadPicture() async {
    try {
      // Pumili ng picture at i-convert sa base64
      final url = await StorageService.instance.pickAndConvertToBase64();
      if (url != null && mounted) {
        // I-save ang URL sa RTDB
        final user = FirebaseAuth.instance.currentUser!;
        await DatabaseService.instance.saveUserProfile(
          uid: user.uid,
          name: _profileName,
          email: user.email ?? '',
          photoUrl: url,
        );
        // I-update agad ang preview sa avatar
        setState(() => _photoUrl = url);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile picture updated!')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _saveProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null &&
        _nameCtrl.text.isNotEmpty &&
        _nameCtrl.text != _profileName) {
      await user.updateDisplayName(_nameCtrl.text);
      // Masesave din sa Realtime Database for permanent record
      await DatabaseService.instance.saveUserProfile(
        uid: user.uid,
        name: _nameCtrl.text,
        email: user.email ?? '',
      );
    }

    setState(() {
      _profileName = _nameCtrl.text.isNotEmpty ? _nameCtrl.text : _profileName;
    });

    if (mounted) {
      _showSuccessModal();
    }
  }

  Future<void> _changePassword() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user?.email == null) {
      throw Exception('No user logged in.');
    }

    await AuthService().changePassword(
      email: user!.email!,
      currentPassword: _currentPwCtrl.text,
      newPassword: _newPwCtrl.text,
    );

    _currentPwCtrl.clear();
    _newPwCtrl.clear();
    _confirmPwCtrl.clear();

    if (mounted) {
      _showSuccessModal(message: 'Your password has been changed successfully!');
    }
  }

  void _showLogoutSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => LogoutSheet(
        onLogout: () async {
          try {
            await AuthService().signOut();
            if (!ctx.mounted) return;
            Navigator.of(ctx).pop();
            Navigator.of(context).pop();
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const LoginScreen()),
              (route) => false,
            );
          } catch (e) {
            if (!ctx.mounted) return;
            ScaffoldMessenger.of(
              ctx,
            ).showSnackBar(SnackBar(content: Text('Error logging out: $e')));
          }
        },
      ),
    );
  }

  String get _pageTitle {
    switch (_currentPage) {
      case 1:
        return 'Edit Profile';
      case 2:
        return 'Change Password';
      case 3:
        return 'Notifications';
      case 4:
        return 'Crayfish Stage';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Column(
        children: [
          Container(
            height: MediaQuery.of(context).padding.top,
            color: Colors.white,
          ),
          _buildHeader(),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeIn,
              switchOutCurve: Curves.easeOut,
              layoutBuilder: (child, List<Widget> previousChildren) {
                return Stack(
                  alignment: Alignment.topCenter,
                  children: [...previousChildren, if (child != null) child],
                );
              },
              child: [
                SettingsMenu(
                  key: const ValueKey('menu'),
                  profileName: _profileName,
                  profileEmail: _profileEmail,
                  onGoTo: _goTo,
                  onLogout: _showLogoutSheet,
                  photoUrl: _photoUrl,
                ),
                ProfileEditForm(
                  key: const ValueKey('edit-profile'),
                  nameCtrl: _nameCtrl,
                  emailCtrl: _emailCtrl,
                  onSave: _saveProfile,
                  onTapCamera: _pickAndUploadPicture,
                  photoUrl: _photoUrl,
                ),
                ChangePasswordForm(
                  key: const ValueKey('change-password'),
                  currentPwCtrl: _currentPwCtrl,
                  newPwCtrl: _newPwCtrl,
                  confirmPwCtrl: _confirmPwCtrl,
                  onChangePassword: _changePassword,
                ),
                NotifSettings(
                  key: const ValueKey('notifications'),
                  notifSound: _notifSound,
                  notifVibration: _notifVibration,
                  notifCritical: _notifCritical,
                  notifWarning: _notifWarning,
                  notifFeeding: _notifFeeding,
                  notifSampling: _notifSampling,
                  onNotifSoundChanged: (v) {
                    setState(() => _notifSound = v ?? true);
                    _saveNotifPrefs();
                  },
                  onNotifVibrationChanged: (v) {
                    setState(() => _notifVibration = v ?? true);
                    _saveNotifPrefs();
                  },
                  onNotifCriticalChanged: (v) {
                    setState(() => _notifCritical = v ?? true);
                    _saveNotifPrefs();
                  },
                  onNotifWarningChanged: (v) {
                    setState(() => _notifWarning = v ?? true);
                    _saveNotifPrefs();
                  },
                  onNotifFeedingChanged: (v) {
                    setState(() => _notifFeeding = v ?? true);
                    _saveNotifPrefs();
                  },
                  onNotifSamplingChanged: (v) {
                    setState(() => _notifSampling = v ?? true);
                    _saveNotifPrefs();
                  },
                ),
                StageSettings(key: const ValueKey('stage-settings')),
              ][_currentPage],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final Widget header = Container(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
      decoration: const BoxDecoration(
        color: Colors.transparent,
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 20),
            color: AppColors.dark,
            onPressed: _back,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
          const SizedBox(width: 4),
          Text(
            _currentPage == 0 ? 'Profile & Settings' : _pageTitle,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.dark,
            ),
          ),
        ],
      ),
    );

    return ClipRRect(
      child: Stack(
        children: [
          Positioned.fill(
            child: Align(
              alignment: const Alignment(0.7, 0),
              child: Transform.scale(
                scale: 1.8,
                child: Image.asset(
                  'assets/images/crayfish_stage_image.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          header,
        ],
      ),
    );
  }
}
