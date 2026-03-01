import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app/features/profile/providers/profile_provider.dart';
import 'package:app/core/storage/storage_service.dart';

class EditProfilePage extends ConsumerStatefulWidget {
  const EditProfilePage({super.key});

  @override
  ConsumerState<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends ConsumerState<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _usernameController = TextEditingController();
  
  // We need to load initial data. Since we don't have a robust "Get Profile" API yet that returns phone number,
  // we might start with empty or rely on what we stored.
  // For this task, I'll fetch basic info from storage or just leave empty if not available.
  // Ideally, we should pass the User object to this page or fetch it.
  
  @override
  void initState() {
    super.initState();
    // Simulate loading user data or fetch if possible.
    // Since we don't have the full user object with phone number in storage easily accessible without extra calls,
    // I will try to load what I can.
    _loadUserData();
  }
  
  Future<void> _loadUserData() async {
    final storage = ref.read(storageServiceProvider);
    final username = await storage.read('username');
    if (mounted && username != null) {
      _usernameController.text = username;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(profileViewModelProvider);
    
    // Listen for success/error
    ref.listen(profileViewModelProvider, (prev, next) {
      if (next.successMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next.successMessage!)));
        context.pop(); // Go back on success
      }
      if (next.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next.error!), backgroundColor: Colors.red));
        ref.read(profileViewModelProvider.notifier).clearMessages();
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Read-only Username
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  filled: true,
                  fillColor: Colors.black12, // Visual cue for read-only
                  prefixIcon: Icon(Icons.person),
                ),
                readOnly: true,
                // If we don't have username, it will be empty. 
                // In a real app, we must have it.
              ),
              const SizedBox(height: 16),
              
              // Email
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email),
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
              
              // Phone Number
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  prefixIcon: Icon(Icons.phone),
                  hintText: '+1234567890',
                ),
                keyboardType: TextInputType.phone,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter phone number';
                  }
                  // Basic regex for phone
                  if (!RegExp(r'^\+?[0-9]{10,15}$').hasMatch(value)) {
                    return 'Invalid phone number format (10-15 digits)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: state.isLoading ? null : _submit,
                  child: state.isLoading 
                      ? const CircularProgressIndicator(color: Colors.white) 
                      : const Text('Save Changes'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      ref.read(profileViewModelProvider.notifier).updateProfile(
        _emailController.text.trim(),
        _phoneController.text.trim(),
      );
    }
  }
  
  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    _usernameController.dispose();
    super.dispose();
  }
}
