import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/api_config.dart';
import '../utils/token_storage.dart';
import '../services/profile_api_service.dart'; // 🔥 新增：個人資料 API 服務
import 'login_page.dart'; // 🔥 新增：登入頁面

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _isLoadingProfile = true;
  bool _showCurrentPassword = false;
  bool _showNewPassword = false;
  bool _showConfirmPassword = false;
  bool _changePassword = false;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  Map<String, dynamic>? _originalUserData;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _loadUserProfile();
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    try {
      final userInfo = await TokenStorage.getUser();
      if (userInfo != null) {
        setState(() {
          _originalUserData = userInfo;
          _usernameController.text = userInfo['username'] ?? '';
          _emailController.text = userInfo['email'] ?? '';
          _isLoadingProfile = false;
        });
      }
    } catch (e) {
      print('Error loading user profile: $e');
      setState(() {
        _isLoadingProfile = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('載入個人資料失敗: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // 驗證函數
  String? _validateUsername(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '用戶名不能為空';
    }
    if (value.trim().length < 2) {
      return '用戶名至少需要 2 個字符';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email 不能為空';
    }
    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value.trim())) {
      return '請輸入有效的 Email 格式';
    }
    return null;
  }

  String? _validateCurrentPassword(String? value) {
    if (!_changePassword) return null;
    if (value == null || value.isEmpty) {
      return '請輸入當前密碼';
    }
    return null;
  }

  String? _validateNewPassword(String? value) {
    if (!_changePassword) return null;
    if (value == null || value.isEmpty) {
      return '請輸入新密碼';
    }
    if (value.length < 6) {
      return '密碼至少需要 6 個字符';
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (!_changePassword) return null;
    if (value == null || value.isEmpty) {
      return '請確認新密碼';
    }
    if (value != _newPasswordController.text) {
      return '兩次輸入的密碼不一致';
    }
    return null;
  }

  Future<Map<String, String>> _getHeaders() async {
    final token = await TokenStorage.getToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${token ?? ''}',
    };
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final headers = await _getHeaders();

      // 準備更新資料
      final updateData = <String, dynamic>{};

      // 檢查用戶名是否有變更
      if (_usernameController.text.trim() != _originalUserData?['username']) {
        updateData['username'] = _usernameController.text.trim();
      }

      // 檢查 Email 是否有變更
      if (_emailController.text.trim() != _originalUserData?['email']) {
        updateData['email'] = _emailController.text.trim();
      }

      // 如果要修改密碼
      if (_changePassword) {
        updateData['current_password'] = _currentPasswordController.text;
        updateData['new_password'] = _newPasswordController.text;
      }

      // 如果沒有任何變更
      if (updateData.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('沒有檢測到任何變更'),
            backgroundColor: Colors.orange,
          ),
        );
        setState(() {
          _isLoading = false;
        });
        return;
      }

      print('更新資料: $updateData');

      final response = await http.put(
        Uri.parse('${ApiConfig.currentUrl}/api/v1/profile'),
        headers: headers,
        body: jsonEncode(updateData),
      );

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);

        // 更新本地儲存的用戶資料
        if (responseData['user'] != null) {
          await TokenStorage.saveUser(responseData['user']);
        }

        // 清空密碼欄位
        _currentPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
        setState(() {
          _changePassword = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('個人資料更新成功！'),
              ],
            ),
            backgroundColor: Colors.green,
          ),
        );

        // 重新載入個人資料
        _loadUserProfile();
      } else {
        String errorMessage = '更新失敗';
        try {
          final errorResponse = jsonDecode(response.body);
          errorMessage = errorResponse['error'] ?? errorMessage;
        } catch (e) {
          errorMessage = '更新失敗：伺服器響應格式錯誤';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text(errorMessage)),
              ],
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.warning, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text('網路錯誤: $e')),
            ],
          ),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Widget _buildBasicInfoSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.person,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '基本資料',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 用戶名
            TextFormField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: '用戶名',
                hintText: '請輸入用戶名',
                prefixIcon: Icon(Icons.account_circle),
              ),
              validator: _validateUsername,
              enabled: !_isLoading,
            ),

            const SizedBox(height: 16),

            // Email
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: '請輸入 Email',
                prefixIcon: Icon(Icons.email),
              ),
              keyboardType: TextInputType.emailAddress,
              validator: _validateEmail,
              enabled: !_isLoading,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.lock,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '密碼設定',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                Switch(
                  value: _changePassword,
                  onChanged: _isLoading
                      ? null
                      : (value) {
                          setState(() {
                            _changePassword = value;
                            if (!value) {
                              _currentPasswordController.clear();
                              _newPasswordController.clear();
                              _confirmPasswordController.clear();
                            }
                          });
                        },
                ),
              ],
            ),
            if (!_changePassword) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '開啟開關以修改密碼',
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_changePassword) ...[
              const SizedBox(height: 16),

              // 當前密碼
              TextFormField(
                controller: _currentPasswordController,
                decoration: InputDecoration(
                  labelText: '當前密碼',
                  hintText: '請輸入當前密碼',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showCurrentPassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed: () {
                      setState(() {
                        _showCurrentPassword = !_showCurrentPassword;
                      });
                    },
                  ),
                ),
                obscureText: !_showCurrentPassword,
                validator: _validateCurrentPassword,
                enabled: !_isLoading,
              ),

              const SizedBox(height: 16),

              // 新密碼
              TextFormField(
                controller: _newPasswordController,
                decoration: InputDecoration(
                  labelText: '新密碼',
                  hintText: '請輸入新密碼（至少 6 個字符）',
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showNewPassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed: () {
                      setState(() {
                        _showNewPassword = !_showNewPassword;
                      });
                    },
                  ),
                ),
                obscureText: !_showNewPassword,
                validator: _validateNewPassword,
                enabled: !_isLoading,
              ),

              const SizedBox(height: 16),

              // 確認新密碼
              TextFormField(
                controller: _confirmPasswordController,
                decoration: InputDecoration(
                  labelText: '確認新密碼',
                  hintText: '請再次輸入新密碼',
                  prefixIcon: const Icon(Icons.lock_clock),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showConfirmPassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed: () {
                      setState(() {
                        _showConfirmPassword = !_showConfirmPassword;
                      });
                    },
                  ),
                ),
                obscureText: !_showConfirmPassword,
                validator: _validateConfirmPassword,
                enabled: !_isLoading,
                onFieldSubmitted: (_) => _saveProfile(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ElevatedButton(
        onPressed: _isLoading ? null : _saveProfile,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isLoading
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  SizedBox(width: 12),
                  Text('更新中...'),
                ],
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.save),
                  SizedBox(width: 8),
                  Text('保存變更'),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('編輯個人資料'),
        actions: [
          if (!_isLoading)
            TextButton(
              onPressed: () {
                // 重置表單
                _loadUserProfile();
                setState(() {
                  _changePassword = false;
                });
                _currentPasswordController.clear();
                _newPasswordController.clear();
                _confirmPasswordController.clear();
              },
              child: const Text('重置'),
            ),
        ],
      ),
      body: _isLoadingProfile
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('載入個人資料中...'),
                ],
              ),
            )
          : FadeTransition(
              opacity: _fadeAnimation,
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 個人資料頭像區域
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            children: [
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                child: Center(
                                  child: Text(
                                    _getUserInitials(),
                                    style: const TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _originalUserData?['username'] ?? '用戶',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              Text(
                                _originalUserData?['email'] ?? '',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.7),
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // 基本資料區域
                      _buildBasicInfoSection(),

                      const SizedBox(height: 16),

                      // 密碼設定區域
                      _buildPasswordSection(),

                      const SizedBox(height: 24),

                      // 🔥 新增：危險操作區域
                      _buildDangerousOperationsSection(),

                      const SizedBox(height: 24),

                      // 保存按鈕
                      _buildSaveButton(),

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  String _getUserInitials() {
    final username = _originalUserData?['username'] ?? '';
    final email = _originalUserData?['email'] ?? '';

    if (username.isNotEmpty) {
      final words = username.split(' ');
      if (words.length >= 2) {
        return '${words[0][0]}${words[1][0]}'.toUpperCase();
      }
      return username.substring(0, 1).toUpperCase();
    }

    if (email.isNotEmpty) {
      return email.substring(0, 1).toUpperCase();
    }

    return 'U';
  }

  // 🔥 新增：危險操作區域
  Widget _buildDangerousOperationsSection() {
    return Card(
      color: Colors.red.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 警告標題
            Row(
              children: [
                Icon(Icons.warning, color: Colors.red[700], size: 20),
                const SizedBox(width: 8),
                Text(
                  '危險操作',
                  style: TextStyle(
                    color: Colors.red[700],
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '以下操作將永久影響您的帳戶，請謹慎操作。',
              style: TextStyle(
                color: Colors.red[600],
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),

            // 刪除帳戶按鈕
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _showSoftDeleteDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.delete_forever, size: 18),
                label: const Text('刪除帳戶'),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // 🔥 新增：刪除帳戶對話框
  void _showSoftDeleteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.red[700]),
            const SizedBox(width: 8),
            const Text('刪除帳戶'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '您確定要停用您的帳戶嗎？',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text('停用後：'),
            const SizedBox(height: 8),
            const Text('• 您的帳戶將被停用，無法登入'),
            const Text('• 其他用戶將無法看到您的個人資料'),
            const Text('• 您將無法接收消息和通知'),
            const Text('• 您的聊天記錄將被保留'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info, color: Colors.blue, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '您可以隨時聯繫客服恢復帳戶',
                      style: TextStyle(fontSize: 12, color: Colors.blue),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '請輸入您的密碼以確認此操作：',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showPasswordConfirmationDialog();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('繼續'),
          ),
        ],
      ),
    );
  }

  // 🔥 新增：密碼確認對話框
  void _showPasswordConfirmationDialog() {
    final passwordController = TextEditingController();
    bool isPasswordVisible = false;
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('確認密碼'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('請輸入您的密碼以確認停用帳戶：'),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: !isPasswordVisible,
                decoration: InputDecoration(
                  labelText: '密碼',
                  hintText: '輸入您的密碼',
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(
                      isPasswordVisible
                          ? Icons.visibility
                          : Icons.visibility_off,
                    ),
                    onPressed: () {
                      setDialogState(() {
                        isPasswordVisible = !isPasswordVisible;
                      });
                    },
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      final password = passwordController.text.trim();
                      if (password.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('請輸入密碼'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      setDialogState(() {
                        isLoading = true;
                      });

                      try {
                        await _performSoftDelete(password);
                        if (context.mounted) {
                          Navigator.pop(context);
                        }
                      } catch (e) {
                        setDialogState(() {
                          isLoading = false;
                        });
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('停用失敗: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text('確認停用'),
            ),
          ],
        ),
      ),
    );
  }

  // 🔥 新增：執行偽刪除操作
  Future<void> _performSoftDelete(String password) async {
    try {
      // 調用後端 API 來執行偽刪除
      final result = await ProfileApiService.softDeleteAccount(password);

      if (mounted) {
        if (result['success']) {
          // 顯示成功消息
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message']),
              backgroundColor: Colors.green,
            ),
          );

          // 等待一下讓用戶看到消息
          await Future.delayed(const Duration(seconds: 1));

          // 清除本地存儲並導航到登入頁面
          await TokenStorage.clearAll();

          if (mounted) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (context) => const LoginPage()),
              (route) => false,
            );
          }
        } else {
          // 顯示錯誤消息
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message']),
              backgroundColor: Colors.red,
            ),
          );
          throw Exception(result['message']);
        }
      }
    } catch (e) {
      print('刪除帳戶失敗: $e');
      rethrow;
    }
  }
}
