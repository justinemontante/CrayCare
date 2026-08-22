from pathlib import Path


def replace_once(path, old, new):
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected 1 match, found {count}')
    p.write_text(text.replace(old, new, 1), encoding='utf-8')
    print('patched', path)


# Returning unverified users already have an active session after AuthService.signIn.
# Do not immediately resend here; VerifyScreen owns resend + cooldown handling.
replace_once(
    'lib/screens/signup_screen.dart',
    """        final user = FirebaseAuth.instance.currentUser;
        if (user != null && !user.emailVerified) {
          await user.sendEmailVerification();
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const VerifyScreen()),
          );
          return;
        }
""",
    """        final user = FirebaseAuth.instance.currentUser;
        if (user != null && !user.emailVerified) {
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const VerifyScreen()),
          );
          return;
        }
""",
)

# Dispose temporary grow-out form controllers after the bottom sheet closes.
replace_once(
    'lib/screens/production_screen.dart',
    """      },
    );
  }

  Widget _buildBatchNameField(TextEditingController controller) {""",
    """      },
    ).whenComplete(() {
      batchNameCtrl.dispose();
      countCtrl.dispose();
      sampleCountCtrl.dispose();
      totalWeightCtrl.dispose();
      totalLengthCtrl.dispose();
    });
  }

  Widget _buildBatchNameField(TextEditingController controller) {""",
)

# Dispose mortality input controller after its sheet closes.
replace_once(
    'lib/screens/production_screen.dart',
    """      },
    );
  }

  void _showLogsModal() {""",
    """      },
    ).whenComplete(countCtrl.dispose);
  }

  void _showLogsModal() {""",
)

# Dispose threshold editor controllers after the dialog closes.
replace_once(
    'lib/widgets/settings/sensor_threshold_settings.dart',
    """      ),
    );
  }

  Widget _buildModalField(String label, TextEditingController ctrl, String unit) {""",
    """      ),
    ).whenComplete(() {
      minCtrl.dispose();
      maxCtrl.dispose();
    });
  }

  Widget _buildModalField(String label, TextEditingController ctrl, String unit) {""",
)

print('Follow-up audit fixes applied.')
