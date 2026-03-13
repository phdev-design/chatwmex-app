import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app/features/auth/providers/auth_provider.dart';
import 'package:app/features/auth/widgets/key_recovery_dialog.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailController = TextEditingController();
  bool _isRegister = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _submit() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    final email = _emailController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please fill all fields')));
      return;
    }

    if (_isRegister) {
      if (email.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Please enter email')));
        return;
      }
      if (!email.contains('@')) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Invalid email format')));
        return;
      }
      await ref
          .read(authViewModelProvider.notifier)
          .register(username, password, email);
    } else {
      await ref.read(authViewModelProvider.notifier).login(username, password);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authViewModelProvider);

    // Listen for auth success
    ref.listen(authViewModelProvider, (prev, next) {
      if (next.isAuthenticated) {
        context.go('/chat-list');
      }

      if (next.isRegistered && !(prev?.isRegistered ?? false)) {
        // Reset registered state to avoid repeating
        ref.read(authViewModelProvider.notifier).resetRegistered();

        // Switch back to login mode
        setState(() => _isRegister = false);

        // Clear input fields
        _usernameController.clear();
        _passwordController.clear();
        _emailController.clear();

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account created successfully! Please sign in.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }

      if (next.error != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.error!)));
      }
    });

    // Listen for key recovery needs
    ref.listen(authViewModelProvider, (prev, next) {
      if (next.needsKeyRecovery && !(prev?.needsKeyRecovery ?? false)) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const KeyRecoveryDialog(),
        );
      }
    });

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 64,
                  color: Theme.of(context).primaryColor,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'ChatWmex',
                style: Theme.of(
                  context,
                ).textTheme.displayLarge?.copyWith(fontSize: 28),
              ),
              const SizedBox(height: 8),
              Text(
                'Enterprise Communication',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 32),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _isRegister ? 'Create Account' : 'Welcome Back',
                        style: Theme.of(context).textTheme.headlineMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _usernameController,
                        decoration: InputDecoration(
                          labelText: _isRegister
                              ? 'Username'
                              : 'Username or Email',
                          prefixIcon: const Icon(Icons.person_outline),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_isRegister) ...[
                        TextField(
                          controller: _emailController,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextField(
                        controller: _passwordController,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                        obscureText: true,
                      ),
                      const SizedBox(height: 24),
                      if (state.isLoading)
                        const Center(child: CircularProgressIndicator())
                      else
                        ElevatedButton(
                          onPressed: _submit,
                          child: Text(_isRegister ? 'Sign Up' : 'Sign In'),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => setState(() => _isRegister = !_isRegister),
                child: Text(
                  _isRegister
                      ? 'Already have an account? Sign In'
                      : 'Don\'t have an account? Sign Up',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
