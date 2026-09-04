import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../theme/app_colors.dart';
import 'login_screen.dart';
import '../widgets/settings/settings_menu.dart';
import '../widgets/settings/profile_edit_form.dart';
import '../widgets/settings/change_password_form.dart';
import '../widgets/settings/notif_settings.dart';
import '../widgets/settings/sensor_threshold_settings.dart';
import '../widgets/settings/logout_sheet.dart';
import '../services/database_service.dart';
import '../services/storage_service.dart'; // Para sa pag-pick ng profile picture
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../utils/snackbar_helper.dart';

class SettingsScreen extends StatefulWidget {
  final String? initialPhotoUrl;
  final ImageProvider<Object>? initialPhotoImage;

  const SettingsScreen({
    super.key,
    this.initialPhotoUrl,
    this.initialPhotoImage,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  int _currentPage = 0;
  String _profileName = 'Loading...';
  String _profileEmail = 'Loading...';
  String? _photoUrl; // Canonical users/{uid}.photo_url from Firestore
  ImageProvider<Object>? _photoImage;
  bool _isAdmin = false;
  bool _roleResolved = false;
  bool _hasPasswordProvider = false;

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
  bool _notifOperational = true;
  AuthorizationStatus _notificationPermission =
      AuthorizationStatus.notDetermined;
  bool _notificationPermissionBusy = false;
  Timer? _notifSaveDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _photoUrl = widget.initialPhotoUrl;
    _photoImage =
        widget.initialPhotoImage ?? _decodePhoto(widget.initialPhotoUrl);
    _loadUserData();
    unawaited(_refreshNotificationPermission());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshNotificationPermission());
    }
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _hasPasswordProvider = user.providerData.any(
        (provider) => provider.providerId == 'password',
      );
      final profile = await DatabaseService.instance.getUserProfile(user.uid);
      if (profile != null && mounted) {
        final normalizedRole = profile['role']?.toString().trim().toLowerCase();
        setState(() {
          _profileName =
              (profile['full_name'] as String?) ??
              (profile['displayName'] as String?) ??
              user.displayName ??
              'CrayCare User';
          _profileEmail =
              (profile['email'] as String?) ?? user.email ?? 'No email linked';
          _isAdmin = normalizedRole == 'admin';
          _roleResolved = true;
        });
      } else if (mounted) {
        setState(() {
          _profileName = user.displayName ?? 'CrayCare User';
          _profileEmail = user.email ?? 'No email linked';
          _isAdmin = false;
          _roleResolved = true;
        });
      }
      if (widget.initialPhotoUrl == null) {
        _loadPhotoFromFirestore(user.uid);
      }
      final isOwner =
          profile?['role']?.toString().trim().toLowerCase() == 'owner';
      final notifPrefs = isOwner
          ? await DatabaseService.instance.getNotificationPrefs(user.uid)
          : null;
      if (notifPrefs != null && mounted) {
        setState(() {
          _notifSound = notifPrefs['sound'] as bool? ?? true;
          _notifVibration = notifPrefs['vibration'] as bool? ?? true;
          _notifCritical = notifPrefs['critical'] as bool? ?? true;
          _notifFeeding = notifPrefs['feeding'] as bool? ?? true;
          _notifSampling = notifPrefs['sampling'] as bool? ?? true;
          _notifWarning = notifPrefs['warning'] as bool? ?? true;
          _notifOperational = notifPrefs['operational'] as bool? ?? true;
        });
      }
    }
  }

  Future<void> _loadPhotoFromFirestore(String uid) async {
    final data = await DatabaseService.instance.getUserProfile(uid);
    final photo = data?['photo_url'] ?? data?['photoUrl'];
    if (photo is String && mounted) {
      _setPhoto(photo);
    }
  }

  ImageProvider<Object>? _decodePhoto(String? value) {
    if (value == null || value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return NetworkImage(value);
    }
    try {
      return MemoryImage(base64Decode(value.split(',').last));
    } on FormatException {
      return null;
    }
  }

  void _setPhoto(String value) {
    if (value == _photoUrl && _photoImage != null) return;
    final image = _decodePhoto(value);
    if (!mounted) return;
    setState(() {
      _photoUrl = value;
      _photoImage = image;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final hasPendingNotifSave = _notifSaveDebounce?.isActive ?? false;
    _notifSaveDebounce?.cancel();
    if (hasPendingNotifSave && _roleResolved && !_isAdmin) {
      unawaited(_saveNotifPrefs());
    }
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _currentPwCtrl.dispose();
    _newPwCtrl.dispose();
    _confirmPwCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshNotificationPermission() async {
    try {
      final status = await NotificationService.instance
          .notificationAuthorizationStatus();
      if (mounted) setState(() => _notificationPermission = status);
    } catch (e) {
      debugPrint('[Settings] Notification permission status error: $e');
    }
  }

  Future<void> _handleNotificationPermissionAction() async {
    if (_notificationPermissionBusy) return;
    setState(() => _notificationPermissionBusy = true);
    try {
      if (_notificationPermission == AuthorizationStatus.notDetermined) {
        await NotificationService.instance.requestNotificationPermission();
        await _refreshNotificationPermission();
      } else {
        final opened = await NotificationService.instance
            .openNotificationSettings();
        if (!opened && mounted) {
          showBeautifulSnackbar(
            context,
            'Could not open phone notification settings.',
            false,
          );
        }
      }
    } finally {
      if (mounted) setState(() => _notificationPermissionBusy = false);
    }
  }

  Future<void> _saveNotifPrefs() async {
    if (!_roleResolved || _isAdmin) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await DatabaseService.instance.saveNotificationPrefs(
      uid: user.uid,
      sound: _notifSound,
      vibration: _notifVibration,
      critical: _notifCritical,
      feeding: _notifFeeding,
      sampling: _notifSampling,
      operational: _notifOperational,
      warning: _notifWarning,
    );
  }

  void _scheduleNotifPrefsSave() {
    if (!_roleResolved || _isAdmin) return;
    _notifSaveDebounce?.cancel();
    _notifSaveDebounce = Timer(
      const Duration(milliseconds: 450),
      () => unawaited(_saveNotifPrefs()),
    );
  }

  void _goTo(int page) {
    if ((!_roleResolved || _isAdmin) && (page == 3 || page == 4)) return;
    if (page == 1) {
      _nameCtrl.text = _profileName;
      _emailCtrl.text = _profileEmail;
    }
    setState(() => _currentPage = page);
  }

  void _back() {
    if (_currentPage == 0) {
      Navigator.of(
        context,
      ).pop(_photoUrl); // Ibalik ang photoUrl para iwas reload
    } else {
      setState(() => _currentPage = 0);
    }
  }

  void _showSuccessModal({
    String message = 'Your profile name has been saved!',
  }) {
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
        // Save the compact data URL to the canonical Firestore profile field.
        final user = FirebaseAuth.instance.currentUser!;
        await DatabaseService.instance.saveUserProfile(
          uid: user.uid,
          name: _profileName,
          email: user.email ?? '',
          photoUrl: url,
        );
        // I-update agad ang preview sa avatar
        _setPhoto(url);
        if (mounted) {
          showBeautifulSnackbar(context, 'Profile picture updated.', true);
        }
      }
    } catch (e) {
      if (mounted) {
        showBeautifulSnackbar(
          context,
          e.toString().replaceFirst('Exception: ', ''),
          false,
        );
      }
    }
  }

  Future<void> _saveProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    final previousName = _profileName;
    final nextName = _nameCtrl.text.trim();

    if (nextName.isEmpty) {
      throw Exception('Full name cannot be empty.');
    }

    if (user == null) {
      throw Exception('No user logged in.');
    }

    if (nextName == previousName) {
      _back();
      return;
    }

    try {
      await user.updateDisplayName(nextName);
      await DatabaseService.instance.saveUserProfile(
        uid: user.uid,
        name: nextName,
        email: user.email ?? '',
      );
      if (!mounted) return;
      setState(() => _profileName = nextName);
      _showSuccessModal();
    } catch (e) {
      throw Exception('Could not save profile changes: $e');
    }
  }

  Future<void> _changePassword() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user?.email == null) {
      throw Exception('No user logged in.');
    }

    final wasCreatingPassword = !_hasPasswordProvider;
    if (!wasCreatingPassword) {
      await AuthService().changePassword(
        email: user!.email!,
        currentPassword: _currentPwCtrl.text,
        newPassword: _newPwCtrl.text,
      );
    } else {
      await AuthService().createPasswordForCurrentUser(
        email: user!.email!,
        newPassword: _newPwCtrl.text,
      );
      await user.reload();
      if (mounted) {
        setState(() => _hasPasswordProvider = true);
      }
    }

    _currentPwCtrl.clear();
    _newPwCtrl.clear();
    _confirmPwCtrl.clear();

    if (mounted) {
      _showSuccessModal(
        message: wasCreatingPassword
            ? 'Your password has been created successfully! You can now sign in using Google or your email and password.'
            : 'Your password has been changed successfully!',
      );
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
            if (!ctx.mounted || !mounted) return;
            Navigator.of(ctx).pop();
            Navigator.of(context).pop();
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const LoginScreen()),
              (route) => false,
            );
          } catch (e) {
            if (!ctx.mounted || !mounted) return;
            showBeautifulSnackbar(
              ctx,
              'Could not log out: ${e.toString().replaceFirst('Exception: ', '')}',
              false,
            );
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
        return _hasPasswordProvider ? 'Change Password' : 'Create Password';
      case 3:
        return 'Notifications';
      case 4:
        return 'Sensor Thresholds';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
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
              duration: const Duration(milliseconds: 180),
              reverseDuration: const Duration(milliseconds: 120),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final slide = Tween<Offset>(
                  begin: const Offset(0.025, 0),
                  end: Offset.zero,
                ).animate(animation);
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: slide, child: child),
                );
              },
              layoutBuilder: (child, List<Widget> previousChildren) {
                return Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    ...previousChildren,
                    ...?child != null ? [child] : null,
                  ],
                );
              },
              child: [
                SettingsMenu(
                  key: const ValueKey('menu'),
                  profileName: _profileName,
                  profileEmail: _profileEmail,
                  onGoTo: _goTo,
                  onLogout: _showLogoutSheet,
                  photoImage: _photoImage,
                  isAdmin: _isAdmin || !_roleResolved,
                  hasPasswordProvider: _hasPasswordProvider,
                ),
                ProfileEditForm(
                  key: const ValueKey('edit-profile'),
                  nameCtrl: _nameCtrl,
                  emailCtrl: _emailCtrl,
                  onSave: _saveProfile,
                  onTapCamera: _pickAndUploadPicture,
                  photoImage: _photoImage,
                ),
                ChangePasswordForm(
                  key: const ValueKey('change-password'),
                  currentPwCtrl: _currentPwCtrl,
                  newPwCtrl: _newPwCtrl,
                  confirmPwCtrl: _confirmPwCtrl,
                  onChangePassword: _changePassword,
                  isCreatingPassword: !_hasPasswordProvider,
                ),
                NotifSettings(
                  key: const ValueKey('notifications'),
                  notifSound: _notifSound,
                  notifVibration: _notifVibration,
                  notifCritical: _notifCritical,
                  notifWarning: _notifWarning,
                  notifFeeding: _notifFeeding,
                  notifSampling: _notifSampling,
                  notifOperational: _notifOperational,
                  notificationPermissionStatus:
                      switch (_notificationPermission) {
                        AuthorizationStatus.authorized => 'Allowed',
                        AuthorizationStatus.provisional => 'Allowed',
                        AuthorizationStatus.denied => 'Blocked',
                        _ => 'Not enabled',
                      },
                  notificationPermissionAllowed:
                      _notificationPermission ==
                          AuthorizationStatus.authorized ||
                      _notificationPermission ==
                          AuthorizationStatus.provisional,
                  notificationPermissionBusy: _notificationPermissionBusy,
                  onNotificationPermissionAction:
                      _handleNotificationPermissionAction,
                  onNotifSoundChanged: (v) {
                    _notifSound = v ?? true;
                    _scheduleNotifPrefsSave();
                  },
                  onNotifVibrationChanged: (v) {
                    _notifVibration = v ?? true;
                    _scheduleNotifPrefsSave();
                  },
                  onNotifCriticalChanged: (v) {
                    _notifCritical = v ?? true;
                    _scheduleNotifPrefsSave();
                  },
                  onNotifWarningChanged: (v) {
                    _notifWarning = v ?? true;
                    _scheduleNotifPrefsSave();
                  },
                  onNotifFeedingChanged: (v) {
                    _notifFeeding = v ?? true;
                    _scheduleNotifPrefsSave();
                  },
                  onNotifSamplingChanged: (v) {
                    _notifSampling = v ?? true;
                    _scheduleNotifPrefsSave();
                  },
                  onNotifOperationalChanged: (v) {
                    _notifOperational = v ?? true;
                    _scheduleNotifPrefsSave();
                  },
                ),
                SensorThresholdSettings(
                  key: const ValueKey('sensor-thresholds'),
                ),
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
      decoration: const BoxDecoration(color: Colors.transparent),
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
      child: ColoredBox(
        color: Colors.white,
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
      ),
    );
  }
}
