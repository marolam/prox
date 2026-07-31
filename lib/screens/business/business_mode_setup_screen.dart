import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:prox/services/business_mode/business_mode_state_service.dart';
import 'package:prox/services/business_mode_service.dart';
import 'package:prox/services/image_picker_guard.dart';
import 'package:prox/services/monetization_service.dart';
import 'package:prox/release/release_flags.dart';

/// Business Mode Setup & Avatar Selection Screen
///
/// Guides users through business mode setup and avatar configuration
class BusinessModeSetupScreen extends StatefulWidget {
  const BusinessModeSetupScreen({super.key});

  @override
  State<BusinessModeSetupScreen> createState() =>
      _BusinessModeSetupScreenState();
}

class _BusinessModeSetupScreenState extends State<BusinessModeSetupScreen> {
  int _currentStep = 0;
  bool _saving = false;
  String? _error;

  String _businessName = '';
  String _businessDescription = '';
  String? _businessCategory;
  String _selectedTier = 'business';
  String _avatarName = '';
  String _avatarType = 'business';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Business Mode Setup'),
        elevation: 0,
      ),
      body: IndexedStack(
        index: _currentStep,
        children: [
          _BusinessInfoStep(
            initialName: _businessName,
            initialDescription: _businessDescription,
            initialCategory: _businessCategory,
            onContinue: (name, description, category) {
              setState(() {
                _businessName = name;
                _businessDescription = description;
                _businessCategory = category;
              });
              _nextStep();
            },
          ),
          _SubscriptionStep(
            initialTier: _selectedTier,
            onContinue: (tier) {
              setState(() => _selectedTier = tier);
              _nextStep();
            },
            onBack: _previousStep,
          ),
          _AvatarStep(
            initialName: _avatarName,
            initialType: _avatarType,
            onContinue: (name, type) {
              setState(() {
                _avatarName = name;
                _avatarType = type;
              });
              _nextStep();
            },
            onBack: _previousStep,
          ),
          _ConfirmationStep(
            onBack: _previousStep,
            onFinish: _saveAndFinish,
            saving: _saving,
            error: _error,
          ),
        ],
      ),
    );
  }

  Future<void> _saveAndFinish() async {
    if (_saving) return;

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.trim().isEmpty) {
      setState(() => _error = 'You must be signed in.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await BusinessModeService.instance.createBusinessProfile(
        businessName: _businessName.trim(),
        businessDescription: _businessDescription.trim(),
        businessCategory: _businessCategory,
      );

      if (_selectedTier == 'business') {
        bool timedOut = false;
        final ok = await MonetizationService.instance
            .startMonthlySubscriptionWithPoints(uid)
            .timeout(
              ReleaseFlags.permissiveTesterUX
                  ? const Duration(seconds: 10)
                  : const Duration(seconds: 35),
              onTimeout: () {
                timedOut = true;
                return false;
              },
            );
        if (timedOut && ReleaseFlags.permissiveTesterUX) {
          await BusinessModeStateService.instance.setTesterUnlocked(uid, true);
          await BusinessModeStateService.instance.setActive(uid, true);
        } else if (!ok) {
          throw Exception('Not enough points to activate Business Mode subscription.');
        } else {
          await BusinessModeStateService.instance.setActive(uid, true);
        }
      }

      if (_avatarName.trim().isNotEmpty) {
        await BusinessModeService.instance.createAvatar(
          name: _avatarName.trim(),
          description: 'Auto-responder for $_businessName',
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Business Mode setup complete.')),
      );
      Navigator.of(context).pop();
    } on FirebaseException catch (e) {
      if (!mounted) return;
      final msg = e.code == 'permission-denied'
          ? 'Setup failed: Firestore permission denied for business profile writes.'
          : 'Setup failed: ${e.message ?? e.code}';
      setState(() => _error = msg);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Setup failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _nextStep() {
    if (_currentStep < 3) {
      setState(() => _currentStep++);
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }
}

/// Step 1: Business Info
class _BusinessInfoStep extends StatefulWidget {
  final String initialName;
  final String initialDescription;
  final String? initialCategory;
  final void Function(String name, String description, String? category) onContinue;

  const _BusinessInfoStep({
    required this.initialName,
    required this.initialDescription,
    required this.initialCategory,
    required this.onContinue,
  });

  @override
  State<_BusinessInfoStep> createState() => _BusinessInfoStepState();
}

class _BusinessInfoStepState extends State<_BusinessInfoStep> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _descriptionController = TextEditingController(text: widget.initialDescription);
    _selectedCategory = widget.initialCategory;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tell us about your business',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'This helps other Prox users find and connect with you',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
            const SizedBox(height: 32),
            // Business name
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Business Name',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              validator: (value) =>
                  value?.isEmpty ?? true ? 'Business name required' : null,
            ),
            const SizedBox(height: 16),
            // Business category
            DropdownButtonFormField<String>(
              initialValue: _selectedCategory,
              hint: const Text('Select Category'),
              decoration: InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              items: [
                'Freelancer',
                'Service',
                'Retail',
                'Tech',
                'Other',
              ]
                  .map((cat) => DropdownMenuItem(
                        value: cat,
                        child: Text(cat),
                      ))
                  .toList(),
              onChanged: (value) =>
                  setState(() => _selectedCategory = value),
              validator: (value) =>
                  value == null ? 'Category required' : null,
            ),
            const SizedBox(height: 16),
            // Business description
            TextFormField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: 'Business Description',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              maxLines: 4,
              validator: (value) => value?.isEmpty ?? true
                  ? 'Description required'
                  : null,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    widget.onContinue(
                      _nameController.text.trim(),
                      _descriptionController.text.trim(),
                      _selectedCategory,
                    );
                  }
                },
                child: const Text('Continue'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Step 2: Subscription Selection
class _SubscriptionStep extends StatefulWidget {
  final String initialTier;
  final void Function(String tier) onContinue;
  final VoidCallback onBack;

  const _SubscriptionStep({
    required this.initialTier,
    required this.onContinue,
    required this.onBack,
  });

  @override
  State<_SubscriptionStep> createState() => _SubscriptionStepState();
}

class _SubscriptionStepState extends State<_SubscriptionStep> {
  late String _selectedTier;

  @override
  void initState() {
    super.initState();
    _selectedTier = widget.initialTier;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose Your Subscription',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Unlock advanced features for your business',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
          const SizedBox(height: 32),
          // Free tier
          _SubscriptionTierCard(
            title: 'Business',
            price: '\$50/month (50 points)',
            features: [
              'Auto-responder avatar',
              'Priority matching',
              'Business store unlocks',
            ],
            isSelected: _selectedTier == 'business',
            isPremium: true,
            onTap: () => setState(() => _selectedTier = 'business'),
          ),
          const SizedBox(height: 32),
          // Navigation buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onBack,
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => widget.onContinue(_selectedTier),
                  child: const Text('Continue'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Subscription tier card
class _SubscriptionTierCard extends StatelessWidget {
  final String title;
  final String price;
  final List<String> features;
  final bool isSelected;
  final bool isPremium;
  final VoidCallback onTap;

  const _SubscriptionTierCard({
    required this.title,
    required this.price,
    required this.features,
    required this.isSelected,
    this.isPremium = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surface,
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      price,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                  ],
                ),
                if (isPremium)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Premium',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Colors.white,
                          ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ...features.map((feature) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          feature,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

/// Step 3: Avatar Configuration
class _AvatarStep extends StatefulWidget {
  final String initialName;
  final String initialType;
  final void Function(String name, String type) onContinue;
  final VoidCallback onBack;

  const _AvatarStep({
    required this.initialName,
    required this.initialType,
    required this.onContinue,
    required this.onBack,
  });

  @override
  State<_AvatarStep> createState() => _AvatarStepState();
}

class _AvatarStepState extends State<_AvatarStep> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _avatarNameController;
  String _avatarType = 'business';
  Uint8List? _selectedImageBytes;
  bool _pickingImage = false;

  @override
  void initState() {
    super.initState();
    _avatarNameController = TextEditingController(text: widget.initialName);
    _avatarType = widget.initialType;
  }

  @override
  void dispose() {
    _avatarNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Create Your Avatar',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your avatar represents you in the Prox community',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
            const SizedBox(height: 32),
            // Avatar preview
            Center(
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  image: _selectedImageBytes != null
                      ? DecorationImage(
                          image: MemoryImage(_selectedImageBytes!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: _selectedImageBytes == null
                    ? Icon(
                        Icons.person,
                        size: 60,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 12),
              Center(
                child: TextButton.icon(
                  onPressed: _pickingImage ? null : _pickImage,
                  icon: const Icon(Icons.photo_camera),
                  label: const Text('Upload Photo'),
                ),
              ),
            const SizedBox(height: 32),
            // Avatar name
            TextFormField(
              controller: _avatarNameController,
              decoration: InputDecoration(
                labelText: 'Avatar Name',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              validator: (value) =>
                  value?.isEmpty ?? true ? 'Avatar name required' : null,
            ),
            const SizedBox(height: 16),
            // Avatar type
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(label: Text('Personal'), value: 'personal'),
                ButtonSegment(label: Text('Business'), value: 'business'),
              ],
              selected: {_avatarType},
              onSelectionChanged: (Set<String> newSelection) {
                setState(() => _avatarType = newSelection.first);
              },
            ),
            const SizedBox(height: 32),
            // Navigation buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onBack,
                    child: const Text('Back'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      if (_formKey.currentState!.validate()) {
                        widget.onContinue(
                          _avatarNameController.text.trim(),
                          _avatarType,
                        );
                      }
                    },
                    child: const Text('Continue'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    if (_pickingImage || ImagePickerGuard.isActive) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image picker is already open.')),
      );
      return;
    }

    if (!ImagePickerGuard.tryAcquire()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image picker is already open.')),
      );
      return;
    }

    setState(() => _pickingImage = true);
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        imageQuality: 85,
      );
      if (!mounted || file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _selectedImageBytes = bytes;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo selected for avatar preview.')),
      );
    } catch (e) {
      final String msg = e.toString().toLowerCase();
      if (msg.contains('already_active') || msg.contains('already being used')) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image picker is already open.')),
        );
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Couldn\'t open image picker: $e')),
      );
    } finally {
      ImagePickerGuard.release();
      if (mounted) {
        setState(() => _pickingImage = false);
      } else {
        _pickingImage = false;
      }
    }
  }
}

