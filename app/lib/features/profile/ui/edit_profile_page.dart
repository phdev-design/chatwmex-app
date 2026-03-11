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
    
    // 修正：如果在進入頁面時 Profile 已經載入過，直接綁定現有資料
    final currentState = ref.read(profileViewModelProvider);
    if (currentState.username.isNotEmpty) {
      _populateFields(currentState);
      _didBindInitialData = true;
    } else {
      Future.microtask(() {
        ref.read(profileViewModelProvider.notifier).loadProfile();
      });
    }
  }

  void _populateFields(ProfileState state) {
    _usernameController.text = state.username;
    _emailController.text = state.email;
    _phoneController.text = state.phoneNumber;
    _firstNameController.text = state.firstName;
    _lastNameController.text = state.lastName;
    _bioController.text = state.bio;
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

  void _submit() {
    if (_formKey.currentState!.validate()) {
      ref.read(profileViewModelProvider.notifier).updateProfile(
            _emailController.text.trim(),
            _phoneController.text.trim(),
            _firstNameController.text.trim(),
            _lastNameController.text.trim(),
            _bioController.text.trim(),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(profileViewModelProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // 與 profile_page 一致的背景色與卡片色
    final bgColor = isDark ? const Color(0xFF0D0D0D) : const Color(0xFFF4F6F8);
    final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final hintColor = isDark ? Colors.white38 : Colors.black38;
    final iconColor = isDark ? Colors.white54 : Colors.grey[600];

    ref.listen(profileViewModelProvider, (prev, next) {
      // 若進入時未綁定，等 API 讀取完畢後補綁定
      if (!_didBindInitialData && !next.isLoading && next.username.isNotEmpty) {
        _populateFields(next);
        _didBindInitialData = true;
      }

      if (next.successMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.successMessage!),
            backgroundColor: Colors.green,
          ),
        );
        ref.read(profileViewModelProvider.notifier).clearMessages();
        if (mounted) context.pop(); // 儲存成功後返回上一頁
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
      fillColor: cardColor, // 適應深/淺色模式
      labelStyle: TextStyle(color: iconColor),
      hintStyle: TextStyle(color: hintColor),
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isDark ? Colors.white24 : Colors.grey.shade300,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isDark ? Colors.white24 : Colors.grey.shade300,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.blueAccent, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
    );

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          '編輯個人資料',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 17,
            color: textColor,
          ),
        ),
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: textColor),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionTitle('基本資訊', isDark),
                const SizedBox(height: 8),
                // 1. First Name
                TextFormField(
                  controller: _firstNameController,
                  style: TextStyle(color: textColor),
                  decoration: inputDecorationTheme.copyWith(
                    labelText: '名字 (First Name)',
                    hintText: '請輸入名字',
                    prefixIcon: Icon(Icons.badge_outlined, color: iconColor),
                  ),
                  maxLength: 50,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return '此欄位必填';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // 2. Last Name
                TextFormField(
                  controller: _lastNameController,
                  style: TextStyle(color: textColor),
                  decoration: inputDecorationTheme.copyWith(
                    labelText: '姓氏 (Last Name)',
                    hintText: '請輸入姓氏',
                    prefixIcon: Icon(Icons.badge_outlined, color: iconColor),
                  ),
                  maxLength: 50,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return '此欄位必填';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // 3. Bio
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _bioController,
                  builder: (context, value, child) {
                    return TextFormField(
                      controller: _bioController,
                      style: TextStyle(color: textColor),
                      decoration: inputDecorationTheme.copyWith(
                        labelText: '個人簡介 (Bio)',
                        hintText: '介紹一下你自己...',
                        counterText: '${value.text.length} / 150',
                        counterStyle: TextStyle(color: iconColor),
                      ),
                      minLines: 3,
                      maxLines: 6,
                      maxLength: 150,
                      maxLengthEnforcement: MaxLengthEnforcement.enforced,
                    );
                  },
                ),
                const SizedBox(height: 32),
                
                _buildSectionTitle('帳號聯絡資訊', isDark),
                const SizedBox(height: 8),

                // 4. Username (Read Only)
                TextFormField(
                  controller: _usernameController,
                  style: TextStyle(color: isDark ? Colors.white54 : Colors.black54),
                  decoration: inputDecorationTheme.copyWith(
                    labelText: '使用者名稱 (Username)',
                    prefixIcon: Icon(Icons.person_outline, color: iconColor),
                    fillColor: isDark ? const Color(0xFF151515) : Colors.grey.shade100,
                  ),
                  readOnly: true, // 不允許修改
                ),
                const SizedBox(height: 16),

                // 5. Email
                TextFormField(
                  controller: _emailController,
                  style: TextStyle(color: textColor),
                  keyboardType: TextInputType.emailAddress,
                  decoration: inputDecorationTheme.copyWith(
                    labelText: '電子郵件 (Email)',
                    prefixIcon: Icon(Icons.email_outlined, color: iconColor),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return '請輸入電子郵件';
                    if (!value.contains('@')) return '電子郵件格式無效';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // 6. Phone Number
                TextFormField(
                  controller: _phoneController,
                  style: TextStyle(color: textColor),
                  decoration: inputDecorationTheme.copyWith(
                    labelText: '電話號碼 (Phone)',
                    prefixIcon: Icon(Icons.phone_outlined, color: iconColor),
                    hintText: '+1234567890',
                  ),
                  keyboardType: TextInputType.phone,
                  validator: (value) {
                    if (value != null && value.isNotEmpty) {
                      if (!RegExp(r'^\+?[0-9]{8,15}$').hasMatch(value)) {
                        return '電話號碼格式無效';
                      }
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 40),

                // Save Button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: state.isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0056B3), // 統一的主題藍色
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    child: state.isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Text(
                            '儲存變更',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
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

  // 小標題 UI 元件
  Widget _buildSectionTitle(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white54 : Colors.grey[600],
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}