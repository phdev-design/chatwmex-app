import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app/features/profile/providers/profile_provider.dart';

class EditProfilePage extends ConsumerStatefulWidget {
  const EditProfilePage({super.key});

  @override
  ConsumerState<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends ConsumerState<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _bioController = TextEditingController();

  bool _didBindInitialData = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(profileViewModelProvider.notifier).loadProfile();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(profileViewModelProvider);

    ref.listen(profileViewModelProvider, (prev, next) {
      if (!_didBindInitialData && !next.isLoading && next.username.isNotEmpty) {
        _usernameController.text = next.username;
        _emailController.text = next.email;
        _phoneController.text = next.phoneNumber;
        _firstNameController.text = next.firstName;
        _lastNameController.text = next.lastName;
        _bioController.text = next.bio;
        _didBindInitialData = true;
      }
      if (next.successMessage != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.successMessage!)));
        context.pop();
      }
      if (next.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.error!), backgroundColor: Colors.red),
        );
        ref.read(profileViewModelProvider.notifier).clearMessages();
      }
    });

    final inputDecorationTheme = InputDecoration(
      filled: true,
      fillColor: const Color(0xFF1C1C1E),
      labelStyle: const TextStyle(color: Colors.white70),
      hintStyle: const TextStyle(color: Colors.white38),
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white24),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white24),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.blueAccent),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
    );

    return Scaffold(
      backgroundColor: const Color(0xFF000000), // Match existing dark theme
      appBar: AppBar(
        title: const Text('Edit Profile'),
        backgroundColor: const Color(0xFF000000),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. First Name
                TextFormField(
                  controller: _firstNameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: inputDecorationTheme.copyWith(
                    labelText: 'First Name',
                    hintText: 'Enter your first name',
                    prefixIcon: const Icon(
                      Icons.person_outline,
                      color: Colors.white54,
                    ),
                  ),
                  maxLength: 50,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Required';
                    }
                    if (!RegExp(r'^[a-zA-Z]+$').hasMatch(value.trim())) {
                      return 'Letters only';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // 2. Last Name
                TextFormField(
                  controller: _lastNameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: inputDecorationTheme.copyWith(
                    labelText: 'Last Name',
                    hintText: 'Enter your last name',
                    prefixIcon: const Icon(
                      Icons.person_outline,
                      color: Colors.white54,
                    ),
                  ),
                  maxLength: 50,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Required';
                    }
                    if (!RegExp(r'^[a-zA-Z]+$').hasMatch(value.trim())) {
                      return 'Letters only';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // 3. Username
                TextFormField(
                  controller: _usernameController,
                  style: const TextStyle(color: Colors.white54),
                  decoration: inputDecorationTheme.copyWith(
                    labelText: 'Username',
                    prefixIcon: const Icon(Icons.person, color: Colors.white54),
                    fillColor: const Color(0xFF151515),
                  ),
                  readOnly: true,
                ),
                const SizedBox(height: 16),

                // 4. Email
                TextFormField(
                  controller: _emailController,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.emailAddress,
                  decoration: inputDecorationTheme.copyWith(
                    labelText: 'Email',
                    prefixIcon: const Icon(Icons.email, color: Colors.white54),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter email';
                    }
                    if (!value.contains('@')) {
                      return 'Invalid email format';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // 5. Phone Number
                TextFormField(
                  controller: _phoneController,
                  style: const TextStyle(color: Colors.white),
                  decoration: inputDecorationTheme.copyWith(
                    labelText: 'Phone Number',
                    prefixIcon: const Icon(Icons.phone, color: Colors.white54),
                    hintText: '+1234567890',
                  ),
                  keyboardType: TextInputType.phone,
                  validator: (value) {
                    if (value != null && value.isNotEmpty) {
                      if (!RegExp(r'^\+?[0-9]{10,15}$').hasMatch(value)) {
                        return 'Invalid phone number format';
                      }
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // 6. Bio
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _bioController,
                  builder: (context, value, child) {
                    return TextFormField(
                      controller: _bioController,
                      style: const TextStyle(color: Colors.white),
                      decoration: inputDecorationTheme.copyWith(
                        labelText: 'Bio',
                        hintText: 'Tell us a bit about yourself...',
                        counterText: '${value.text.length} / 150',
                        counterStyle: const TextStyle(color: Colors.white54),
                      ),
                      minLines: 3,
                      maxLines: 6,
                      maxLength: 150,
                      maxLengthEnforcement: MaxLengthEnforcement.enforced,
                    );
                  },
                ),
                const SizedBox(height: 32),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: state.isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: state.isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            'Save Changes',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      ref
          .read(profileViewModelProvider.notifier)
          .updateProfile(
            _emailController.text.trim(),
            _phoneController.text.trim(),
            _firstNameController.text.trim(),
            _lastNameController.text.trim(),
            _bioController.text.trim(),
          );
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _bioController.dispose();
    super.dispose();
  }
}