/// Step 4: Confirmation
class _ConfirmationStep extends StatelessWidget {
  final VoidCallback onBack;
  final Future<void> Function() onFinish;
  final bool saving;
  final String? error;

  const _ConfirmationStep({
    required this.onBack,
    required this.onFinish,
    required this.saving,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'You\'re All Set!',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              border: Border.all(color: Colors.green),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Business mode activated',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Your business profile is now live. Other Prox users can find and connect with you.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'What\'s Next?',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          _NextStepTile(
            icon: Icons.store,
            title: 'Explore the Store',
            subtitle: 'Browse and purchase items to customize your profile',
          ),
          const SizedBox(height: 8),
          _NextStepTile(
            icon: Icons.palette,
            title: 'Color Matching',
            subtitle: 'Use the full-screen color feature to find matches',
          ),
          const SizedBox(height: 8),
          _NextStepTile(
            icon: Icons.leaderboard,
            title: 'Check Leaderboard',
            subtitle: 'Compete with other users and climb the rankings',
          ),
          const SizedBox(height: 32),
          if (error != null) ...[
            Text(
              error!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 12),
          ],
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: saving ? null : onFinish,
              child: Text(saving ? 'Saving...' : 'Start Using Prox'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Next step tile
class _NextStepTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _NextStepTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(
          color: Theme.of(context).colorScheme.outline,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.arrow_forward,
            size: 16,
            color: Theme.of(context).colorScheme.outline,
          ),
        ],
      ),
    );
  }
}
