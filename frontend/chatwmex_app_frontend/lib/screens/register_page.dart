import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/api_config.dart';
import 'login_page.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  _RegisterPageState createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _languageController = TextEditingController(text: 'zh'); // 預設值
  
  bool _isLoading = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _languageController.dispose();
    super.dispose();
  }

  // 驗證函數
  String? _validateRequired(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName 為必填項';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email 為必填項';
    }
    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value.trim())) {
      return '請輸入有效的 Email 格式';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '密碼為必填項';
    }
    if (value.length < 6) {
      return '密碼至少需要 6 個字符';
    }
    return null;
  }

  Future<void> _register() async {
    // 先驗證表單
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // 檢查 context 是否仍然有效
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // 準備要發送的數據，並去除前後空格
      final requestData = {
        'username': _usernameController.text.trim(),
        'email': _emailController.text.trim(),
        'password': _passwordController.text,
        'language': _languageController.text.trim(),
      };

      print('發送註冊請求: $requestData'); // 調試用

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/v1/register'),
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode(requestData),
      );

      print('響應狀態碼: ${response.statusCode}'); // 調試用
      print('響應內容: ${response.body}'); // 調試用

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      if (response.statusCode == 201) {
        // 註冊成功
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('註冊成功！請登入。'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginPage()),
          (Route<dynamic> route) => false,
        );
      } else {
        // 嘗試解析錯誤訊息
        String errorMessage = '註冊失敗';
        try {
          final errorResponse = jsonDecode(response.body);
          if (errorResponse['error'] != null) {
            errorMessage = errorResponse['error'];
          }
        } catch (e) {
          errorMessage = '註冊失敗：伺服器響應格式錯誤';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      
      setState(() {
        _isLoading = false;
      });
      
      // 網路或其他錯誤
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('發生錯誤: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('註冊'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: <Widget>[
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: '使用者名稱',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => _validateRequired(value, '使用者名稱'),
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: _validateEmail,
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: '密碼',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
                validator: _validatePassword,
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _languageController,
                decoration: const InputDecoration(
                  labelText: '語言',
                  border: OutlineInputBorder(),
                  hintText: '例如: zh, en',
                ),
                validator: (value) => _validateRequired(value, '語言'),
                enabled: !_isLoading,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _register,
                  child: _isLoading
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 8),
                            Text('註冊中...'),
                          ],
                        )
                      : const Text('註冊'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}